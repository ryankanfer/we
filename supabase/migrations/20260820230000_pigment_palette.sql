-- Pigment: eight hue families, and the two colours that stop existing.
--
-- `field_identity` restricted swatch_a to four warm names and swatch_b to
-- four cool ones. Two of those eight are retired: clay was always a lighter
-- rust and slate a lighter indigo, and measuring the palette against two
-- canvases is what showed they were variations rather than families.
--
-- WHAT THIS HAS TO GET RIGHT
--
-- These columns hold a choice somebody made. A migration that drops the
-- constraint and leaves the data would strand rows the new constraint
-- rejects; one that resets them to a default would take the choice away
-- silently, which is worse than an error. So the data moves first, into the
-- family each retired colour was a variation of, and only then does the
-- constraint tighten around it.
--
-- The Swift side mirrors this exactly in `FieldSwatch.retired`, and
-- `FieldSwatch.init(stored:)` is the only door a persisted string goes
-- through — `init(rawValue:)` returns nil for a retired name and every
-- caller had a fallback behind it, which is the migration failing quietly on
-- the one path that matters.
--
-- WHY BOTH COLUMNS NOW ALLOW ALL EIGHT
--
-- The warm and cool split was a way of keeping two people's colours from
-- being nearly the same colour. Pigment does that by measurement instead:
-- every pair of families is at least CIEDE2000 12 apart, and the four pairs
-- whose blend is muddy are handled in the product, after both people commit,
-- by offering nearby variations to both at the same instant. A database
-- constraint encoding a picker's layout would outlive the picker.
--
-- `couple_members.hue` deliberately does not change. It is a separate and
-- older vocabulary, and every value the new swatches bridge to — burgundy,
-- blush, ember, sage, celadon, tide, plum — is already permitted there.

-- MARK: Move the data before tightening around it ---------------------------

alter table public.field_identity
  drop constraint if exists field_identity_swatch_a_check,
  drop constraint if exists field_identity_swatch_b_check;

update public.field_identity
set swatch_a = case swatch_a
      when 'clay' then 'rust'
      when 'slate' then 'indigo'
      else swatch_a
    end,
    swatch_b = case swatch_b
      when 'clay' then 'rust'
      when 'slate' then 'indigo'
      else swatch_b
    end
where swatch_a in ('clay', 'slate') or swatch_b in ('clay', 'slate');

-- MARK: The eight ----------------------------------------------------------

alter table public.field_identity
  alter column swatch_a set default 'burgundy',
  alter column swatch_b set default 'sage';

alter table public.field_identity
  add constraint field_identity_swatch_a_check
    check (swatch_a in ('burgundy', 'rose', 'rust', 'amber',
                        'sage', 'moss', 'teal', 'indigo')),
  add constraint field_identity_swatch_b_check
    check (swatch_b in ('burgundy', 'rose', 'rust', 'amber',
                        'sage', 'moss', 'teal', 'indigo'));

-- MARK: The trigger that fills the other side ------------------------------

-- `private.field_preserve_actor` stamps the *other* person's swatch on
-- insert, so either partner can be the first to finish onboarding. It wrote
-- 'clay' and 'slate' literally, which the new constraint rejects — the one
-- place where leaving this alone turns a palette change into a failed insert
-- on somebody's first evening with the app.
--
-- Reproduced whole from `20260731230000_field_actor_integrity.sql` because a
-- plpgsql body cannot be patched in place, with exactly two literals changed
-- and every other table's handling carried across untouched. Diff it against
-- that migration before editing either.
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
