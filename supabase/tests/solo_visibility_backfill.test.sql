-- The acceptance test for the solo-visibility backfill.
--
-- The bar, stated the way the suites this sits beside state theirs: if a row
-- authored while alone is readable by a partner who joins later without its
-- author having crossed it deliberately, the phase is not done — and it makes
-- no difference whether the row predates the visibility column or not.
--
-- ON RECONSTRUCTING THE PRE-MIGRATION STATE
--
-- `20260803180000` stamps every new solo row 'private' via
-- `private.field_stamp_visibility`, so a row inserted by this test is already
-- correct and proves nothing. The state under test is the one that trigger
-- never saw: rows sitting at 'shared' in a one-member couple, which is what
-- `add column ... default 'shared'` produced for everybody who was alone when
-- it deployed.
--
-- They are forced there as the session role. The trigger returns early when
-- the request role is null, which is the same door the migration itself goes
-- through — so this reproduces the real defect rather than a lookalike. The
-- role is reset immediately afterwards, because several assertions below
-- depend on a *client* being unable to do what those lines just did.

begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- MARK: Two people ----------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '93000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'backfill-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '93000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'backfill-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  ),
  -- A second, already-paired couple. The backfill must not touch it, and
  -- proving that needs a couple that actually has two members in it.
  (
    '93000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'backfill-c@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner C"}', now(), now()
  ),
  (
    '93000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'backfill-d@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner D"}', now(), now()
  );

-- MARK: A, alone ------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_couple()$$,
  'A has a real space before anybody else is in it'
);

insert into public.field_life_items (couple_id, title, category, source)
values (public.my_couple_id(), 'Therapy on Thursday', 'care', 'captured');

insert into public.field_captures (couple_id, text, destination, reasoning)
values (public.my_couple_id(), 'therapy thursday', '', '');

insert into public.field_corrections (
  couple_id, client_id, input, original_destination, corrected_destination
)
values (public.my_couple_id(), 'corr-1', 'therapy', 'notes', 'care');

insert into public.field_standing_rules (couple_id, client_id, text)
values (public.my_couple_id(), 'rule-1', 'Never plan anything before 10am');

insert into public.field_held_topics (
  couple_id, client_id, title, timing, reason
)
values (
  public.my_couple_id(), 'promote:japan', 'Japan', 'NOT THIS YEAR',
  'Money is going into the move instead'
);

-- MARK: A paired couple, for the untouched case ------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_couple()$$,
  'C has a space'
);

reset role;

create temp table ctx on commit drop as
select
  (
    select couple_id from public.couple_members
    where profile_id = '93000000-0000-0000-0000-000000000001'
  ) as solo_couple,
  (
    select couple_id from public.couple_members
    where profile_id = '93000000-0000-0000-0000-000000000003'
  ) as paired_couple;

-- D joins C, so this couple is genuinely two people before the backfill runs.
-- `hue` is checked against ('burgundy','sage') and `member_slot` against
-- (1, 2); `join_couple` pairs slot 2 with sage, so this matches what real
-- pairing produces.
insert into public.couple_members (couple_id, profile_id, hue, member_slot)
values (
  (select paired_couple from ctx),
  '93000000-0000-0000-0000-000000000004',
  'sage',
  2
);

-- C writes one item, which the trigger correctly stamps 'shared' because the
-- couple already has two members.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

insert into public.field_life_items (couple_id, title, category, source)
values (public.my_couple_id(), 'Book the flights', 'plans', 'captured');

reset role;

select is(
  (
    select visibility from public.field_life_items
    where couple_id = (select paired_couple from ctx)
  ),
  'shared',
  'a row written inside a real couple is shared, as it should be'
);

-- MARK: Reconstruct the pre-migration state ---------------------------------
--
-- Every solo row forced to 'shared', which is what the column default did to
-- everybody who was alone on 2026-08-03.
--
-- The claims have to be cleared, not just the role. `reset role` returns the
-- session to its own identity but leaves `request.jwt.claims` exactly where
-- the last `set_config` put it, and `field_stamp_visibility` reads the claims
-- rather than the role. Left set, it would see 'authenticated', take its
-- UPDATE branch, and freeze the column — the five statements below would
-- report success and change nothing, and the assertion after them is what
-- would have caught it.
select set_config('request.jwt.claims', '', true);

update public.field_life_items set visibility = 'shared'
where couple_id = (select solo_couple from ctx);
update public.field_captures set visibility = 'shared'
where couple_id = (select solo_couple from ctx);
update public.field_corrections set visibility = 'shared'
where couple_id = (select solo_couple from ctx);
update public.field_standing_rules set visibility = 'shared'
where couple_id = (select solo_couple from ctx);
update public.field_held_topics set visibility = 'shared'
where couple_id = (select solo_couple from ctx);

