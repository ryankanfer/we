-- Private intake publication.
--
-- The Share Extension never writes to these tables. It writes an encrypted,
-- account-isolated local draft. Only the containing app can create an
-- immutable publication session after exact review.

create schema if not exists private;

create table public.share_publication_sessions (
  id uuid primary key,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  created_by uuid not null
    references public.profiles(id) on delete cascade,
  draft_id uuid not null,
  revision integer not null check (revision > 0),
  title text not null check (char_length(title) between 1 and 180),
  body text not null default '' check (char_length(body) <= 5000),
  category text not null check (
    category ~ '^[a-z]+( [a-z]+)?$'
    and char_length(category) between 3 and 18
    and category <> 'calendar'
  ),
  expected_urls jsonb not null default '[]'::jsonb
    check (jsonb_typeof(expected_urls) = 'array'),
  expected_resources jsonb not null default '[]'::jsonb
    check (jsonb_typeof(expected_resources) = 'array'),
  state text not null default 'created'
    check (state in ('created', 'finalized', 'retired')),
  life_item_id uuid
    references public.field_life_items(id) on delete set null,
  created_at timestamptz not null default now(),
  finalized_at timestamptz,
  retired_at timestamptz,
  unique (created_by, draft_id, revision)
);

create index share_publication_sessions_couple_idx
  on public.share_publication_sessions(couple_id, created_at desc);

create table public.field_life_resources (
  id uuid primary key,
  life_item_id uuid not null
    references public.field_life_items(id) on delete cascade,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  created_by uuid
    references public.profiles(id) on delete set null,
  kind text not null check (kind in ('url', 'image')),
  url text,
  object_path text,
  sha256 text,
  content_type text,
  byte_count integer,
  created_at timestamptz not null default now(),
  check (
    (
      kind = 'url'
      and url is not null
      and object_path is null
      and sha256 is null
      and content_type is null
      and byte_count is null
    )
    or
    (
      kind = 'image'
      and url is null
      and object_path is not null
      and sha256 ~ '^[0-9a-f]{64}$'
      and content_type in ('image/jpeg', 'image/png')
      and byte_count between 1 and 8388608
    )
  )
);

create unique index field_life_resources_object_path_idx
  on public.field_life_resources(object_path)
  where object_path is not null;
create index field_life_resources_item_idx
  on public.field_life_resources(life_item_id);
create index field_life_resources_couple_idx
  on public.field_life_resources(couple_id, created_at desc);

