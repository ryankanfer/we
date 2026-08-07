-- Putting a built-in LIFE group away, at the row level.
--
-- Two properties are under test, and they pull in opposite directions:
--
--   1. A hide is *joint*. Both partners see it, either can make it, either can
--      undo it. LIFE is one shared page, and two people looking at different
--      sets of headings over the same items is not a preference.
--
--   2. A hide is still *couple-scoped*. Nobody outside the couple can read it,
--      write it, or delete it.
--
-- Partner B joins by inserting the membership row directly rather than by
-- redeeming a code, for the reason `field_solo_visibility.test.sql` gives:
-- what is under test is the policy, and routing through the pairing RPC would
-- make a policy failure and an invitation failure look identical.

begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- MARK: Three people --------------------------------------------------------
--
-- Two in a couple, and one stranger with a couple of their own. The stranger
-- is the assertion that "couple-scoped" means something: a test with only one
-- couple in it cannot tell a working policy from a missing one.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '92000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'hidden-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'hidden-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  ),
  (
    '92000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'hidden-c@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Stranger"}', now(), now()
  );

-- MARK: A's couple ----------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok($$select public.create_couple()$$, 'A has a space');

-- Scoped to *this* couple, never to the table — the mistake
-- `field_solo_visibility.test.sql` documents, where an unscoped insert reads
-- as harmless against one row and corrupts every couple against real data.
reset role;
create temp table ctx on commit drop as
select couple_id from public.couple_members
where profile_id = '92000000-0000-0000-0000-000000000001';

-- The temp table belongs to the session role, and everything below reads it
-- while impersonating `authenticated`. Without this the assertions fail with
-- "permission denied for table ctx" — which looks like a policy rejecting the
-- read, and is really the scaffolding being unreadable.
grant select on ctx to authenticated;

insert into public.couple_members (couple_id, profile_id, hue, member_slot)
select couple_id, '92000000-0000-0000-0000-000000000002', 'sage', 2 from ctx;

-- MARK: The stranger's couple -----------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select lives_ok($$select public.create_couple()$$, 'the stranger has one too');

-- MARK: A puts Watchlist away -----------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

insert into public.field_hidden_categories (couple_id, category)
values (public.my_couple_id(), 'watchlist');

select is(
  (
    select count(*) from public.field_hidden_categories
    where couple_id = (select couple_id from ctx)
  ),
  1::bigint,
  'A can put a group away'
);

-- Stamped by the database, not supplied by the client.
select is(
  (
    select hidden_by from public.field_hidden_categories
    where couple_id = (select couple_id from ctx) and category = 'watchlist'
  ),
  '92000000-0000-0000-0000-000000000001'::uuid,
  'and the database records who did it, without being told'
);

-- The client cannot claim it was somebody else. This is the assertion that
-- would fail if the trigger were ever dropped in favour of trusting the
-- payload — and `hidden_by` is the one column that could be used to write
-- copy blaming the wrong partner.
insert into public.field_hidden_categories (couple_id, category, hidden_by)
values (public.my_couple_id(), 'money', '92000000-0000-0000-0000-000000000002');

select is(
  (
    select hidden_by from public.field_hidden_categories
    where couple_id = (select couple_id from ctx) and category = 'money'
  ),
  '92000000-0000-0000-0000-000000000001'::uuid,
  'and a client cannot attribute its own hide to its partner'
);

-- MARK: It is joint ---------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select isnt(
  public.my_couple_id(), null,
  'B is really in the couple, so the counts below are the policy and not a miss'
);

select is(
  (select count(*) from public.field_hidden_categories), 2::bigint,
  'B sees what A put away — LIFE is one page, not two'
);

-- Either of them can undo it. There is no "only the person who hid it may
-- bring it back": a couple who cannot reverse each other's shared settings
-- has a shared page one of them owns.
delete from public.field_hidden_categories where category = 'money';

select is(
  (select count(*) from public.field_hidden_categories), 1::bigint,
  'and B can bring back a group A put away'
);

-- And B can put one away themselves.
insert into public.field_hidden_categories (couple_id, category)
values (public.my_couple_id(), 'trips');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.field_hidden_categories), 2::bigint,
  'and A sees what B put away'
);

-- MARK: It stops at the couple ----------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.field_hidden_categories), 0::bigint,
  'a stranger sees none of it'
);

-- A row you cannot see is a row you cannot destroy. Written as a delete
-- because `for all` policies OR together with the select policy, and a
-- too-wide write policy is the failure mode that passed every read test in
-- the solo-visibility migration's first draft.
delete from public.field_hidden_categories;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.field_hidden_categories), 2::bigint,
  'and cannot delete what they cannot see'
);

-- Nor insert into somebody else's couple, even naming it explicitly.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.field_hidden_categories (couple_id, category)
    select couple_id, 'care' from ctx$$,
  '42501',
  null,
  'and cannot put a group away in a couple they are not in'
);

-- MARK: Idempotence ---------------------------------------------------------
--
-- The client upserts. Hiding a group that is already hidden must be one row
-- and not an error, or a second device repeating a queued write breaks the
-- flush.

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$insert into public.field_hidden_categories (couple_id, category)
    values (public.my_couple_id(), 'watchlist')
    on conflict (couple_id, category) do nothing$$,
  'putting away a group that is already away is not an error'
);

select is(
  (select count(*) from public.field_hidden_categories), 2::bigint,
  'and does not make a second row'
);

-- MARK: This table carries no visibility ------------------------------------
--
-- Stated as an assertion rather than an omission, the way
-- `field_solo_visibility.test.sql` does, so that adding one later is a
-- deliberate change. A per-person hide is the thing this design rules out.

select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'field_hidden_categories'
      and column_name = 'visibility'
  ),
  0::bigint,
  'a hide is joint, so there is nothing for a visibility column to say'
);

select * from finish();
rollback;
