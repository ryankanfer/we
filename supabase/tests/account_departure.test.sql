-- The acceptance test for one person leaving and the other staying.
--
-- The bar: if B deletes their account and A loses the shared field, the phase
-- is not done. If A can afterwards read something B wrote before A existed,
-- the phase is not done either. Those two failures pull in opposite
-- directions, which is the whole reason this file is long — a deletion that
-- keeps everything and a deletion that keeps nothing are both easy, and both
-- wrong.
--
-- The claims:
--
--   1. the couple survives, one member lighter, slot vacated not renumbered
--   2. shared-era rows survive whoever authored them, attribution nulled
--   3. the leaver's solo-era private rows are gone, not merely unreadable
--   4. a person alone still takes the whole couple with them
--   5. no consent row can veto the departure, or outlive it in a state the
--      survivor could act on
--
-- ON ORDER
--
-- `private.delete_my_account` deletes the leaver's private rows *before*
-- dropping their profile, because `on delete set null` on the actor column
-- would otherwise erase the only thing identifying them. Claim 3 is what
-- catches a regression that reorders those two steps: the rows would still be
-- invisible to A — the select policy needs `visibility = 'shared'` or a
-- matching actor, and null is neither — so an existence check against A's
-- view would pass while the rows sat there forever. It is asserted as the
-- table owner for that reason.
--
-- ON ROLES
--
-- Every temp table is built after `reset role`, following the convention in
-- `solo_visibility_backfill.test.sql`. Couple ids are read from
-- `couple_members` by profile rather than from `my_couple_id()`, so the
-- lookup does not depend on which claims happen to be set.

begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- MARK: Four people ---------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '94000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'departure-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '94000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'departure-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  ),
  -- Somebody who never pairs with anyone, for claim 4.
  (
    '94000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'departure-solo@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Alone"}', now(), now()
  ),
  -- The person who eventually takes the vacated slot, for claim 1.
  (
    '94000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'departure-new@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Someone New"}', now(), now()
  );

-- MARK: A, alone, writes solo-era history -----------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_couple()$$,
  'A has a space before anybody else is in it'
);

insert into public.field_life_items (couple_id, title, category, source)
values (public.my_couple_id(), 'A alone: therapy', 'care', 'captured');

insert into public.field_captures (couple_id, text, destination, reasoning)
values (public.my_couple_id(), 'a alone capture', '', '');

reset role;

-- The join code is captured here, as the owner. B cannot read it: an
-- invitation is redeemed by someone who is not yet a member, and the
-- `couples` policy quite correctly shows them nothing. Selecting it under
-- B's role returns NULL and the fixture calls `join_couple(NULL)`.
create temp table ctx on commit drop as
select cm.couple_id, c.join_code
from public.couple_members cm
join public.couples c on c.id = cm.couple_id
where cm.profile_id = '94000000-0000-0000-0000-000000000001';

-- The fixture is built as the owning role; the assertions below read it
-- back as `authenticated`, which has no privilege on a temp table it
-- does not own. Without this the file aborts on first read and every
-- assertion after it silently never runs.
grant select on ctx to authenticated;

-- MARK: B joins, and the two of them build something ------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select lives_ok(
  format(
    $$select public.join_couple(%L)$$,
    (select join_code from ctx)
  ),
  'B redeems A''s invitation'
);

insert into public.field_life_items (couple_id, title, category, source)
values (public.my_couple_id(), 'B shared: the move', 'plans', 'captured');

insert into public.field_captures (couple_id, text, destination, reasoning)
values (public.my_couple_id(), 'b shared capture', '', '');

reset role;

select is(
  (select count(*)::int from public.field_life_items
   where couple_id = (select couple_id from ctx) and visibility = 'shared'),
  1,
  'B''s item is stamped shared, because a couple''s field is shared'
);

