-- One person leaves, the other keeps the field. Phase 2c, and a P0.
--
-- WHAT IS WRONG TODAY
--
-- `private.delete_my_account()` was written on 2026-07-25, against a product
-- that had `plans`, `responsibilities` and `insights` in it. It has not been
-- revised through the v2 rewrite, the Field zones, Yours, or private intake.
-- It does two things, and both are now wrong:
--
--   1. `delete from public.couples where id = v_couple` — which cascades
--      through twenty-nine tables and destroys the *entire shared field*.
--      Every LIFE item, every ours item, every season, horizon, rhythm and
--      capture the two people built together. The person who did not delete
--      anything loses all of it, silently, with no event and no warning.
--
--   2. It writes a `relationship_archives` row to soften that, holding a
--      snapshot of `plans`, `responsibilities` and resolved `insight_consent`.
--      Nothing under `WE/WE/Field/` has written to those tables since the v2
--      rewrite, and the only screen that reads an archive back is
--      `ProfileView.swift`, which the Field shell replaced. So the consolation
--      is empty in practice and unreachable in fact.
--
-- The net effect is the worst available outcome: A deletes their account, and
-- B's relationship record is destroyed by a decision B was never party to.
--
-- THE RULE THIS MIGRATION APPLIES
--
-- It is already written down, in `20260807042919:600`:
--
--   "finalized resources belong to the shared LIFE item and deliberately
--    survive creator-account deletion while the couple exists."
--
-- Generalised: **the shared field belongs to the couple, not to either
-- author.** One person leaving takes their own material with them and leaves
-- the shared record standing. So:
--
--   stays   shared-era rows in couple-scoped tables, whoever authored them
--   goes    solo-era (`visibility = 'private'`) rows the leaver authored
--   goes    everything owner-scoped — yours_*, private_proposals,
--           signal_consents, insight_declines, field_away_windows
--
-- The couple row itself survives, one member lighter, and the survivor is
-- back in the solo era that `20260803180000` already models. A person with no
-- partner still takes the whole couple with them, exactly as before.
--
-- WHY THE PRIVATE ROWS NEED AN EXPLICIT DELETE
--
-- They would not be reached by any cascade — they hang off `couples`, which
-- now survives — and their actor column is `on delete set null`. The select
-- policy from `20260803180000:322` is
--
--   couple_id = public.my_couple_id()
--     and (visibility = 'shared' or <actor> = (select auth.uid()))
--
-- so a private row whose actor has become null satisfies neither branch. It
-- is visible to nobody, and because UPDATE and DELETE carry the same
-- predicate, it is deletable by nobody either. Leaving them behind does not
-- leak anything — it accumulates rows that no longer have a living owner and
-- that the API can never reach again. They are deleted here, before the
-- profile cascade nulls the actor that identifies them.
--
-- Order therefore matters and is not negotiable:
--
--   1. freeze what the survivor still needs to render (below)
--   2. delete the leaver's private rows *while created_by still names them*
--   3. delete the leaver's couple_members row
--   4. delete auth.users, and let the cascade null the shared attribution
--
-- THE VACATED SLOT
--
-- `couple_members` carries `unique (couple_id, member_slot)` with slots
-- constrained to (1, 2), and `20260731230000:50` derives every row's A/B side
-- from that slot. Renumbering the survivor from 2 to 1 would silently flip
-- the meaning of every historical row in the field, so the slot is vacated
-- and left vacant. `join_couple` is taught to claim whichever slot is free
-- rather than hardcoding 2 — without that, a survivor who sat in slot 2 could
-- never pair with anyone again.
--
-- WHAT THE SURVIVOR CAN STILL SEE
--
-- Hues are already safe: `field_identity.swatch_a`/`swatch_b` hang off the
-- couple, not off the members, so the departed partner's colour survives
-- their profile. `field_life_items.owner` is likewise a stored 'a'/'b'/'shared'
-- column, so items keep their side.
--
-- `field_captures` is the exception. It stores only `spoken_by`, and
-- `FieldSupabaseBackend.swift:522` resolves the side through
-- `owner(for: row.spoken_by)`, which returns `.shared` for an unrecognised or
-- null profile. Every capture the departed partner spoke would start
-- rendering in the two-colour blend — and `FieldTokens.swift:232` is explicit
-- that the blend "must appear only where something is genuinely shared. Its
-- scarcity is what gives it meaning." So captures get the same denormalised
-- side column life items already have.
--
-- The name does not survive, and that is deliberate. A hue is a product
-- token; a name is the personal data of somebody who just asked to be
-- deleted. `FieldSupabaseBackend`'s existing "Them" fallback covers it.
--
-- REVERSIBILITY
--
-- Additive columns and replaceable functions. Reverting is re-running the
-- `private.delete_my_account()` body from `20260725053000` and dropping the
-- three columns added here; nothing below drops or narrows an existing
-- policy.

