begin;

-- Account deletion could not finish.
--
-- `private.delete_my_account()` vacates the membership slot and then deletes
-- the `auth.users` row, which cascades `on delete set null` onto the shared
-- attribution the survivor keeps — `plans.created_by`, `plans.updated_by`,
-- `responsibilities.owner_id`. That cascade is an UPDATE, so
-- `private.prepare_shared_item()` fires on it, finds the membership row
-- already gone, and raises 'not your active WE space'. The deletion aborts.
--
-- Two things were wrong, and the second would have survived a fix to the
-- first: had the row reached the assignments below, `new.created_by :=
-- old.created_by` would have written the departing person's id straight back
-- over the null the cascade had just set.
--
-- This was invisible until now for a precise reason. Before
-- 20260904120000 the guard read `x <> (select public.my_couple_id())`, which
-- evaluates to NULL rather than TRUE once the membership is gone — so the
-- cascade fell through the hole that migration was written to close. Closing
-- it broke deletion, and the schema lane has never run pgTAP (it died at
-- 20260820161957), so nothing said so. Asserted by native_product.test.sql
-- tests 52-64.
--
-- The exemption is deliberately the exact shape of that cascade and nothing
-- else: an UPDATE where every column but the attribution ones is untouched,
-- and every attribution column that did change went to NULL. A client cannot
-- reach it — INSERT and UPDATE on both tables are already revoked from
-- `authenticated` — and it cannot be used to move, retitle, or reassign
-- anything, because any such change fails the equality test.

create or replace function private.prepare_shared_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  -- Read through jsonb rather than record fields: `owner_id` exists on
  -- responsibilities and not on plans, and naming it directly is what made
  -- every plan write fail before 20260904120000.
  v_attribution constant text[] := array['created_by', 'updated_by', 'owner_id'];
  v_new jsonb;
  v_old jsonb;
begin
  if tg_op = 'UPDATE' then
    v_new := to_jsonb(new);
    v_old := to_jsonb(old);
    if (v_new - v_attribution) = (v_old - v_attribution)
       and not exists (
         select 1
         from unnest(v_attribution) as attribution(name)
         where v_new -> attribution.name
                 is distinct from v_old -> attribution.name
           and v_new ->> attribution.name is not null
       ) then
      -- The database tidying up after someone who left, not a client
      -- writing into a space it does not belong to.
      return new;
    end if;
  end if;

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

revoke all on function private.prepare_shared_item()
  from public, anon, authenticated;

commit;
