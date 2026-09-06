-- Leaving is blocked by a consent row nobody remembers writing. A P0.
--
-- WHAT HAPPENS TODAY
--
-- `DELETE MY ACCOUNT` fails on the device with
--
--   update or delete on table "profiles" violates foreign key constraint
--   "insight_consent_initiator_id_fkey" on table "insight_consent"
--
-- and the person is left on the confirmation screen, having typed DELETE,
-- being told by Postgres that they may not leave.
--
-- `20260808000000` made the couple survive one member's departure. That was
-- right, and it is the reason this breaks: before it, `delete from couples`
-- cascaded through `insights` and took `insight_consent` with it, so the
-- restricting references never had a live row pointing at the profile by the
-- time the profile went. Now the couple stays, its insights stay, and their
-- consent rows keep naming somebody who is trying to stop existing.
--
-- `insight_consent` is the only place in the schema where this is possible.
-- Every other reference to `public.profiles(id)` — thirty-odd of them —
-- carries an explicit `on delete` action. These two, written on 2026-07-24,
-- carry none, and a bare `references` is `no action`: a hard veto.
--
--   owner_id      uuid references public.profiles(id)
--   initiator_id  uuid references public.profiles(id)
--
-- The table is not vestigial. `refresh_shared_journey_question` in
-- `20260808120000:497` writes a consent row for every journey question, and
-- `request_share` in `20260725062000:59` stamps `initiator_id` on any request
-- to bring a private item across. A couple that has used the product at all
-- has rows here.
--
-- TWO SEPARATE THINGS ARE WRONG
--
-- The veto is the visible one, and `on delete set null` clears it. That is
-- also the right resting state for a resolved row: `20260808000000` already
-- establishes that shared-era material stays with the couple and loses its
-- attribution, which is what the survivor sees on every field row B ever
-- wrote.
--
-- But `set null` alone would leave two rows in states that are wrong on their
-- own terms, quietly, after the crash stops:
--
--   1. A *pending request* whose initiator has gone. `accept_share` guards
--      with `if c.initiator_id = auth.uid() then raise` — against null that
--      predicate is null, so the guard passes and the survivor can accept a
--      request from nobody, flipping a private item to `mutual`. The item
--      being made shared is the departed person's. That is precisely the
--      crossing `CIRCLE.md` does not permit, executed by somebody who cannot
--      consent because they are gone.
--
--   2. A *private consent row* the leaver owned. The select policy from
--      `20260725053000:158` is `ic.visibility <> 'private' or ic.owner_id =
--      auth.uid()`; with the owner nulled it is readable by nobody and, by
--      the same predicate, deletable by nobody. This is the exact shape
--      `20260808000000` argued against for the field tables: a row with no
--      living owner that the API can never reach again.
--
-- So the constraint is relaxed *and* `private.delete_my_account()` is taught
-- to settle both cases first, in the same order and for the same reason the
-- field tables are settled there: while `initiator_id` and `owner_id` still
-- name the person who is leaving.
--
-- A withdrawn request rather than a deleted one, because `withdrawn` is a
-- state the readiness check already allows and `withdraw_share` in
-- `20260725053000:237` already produces from the same three columns. The
-- survivor sees a request that is no longer live, which is true.
--
-- REVERSIBILITY
--
-- Two constraints and one replaceable function. Reverting is re-adding the
-- bare references and re-running the `private.delete_my_account()` body from
-- `20260808000000`.

begin;

-- MARK: The veto ------------------------------------------------------------
--
-- Named explicitly rather than looked up, because these are the default
-- names Postgres gave them in `20260724015432` and the device error quotes
-- one of them verbatim.

alter table public.insight_consent
  drop constraint if exists insight_consent_owner_id_fkey;

alter table public.insight_consent
  add constraint insight_consent_owner_id_fkey
  foreign key (owner_id) references public.profiles(id)
  on delete set null;

alter table public.insight_consent
  drop constraint if exists insight_consent_initiator_id_fkey;

alter table public.insight_consent
  add constraint insight_consent_initiator_id_fkey
  foreign key (initiator_id) references public.profiles(id)
  on delete set null;

-- MARK: Leaving -------------------------------------------------------------
--
-- The body of `20260808000000` with one section added. Re-declared whole
-- rather than patched, following `20260803180000:225`.

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

    -- Step 2b. A request to cross the private/shared line, made by somebody
    -- who is no longer here to mean it. Left as `requested` with a nulled
    -- initiator it becomes acceptable by the survivor — `accept_share`'s
    -- "cannot accept your own request" guard is null against null — and
    -- accepting it would publish the departed person's private item.
    update public.insight_consent ic
    set readiness = 'withdrawn',
        initiator_id = null,
        requested_at = null
    from public.insights i
    where i.id = ic.insight_id
      and i.couple_id = v_couple
      and ic.initiator_id = v_user
      and ic.readiness = 'requested';

    -- Step 2c. A private item is one person's. Theirs goes with them, whole,
    -- rather than surviving as a row the select policy leaves readable by
    -- nobody once the owner is nulled. The insight is deleted, not just its
    -- consent: every table hanging off `insights` cascades from it.
    delete from public.insights i
    using public.insight_consent ic
    where ic.insight_id = i.id
      and i.couple_id = v_couple
      and ic.visibility = 'private'
      and ic.owner_id = v_user;

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
  -- the survivor keeps, `insight_consent` now included.
  delete from auth.users where id = v_user;
end;
$$;

revoke all on function private.delete_my_account()
  from public, anon, authenticated;

commit;