begin;

-- MARK: Which side spoke ----------------------------------------------------
--
-- Backfilled from the slot the speaker holds today, which is the same mapping
-- `20260731230000:50` uses. Rows whose speaker has already gone stay null and
-- keep resolving to `.shared`, because there is no longer anything that could
-- tell us otherwise.

alter table public.field_captures
  add column if not exists spoken_side text;

alter table public.field_captures
  drop constraint if exists field_captures_spoken_side_check;

alter table public.field_captures
  add constraint field_captures_spoken_side_check
  check (spoken_side is null or spoken_side in ('a', 'b'));

update public.field_captures c
set spoken_side = case cm.member_slot when 1 then 'a' when 2 then 'b' end
from public.couple_members cm
where cm.profile_id = c.spoken_by
  and cm.couple_id = c.couple_id
  and c.spoken_side is null;

-- Stamped on insert and frozen after, for the reason `20260803180000:143`
-- gives about `visibility`: a column the client can send is a column one
-- partner can use to rewrite the other's attribution.
--
-- A separate function rather than a branch inside `private.field_preserve_actor`,
-- following `20260803180000:225` — re-declaring two hundred lines to add one
-- branch is how a migration silently reverts the rest of itself. The trigger
-- name sorts after `field_actor_integrity`, so `spoken_by` is settled before
-- the side derived from it is recorded.

create or replace function private.field_stamp_capture_side()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims_text text :=
    nullif(current_setting('request.jwt.claims', true), '');
  v_request_role text;
begin
  if v_claims_text is not null then
    v_request_role := v_claims_text::jsonb ->> 'role';
  end if;
  v_request_role := coalesce(
    v_request_role,
    nullif(current_setting('request.jwt.claim.role', true), '')
  );

  -- Migration and service-role connections say what they mean, as everywhere
  -- else in this schema.
  if v_request_role is null or v_request_role = 'service_role' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    new.spoken_side := old.spoken_side;
    return new;
  end if;

  select case cm.member_slot when 1 then 'a' when 2 then 'b' end
  into new.spoken_side
  from public.couple_members cm
  where cm.profile_id = new.spoken_by
    and cm.couple_id = new.couple_id;

  return new;
end;
$$;

revoke all on function private.field_stamp_capture_side()
  from public, anon, authenticated;

drop trigger if exists field_capture_side_integrity on public.field_captures;

create trigger field_capture_side_integrity
  before insert or update on public.field_captures
  for each row execute function private.field_stamp_capture_side();

-- MARK: That somebody left --------------------------------------------------
--
-- `departed_at` distinguishes the two shapes of a one-member couple: someone
-- who has never paired, and someone whose partner deleted their account. They
-- are the same row count and completely different situations.
--
-- `departure_seen_at` is the one quiet moment. The pattern is
-- `yours_owner_state.taught_in_promise` from `20260804090000:337`: a fact is
-- told once, the telling is recorded, and the interface never raises it
-- again. CIRCLE.md:52 — "a symbol can become wordless after it is learned,
-- not before."

alter table public.couples
  add column if not exists departed_at timestamptz;

alter table public.couples
  add column if not exists departure_seen_at timestamptz;

-- MARK: Leaving -------------------------------------------------------------

