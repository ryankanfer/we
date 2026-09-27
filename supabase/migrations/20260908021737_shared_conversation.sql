create table public.field_chat_messages (
 id uuid primary key,
 couple_id uuid not null references public.couples(id) on delete cascade,
 sender_id uuid not null,
 body text not null check(length(trim(body)) between 1 and 4000),
 created_at timestamptz not null default clock_timestamp(),
 context_kind text check(context_kind in ('goal','life')),
 context_id uuid,
 decision boolean not null default false,
 confirmed_by uuid,
 source_id uuid references public.field_chat_messages(id) on delete set null,
 check((context_kind is null) = (context_id is null)),
 check(confirmed_by is null or (decision and confirmed_by <> sender_id)),
 foreign key(couple_id,sender_id) references public.couple_members(couple_id,profile_id) on delete cascade
);
create index field_chat_timeline on public.field_chat_messages(couple_id,created_at desc,id desc);
alter table public.field_chat_messages enable row level security;
create policy chat_read on public.field_chat_messages for select to authenticated using(couple_id=(select public.my_couple_id()));
create policy chat_send on public.field_chat_messages for insert to authenticated with check(
 couple_id=(select public.my_couple_id()) and sender_id=(select auth.uid()) and confirmed_by is null
 and created_at between now()-interval '5 minutes' and now()+interval '5 minutes'
 and (source_id is null or exists(select 1 from public.field_chat_messages m where m.id=source_id and m.couple_id=field_chat_messages.couple_id))
 and (context_id is null or (context_kind='goal' and exists(select 1 from public.field_horizons h where h.id=context_id and h.couple_id=field_chat_messages.couple_id))
 or (context_kind='life' and exists(select 1 from public.field_life_items i where i.id=context_id and i.couple_id=field_chat_messages.couple_id and coalesce(i.visibility,'shared')='shared')))
);
create policy chat_confirm on public.field_chat_messages for update to authenticated
 using(couple_id=(select public.my_couple_id()) and sender_id<>(select auth.uid()) and decision)
 with check(couple_id=(select public.my_couple_id()) and confirmed_by=(select auth.uid()) and sender_id<>(select auth.uid()) and decision);
revoke all on public.field_chat_messages from anon,authenticated;
grant select,insert on public.field_chat_messages to authenticated;
grant update(confirmed_by) on public.field_chat_messages to authenticated;

create table public.field_chat_preferences (
 couple_id uuid not null,
 profile_id uuid not null,
 notices boolean not null default false,
 read_at timestamptz,
 primary key(couple_id,profile_id),
 foreign key(couple_id,profile_id) references public.couple_members(couple_id,profile_id) on delete cascade
);
alter table public.field_chat_preferences enable row level security;
create policy chat_preferences_read on public.field_chat_preferences for select to authenticated using(couple_id=(select public.my_couple_id()));
create policy chat_preferences_own on public.field_chat_preferences for all to authenticated
 using(couple_id=(select public.my_couple_id()) and profile_id=(select auth.uid()))
 with check(couple_id=(select public.my_couple_id()) and profile_id=(select auth.uid()));
revoke all on public.field_chat_preferences from anon,authenticated;
grant select,insert,update on public.field_chat_preferences to authenticated;

create function public.field_chat_send(p_id uuid,p_body text,p_context_kind text default null,p_context_id uuid default null,p_decision boolean default false,p_source uuid default null)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if exists(select 1 from public.field_chat_messages where id=p_id) then
   if not exists(select 1 from public.field_chat_messages where id=p_id and sender_id=auth.uid() and body=p_body and decision=p_decision and context_kind is not distinct from p_context_kind and context_id is not distinct from p_context_id and source_id is not distinct from p_source) then raise exception 'Message id already used'; end if;
   return;
 end if;
 insert into public.field_chat_messages(id,couple_id,sender_id,body,context_kind,context_id,decision,source_id)
 values(p_id,public.my_couple_id(),auth.uid(),p_body,p_context_kind,p_context_id,p_decision,p_source);
end $$;
create function public.field_chat_page(p_before uuid default null,p_decisions boolean default false)
returns setof public.field_chat_messages language sql stable security invoker set search_path='' as $$
 select m.* from public.field_chat_messages m
 where m.couple_id=public.my_couple_id() and (not p_decisions or (m.decision and m.confirmed_by is not null))
 and (p_before is null or (m.created_at,m.id)<(select b.created_at,b.id from public.field_chat_messages b where b.id=p_before))
 order by m.created_at desc,m.id desc limit 100;
$$;
create function public.field_chat_preference(p_notices boolean,p_read boolean default false)
returns void language sql security invoker set search_path='' as $$
 insert into public.field_chat_preferences(couple_id,profile_id,notices,read_at)
 values(public.my_couple_id(),auth.uid(),p_notices,case when p_read then now() else null end)
 on conflict(couple_id,profile_id) do update set notices=excluded.notices,read_at=coalesce(excluded.read_at,field_chat_preferences.read_at);
$$;
revoke all on function public.field_chat_send(uuid,text,text,uuid,boolean,uuid) from public,anon;
revoke all on function public.field_chat_page(uuid,boolean) from public,anon;
revoke all on function public.field_chat_preference(boolean,boolean) from public,anon;
grant execute on function public.field_chat_send(uuid,text,text,uuid,boolean,uuid),public.field_chat_page(uuid,boolean),public.field_chat_preference(boolean,boolean) to authenticated;
alter publication supabase_realtime add table public.field_chat_messages,public.field_chat_preferences;

alter table public.field_life_items add column source_url text check(source_url is null or source_url ~ '^https?://');
