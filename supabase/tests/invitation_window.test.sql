-- The acceptance test for the invitation window.
--
-- The bar: if a code that was shared once still works forever, the phase is
-- not done. Four properties, and each has a way of quietly not holding:
--
--   bounded    an expired code must be refused even though the row is still
--              there and still looks live to a naive query
--   single use the second redemption must fail, including when the first
--              person has since left and a slot is free again
--   revocable  withdrawal must take effect immediately, not at next expiry
--   singular   two concurrent regenerations must not both survive
--
-- ON TIME
--
-- Expiry is forced by writing `expires_at` into the past as the table owner
-- rather than by waiting. Clients cannot reach the column — every write goes
-- through an RPC — so this reproduces the state, not the mechanism.
--
-- ON ROLES
--
-- Temp tables are built after `reset role`, following the convention in
-- `solo_visibility_backfill.test.sql`.

begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '95000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'invite-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Inviter"}', now(), now()
  ),
  (
    '95000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'invite-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Invited"}', now(), now()
  ),
  (
    '95000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'invite-c@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Outsider"}', now(), now()
  ),
  (
    '95000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'invite-d@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Fourth"}', now(), now()
  );

-- MARK: Creating a couple mints an invitation with an end -------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_couple()$$,
  'the inviter has a space'
);

reset role;

create temp table ctx on commit drop as
select cm.couple_id
from public.couple_members cm
where cm.profile_id = '95000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.invitations
   where couple_id = (select couple_id from ctx)
     and consumed_at is null and revoked_at is null),
  1,
  'creating a couple mints exactly one live invitation'
);

-- The window is the point. A code with no end is the thing this replaces.
select ok(
  (select i.expires_at > now() from public.invitations i
   where i.couple_id = (select couple_id from ctx)),
  'the invitation has not expired yet'
);

select ok(
  (select i.expires_at <= now() + interval '7 days' from public.invitations i
   where i.couple_id = (select couple_id from ctx)),
  'the window is seven days, not forever'
);

-- `Couple.joinCode` is non-optional in `Models.swift:20`, so the mirror has
-- to hold the live code or every existing client shows a string that will be
-- refused.
select is(
  (select c.join_code from public.couples c
   where c.id = (select couple_id from ctx)),
  (select i.code from public.invitations i
   where i.couple_id = (select couple_id from ctx)
     and i.consumed_at is null and i.revoked_at is null),
  'couples.join_code mirrors the live invitation'
);

-- MARK: Nobody can enumerate live codes -------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*)::int from public.invitations),
  0,
  'an outsider cannot read invitations, only redeem one they were given'
);

select throws_ok(
  format(
    $$insert into public.invitations (couple_id, code, expires_at)
      values (%L, 'FORGEDCODE', now() + interval '100 years')$$,
    (select couple_id from ctx)
  ),
  '42501',
  null::text,
  'a client cannot write its own invitation, and so cannot set its own window'
);

-- MARK: Bounded -------------------------------------------------------------

reset role;

create temp table expiring on commit drop as
select i.code from public.invitations i
where i.couple_id = (select couple_id from ctx);

update public.invitations
set expires_at = now() - interval '1 minute'
where couple_id = (select couple_id from ctx);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

-- Distinct from 'that code does not match anything' on purpose: the two are
-- different facts about the world, and collapsing them means somebody retypes
-- a code that was never going to work.
select throws_like(
  format($$select public.join_couple(%L)$$, (select code from expiring)),
  '%expired%',
  'an expired invitation is refused, and says so'
);

-- MARK: Regenerating revokes the previous one -------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_invitation()$$,
  'the inviter can issue a fresh invitation'
);

reset role;

select is(
  (select count(*)::int from public.invitations
   where couple_id = (select couple_id from ctx)
     and consumed_at is null and revoked_at is null),
  1,
  'still exactly one live invitation — "the code" stays an unambiguous phrase'
);

create temp table live on commit drop as
select i.code from public.invitations i
where i.couple_id = (select couple_id from ctx)
  and i.consumed_at is null and i.revoked_at is null;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

-- "I sent it to the wrong person" has to mean the old one stops working at
-- the instant the new one starts. The superseded code was also expired above,
-- so this asserts only that it is refused, not which reason wins.
select throws_ok(
  format($$select public.join_couple(%L)$$, (select code from expiring)),
  'P0001',
  null::text,
  'the superseded code no longer works'
);

-- MARK: Single use ----------------------------------------------------------

select lives_ok(
  format($$select public.join_couple(%L)$$, (select code from live)),
  'the invited person redeems it'
);

reset role;

select isnt(
  (select i.consumed_at from public.invitations i
   where i.code = (select code from live)),
  null,
  'redemption is recorded on the invitation'
);

-- The dangerous case is not a second redemption while the space is full —
-- the member count catches that on its own. It is a second redemption after a
-- slot frees up again, which is exactly what `20260808000000` makes possible.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.delete_my_account()$$,
  'the invited person later leaves, vacating their slot'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);

select throws_like(
  format($$select public.join_couple(%L)$$, (select code from live)),
  '%already been used%',
  'a spent code does not come back to life when a slot does'
);

-- MARK: Revocable -----------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_invitation()$$,
  'the inviter issues another one'
);

reset role;

create temp table withdrawn on commit drop as
select i.code from public.invitations i
where i.couple_id = (select couple_id from ctx)
  and i.consumed_at is null and i.revoked_at is null;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.revoke_invitation()$$,
  'the inviter withdraws it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);

select throws_like(
  format($$select public.join_couple(%L)$$, (select code from withdrawn)),
  '%withdrawn%',
  'a withdrawn invitation stops working immediately, not at expiry'
);

reset role;

-- The mirror must not keep displaying a code that would now be refused.
select isnt(
  (select c.join_code from public.couples c
   where c.id = (select couple_id from ctx)),
  (select code from withdrawn),
  'the withdrawn code is no longer shown as the couple''s code'
);

-- MARK: Singular ------------------------------------------------------------
--
-- Enforced by a partial unique index rather than by the RPC, so that two
-- concurrent regenerations cannot both commit. Asserted as owner because no
-- client can reach the table to try.

select lives_ok(
  format(
    $$insert into public.invitations (couple_id, code, expires_at)
      values (%L, 'FIRSTLIVEONE', now() + interval '7 days')$$,
    (select couple_id from ctx)
  ),
  'with nothing live, one invitation can be inserted'
);

select throws_ok(
  format(
    $$insert into public.invitations (couple_id, code, expires_at)
      values (%L, 'SECONDLIVEONE', now() + interval '7 days')$$,
    (select couple_id from ctx)
  ),
  '23505',
  null::text,
  'a couple cannot hold two live invitations at once'
);

select * from finish();
rollback;
