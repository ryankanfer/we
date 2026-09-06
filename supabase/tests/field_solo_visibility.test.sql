-- The acceptance test for Phase 2a.
--
-- The plan states the bar: "pgTAP tests for every table, before and after
-- partner B joins, asserting exactly what B can and cannot read. If any
-- pre-pairing private record is readable, the phase is not done."
--
-- Partner B joins here by inserting the membership row directly rather than by
-- redeeming a code. That is deliberate: what is under test is the row-level
-- policy, and routing through the pairing RPC would make a policy failure and
-- an invitation failure look identical.

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
    '91000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'solo-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '91000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'solo-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  );

-- MARK: A, alone ------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_couple()$$,
  'A has a real space before anybody else is in it'
);

-- Everything below is scoped to *this* couple, never to the table.
--
-- An earlier draft paired partner B with `select id from public.couples` and no
-- WHERE clause. In the isolated stack this file is written for that is exactly
-- one row and reads as harmless; against a database with real couples in it, it
-- inserts a fabricated member into every one of them. A unique constraint
-- happened to catch it. Nothing about the test caught it.
-- Captured as the session role, not as `authenticated`: creating a temp table
-- needs TEMPORARY on the database, which the `authenticated` role has no
-- reason to hold.
reset role;
create temp table ctx on commit drop as
select couple_id from public.couple_members
where profile_id = '91000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (
    select count(*) from public.couple_members
    where couple_id = (select couple_id from ctx)
  ),
  1::bigint,
  'the solo era is one member'
);

-- Everything a person can author, written while alone.
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

-- The era decides, and nobody was asked.
select is(
  (select visibility from public.field_life_items
     where couple_id = (select couple_id from ctx)),
  'private',
  'a life item written alone is private'
);
select is(
  (select visibility from public.field_captures
     where couple_id = (select couple_id from ctx)),
  'private',
  'a capture written alone is private'
);
select is(
  (select visibility from public.field_corrections
     where couple_id = (select couple_id from ctx)),
  'private',
  'a correction made alone is private'
);
select is(
  (select visibility from public.field_standing_rules
     where couple_id = (select couple_id from ctx)),
  'private',
  'a rule set alone is private'
);
select is(
  (select visibility from public.field_held_topics
     where couple_id = (select couple_id from ctx)),
  'private',
  'a topic held alone is private'
);

select is(
  (
    select created_by from public.field_held_topics
    where couple_id = (select couple_id from ctx)
  ),
  '91000000-0000-0000-0000-000000000001'::uuid,
  'held topics now record who held them'
);

-- A cannot promote their own row by sending the column.
update public.field_life_items set visibility = 'shared'
where couple_id = (select couple_id from ctx);
select is(
  (select visibility from public.field_life_items
     where couple_id = (select couple_id from ctx)),
  'private',
  'visibility cannot be changed by writing to it'
);

-- MARK: B joins -------------------------------------------------------------

reset role;

-- `hue` is not null and checked against ('burgundy','sage'); `join_couple`
-- pairs slot 2 with sage, so this matches what real pairing produces.
insert into public.couple_members (couple_id, profile_id, hue, member_slot)
select couple_id, '91000000-0000-0000-0000-000000000002', 'sage', 2
from ctx;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select isnt(
  public.my_couple_id(),
  null,
  'B is really in the couple, so a zero below is the policy and not a miss'
);

-- The whole phase, in five assertions.
select is(
  (select count(*) from public.field_life_items), 0::bigint,
  'B cannot read the life items A wrote alone'
);
select is(
  (select count(*) from public.field_captures), 0::bigint,
  'B cannot read the captures A wrote alone'
);
select is(
  (select count(*) from public.field_corrections), 0::bigint,
  'B cannot read the corrections A made alone'
);
select is(
  (select count(*) from public.field_standing_rules), 0::bigint,
  'B cannot read the rules A set alone'
);
select is(
  (select count(*) from public.field_held_topics), 0::bigint,
  'B cannot read what A held alone'
);