-- The side is denormalised at insert, so it can outlive B's profile. Without
-- this column every capture B spoke would render in the two-colour blend that
-- `FieldTokens.swift:232` reserves for genuinely shared things.
select is(
  (select c.spoken_side from public.field_captures c
   where c.text = 'b shared capture'),
  'b',
  'a capture records which side spoke it, not only who'
);

-- MARK: Consent rows that name B ---------------------------------------------
--
-- Written as the table owner because `insight_consent` has no insert policy —
-- only RPCs write it — and the shapes under test are states those RPCs
-- produce: `request_share` stamps `initiator_id`, and a private item carries
-- `owner_id`. These two rows are what made `DELETE MY ACCOUNT` fail on the
-- device: a bare `references public.profiles(id)` is a veto, not a cascade.

insert into public.insights (
  id, couple_id, seed_key, kind, domain, present,
  title, body, evidence, source, options
) values
  (
    '94000000-0000-0000-0000-0000000000a1',
    (select couple_id from ctx), 'departure-shared', 'relational', 'us', true,
    'A shared question', 'body', 'evidence', 'test', array['one', 'two']
  ),
  (
    '94000000-0000-0000-0000-0000000000a2',
    (select couple_id from ctx), 'departure-private', 'relational', 'us', true,
    'B''s private question', 'body', 'evidence', 'test', array['one', 'two']
  );

insert into public.insight_consent (
  insight_id, visibility, owner_id, readiness, initiator_id, requested_at
) values
  (
    '94000000-0000-0000-0000-0000000000a1', 'shared', null,
    'requested', '94000000-0000-0000-0000-000000000002', now()
  ),
  (
    '94000000-0000-0000-0000-0000000000a2', 'private',
    '94000000-0000-0000-0000-000000000002', 'idle', null, null
  );

-- MARK: B leaves ------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.delete_my_account()$$,
  'B can delete their own account'
);

reset role;

-- Claim 1: the couple is still there.
select is(
  (select count(*)::int from public.couples
   where id = (select couple_id from ctx)),
  1,
  'the shared space survives one person leaving it'
);

select is(
  (select count(*)::int from public.couple_members
   where couple_id = (select couple_id from ctx)),
  1,
  'one member remains'
);

-- The survivor keeps the slot they have always had. Renumbering them would
-- silently flip the A/B side of every row already written, because
-- `20260731230000:50` derives the side from the slot.
select is(
  (select cm.member_slot from public.couple_members cm
   where cm.couple_id = (select couple_id from ctx)),
  1::smallint,
  'the survivor is not renumbered into the vacated slot'
);

select isnt(
  (select c.departed_at from public.couples c
   where c.id = (select couple_id from ctx)),
  null,
  'the couple records that somebody left, not merely that it is small'
);

select is(
  (select c.departure_seen_at from public.couples c
   where c.id = (select couple_id from ctx)),
  null,
  'the survivor has not been told yet'
);

-- Claim 2: shared-era rows survive, attribution nulled by the cascade.
select is(
  (select count(*)::int from public.field_life_items
   where couple_id = (select couple_id from ctx)
     and title = 'B shared: the move'),
  1,
  'what B contributed to the shared field stays with the couple'
);

select is(
  (select i.created_by from public.field_life_items i
   where i.title = 'B shared: the move'),
  null,
  'B''s name comes off it'
);

select is(
  (select c.spoken_side from public.field_captures c
   where c.text = 'b shared capture'),
  'b',
  'the side survives the profile, so the hue does not collapse to the blend'
);

-- Claim 3: A's own private material is untouched by somebody else leaving.
select is(
  (select count(*)::int from public.field_life_items
   where couple_id = (select couple_id from ctx)
     and visibility = 'private'
     and title = 'A alone: therapy'),
  1,
  'A''s own solo history is untouched by B leaving'
);

-- A consent row must not be able to veto somebody's departure. This is the
-- assertion the device error would have failed: `insight_consent_initiator_id_fkey`.
select is(
  (select ic.readiness from public.insight_consent ic
   where ic.insight_id = '94000000-0000-0000-0000-0000000000a1'),
  'withdrawn',
  'a request to cross the line dies with the person who made it'
);

