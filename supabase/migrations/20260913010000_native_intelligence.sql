-- Account-owned originals are never included in couple realtime or shared context.
create table public.private_artifacts (
  id uuid not null,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  version bigint not null default 1,
  manifest jsonb not null,
  content jsonb not null,
  updated_at timestamptz not null default now(),
  primary key(owner_id, id)
);
create table public.private_artifact_tombstones (
  owner_id uuid not null references auth.users(id) on delete cascade,
  artifact_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(owner_id, artifact_id)
);
create table private.artifact_operations (
  owner_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  artifact_id uuid not null,
  payload_hash text not null,
  version bigint not null,
  primary key(owner_id, operation_id)
);
create table private.intake_resource_verifications (
  owner_id uuid not null references auth.users(id) on delete cascade,
  bucket text not null,
  path text not null,
  sha256 text not null,
  byte_count bigint not null,
  primary key(bucket, path)
);
alter table public.private_artifacts enable row level security;
alter table public.private_artifact_tombstones enable row level security;
create policy artifact_owner_read on public.private_artifacts for select to authenticated using(owner_id = auth.uid());
create policy tombstone_owner_read on public.private_artifact_tombstones for select to authenticated using(owner_id = auth.uid());
grant select on public.private_artifacts, public.private_artifact_tombstones to authenticated;
revoke insert, update, delete on public.private_artifacts, public.private_artifact_tombstones from anon, authenticated;

insert into storage.buckets(id, name, public, file_size_limit) values('private-originals', 'private-originals', false, 67108864)
on conflict(id) do nothing;
create policy original_read on storage.objects for select to authenticated using(
 bucket_id = 'private-originals' and (storage.foldername(name))[1] = auth.uid()::text
 and not exists(select 1 from public.private_artifact_tombstones t where t.owner_id = auth.uid() and t.artifact_id::text = (storage.foldername(name))[2])
);
create policy original_insert on storage.objects for insert to authenticated with check(
 bucket_id = 'private-originals' and (storage.foldername(name))[1] = auth.uid()::text
 and array_length(storage.foldername(name),1) = 2
 and (storage.foldername(name))[2] ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
 and storage.filename(name) ~ '^[a-f0-9]{64}$'
 and not exists(select 1 from public.private_artifact_tombstones t where t.owner_id = auth.uid() and t.artifact_id::text = (storage.foldername(name))[2])
);
-- No client update/delete: resources are immutable and cleanup is server-owned.
create or replace function public.intake_record_verification(p_owner uuid, p_bucket text, p_path text, p_sha256 text, p_bytes bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare artifact uuid;
begin
 if p_bucket='private-originals' then
   if split_part(p_path,'/',1)<>p_owner::text then raise exception 'invalid owner'; end if;
   artifact:=split_part(p_path,'/',2)::uuid;
 else
   select draft_id into artifact from public.share_publication_sessions
   where id=split_part(p_path,'/',2)::uuid and created_by=p_owner and state='created';
   if artifact is null then raise exception 'publication unavailable'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text||artifact::text,0));
 if exists(select 1 from public.private_artifact_tombstones where owner_id=p_owner and artifact_id=artifact)
 then raise exception 'artifact deleted'; end if;
 if p_bucket not in ('private-originals','life-resources') or p_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'invalid verification'; end if;
 insert into private.intake_resource_verifications values(p_owner,p_bucket,p_path,p_sha256,p_bytes)
 on conflict(bucket,path) do update set sha256=excluded.sha256, byte_count=excluded.byte_count
 where private.intake_resource_verifications.owner_id=excluded.owner_id;
