-- Two defects found by the dual-sided lifecycle run.
--
-- 1. private.prepare_shared_item() fires for both public.plans and
--    public.responsibilities, but only responsibilities carry owner_id.
--    PL/pgSQL evaluates an IF condition as a single SQL expression, so the
--    leading tg_table_name test did not short-circuit: on a plans row the
--    planner still resolved new.owner_id and raised
--      record "new" has no field "owner_id"
--    which made every create_plan, update_plan, and set_plan_status fail. The
--    owner check now sits inside its own table-scoped branch.
--
-- 2. Every space guard shaped `x <> (select public.my_couple_id())` evaluates
--    to NULL, not TRUE, for a caller who belongs to no WE space. NULL is not
--    TRUE, so the guard fell through and a signed-in stranger holding a couple
--    id could drive another couple's consent state and write into their Life
--    and Ahead. The comparisons are now null-safe, and the shared-item paths
--    additionally assert membership rather than inferring it.
--    private.assert_v2_member() was already safe: its membership test made the
--    OR true regardless of the NULL comparison.

create or replace function private.prepare_shared_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null
     or new.couple_id is null
     or new.couple_id is distinct from (select public.my_couple_id())
     or not exists (
       select 1
       from public.couple_members cm
       where cm.couple_id = new.couple_id
         and cm.profile_id = v_user
     ) then
    raise exception 'not your active WE space';
  end if;

  -- Account deletion takes FOR UPDATE on this same relationship row.
  -- Mutations already in flight finish first; later ones wait and then fail.
  perform 1
  from public.couples c
  where c.id = new.couple_id
  for key share;
  if not found then
    raise exception 'not your active WE space';
  end if;

  if tg_table_name = 'responsibilities' then
    if new.owner_id is not null
       and not exists (
         select 1
         from public.couple_members cm
         where cm.couple_id = new.couple_id
           and cm.profile_id = new.owner_id
       ) then
      raise exception 'responsibility owner is not in this WE space';
    end if;
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

create or replace function public.assert_my_insight(p_insight uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_user uuid := (select auth.uid());
begin
  select i.couple_id
  into v_couple
  from public.insights i
  where i.id = p_insight;

  if v_user is null
     or v_couple is null
     or v_couple is distinct from (select public.my_couple_id())
     or not exists (
       select 1
       from public.couple_members cm
       where cm.couple_id = v_couple
         and cm.profile_id = v_user
     ) then
    raise exception 'not your insight';
  end if;

  perform 1
  from public.couples c
  where c.id = v_couple
  for key share;
  if not found then
    raise exception 'not your insight';
  end if;

  return v_couple;
end;
$$;

create or replace function public.create_plan(
  p_couple uuid,
  p_title text,
  p_note text default null,
  p_scheduled_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_couple is null
     or p_couple is distinct from (select public.my_couple_id()) then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(p_couple);
  insert into public.plans (
    couple_id, title, note, scheduled_on
  ) values (
    p_couple, trim(p_title), p_note, p_scheduled_on
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.create_responsibility(
  p_couple uuid,
  p_title text,
  p_note text default null,
  p_owner uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_couple is null
     or p_couple is distinct from (select public.my_couple_id()) then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(p_couple);
  insert into public.responsibilities (
    couple_id, title, note, owner_id
  ) values (
    p_couple, trim(p_title), p_note, p_owner
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.prepare_shared_item()
  from public, anon, authenticated;
revoke execute on function public.assert_my_insight(uuid)
  from public, anon, authenticated;
revoke all on function public.create_plan(uuid, text, text, date)
  from public, anon;
revoke all on function public.create_responsibility(uuid, text, text, uuid)
  from public, anon;
grant execute on function public.create_plan(uuid, text, text, date)
  to authenticated;
grant execute on function public.create_responsibility(uuid, text, text, uuid)
  to authenticated;
