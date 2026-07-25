-- WE native product: shared plans/responsibilities, durable appearance,
-- read-only relationship archives, and self-service account deletion.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.couple_members
  add column hue_chosen_at timestamptz;

alter table public.couple_members drop constraint couple_members_hue_check;
alter table public.couple_members add constraint couple_members_hue_check
  check (hue in (
    'burgundy', 'sage', 'ember', 'tide', 'plum',
    'clay', 'pearl', 'mist', 'blush', 'celadon'
  ));

-- A WE space is structurally two-person. Slots provide a database-enforced
-- invariant in addition to the serialized join function below.
alter table public.couple_members add column member_slot smallint;

with ranked_members as (
  select
    couple_id,
    profile_id,
    row_number() over (
      partition by couple_id order by joined_at, profile_id
    ) as slot
  from public.couple_members
)
update public.couple_members cm
set member_slot = ranked_members.slot
from ranked_members
where cm.couple_id = ranked_members.couple_id
  and cm.profile_id = ranked_members.profile_id;

do $$
begin
  if exists (
    select 1 from public.couple_members where member_slot > 2
  ) then
    raise exception 'A WE space already contains more than two members';
  end if;
end;
$$;

alter table public.couple_members
  alter column member_slot set not null,
  add constraint couple_members_slot_check check (member_slot in (1, 2)),
  add constraint couple_members_couple_slot_key unique (couple_id, member_slot);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  note text check (note is null or char_length(note) <= 2000),
  scheduled_on date,
  status text not null default 'active'
    check (status in ('active', 'completed', 'archived')),
  completed_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.responsibilities (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  note text check (note is null or char_length(note) <= 2000),
  owner_id uuid references public.profiles(id) on delete set null,
  status text not null default 'active'
    check (status in ('active', 'completed', 'archived')),
  completed_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Archives are deliberately detached from couples. A live couple is deleted
-- when one account ends it; the surviving profile owns one sanitized snapshot.
create table public.relationship_archives (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  ended_at timestamptz not null,
  snapshot_version smallint not null default 1 check (snapshot_version = 1),
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create index couple_members_profile_id_idx
  on public.couple_members(profile_id);
create index insights_couple_id_idx on public.insights(couple_id);
create index plans_couple_status_date_idx
  on public.plans(couple_id, status, scheduled_on);
create index responsibilities_couple_status_owner_idx
  on public.responsibilities(couple_id, status, owner_id);
create index relationship_archives_owner_ended_idx
  on public.relationship_archives(owner_id, ended_at desc);

-- The helper is used by every live-couple RLS predicate. Wrapping auth.uid()
-- in a scalar select lets Postgres cache the value for the statement.
create or replace function public.my_couple_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select cm.couple_id
  from public.couple_members cm
  where cm.profile_id = (select auth.uid())
  limit 1;
$$;

create or replace function private.prepare_shared_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null or new.couple_id <> (select public.my_couple_id()) then
    raise exception 'not your active WE space';
  end if;

  if tg_table_name = 'responsibilities'
     and new.owner_id is not null
     and not exists (
       select 1
       from public.couple_members cm
       where cm.couple_id = new.couple_id
         and cm.profile_id = new.owner_id
     ) then
    raise exception 'responsibility owner is not in this WE space';
  end if;

  if tg_op = 'INSERT' then
    new.created_by := v_user;
    new.created_at := now();
  else
    if new.couple_id <> old.couple_id then
      raise exception 'a shared item cannot move between WE spaces';
    end if;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;

  new.updated_by := v_user;
  new.updated_at := now();
  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
  elsif new.status = 'active' then
    new.completed_at := null;
  end if;
  return new;
end;
$$;

create trigger plans_prepare_shared_item
  before insert or update on public.plans
  for each row execute function private.prepare_shared_item();

create trigger responsibilities_prepare_shared_item
  before insert or update on public.responsibilities
  for each row execute function private.prepare_shared_item();

alter table public.plans enable row level security;
alter table public.responsibilities enable row level security;
alter table public.relationship_archives enable row level security;

create policy plans_select on public.plans for select to authenticated
  using (couple_id = (select public.my_couple_id()));
create policy plans_insert on public.plans for insert to authenticated
  with check (couple_id = (select public.my_couple_id()));
create policy plans_update on public.plans for update to authenticated
  using (couple_id = (select public.my_couple_id()))
  with check (couple_id = (select public.my_couple_id()));

create policy responsibilities_select on public.responsibilities
  for select to authenticated
  using (couple_id = (select public.my_couple_id()));
create policy responsibilities_insert on public.responsibilities
  for insert to authenticated
  with check (couple_id = (select public.my_couple_id()));
create policy responsibilities_update on public.responsibilities
  for update to authenticated
  using (couple_id = (select public.my_couple_id()))
  with check (couple_id = (select public.my_couple_id()));

create policy relationship_archives_select on public.relationship_archives
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy couple_members_update_own on public.couple_members
  for update to authenticated
  using (
    profile_id = (select auth.uid())
    and couple_id = (select public.my_couple_id())
  )
  with check (
    profile_id = (select auth.uid())
    and couple_id = (select public.my_couple_id())
  );

grant select, insert, update on public.plans to authenticated;
grant select, insert, update on public.responsibilities to authenticated;
grant select on public.relationship_archives to authenticated;
grant select, update(name) on public.profiles to authenticated;
grant select, update(hue, hue_chosen_at) on public.couple_members to authenticated;
grant select on public.couples, public.insights, public.insight_consent,
  public.responses, public.dismissals, public.reflections to authenticated;
grant insert on public.reflections to authenticated;

alter publication supabase_realtime add table public.plans;
alter publication supabase_realtime add table public.responsibilities;
alter publication supabase_realtime add table public.relationship_archives;

-- This privileged operation is kept out of the exposed public schema. The
-- public wrapper is security-invoker and authenticated-only.
create or replace function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid;
  v_survivor uuid;
  v_ended timestamptz := now();
  v_snapshot jsonb;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;

  select cm.couple_id
  into v_couple
  from public.couple_members cm
  where cm.profile_id = v_user
  limit 1
  for update;

  if v_couple is not null then
    select cm.profile_id
    into v_survivor
    from public.couple_members cm
    where cm.couple_id = v_couple
      and cm.profile_id <> v_user
    limit 1;

    if v_survivor is not null then
      v_snapshot := jsonb_build_object(
        'plans', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', p.id,
            'title', p.title,
            'note', p.note,
            'scheduledOn', p.scheduled_on,
            'status', p.status,
            'completedAt', p.completed_at,
            'updatedAt', p.updated_at
          ) order by p.created_at)
          from public.plans p
          where p.couple_id = v_couple
        ), '[]'::jsonb),
        'responsibilities', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', r.id,
            'title', r.title,
            'note', r.note,
            'ownership', case
              when r.owner_id is null then 'together'
              when r.owner_id = v_survivor then 'me'
              else 'partner'
            end,
            'status', r.status,
            'completedAt', r.completed_at,
            'updatedAt', r.updated_at
          ) order by r.created_at)
          from public.responsibilities r
          where r.couple_id = v_couple
        ), '[]'::jsonb),
        'resolutions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'insightID', i.id,
            'title', i.title,
            'resolutionType', ic.resolution_type,
            'resolutionChoice', ic.resolution_choice,
            'resolvedAt', ic.resolved_at
          ) order by ic.resolved_at)
          from public.insights i
          join public.insight_consent ic on ic.insight_id = i.id
          where i.couple_id = v_couple
            and ic.resolution_type is not null
        ), '[]'::jsonb)
      );

      insert into public.relationship_archives (
        owner_id, ended_at, snapshot_version, snapshot
      ) values (v_survivor, v_ended, 1, v_snapshot);
    end if;

    delete from public.couples where id = v_couple;
  end if;

  delete from auth.users where id = v_user;
