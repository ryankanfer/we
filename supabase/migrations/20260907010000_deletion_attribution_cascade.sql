begin;

-- Account deletion could not finish, in three separate places.
--
-- `private.delete_my_account()` vacates the membership slot and then deletes
-- the `auth.users` row. That cascades `on delete set null` across every
-- column recording who did something — the shared attribution the survivor
-- keeps. Each cascade arrives as an UPDATE, after the membership row is
-- already gone, and every guard it meets judges it as a client write:
--
--   * `private.prepare_shared_item()` on plans and responsibilities:
--     'not your active WE space'
--   * `private.field_preserve_actor()` on the Field tables:
--     'an active WE membership is required for Field writes'
--   * `invitations_consumed_together`, which reads a consumed invitation
--     whose consumer has left as half a record
--
-- Past the first two guards a second failure waited: both triggers restore
-- attribution from `old`, writing the departing person's id back over the
-- null the cascade had just set.
--
-- This was invisible for a precise reason. Before 20260904120000 the shared
-- guard read `x <> (select public.my_couple_id())`, which evaluates to NULL
-- rather than TRUE once membership is gone — the cascade fell through the
-- very hole that migration closed. And the schema lane has never reached
-- pgTAP: it died at 20260820161957. Asserted by native_product.test.sql
-- 52-64, account_departure.test.sql 5-7, invitation_window.test.sql 14-16.

-- MARK: What a departure looks like -----------------------------------------