create table private.share_storage_cleanup_jobs (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid,
  resource_id uuid,
  object_path text not null unique,
  state text not null default 'pending'
    check (state in ('pending', 'processing', 'done')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index share_cleanup_pending_idx
  on private.share_storage_cleanup_jobs(available_at, created_at)
  where state = 'pending';

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'life-resources',
  'life-resources',
  false,
  8388608,
  array['image/jpeg', 'image/png']::text[]
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- MARK: Validation ---------------------------------------------------------

create or replace function private.share_validate_urls(p_urls jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_url jsonb;
begin
  if jsonb_typeof(p_urls) <> 'array'
     or jsonb_array_length(p_urls) > 5 then
    raise exception 'invalid url manifest';
  end if;

  if (
    select count(*) <> count(distinct value ->> 'id')
    from jsonb_array_elements(p_urls)
  ) then
    raise exception 'duplicate url id';
  end if;
  if (
    select count(*) <> count(distinct value ->> 'url')
    from jsonb_array_elements(p_urls)
  ) then
    raise exception 'duplicate reviewed url';
  end if;

  for v_url in select value from jsonb_array_elements(p_urls)
  loop
    if jsonb_typeof(v_url) <> 'object'
       or v_url - array['id', 'url'] <> '{}'::jsonb
       or coalesce(v_url ->> 'id', '') !~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(v_url ->> 'url', '') !~
          '^https://[^/@[:space:]]+([/:?#][^[:space:]]*)?$'
       or char_length(v_url ->> 'url') > 2048 then
      raise exception 'invalid reviewed url';
    end if;
  end loop;
end;
$$;

create or replace function private.share_validate_resources(
  p_resources jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_resource jsonb;
begin
  if jsonb_typeof(p_resources) <> 'array'
     or jsonb_array_length(p_resources) > 5 then
    raise exception 'invalid resource manifest';
  end if;

  if (
    select count(*) <> count(distinct value ->> 'id')
    from jsonb_array_elements(p_resources)
  ) then
    raise exception 'duplicate resource id';
  end if;
  if (
    select count(*) <> count(distinct value ->> 'sha256')
    from jsonb_array_elements(p_resources)
  ) then
    raise exception 'duplicate reviewed resource';
  end if;

  for v_resource in select value from jsonb_array_elements(p_resources)
  loop
    if jsonb_typeof(v_resource) <> 'object'
       or v_resource
          - array['id', 'sha256', 'content_type', 'byte_count']
          <> '{}'::jsonb
       or coalesce(v_resource ->> 'id', '') !~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(v_resource ->> 'sha256', '') !~ '^[0-9a-f]{64}$'
       or coalesce(v_resource ->> 'content_type', '') not in (
         'image/jpeg',
         'image/png'
       )
       or coalesce((v_resource ->> 'byte_count')::bigint, 0)
          not between 1 and 8388608 then
      raise exception 'invalid reviewed resource';
    end if;
  end loop;
end;
$$;

-- MARK: Session creation ---------------------------------------------------

create or replace function public.share_create_publication_session(
  p_snapshot uuid,
  p_draft uuid,
  p_revision integer,
  p_title text,
  p_body text,
  p_category text,
  p_urls jsonb default '[]'::jsonb,
  p_resources jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_couple uuid := public.my_couple_id();
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_expected jsonb := '[]'::jsonb;
  v_resource jsonb;
  v_extension text;
  v_existing public.share_publication_sessions%rowtype;
begin
  if v_user is null or v_couple is null then
    raise exception 'not signed into a relationship';
  end if;
  if p_snapshot is null or p_draft is null or p_revision < 1 then
    raise exception 'invalid publication identity';
  end if;
  if char_length(v_title) not between 1 and 180
     or char_length(v_body) > 5000 then
    raise exception 'invalid reviewed copy';
  end if;
  if p_category !~ '^[a-z]+( [a-z]+)?$'
     or char_length(p_category) not between 3 and 18
     or p_category = 'calendar' then
    raise exception 'invalid life destination';
  end if;

  perform private.share_validate_urls(p_urls);
  perform private.share_validate_resources(p_resources);

  if exists (
    select 1
    from jsonb_array_elements(p_urls) u
    join jsonb_array_elements(p_resources) r
      on u ->> 'id' = r ->> 'id'
  ) then
    raise exception 'resource identities overlap';
  end if;

  for v_resource in
    select value from jsonb_array_elements(p_resources)
  loop
    v_extension := case v_resource ->> 'content_type'
      when 'image/png' then '.png'
      else '.jpg'
    end;
    v_expected := v_expected || jsonb_build_array(
      (v_resource - 'id') || jsonb_build_object(
        'resource_id', v_resource ->> 'id',
        'object_path',
          v_couple::text || '/' ||
          p_snapshot::text || '/' ||
          (v_resource ->> 'id') || v_extension
      ) - 'id'
    );
  end loop;

  insert into public.share_publication_sessions (
    id,
    couple_id,
    created_by,
    draft_id,
    revision,
    title,
    body,
    category,
    expected_urls,
    expected_resources
  )
  values (
    p_snapshot,
    v_couple,
    v_user,
    p_draft,
    p_revision,
    v_title,
    v_body,
    p_category,
    p_urls,
    v_expected
  )
  on conflict (id) do nothing;

  select *
  into v_existing
  from public.share_publication_sessions
  where id = p_snapshot
  for update;

  if not found
     or v_existing.created_by <> v_user
     or v_existing.couple_id <> v_couple
     or v_existing.draft_id <> p_draft
     or v_existing.revision <> p_revision
     or v_existing.title <> v_title
     or v_existing.body <> v_body
     or v_existing.category <> p_category
     or v_existing.expected_urls <> p_urls
     or v_existing.expected_resources <> v_expected then
    raise exception 'publication identity was reused with different content';
  end if;
  if v_existing.state = 'retired' then
    raise exception 'publication revision was retired';
  end if;

  return jsonb_build_object(
    'id', v_existing.id,
    'uploads', v_existing.expected_resources
  );
end;
$$;

-- MARK: Finalization -------------------------------------------------------

create or replace function public.share_finalize_publication(
  p_session uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_couple uuid := public.my_couple_id();
  v_session public.share_publication_sessions%rowtype;
  v_resource jsonb;
  v_url jsonb;
  v_item uuid;
  v_expected_count integer;
  v_actual_count integer;
begin
  if v_user is null or v_couple is null then
    raise exception 'not signed into a relationship';
  end if;

  select *
  into v_session
  from public.share_publication_sessions
  where id = p_session
  for update;

  if not found
     or v_session.created_by <> v_user
     or v_session.couple_id <> v_couple then
    raise exception 'publication session unavailable';
  end if;

  -- Membership is checked before returning an old result. A lost response is
  -- idempotent for a current member, never a way back into a former couple.
  if v_session.state = 'finalized' then
    return jsonb_build_object('life_item_id', v_session.life_item_id);
  end if;
  if v_session.state <> 'created' then
    raise exception 'publication session is not active';
  end if;

  v_expected_count := jsonb_array_length(v_session.expected_resources);
  select count(*)::integer
  into v_actual_count
  from storage.objects o
  where o.bucket_id = 'life-resources'
    and o.name like (
      v_session.couple_id::text || '/' ||
      v_session.id::text || '/%'
    );

  if v_actual_count <> v_expected_count then
    raise exception 'uploaded resource set does not match review';
  end if;

  for v_resource in
    select value
    from jsonb_array_elements(v_session.expected_resources)
  loop
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'life-resources'
        and o.name = v_resource ->> 'object_path'
        and coalesce(
          to_jsonb(o) -> 'user_metadata' ->> 'sha256',
          o.metadata -> 'metadata' ->> 'sha256',
          o.metadata ->> 'sha256'
        ) = v_resource ->> 'sha256'
        and coalesce(
          to_jsonb(o) -> 'user_metadata' ->> 'resource_id',
          o.metadata -> 'metadata' ->> 'resource_id',
          o.metadata ->> 'resource_id'
        ) = v_resource ->> 'resource_id'
        and coalesce((o.metadata ->> 'size')::bigint, -1)
          = (v_resource ->> 'byte_count')::bigint
    ) then
      raise exception 'uploaded resource failed verification';
    end if;
  end loop;

  v_item := gen_random_uuid();
  insert into public.field_life_items (
    id,
    couple_id,
    title,
    category,
    owner,
    source,
    detail,
    is_time_critical,
    is_done,
    created_by
  )
  values (
    v_item,
    v_couple,
    v_session.title,
    v_session.category,
    'shared',
    'captured',
    nullif(v_session.body, ''),
    false,
    false,
    v_user
  );

  for v_url in
    select value from jsonb_array_elements(v_session.expected_urls)
  loop
    insert into public.field_life_resources (
      id,
      life_item_id,
      couple_id,
      created_by,
      kind,
      url
    )
    values (
      (v_url ->> 'id')::uuid,
      v_item,
      v_couple,
      v_user,
      'url',
      v_url ->> 'url'
    );
  end loop;

  for v_resource in
    select value
    from jsonb_array_elements(v_session.expected_resources)
  loop
    insert into public.field_life_resources (
      id,
      life_item_id,
      couple_id,
      created_by,
      kind,
      object_path,
      sha256,
      content_type,
      byte_count
    )
    values (
      (v_resource ->> 'resource_id')::uuid,
      v_item,
      v_couple,
      v_user,
      'image',
      v_resource ->> 'object_path',
      v_resource ->> 'sha256',
      v_resource ->> 'content_type',
      (v_resource ->> 'byte_count')::integer
    );
  end loop;

  update public.share_publication_sessions
  set
    state = 'finalized',
    life_item_id = v_item,
    finalized_at = now()
  where id = v_session.id;

  return jsonb_build_object('life_item_id', v_item);
end;
$$;

-- MARK: Retirement and deletion -------------------------------------------

create or replace function public.share_retire_publication_session(
  p_session uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_couple uuid := public.my_couple_id();
  v_session public.share_publication_sessions%rowtype;
  v_resource jsonb;
begin
  select *
  into v_session
  from public.share_publication_sessions
  where id = p_session
  for update;

  if v_user is null
     or v_couple is null
     or not found
     or v_session.created_by <> v_user
     or v_session.couple_id <> v_couple then
    raise exception 'publication session unavailable';
  end if;
  if v_session.state = 'finalized' then
    raise exception 'a released revision cannot be retired';
  end if;
  if v_session.state = 'retired' then
    return;
  end if;

  for v_resource in
    select value
    from jsonb_array_elements(v_session.expected_resources)
  loop
    insert into private.share_storage_cleanup_jobs (
      couple_id,
      resource_id,
      object_path
    )
    values (
      v_session.couple_id,
      (v_resource ->> 'resource_id')::uuid,
      v_resource ->> 'object_path'
    )
    on conflict (object_path) do nothing;
  end loop;

  update public.share_publication_sessions
  set state = 'retired', retired_at = now()
  where id = p_session;
end;
$$;

create or replace function private.queue_life_resource_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.kind = 'image' and old.object_path is not null then
    insert into private.share_storage_cleanup_jobs (
      couple_id,
      resource_id,
      object_path
    )
    values (old.couple_id, old.id, old.object_path)
    on conflict (object_path) do nothing;
  end if;
  return old;
end;
$$;

create trigger field_life_resources_cleanup
before delete on public.field_life_resources
for each row execute function private.queue_life_resource_cleanup();

-- A deleted account or relationship can cascade through an unfinished upload
-- session before it ever created field_life_resources rows. Queue only those
-- unfinished objects here: finalized resources belong to the shared LIFE item
-- and deliberately survive creator-account deletion while the couple exists.
create or replace function private.queue_unreleased_session_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource jsonb;
begin
  if old.state <> 'finalized' then
    for v_resource in
      select value from jsonb_array_elements(old.expected_resources)
    loop
      insert into private.share_storage_cleanup_jobs (
        couple_id,
        resource_id,
        object_path
      )
      values (
        old.couple_id,
        (v_resource ->> 'resource_id')::uuid,
        v_resource ->> 'object_path'
      )
      on conflict (object_path) do nothing;
    end loop;
  end if;
  return old;
end;
$$;

create trigger share_publication_sessions_cleanup
before delete on public.share_publication_sessions
for each row execute function private.queue_unreleased_session_cleanup();

create or replace function public.share_remove_life_resource(
  p_resource uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.my_couple_id() is null then
    raise exception 'not signed into a relationship';
  end if;

  delete from public.field_life_resources
  where id = p_resource
    and couple_id = public.my_couple_id();

  if not found then
    raise exception 'resource unavailable';
  end if;
end;
$$;

create or replace function public.share_delete_life_item(
  p_item uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.my_couple_id() is null then
    raise exception 'not signed into a relationship';
  end if;

  delete from public.field_life_items
  where id = p_item
    and couple_id = public.my_couple_id();

  if not found then
    raise exception 'life item unavailable';
  end if;
end;
$$;

-- MARK: Server-owned cleanup worker ---------------------------------------

create or replace function private.expire_unreleased_publications()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.share_publication_sessions%rowtype;
  v_resource jsonb;
begin
  for v_session in
    select *
    from public.share_publication_sessions
    where state = 'created'
      and created_at < now() - interval '30 days'
    order by created_at
    limit 100
    for update skip locked
  loop
    for v_resource in
      select value
      from jsonb_array_elements(v_session.expected_resources)
    loop
      insert into private.share_storage_cleanup_jobs (
        couple_id,
        resource_id,
        object_path
      )
      values (
        v_session.couple_id,
        (v_resource ->> 'resource_id')::uuid,
        v_resource ->> 'object_path'
      )
      on conflict (object_path) do nothing;
    end loop;

    update public.share_publication_sessions
    set state = 'retired', retired_at = now()
    where id = v_session.id;
  end loop;
end;
$$;

create or replace function public.share_claim_cleanup_jobs(
  p_limit integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_jobs jsonb;
begin
  if p_limit not between 1 and 100 then
    raise exception 'invalid cleanup batch';
  end if;

  perform private.expire_unreleased_publications();

  with candidates as (
    select id
    from private.share_storage_cleanup_jobs
    where (
      state = 'pending'
      and available_at <= now()
    ) or (
      state = 'processing'
      and locked_at < now() - interval '15 minutes'
    )
    order by created_at
    limit p_limit
    for update skip locked
  ),
  claimed as (
    update private.share_storage_cleanup_jobs j
    set
      state = 'processing',
      locked_at = now(),
      attempts = attempts + 1
    from candidates c
    where j.id = c.id
    returning j.id, j.object_path
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('id', id, 'object_path', object_path)
      order by id
    ),
    '[]'::jsonb
  )
  into v_jobs
  from claimed;

  return v_jobs;
end;
$$;

create or replace function public.share_complete_cleanup_job(
  p_job uuid,
  p_succeeded boolean,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_succeeded then
    update private.share_storage_cleanup_jobs
    set
      state = 'done',
      completed_at = now(),
      locked_at = null,
      last_error_code = null
    where id = p_job and state = 'processing';
  else
    update private.share_storage_cleanup_jobs
    set
      state = 'pending',
      available_at = now() + (
        least(3600, (30 * power(2, least(attempts, 7)))::integer)
        * interval '1 second'
      ),
      locked_at = null,
      last_error_code = left(coalesce(p_error_code, 'unknown'), 80)
    where id = p_job and state = 'processing';
  end if;

  if not found then
    raise exception 'cleanup job unavailable';
  end if;
end;
$$;

-- MARK: RLS and grants -----------------------------------------------------

alter table public.share_publication_sessions enable row level security;
alter table public.field_life_resources enable row level security;
-- Internal-only queue: no client policies. Security-definer worker functions
-- remain the sole access path, while RLS supplies defense in depth.
alter table private.share_storage_cleanup_jobs enable row level security;

create policy share_publication_sessions_select
on public.share_publication_sessions
for select
using (
  created_by = (select auth.uid())
  and couple_id = (select public.my_couple_id())
);

create policy field_life_resources_select
on public.field_life_resources
for select
using (couple_id = (select public.my_couple_id()));

revoke all on table public.share_publication_sessions
  from public, anon, authenticated;
revoke all on table public.field_life_resources
  from public, anon, authenticated;
grant select on table public.share_publication_sessions to authenticated;
grant select on table public.field_life_resources to authenticated;

-- The uploader may touch only a server-generated path in its own current,
-- unretired session. Hash and resource id metadata must match the review.
create policy life_resources_upload
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'life-resources'
  and exists (
    select 1
    from public.share_publication_sessions s
    cross join lateral jsonb_array_elements(s.expected_resources) r
    where s.created_by = (select auth.uid())
      and s.couple_id = (select public.my_couple_id())
      and s.state = 'created'
      and r ->> 'object_path' = name
      and r ->> 'sha256' = coalesce(
        to_jsonb(objects) -> 'user_metadata' ->> 'sha256',
        metadata -> 'metadata' ->> 'sha256',
        metadata ->> 'sha256'
      )
      and r ->> 'resource_id' = coalesce(
        to_jsonb(objects) -> 'user_metadata' ->> 'resource_id',
        metadata -> 'metadata' ->> 'resource_id',
        metadata ->> 'resource_id'
      )
  )
);

create policy life_resources_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'life-resources'
  and exists (
    select 1
    from public.share_publication_sessions s
    cross join lateral jsonb_array_elements(s.expected_resources) r
    where s.created_by = (select auth.uid())
      and s.couple_id = (select public.my_couple_id())
      and s.state = 'created'
      and r ->> 'object_path' = name
  )
)
with check (
  bucket_id = 'life-resources'
  and exists (
    select 1
    from public.share_publication_sessions s
    cross join lateral jsonb_array_elements(s.expected_resources) r
    where s.created_by = (select auth.uid())
      and s.couple_id = (select public.my_couple_id())
      and s.state = 'created'
      and r ->> 'object_path' = name
      and r ->> 'sha256' = coalesce(
        to_jsonb(objects) -> 'user_metadata' ->> 'sha256',
        metadata -> 'metadata' ->> 'sha256',
        metadata ->> 'sha256'
      )
      and r ->> 'resource_id' = coalesce(
        to_jsonb(objects) -> 'user_metadata' ->> 'resource_id',
        metadata -> 'metadata' ->> 'resource_id',
        metadata ->> 'resource_id'
      )
  )
);

create policy life_resources_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'life-resources'
  and (
    exists (
      select 1
      from public.field_life_resources r
      where r.kind = 'image'
        and r.object_path = name
        and r.couple_id = (select public.my_couple_id())
    )
    or exists (
      select 1
      from public.share_publication_sessions s
      cross join lateral jsonb_array_elements(s.expected_resources) r
      where s.created_by = (select auth.uid())
        and s.couple_id = (select public.my_couple_id())
        and s.state = 'created'
        and r ->> 'object_path' = name
    )
  )
);

revoke execute on function public.share_create_publication_session(
  uuid, uuid, integer, text, text, text, jsonb, jsonb
) from public, anon, authenticated;
revoke execute on function public.share_finalize_publication(uuid)
  from public, anon, authenticated;
revoke execute on function public.share_retire_publication_session(uuid)
  from public, anon, authenticated;
revoke execute on function public.share_remove_life_resource(uuid)
  from public, anon, authenticated;
revoke execute on function public.share_delete_life_item(uuid)
  from public, anon, authenticated;
revoke execute on function public.share_claim_cleanup_jobs(integer)
  from public, anon, authenticated;
revoke execute on function public.share_complete_cleanup_job(
  uuid, boolean, text
) from public, anon, authenticated;

grant execute on function public.share_create_publication_session(
  uuid, uuid, integer, text, text, text, jsonb, jsonb
) to authenticated;
grant execute on function public.share_finalize_publication(uuid)
  to authenticated;
grant execute on function public.share_retire_publication_session(uuid)
  to authenticated;
grant execute on function public.share_remove_life_resource(uuid)
  to authenticated;
grant execute on function public.share_delete_life_item(uuid)
  to authenticated;
grant execute on function public.share_claim_cleanup_jobs(integer)
  to service_role;
grant execute on function public.share_complete_cleanup_job(
  uuid, boolean, text
) to service_role;

revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private
  from public, anon, authenticated;
revoke all on all functions in schema private
  from public, anon, authenticated;

comment on table public.share_publication_sessions is
  'Immutable reviewed share attempts. Raw intake text is never stored here.';
comment on table private.share_storage_cleanup_jobs is
  'Server-owned trusted Storage object cleanup queue; never client writable.';