end;
$$;

create or replace function public.delete_my_account()
returns void
language sql
security definer
set search_path = ''
as $$
  select private.delete_my_account();
$$;

revoke all on function private.prepare_shared_item() from public, anon, authenticated;
revoke all on function private.delete_my_account() from public, anon, authenticated;
revoke all on function public.delete_my_account() from public, anon;
revoke execute on function public.my_couple_id() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.my_couple_id() to authenticated;

-- Replace the original pairing RPCs so joins serialize on the couple row and
-- both creation paths satisfy the two-slot invariant.
create or replace function public.create_couple()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_code text;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if (select public.my_couple_id()) is not null then
    raise exception 'already in a couple';
  end if;

  v_code := public.gen_join_code();
  insert into public.couples (join_code, created_by)
  values (v_code, (select auth.uid()))
  returning id into v_couple;

  insert into public.couple_members (
    couple_id, profile_id, hue, member_slot
  ) values (
    v_couple, (select auth.uid()), 'burgundy', 1
  );
  perform public.seed_couple_insights(v_couple);
  return json_build_object('couple_id', v_couple, 'join_code', v_code);
end;
$$;

create or replace function public.join_couple(p_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if (select public.my_couple_id()) is not null then
    raise exception 'already in a couple';
  end if;

  -- The row lock makes concurrent join attempts take turns.
  select c.id
  into v_couple
  from public.couples c
  where c.join_code = upper(trim(p_code))
  for update;

  if v_couple is null then
    raise exception 'that code does not match anything';
  end if;

  select count(*) into v_count
  from public.couple_members cm
  where cm.couple_id = v_couple;

  if v_count >= 2 then
    raise exception 'this space already has two people';
  end if;

  insert into public.couple_members (
    couple_id, profile_id, hue, member_slot
  ) values (
    v_couple, (select auth.uid()), 'sage', 2
  );
  return json_build_object('couple_id', v_couple);
end;
$$;

revoke execute on function public.create_couple() from public, anon;
revoke execute on function public.join_couple(text) from public, anon;
grant execute on function public.create_couple() to authenticated;
grant execute on function public.join_couple(text) to authenticated;