end; $$;
revoke all on function public.intake_record_verification(uuid,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.intake_record_verification(uuid,text,text,text,bigint) to service_role;

create or replace function public.intake_write(p_id uuid,p_operation uuid,p_expected bigint,p_manifest jsonb,p_content jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_row public.private_artifacts%rowtype; v_op private.artifact_operations%rowtype; v_hash text; r jsonb; v_path text;
begin
 if v_user is null then raise exception 'authentication required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_id::text,0));
 if exists(select 1 from public.private_artifact_tombstones where owner_id=v_user and artifact_id=p_id) then raise exception 'artifact deleted'; end if;
 if lower(p_manifest->>'id') is distinct from p_id::text or jsonb_typeof(p_content) is distinct from 'object' or octet_length(p_content::text)>262144 or octet_length(p_manifest::text)>262144 or p_expected<0 or p_expected is null or jsonb_typeof(p_manifest->'resources') is distinct from 'array' then raise exception 'invalid artifact'; end if;
 if jsonb_array_length(p_manifest->'resources')>5 then raise exception 'too many originals'; end if;
 if exists(select 1 from public.private_artifact_tombstones where owner_id=v_user and artifact_id::text=lower(p_content->>'connectedPrivatePlanID')) then raise exception 'connected plan deleted'; end if;
 v_hash:=md5(p_manifest::text||p_content::text||p_expected::text);
 select * into v_op from private.artifact_operations where owner_id=v_user and operation_id=p_operation;
 if found then
   if v_op.artifact_id<>p_id or v_op.payload_hash<>v_hash then raise exception 'operation reused'; end if;
   return jsonb_build_object('version',v_op.version);
 end if;
 select * into v_row from public.private_artifacts where owner_id=v_user and id=p_id for update;
 if coalesce(v_row.version,0)<>p_expected then
   return jsonb_build_object('version',v_row.version,'conflict',v_row.content);
 end if;
 for r in select value from jsonb_array_elements(p_manifest->'resources') loop
   v_path:=v_user::text||'/'||p_id::text||'/'||(r->>'sha256');
   if not exists(select 1 from private.intake_resource_verifications where owner_id=v_user and bucket='private-originals' and path=v_path and sha256=r->>'sha256' and byte_count=(r->>'byteCount')::bigint) then raise exception 'original not verified'; end if;
 end loop;
 insert into public.private_artifacts(owner_id,id,version,manifest,content) values(v_user,p_id,p_expected+1,p_manifest,p_content)
 on conflict(owner_id,id) do update set version=excluded.version,manifest=excluded.manifest,content=excluded.content,updated_at=now();
 insert into private.artifact_operations values(v_user,p_operation,p_id,v_hash,p_expected+1);
 return jsonb_build_object('version',p_expected+1);
end; $$;
revoke all on function public.intake_write(uuid,uuid,bigint,jsonb,jsonb) from public,anon;
grant execute on function public.intake_write(uuid,uuid,bigint,jsonb,jsonb) to authenticated;

create table private.intake_cleanup_jobs (
 owner_id uuid not null,
 artifact_id uuid not null,
 resources jsonb not null default '[]'::jsonb,
 primary key(owner_id,artifact_id)
);
create or replace function public.intake_delete_everywhere(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'authentication required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_id::text,0));
 insert into public.private_artifact_tombstones(owner_id,artifact_id) values(v_user,p_id) on conflict do nothing;
 insert into private.intake_cleanup_jobs(owner_id,artifact_id,resources)
 select v_user,p_id,coalesce(jsonb_agg(jsonb_build_object('bucket','life-resources','path',r->>'object_path')) filter(where r is not null),'[]'::jsonb)
 from public.share_publication_sessions s left join lateral jsonb_array_elements(s.expected_resources) r on true
 where s.created_by=v_user and s.draft_id=p_id
 on conflict(owner_id,artifact_id) do nothing;
 -- Publication sessions establish ownership; never trust a client-supplied shared id.
 delete from public.field_life_items where id in(select life_item_id from public.share_publication_sessions where created_by=v_user and draft_id=p_id union select life_item_id from private.artifact_publications where owner_id=v_user and artifact_id=p_id);
 delete from public.share_publication_sessions where created_by=v_user and draft_id=p_id;
 update public.private_artifacts set content=content-'connectedPrivatePlanID',version=version+1,updated_at=now()
 where owner_id=v_user and lower(content->>'connectedPrivatePlanID')=p_id::text;
 delete from public.private_artifacts where owner_id=v_user and id=p_id;
 delete from private.artifact_operations where owner_id=v_user and artifact_id=p_id;

end; $$;
revoke all on function public.intake_delete_everywhere(uuid) from public,anon;
grant execute on function public.intake_delete_everywhere(uuid) to authenticated;

create table private.artifact_publications (
 owner_id uuid not null references auth.users(id) on delete cascade,
 artifact_id uuid not null,
 life_item_id uuid not null references public.field_life_items(id) on delete cascade,
 revision integer not null,
 primary key(owner_id,artifact_id)
);
alter table public.share_publication_sessions add column intelligence_snapshot jsonb;
alter table public.field_life_items add column intelligence_version bigint not null default 0;
alter table public.field_life_items add column timing jsonb;
alter table public.field_life_items add column place text;
alter table public.field_life_items add column connected_plan_id uuid references public.field_life_items(id) on delete set null;

create or replace function public.intake_create_publication(p_snapshot uuid,p_draft uuid,p_revision integer,p_title text,p_body text,p_category text,p_urls jsonb,p_resources jsonb,p_details jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; previous jsonb; target uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_draft::text,0));
 if exists(select 1 from public.private_artifact_tombstones where owner_id=auth.uid() and artifact_id=p_draft) then raise exception 'artifact deleted'; end if;
 if p_details->>'audience' is distinct from public.my_couple_id()::text then raise exception 'audience changed'; end if;
 target:=nullif(p_details->>'connectedPlanID','')::uuid;
 if target is not null and not exists(select 1 from public.field_life_items where id=target and couple_id=public.my_couple_id() and visibility='shared') then raise exception 'destination unavailable'; end if;
 result:=public.share_create_publication_session(p_snapshot,p_draft,p_revision,p_title,p_body,p_category,p_urls,p_resources);
 select intelligence_snapshot into previous from public.share_publication_sessions where id=p_snapshot for update;
 if previous is not null and previous<>p_details then raise exception 'review changed'; end if;
 update public.share_publication_sessions set intelligence_snapshot=p_details where id=p_snapshot;
 return result;
end; $$;
revoke all on function public.intake_create_publication(uuid,uuid,integer,text,text,text,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.intake_create_publication(uuid,uuid,integer,text,text,text,jsonb,jsonb,jsonb) to authenticated;

-- Guard even legacy finalizers: a tombstone wins over every stale publication.
create function private.intake_publication_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb; target uuid; previous private.artifact_publications%rowtype; generated uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(new.created_by::text||new.draft_id::text,0));
 if (TG_OP='INSERT' or (new.state='finalized' and old.state is distinct from 'finalized')) and exists(select 1 from public.private_artifact_tombstones where owner_id=new.created_by and artifact_id=new.draft_id) then raise exception 'artifact deleted'; end if;
 if new.state='finalized' and old.state is distinct from 'finalized' and new.intelligence_snapshot is not null then
   if new.couple_id is distinct from public.my_couple_id() then raise exception 'permission changed'; end if;
   select * into previous from private.artifact_publications where owner_id=new.created_by and artifact_id=new.draft_id for update;
   if coalesce(previous.revision,0) <> coalesce((new.intelligence_snapshot->>'expectedPublishedRevision')::integer,0) then raise exception 'shared revision changed; review again'; end if;
   if new.intelligence_snapshot ? 'expectedPrivateVersion' and
     coalesce((select version from public.private_artifacts where owner_id=new.created_by and id=new.draft_id),0)
     <> (new.intelligence_snapshot->>'expectedPrivateVersion')::bigint then raise exception 'private details changed; review again'; end if;
   target:=nullif(new.intelligence_snapshot->>'connectedPlanID','')::uuid;
   if target is not null and not exists(select 1 from public.field_life_items where id=target and couple_id=new.couple_id and visibility='shared') then raise exception 'destination changed'; end if;
   for r in select value from jsonb_array_elements(new.expected_resources) loop
     if not exists(select 1 from private.intake_resource_verifications where owner_id=new.created_by and bucket='life-resources' and path=r->>'object_path' and sha256=r->>'sha256' and byte_count=(r->>'byte_count')::bigint) then raise exception 'attachment bytes unverified'; end if;
   end loop;
   if previous.life_item_id is not null then
     if (select intelligence_version from public.field_life_items where id=previous.life_item_id for update) <> coalesce((new.intelligence_snapshot->>'expectedLifeVersion')::bigint,0) then raise exception 'shared item changed; review again'; end if;
     if target=previous.life_item_id then raise exception 'an item cannot contain itself'; end if;
     generated:=new.life_item_id;
     update public.field_life_items set title=new.title,detail=nullif(new.body,''),category=new.category where id=previous.life_item_id;
     delete from public.field_life_resources where life_item_id=previous.life_item_id;
     update public.field_life_resources set life_item_id=previous.life_item_id where life_item_id=generated;
     new.life_item_id:=previous.life_item_id;
     delete from public.field_life_items where id=generated;
   end if;
   insert into private.artifact_publications values(new.created_by,new.draft_id,new.life_item_id,new.revision)
   on conflict(owner_id,artifact_id) do update set revision=excluded.revision;
   update public.field_life_items set intelligence_version=intelligence_version+1,timing=new.intelligence_snapshot->'timing',place=new.intelligence_snapshot->>'place',connected_plan_id=target,
     due_on=case when new.intelligence_snapshot#>>'{timing,precision}'='day' then (new.intelligence_snapshot#>>'{timing,startDay}')::date else null end,
     closes_at=case when new.intelligence_snapshot#>>'{timing,precision}'='time' then (new.intelligence_snapshot#>>'{timing,start}')::timestamptz else null end where id=new.life_item_id;
 end if;
 return new;
end; $$;
create trigger intake_publication_guard before insert or update on public.share_publication_sessions for each row execute function private.intake_publication_guard();

create or replace function public.intake_cleanup_jobs(p_owner uuid default null,p_artifact uuid default null)
returns setof private.intake_cleanup_jobs language sql security definer set search_path='' as $$
 select * from private.intake_cleanup_jobs where (p_owner is null or owner_id=p_owner) and (p_artifact is null or artifact_id=p_artifact) limit 50;
$$;
create or replace function public.intake_finish_cleanup(p_owner uuid,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from private.intake_resource_verifications where (owner_id=p_owner and path like p_owner::text||'/'||p_id::text||'/%')
 or path in(select r->>'path' from private.intake_cleanup_jobs j cross join lateral jsonb_array_elements(j.resources) r where j.owner_id=p_owner and j.artifact_id=p_id);
 delete from private.intake_cleanup_jobs where owner_id=p_owner and artifact_id=p_id;
end; $$;
revoke all on function public.intake_cleanup_jobs(uuid,uuid),public.intake_finish_cleanup(uuid,uuid) from public,anon,authenticated;
grant execute on function public.intake_cleanup_jobs(uuid,uuid),public.intake_finish_cleanup(uuid,uuid) to service_role;
create function private.intake_account_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into private.intake_cleanup_jobs(owner_id,artifact_id)
 select old.id,id from public.private_artifacts where owner_id=old.id
 union select old.id,((storage.foldername(name))[2])::uuid from storage.objects
 where bucket_id='private-originals' and (storage.foldername(name))[1]=old.id::text
 on conflict do nothing;
 delete from public.field_life_items where id in(select life_item_id from private.artifact_publications where owner_id=old.id);
 return old;
end; $$;
create trigger intake_account_cleanup before delete on auth.users for each row execute function private.intake_account_cleanup();

-- Old clients may retry old sessions. New verified publication resources are
-- immutable even while the session is pending, closing verify/replace races.
create policy intelligence_resource_immutable on storage.objects as restrictive
for update to authenticated using (
 bucket_id <> 'life-resources' or not exists(
  select 1 from public.share_publication_sessions s where s.intelligence_snapshot is not null
  and s.id::text=(storage.foldername(name))[2]
 )
);

create function public.intake_finalize_publication(p_session uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; canonical uuid;
begin
 result:=public.share_finalize_publication(p_session);
 select life_item_id into canonical from public.share_publication_sessions where id=p_session and created_by=auth.uid() and couple_id=public.my_couple_id();
 if canonical is null then raise exception 'publication unavailable'; end if;
 return jsonb_build_object('life_item_id',canonical);
end; $$;
revoke all on function public.intake_finalize_publication(uuid) from public,anon;
grant execute on function public.intake_finalize_publication(uuid) to authenticated;

create table private.intake_life_edits (
 item_id uuid not null references public.field_life_items(id) on delete cascade,
 actor uuid not null references auth.users(id) on delete cascade,
 expected bigint not null,
 payload_hash text not null,
 primary key(item_id,actor,expected,payload_hash)
);
create function public.intake_update_life(p_id uuid,p_expected bigint,p_fields jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare item public.field_life_items%rowtype; fingerprint text:=md5(p_fields::text);
begin
 select * into item from public.field_life_items where id=p_id and couple_id=public.my_couple_id() for update;
 if not found or auth.uid() is null then raise exception 'item unavailable'; end if;
 if exists(select 1 from private.intake_life_edits where item_id=p_id and actor=auth.uid() and expected=p_expected and payload_hash=fingerprint) then return; end if;
 if item.intelligence_version<>p_expected or p_expected<1 then raise exception 'shared version conflict'; end if;
 update public.field_life_items set title=p_fields->>'title', detail=p_fields->>'detail',
 category=p_fields->>'category', is_done=(p_fields->>'is_done')::boolean,
 due_on=(p_fields->>'due_on')::date,closes_at=(p_fields->>'closes_at')::timestamptz,
 cluster_id=(p_fields->>'cluster_id')::uuid,reached_out_at=(p_fields->>'reached_out_at')::timestamptz,
 timing=case when p_fields ? 'timing' then p_fields->'timing' when due_on is distinct from (p_fields->>'due_on')::date or closes_at is distinct from (p_fields->>'closes_at')::timestamptz then null else timing end,
 intelligence_version=intelligence_version+1 where id=p_id;
 insert into private.intake_life_edits values(p_id,auth.uid(),p_expected,fingerprint);
end; $$;
revoke all on function public.intake_update_life(uuid,bigint,jsonb) from public,anon;
grant execute on function public.intake_update_life(uuid,bigint,jsonb) to authenticated;
-- Invoker security is intentional: only protected server functions can update
-- a versioned publication. A stale legacy client cannot bypass its version check.
create function private.intake_guard_life_write() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and (old.intelligence_version>0 or new.intelligence_version>0) then raise exception 'use versioned item update'; end if;
 return new;
end; $$;
create trigger intake_guard_life_write before update on public.field_life_items for each row execute function private.intake_guard_life_write();

create function private.intake_guard_original_insert() returns trigger
language plpgsql security definer set search_path='' as $$
declare owner uuid; artifact uuid;
begin
 if new.bucket_id<>'private-originals' then return new; end if;
 owner:=((storage.foldername(new.name))[1])::uuid;
 artifact:=((storage.foldername(new.name))[2])::uuid;
 perform pg_advisory_xact_lock(hashtextextended(owner::text||artifact::text,0));
 if exists(select 1 from public.private_artifact_tombstones where owner_id=owner and artifact_id=artifact)
 then raise exception 'artifact deleted'; end if;
 return new;
end; $$;
create trigger intake_guard_original_insert before insert on storage.objects
for each row execute function private.intake_guard_original_insert();