select is(
  (
    select count(*) from public.field_life_items
    where couple_id = (select solo_couple from ctx) and visibility = 'shared'
  ),
  1::bigint,
  'the defect is reproduced: a solo row sits at shared before the backfill'
);

-- MARK: The backfill ---------------------------------------------------------

select ok(
  private.field_backfill_solo_visibility() >= 5,
  'the backfill returns every solo row it moved'
);

select is(
  (
    select count(*) from public.field_life_items
    where couple_id = (select solo_couple from ctx) and visibility = 'private'
  ),
  1::bigint,
  'life items written while alone are private again'
);

select is(
  (
    select count(*) from public.field_captures
    where couple_id = (select solo_couple from ctx) and visibility = 'private'
  ),
  1::bigint,
  'captures written while alone are private again'
);

select is(
  (
    select count(*) from public.field_corrections
    where couple_id = (select solo_couple from ctx) and visibility = 'private'
  ),
  1::bigint,
  'corrections written while alone are private again'
);

select is(
  (
    select count(*) from public.field_standing_rules
    where couple_id = (select solo_couple from ctx) and visibility = 'private'
  ),
  1::bigint,
  'standing rules written while alone are private again'
);

select is(
  (
    select count(*) from public.field_held_topics
    where couple_id = (select solo_couple from ctx) and visibility = 'private'
  ),
  1::bigint,
  'held topics written while alone are private again'
);

-- The hazard the 'shared' default was defending against. If this ever fails,
-- the backfill has started hiding rows a couple can currently see.
select is(
  (
    select visibility from public.field_life_items
    where couple_id = (select paired_couple from ctx)
  ),
  'shared',
  'an already-paired couple is untouched'
);

-- Idempotent: deploying twice, or extending the mapping later and re-running
-- it, must not be a second visibility change.
select is(
  private.field_backfill_solo_visibility(),
  0,
  'running the backfill again moves nothing'
);

-- MARK: No authorless rows hid from the backfill -----------------------------
--
-- The UPDATE skips rows whose actor column is null, because a row with no
-- author cannot be private to anyone. Assert none exists rather than trusting
-- it — if this fails the repair is a NOT NULL on that column, not a wider
-- backfill.

select is(
  (
    select count(*) from public.field_life_items
    where couple_id = (select solo_couple from ctx) and created_by is null
  ) + (
    select count(*) from public.field_captures
    where couple_id = (select solo_couple from ctx) and spoken_by is null
  ) + (
    select count(*) from public.field_corrections
    where couple_id = (select solo_couple from ctx) and corrected_by is null
  ) + (
    select count(*) from public.field_standing_rules
    where couple_id = (select solo_couple from ctx) and set_by is null
  ) + (
    select count(*) from public.field_held_topics
    where couple_id = (select solo_couple from ctx) and created_by is null
  ),
  0::bigint,
  'no solo row is authorless, so none escaped the backfill'
);

-- MARK: B joins, and sees none of it -----------------------------------------
--
-- The whole point. Without the backfill every one of these is B's to read.

insert into public.couple_members (couple_id, profile_id, hue, member_slot)
values (
  (select solo_couple from ctx),
  '93000000-0000-0000-0000-000000000002',
  'sage',
  2
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.field_life_items),
  0::bigint,
  'B cannot read a life item A wrote before the visibility column existed'
);

select is(
  (select count(*) from public.field_captures),
  0::bigint,
  'B cannot read a pre-migration capture'
);

select is(
  (select count(*) from public.field_corrections),
  0::bigint,
  'B cannot read a pre-migration correction'
);

select is(
  (select count(*) from public.field_standing_rules),
  0::bigint,
  'B cannot read a pre-migration standing rule'
);

select is(
  (select count(*) from public.field_held_topics),
  0::bigint,
  'B cannot read a pre-migration held topic'
);

-- A row you cannot see is a row you cannot destroy. The write policies take
-- the same visibility predicate, and this is the assertion that fails loudest
-- if that ever stops being true.
delete from public.field_life_items;

select is(
  (select count(*) from public.field_life_items),
  0::bigint,
  'B deleting everything they can see removes none of it'
);

reset role;

select is(
  (
    select count(*) from public.field_life_items
    where couple_id = (select solo_couple from ctx)
  ),
  1::bigint,
  'A''s pre-migration item survived B''s delete'
);

-- MARK: The backfill is not a client's to call -------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"93000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

-- The message is deliberately unchecked: a client is blocked either by the
-- revoked EXECUTE or by having no USAGE on the `private` schema at all, and
-- both are 42501 with different wording. Cast rather than a bare null, which
-- leaves Postgres unable to pick between `throws_ok`'s overloads.
select throws_ok(
  $$select private.field_backfill_solo_visibility()$$,
  '42501',
  null::text,
  'a client cannot run the backfill'
);

select * from finish();
rollback;