-- And cannot publish them, either. The RPC is scoped to the caller's own rows,
-- so B running it must move nothing of A's.
select is(
  public.field_share_solo_history(), 0,
  'B sharing their own history shares none of A''s'
);

-- A row you cannot see is a row you cannot destroy.
--
-- These three exist because the first draft of the migration narrowed only the
-- select policy and left the generated `_write` policy in place. `for all`
-- includes SELECT, permissive policies OR together, and the entire boundary
-- above would have passed its tests while granting B everything through the
-- other policy. Deletion is the assertion that fails loudest if that returns.
delete from public.field_life_items;
select is(
  (select count(*) from public.field_life_items) , 0::bigint,
  'B still sees nothing after trying to delete it'
);

reset role;
select is(
  (
    select count(*) from public.field_life_items
    where couple_id = (select couple_id from ctx)
  ),
  1::bigint,
  'and A''s private row is still there'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
update public.field_standing_rules set text = 'Rewritten by B';
reset role;
select is(
  (
    select text from public.field_standing_rules
    where couple_id = (select couple_id from ctx)
  ),
  'Never plan anything before 10am',
  'B cannot rewrite a rule they cannot read'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

-- MARK: A couple's writes are shared ----------------------------------------
--
-- The boundary is about the solo era, not about the couple. Once two people
-- are here, a shared field is the entire product.

insert into public.field_life_items (couple_id, title, category, source)
values (public.my_couple_id(), 'Book the ferry', 'calendar', 'captured');

select is(
  (
    select visibility from public.field_life_items
    where title = 'Book the ferry'
  ),
  'shared',
  'a life item written after pairing is shared without being asked'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.field_life_items), 2::bigint,
  'A sees their own private row and the new shared one'
);

-- Held onto, because the assertion that matters is not this number against a
-- literal but this number against what the crossing then moves. Read before
-- the crossing runs, in its own statement, so the comparison below cannot
-- depend on the evaluation order within one select.
create temp table named on commit drop as
  select public.field_solo_history_count() as n;

select is(
  (select n from named), 5,
  'the disclosure can name what would cross before anybody commits'
);

-- MARK: Crossing, once, on purpose ------------------------------------------
--
-- The count and the crossing are asserted against each other, not only
-- against literals. They drifted apart once already: the counting function
-- covered three of the five tables the crossing moves — it omitted
-- corrections and held topics, both of which `FieldCrossingView` names on
-- screen — so the disclosure said three and the button moved five. As two
-- fixed numbers, `3` and `5` sat twelve lines apart and read as two facts
-- rather than as one contradiction. Written this way, that drift fails here.
select is(
  public.field_share_solo_history(),
  (select n from named),
  'A crosses exactly what the disclosure named, and no more'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.field_life_items), 2::bigint,
  'and only then does B see the backlog'
);
select is(
  (select count(*) from public.field_captures), 1::bigint,
  'including the captures'
);
select is(
  (select count(*) from public.field_held_topics), 1::bigint,
  'including what was held, so the app does not re-ask B what A settled'
);

-- MARK: Presence is never shared --------------------------------------------

reset role;
insert into public.field_away_windows (
  couple_id, profile_id, starts_at, ends_at, reason
)
select couple_id, '91000000-0000-0000-0000-000000000001', now(), now(), 'Away'
from ctx;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.field_away_windows), 0::bigint,
  'presence is private to its author permanently, not by era'
);

-- MARK: The joint tables stay joint -----------------------------------------
--
-- Stated as an assertion rather than an omission, so that narrowing one of
-- these later is a deliberate change and not a silent one.

select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'field_identity', 'field_daily_moment', 'field_clusters',
        'field_horizons', 'field_questions', 'field_rhythms', 'field_evidence'
      )
      and column_name = 'visibility'
  ),
  0::bigint,
  'couple-scoped and derived tables carry no visibility column'
);

select * from finish();
rollback;