-- Deliberately narrow, and named so both triggers agree on it: an UPDATE
-- where nothing but attribution changed, and every attribution column that
-- changed went to NULL. That is the shape of `on delete set null` and
-- nothing else. It cannot move a row between spaces, retitle it, reassign
-- it, or hand attribution to somebody new, because any of those fail the
-- equality test.
--
-- Read through jsonb rather than record fields: the columns differ per table
-- — `owner_id` is on responsibilities and not on plans — and naming one that
-- is absent is exactly what made every plan write fail before 20260904120000.
create or replace function private.is_departure_attribution(
  p_op text,
  p_new jsonb,
  p_old jsonb
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_op = 'UPDATE'
    and p_old is not null
    and (p_new - v.names) = (p_old - v.names)
    and not exists (
      select 1
      from unnest(v.names) as attribution(name)
      where p_new -> attribution.name is distinct from p_old -> attribution.name
        and p_new ->> attribution.name is not null
    )
  from (
    select array[
      'created_by', 'updated_by', 'owner_id', 'added_by', 'changed_by',
      'consumed_by', 'corrected_by', 'hidden_by', 'set_by', 'set_down_by',
      'spoken_by'
    ]::text[] as names
  ) as v;
$$;

revoke all on function private.is_departure_attribution(text, jsonb, jsonb)
  from public, anon, authenticated;

-- MARK: The shared-item guard -----------------------------------------------

create or replace function private.prepare_shared_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if private.is_departure_attribution(tg_op, to_jsonb(new), to_jsonb(old)) then
    -- The database tidying up after someone who left, not a client writing
    -- into a space it does not belong to. Returning here also protects the
    -- null itself: the UPDATE branch below restores `created_by` from `old`,
    -- which would write the departing person's id straight back.
    return new;
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

-- MARK: The Field actor guard ----------------------------------------------

create or replace function private.field_preserve_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims_text text :=
    nullif(current_setting('request.jwt.claims', true), '');
  v_request_role text;
  v_user uuid := (select auth.uid());
  v_side text;
  v_existing_actor uuid;
  v_existing_side text;
begin
  if private.is_departure_attribution(tg_op, to_jsonb(new), to_jsonb(old)) then
    return new;
  end if;

  if v_claims_text is not null then
    v_request_role := v_claims_text::jsonb ->> 'role';
  end if;
  v_request_role := coalesce(
    v_request_role,
    nullif(current_setting('request.jwt.claim.role', true), '')
  );

  -- Direct migration/maintenance connections have no request claims. A
  -- service-role request is trusted explicitly; both need to preserve actors
  -- when importing or repairing historical data.
  if v_request_role is null or v_request_role = 'service_role' then
    return new;
  end if;

  if v_user is null then
    raise exception 'a signed-in profile is required for Field writes'
      using errcode = '42501';
  end if;

  select case cm.member_slot when 1 then 'a' when 2 then 'b' end
  into v_side
  from public.couple_members cm
  where cm.profile_id = v_user;

  if v_side is null then
    raise exception 'an active WE membership is required for Field writes'
      using errcode = '42501';
  end if;

  if tg_table_name = 'field_away_windows' then
    if tg_op = 'INSERT' then
      new.profile_id := v_user;
    else
      new.profile_id := old.profile_id;
    end if;
  elsif tg_table_name = 'field_life_items' then
    if tg_op = 'INSERT' then
      -- The client uses INSERT .. ON CONFLICT for both new rows and edits.
      -- PostgreSQL fires BEFORE INSERT before it resolves that conflict, so
      -- preserve an existing row here or a Partner B edit of A's item would
      -- be rejected before the UPDATE branch ever runs.
      select l.created_by, l.owner
      into v_existing_actor, v_existing_side
      from public.field_life_items l
      where l.id = new.id;

      if found then
        new.created_by := v_existing_actor;
        new.owner := v_existing_side;
      else
        new.created_by := v_user;
        if new.owner <> 'shared' and new.owner <> v_side then
          raise exception 'a Field item cannot be authored as the other partner'
            using errcode = '42501';
        end if;
      end if;
    else
      new.created_by := old.created_by;
      new.owner := old.owner;
    end if;
  elsif tg_table_name = 'field_ours_items' then
    if tg_op = 'INSERT' then
      new.added_by := v_user;
    else
      new.added_by := old.added_by;
    end if;
  elsif tg_table_name = 'field_standing_rules' then
    if tg_op = 'INSERT' then
      new.set_by := v_user;
    else
      new.set_by := old.set_by;
    end if;
  elsif tg_table_name = 'field_captures' then
    if tg_op = 'INSERT' then
      new.spoken_by := v_user;
    else
      new.spoken_by := old.spoken_by;
    end if;
  elsif tg_table_name = 'field_corrections' then
    if tg_op = 'INSERT' then
      new.corrected_by := v_user;
    else
      new.corrected_by := old.corrected_by;
    end if;
  elsif tg_table_name = 'field_horizons' then
    if tg_op = 'INSERT' then
      select h.owner
      into v_existing_side
      from public.field_horizons h
      where h.id = new.id;

      if found then
        new.owner := v_existing_side;
      elsif new.owner <> 'shared' and new.owner <> v_side then
        raise exception 'a Field horizon cannot be authored as the other partner'
          using errcode = '42501';
      end if;
    else
      new.owner := old.owner;
    end if;
  elsif tg_table_name = 'field_evidence' then
    if tg_op = 'INSERT' then
      if new.owner <> 'shared' and new.owner <> v_side then
        raise exception 'Field evidence cannot be authored as the other partner'
          using errcode = '42501';
      end if;
    else
      new.owner := old.owner;
    end if;
  elsif tg_table_name = 'field_clusters' then
    if tg_op = 'INSERT' then
      if new.tint <> 'shared' and new.tint <> v_side then
        raise exception 'a Field cluster cannot be authored as the other partner'
          using errcode = '42501';
      end if;
    else
      new.tint := old.tint;
    end if;
  elsif tg_table_name = 'field_identity' then
    if tg_op = 'INSERT' then
      -- Either partner may be the first person to finish onboarding. The
      -- other side starts from the schema default until that person chooses
      -- their own swatch.
      if v_side = 'a' then
        new.swatch_b := 'sage';
      else
        new.swatch_a := 'burgundy';
      end if;
    elsif v_side = 'a' then
      new.swatch_b := old.swatch_b;
    else
      new.swatch_a := old.swatch_a;
    end if;
  else
    raise exception 'field_preserve_actor is attached to an unknown table: %',
      tg_table_name;
  end if;

  return new;
end;
$$;

revoke all on function private.prepare_shared_item()
  from public, anon, authenticated;
revoke all on function private.field_preserve_actor()
  from public, anon, authenticated;

-- MARK: A consumption whose consumer has left -------------------------------

-- The real invariant is that consumption cannot be recorded without its
-- time. A consumed invitation whose consumer's profile is gone is not half a
-- record — it is a complete one, about a person who is no longer here.
alter table public.invitations
  drop constraint if exists invitations_consumed_together;
alter table public.invitations
  add constraint invitations_consumed_together check (
    consumed_by is null or consumed_at is not null
  );

commit;
