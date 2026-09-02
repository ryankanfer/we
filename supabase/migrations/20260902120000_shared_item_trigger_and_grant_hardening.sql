-- Two beta blockers found by running the pgTAP suites for the first time.
--
-- 1. Every write to `plans` failed.
--
--    `private.prepare_shared_item()` backs the BEFORE trigger on both `plans`
--    and `responsibilities`. Its ownership check read `new.owner_id` inside the
--    same IF condition that tests `tg_table_name = 'responsibilities'`. plpgsql
--    compiles a whole IF condition as one SQL expression, so the field
--    reference is resolved against the actual row type before the table guard
--    can short-circuit. `plans` has no `owner_id`, so every plan insert and
--    update raised 42703 "record \"new\" has no field \"owner_id\"".
--
--    That took out `create_plan`, `update_plan` and `set_plan_status`, which is
--    the whole "Add something ahead" path — and the Ahead tab only appears once
--    a plan exists, so it could never unlock. Reading the field through jsonb
--    keeps one trigger correct for both row shapes.
--
-- 2. `authenticated` still held INSERT, UPDATE and DELETE on the relationship
--    tables. Only RLS stood between a client and a forged Thread event, Season,
--    consent row, or a row in someone else's `responses`. The trust model is
--    meant to be enforced twice; this restores the second layer, so a future
--    permissive policy cannot by itself open a write path. Reads, the RPCs, and
--    the three genuine client writes (own name, own hue, own reflection) are
--    unchanged.

create or replace function private.prepare_shared_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_owner uuid;
begin
  if v_user is null or new.couple_id <> (select public.my_couple_id()) then
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

  -- Read owner_id through jsonb: `plans` has no such column, and a direct
  -- new.owner_id reference is resolved for every row type this trigger sees.
  if tg_table_name = 'responsibilities' then
    v_owner := nullif(
      pg_catalog.to_jsonb(new) ->> 'owner_id',
      ''
    )::uuid;

    if v_owner is not null
       and not exists (
         select 1
         from public.couple_members cm
         where cm.couple_id = new.couple_id
           and cm.profile_id = v_owner
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

revoke all on function private.prepare_shared_item()
  from public, anon, authenticated;

-- Relationship state is written by SECURITY DEFINER functions only. Clients
-- read; they never write these tables directly.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles',
    'couples',
    'couple_members',
    'insights',
    'insight_consent',
    'responses',
    'dismissals',
    'reflections',
    'insight_declines',
    'insight_grace',
    'relationship_archives',
    'relationship_presence',
    'signal_consents',
    'anchors',
    'responsibility_handoffs',
    'plan_approaches',
    'relationship_events',
    'seasons',
    'contextual_suggestions',
    'contextual_suggestion_dismissals'
  ]
  loop
    execute format(
      'revoke insert, update, delete, truncate on public.%I from anon, authenticated',
      v_table
    );
  end loop;
end;
$$;

-- The three writes a client genuinely makes on its own behalf.
grant update(name) on public.profiles to authenticated;
grant update(hue, hue_chosen_at) on public.couple_members to authenticated;
grant insert on public.reflections to authenticated;
