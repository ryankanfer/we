-- "Only me", after pairing. See `20260923120000_private_by_choice.sql`.
--
-- The bar: a paired person can keep an item to themselves; their partner can
-- neither read it, nor flip it, nor learn of it through its capture; only its
-- author can share it; and nothing can make a shared row private again.

begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- MARK: Two people, already a couple ----------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '92000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'only-me-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'only-me-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select public.create_couple();

reset role;
create temp table ctx on commit drop as
select couple_id from public.couple_members
where profile_id = '92000000-0000-0000-0000-000000000001';

-- Joined directly, as in `field_solo_visibility.test.sql`: what is under test
-- is the visibility rule, not the invitation.
insert into public.couple_members (couple_id, profile_id, hue, member_slot)
select couple_id, '92000000-0000-0000-0000-000000000002', 'sage', 2
from ctx;

-- MARK: A keeps one thing to themselves --------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

insert into public.field_life_items (
  id, couple_id, title, category, source, visibility
)
values (
  '92000000-0000-0000-0000-00000000a001', public.my_couple_id(),
  'Look into a therapist', 'notes', 'captured', 'private'
);

insert into public.field_captures (
  id, couple_id, text, destination, reasoning, visibility
)
values (
  '92000000-0000-0000-0000-00000000a001', public.my_couple_id(),
  'look into a therapist', '', '', 'private'
);

insert into public.field_life_items (couple_id, title, category, source)
values (public.my_couple_id(), 'Book the ferry', 'trips', 'captured');

select is(
  (
    select visibility from public.field_life_items
    where id = '92000000-0000-0000-0000-00000000a001'
  ),
  'private',
  'a paired person can ask for private, and gets it'
);

select is(
  (select visibility from public.field_life_items where title = 'Book the ferry'),
  'shared',
  'not asking still means shared, as it always has'
);

-- MARK: B cannot see, flip, or infer it --------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.field_life_items), 1::bigint,
  'B sees the shared item and not the private one'
);
select is(
  (select count(*) from public.field_captures), 0::bigint,
  'B cannot read the capture the private item was filed from'
);

update public.field_life_items
set visibility = 'shared'
where id = '92000000-0000-0000-0000-00000000a001';

reset role;
select is(
  (
    select visibility from public.field_life_items
    where id = '92000000-0000-0000-0000-00000000a001'
  ),
  'private',
  'B cannot share something that is not theirs'
);

-- MARK: A shares it, one way -------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

-- A whole-row upsert, the way the app writes, rather than a bare UPDATE.
insert into public.field_life_items (
  id, couple_id, title, category, source, visibility
)
values (
  '92000000-0000-0000-0000-00000000a001', public.my_couple_id(),
  'Look into a therapist', 'notes', 'captured', 'shared'
)
on conflict (id) do update
  set title = excluded.title, visibility = excluded.visibility;

reset role;
select is(
  (
    select visibility from public.field_life_items
    where id = '92000000-0000-0000-0000-00000000a001'
  ),
  'shared',
  'the author can share their own item'
);
select is(
  (
    select visibility from public.field_captures
    where id = '92000000-0000-0000-0000-00000000a001'
  ),
  'shared',
  'and its capture crosses with it'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

update public.field_life_items
set visibility = 'private'
where id = '92000000-0000-0000-0000-00000000a001';

insert into public.field_life_items (
  id, couple_id, title, category, source, visibility
)
values (
  '92000000-0000-0000-0000-00000000a001', public.my_couple_id(),
  'Look into a therapist', 'notes', 'captured', 'private'
)
on conflict (id) do update set visibility = excluded.visibility;

reset role;
select is(
  (
    select visibility from public.field_life_items
    where id = '92000000-0000-0000-0000-00000000a001'
  ),
  'shared',
  'nothing makes a shared row private again, by update or by upsert'
);

-- An edit that does not mention visibility leaves it alone.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

insert into public.field_life_items (
  id, couple_id, title, category, source, visibility
)
values (
  '92000000-0000-0000-0000-00000000a002', public.my_couple_id(),
  'Journal about the move', 'notes', 'captured', 'private'
);

update public.field_life_items
set title = 'Journal about the move, again'
where id = '92000000-0000-0000-0000-00000000a002';

reset role;
select is(
  (
    select visibility from public.field_life_items
    where id = '92000000-0000-0000-0000-00000000a002'
  ),
  'private',
  'editing a private item keeps it private'
);

-- MARK: The solo-era crossing never publishes "Only me" --------------------
--
-- The crossing decision is remembered per device, so a reinstall can ask it
-- again. "Bring it across" must still move only what was written before the
-- partner joined. B's join is moved an hour back so that A's rows above,
-- written at this transaction's `now()`, are unambiguously after it.

reset role;
update public.couple_members
set joined_at = now() - interval '1 hour'
where profile_id = '92000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  public.field_solo_history_count(), 0,
  'nothing chosen as "Only me" is offered as solo history'
);
select is(
  public.field_share_solo_history(), 0,
  'and the crossing moves none of it'
);

reset role;
select is(
  (
    select visibility from public.field_life_items
    where id = '92000000-0000-0000-0000-00000000a002'
  ),
  'private',
  'the private note is still private after the crossing ran'
);

select * from finish();
rollback;
