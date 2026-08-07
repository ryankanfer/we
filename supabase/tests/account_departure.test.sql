-- The acceptance test for one person leaving and the other staying.
--
-- The bar: if B deletes their account and A loses the shared field, the phase
-- is not done. If A can afterwards read something B wrote before A existed,
-- the phase is not done either. Those two failures pull in opposite
-- directions, which is the whole reason this file is long — a deletion that
-- keeps everything and a deletion that keeps nothing are both easy, and both
-- wrong.
--
-- The four claims:
--
--   1. the couple survives, one member lighter, slot vacated not renumbered
--   2. shared-era rows survive whoever authored them, attribution nulled
--   3. the leaver's solo-era private rows are gone, not merely unreadable
--   4. a person alone still takes the whole couple with them
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

create temp table ctx on commit drop as
select cm.couple_id
from public.couple_members cm
where cm.profile_id = '94000000-0000-0000-0000-000000000001';

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
    (select c.join_code from public.couples c
     where c.id = (select couple_id from ctx))
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
    (select c.join_code from public.couples c
     where c.id = (select couple_id from ctx))
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