create or replace function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid;
  v_members integer;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;

  select cm.couple_id
  into v_couple
  from public.couple_members cm
  where cm.profile_id = v_user
  limit 1;

  if v_couple is not null then
    -- Same lock order as every trust mutation. Anything already in flight
    -- commits before the count below; anything later waits and then sees the
    -- membership it depended on gone.
    perform 1 from public.couples where id = v_couple for update;
    perform 1 from public.couple_members
    where couple_id = v_couple
    for update;

    select count(*) into v_members
    from public.couple_members cm
    where cm.couple_id = v_couple;
  end if;

  if v_couple is not null and v_members >= 2 then
    -- Step 2. While `created_by` still names this person: the solo-era rows
    -- they wrote before there was anyone to share with. These were never the
    -- survivor's to read, and after the cascade nulls the actor no policy
    -- could reach them again.
    delete from public.field_life_items
    where couple_id = v_couple
      and visibility = 'private'
      and created_by = v_user;

    delete from public.field_captures
    where couple_id = v_couple
      and visibility = 'private'
      and spoken_by = v_user;

    delete from public.field_corrections
    where couple_id = v_couple
      and visibility = 'private'
      and corrected_by = v_user;

    delete from public.field_standing_rules
    where couple_id = v_couple
      and visibility = 'private'
      and set_by = v_user;

    delete from public.field_held_topics
    where couple_id = v_couple
      and visibility = 'private'
      and created_by = v_user;

    -- Presence is somebody's own, permanently rather than by era — see the
    -- classification in `20260803180000:47`. It hangs off the couple, so the
    -- profile cascade would not reach it either.
    delete from public.field_away_windows
    where couple_id = v_couple
      and profile_id = v_user;

    -- Consent is per person, and a departed person consents to nothing.
    delete from public.signal_consents
    where couple_id = v_couple
      and profile_id = v_user;

    -- Step 3. Vacate the slot without renumbering the survivor: their A/B
    -- side is load-bearing for every row already written.
    delete from public.couple_members
    where couple_id = v_couple
      and profile_id = v_user;

    update public.couples
    set departed_at = now(),
        departure_seen_at = null
    where id = v_couple;
  elsif v_couple is not null then
    -- Nobody else was ever here. The couple is this person.
    delete from public.couples where id = v_couple;
  end if;

  -- Step 4. Cascades to `profiles`, and from there to everything owner-scoped
  -- — yours_entries, yours_owner_state, yours_releases, yours_prepared_offers,
  -- private_proposals, insight_declines — and nulls the shared attribution
  -- the survivor keeps.
  delete from auth.users where id = v_user;
end;
$$;

revoke all on function private.delete_my_account()
  from public, anon, authenticated;

-- `public.delete_my_account()` from `20260725062000:365` takes
-- `private.lock_relationship(v_couple)` first and is unchanged; it continues
-- to wrap this body.

-- MARK: Telling the survivor, once ------------------------------------------

create or replace function public.acknowledge_departure()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
begin
  if v_couple is null then
    raise exception 'not signed into a relationship';
  end if;

  update public.couples
  set departure_seen_at = coalesce(departure_seen_at, now())
  where id = v_couple
    and departed_at is not null;
end;
$$;

revoke all on function public.acknowledge_departure() from public, anon;
grant execute on function public.acknowledge_departure() to authenticated;

-- MARK: Pairing again -------------------------------------------------------
--
-- The only change from `20260725035142:370` is the slot. A survivor sitting
-- in slot 2 could not otherwise pair with anyone ever again: the hardcoded
-- `member_slot = 2` would collide with the unique key, and the failure would
-- read to them as an invalid code.

create or replace function public.join_couple(p_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_count integer;
  v_slot smallint;
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

  select s.slot
  into v_slot
  from (values (1::smallint), (2::smallint)) as s(slot)
  where not exists (
    select 1 from public.couple_members cm
    where cm.couple_id = v_couple
      and cm.member_slot = s.slot
  )
  order by s.slot
  limit 1;

  if v_slot is null then
    raise exception 'this space already has two people';
  end if;

  insert into public.couple_members (
    couple_id, profile_id, hue, member_slot
  ) values (
    v_couple, (select auth.uid()), 'sage', v_slot
  );
  return json_build_object('couple_id', v_couple);
end;
$$;

revoke execute on function public.join_couple(text) from public, anon;
grant execute on function public.join_couple(text) to authenticated;

commit;