select is(
  (select ic.initiator_id from public.insight_consent ic
   where ic.insight_id = '94000000-0000-0000-0000-0000000000a1'),
  null,
  'and stops naming them'
);

-- Left as `requested` with a null initiator, `accept_share`'s "cannot accept
-- your own request" guard is null against null and the survivor could publish
-- a departed person's private item.
select is(
  (select ic.requested_at from public.insight_consent ic
   where ic.insight_id = '94000000-0000-0000-0000-0000000000a1'),
  null,
  'there is no live request left for the survivor to accept'
);

-- Asserted against the base table, as claim 3 is: with the owner nulled the
-- select policy would leave this row readable by nobody and deletable by
-- nobody, which reads identical to gone from A's side.
select is(
  (select count(*)::int from public.insights
   where id = '94000000-0000-0000-0000-0000000000a2'),
  0,
  'B''s private question goes with B, rather than surviving unreachable'
);

select is(
  (select count(*)::int from public.insight_consent
   where insight_id = '94000000-0000-0000-0000-0000000000a2'),
  0,
  'and its consent row goes with it'
);

select is(
  (select count(*)::int from public.insights
   where id = '94000000-0000-0000-0000-0000000000a1'),
  1,
  'the shared question stays with the couple'
);

-- MARK: What the survivor sees ----------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select count(*)::int from public.field_life_items),
  2,
  'A still sees the whole field: their own and what B left behind'
);

select lives_ok(
  $$select public.acknowledge_departure()$$,
  'A can acknowledge the departure'
);

select lives_ok(
  $$select public.create_invitation()$$,
  'the survivor can invite somebody new'
);

reset role;

-- `create_invitation()` mints a fresh code and rotates `couples.join_code` to
-- match (20260808010000). The code captured into `ctx` at the top of this file
-- is the one the departed partner already consumed, so redeeming it again is
-- refused with 'that invitation has already been used' — correctly. Take the
-- new one, as a person reading it off the survivor's screen would.
create temp table reinvite on commit drop as
select c.join_code
from public.couples c
where c.id = (select couple_id from ctx);
grant select on reinvite to authenticated;

select isnt(
  (select c.departure_seen_at from public.couples c
   where c.id = (select couple_id from ctx)),
  null,
  'the telling is recorded, so the interface never raises it again'
);

-- MARK: Pairing again into the vacated slot ---------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);

-- This is the assertion that a hardcoded `member_slot = 2` would fail against
-- a survivor sitting in slot 2, and that the free-slot select fixes.
select lives_ok(
  format(
    $$select public.join_couple(%L)$$,
    (select join_code from reinvite)
  ),
  'somebody new can take the vacated slot'
);

reset role;

select is(
  (select count(*)::int from public.couple_members
   where couple_id = (select couple_id from ctx)),
  2,
  'the space has two people in it again'
);

select is(
  (select cm.member_slot from public.couple_members cm
   where cm.couple_id = (select couple_id from ctx)
     and cm.profile_id = '94000000-0000-0000-0000-000000000004'),
  2::smallint,
  'they take the slot that was vacated, not the one still occupied'
);

-- MARK: Claim 4 — alone, and taking it all ----------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_couple()$$,
  'somebody alone still has a real space'
);

reset role;

create temp table solo_ctx on commit drop as
select cm.couple_id
from public.couple_members cm
where cm.profile_id = '94000000-0000-0000-0000-000000000003';

-- The fixture is built as the owning role; the assertions below read it
-- back as `authenticated`, which has no privilege on a temp table it
-- does not own. Without this the file aborts on first read and every
-- assertion after it silently never runs.
grant select on solo_ctx to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.delete_my_account()$$,
  'they can delete it'
);

reset role;

select is(
  (select count(*)::int from public.couples
   where id = (select couple_id from solo_ctx)),
  0,
  'a person with no partner takes the whole couple with them'
);

select * from finish();
rollback;
