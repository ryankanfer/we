begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- WE's trust model is meant to be enforced twice: row-level security decides
-- what a client may see, and table grants decide that a client may not write
-- relationship state at all. Only the SECURITY DEFINER RPCs write it.
--
-- Before 20260902120000 the second layer was missing on twenty tables — RLS
-- alone stood between a client and a forged Thread event, Season, consent row,
-- or a row in the partner's `responses`. These assertions keep it restored, so
-- one over-permissive policy can never by itself open a write path.

select ok(
  not has_table_privilege('authenticated', 'public.' || t, 'INSERT'),
  format('clients cannot insert into %s directly', t)
)
from unnest(array[
  'profiles',
  'couples',
  'couple_members',
  'insights',
  'insight_consent',
  'responses',
  'dismissals',
  'insight_declines',
  'insight_grace',
  'relationship_archives',
  'relationship_presence',
  'signal_consents',
  'anchors',
  'responsibility_handoffs',
  'plan_approaches',
  'relationship_events',
  'seasons',
  'contextual_suggestions',
  'contextual_suggestion_dismissals',
  'plans',
  'responsibilities'
]) as t;

select ok(
  not has_table_privilege('authenticated', 'public.' || t, 'UPDATE'),
  format('clients cannot update %s directly', t)
)
from unnest(array[
  'couples',
  'insights',
  'insight_consent',
  'responses',
  'dismissals',
  'insight_declines',
  'insight_grace',
  'relationship_archives',
  'relationship_presence',
  'signal_consents',
  'anchors',
  'responsibility_handoffs',
  'plan_approaches',
  'relationship_events',
  'seasons',
  'contextual_suggestions',
  'contextual_suggestion_dismissals',
  'plans',
  'responsibilities',
  'reflections'
]) as t;

select ok(
  not has_table_privilege('authenticated', 'public.' || t, 'DELETE'),
  format('clients cannot delete from %s directly', t)
)
from unnest(array[
  'profiles',
  'couples',
  'couple_members',
  'insights',
  'insight_consent',
  'responses',
  'dismissals',
  'reflections',
  'insight_declines',
  'insight_grace',
  'relationship_archives',
  'relationship_presence',
  'signal_consents',
  'anchors',
  'responsibility_handoffs',
  'plan_approaches',
  'relationship_events',
  'seasons',
  'contextual_suggestions',
  'contextual_suggestion_dismissals',
  'plans',
  'responsibilities'
]) as t;

-- The three writes a person genuinely makes on their own behalf survive.
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE'),
  'a person can still rename themselves'
);
select ok(
  has_column_privilege(
    'authenticated', 'public.couple_members', 'hue', 'UPDATE'
  ),
  'a person can still choose their hue'
);
select ok(
  has_column_privilege(
    'authenticated', 'public.couple_members', 'hue_chosen_at', 'UPDATE'
  ),
  'choosing a hue can still be recorded as complete'
);
select ok(
  has_table_privilege('authenticated', 'public.reflections', 'INSERT'),
  'a person can still keep a private reflection'
);

-- ...and nothing broader came with them.
select ok(
  not has_column_privilege(
    'authenticated', 'public.couple_members', 'member_slot', 'UPDATE'
  ),
  'a person cannot rewrite which side of the relationship they are'
);
select ok(
  not has_column_privilege(
    'authenticated', 'public.profiles', 'id', 'UPDATE'
  ),
  'a person cannot rewrite their own identity'
);

-- Reads are untouched.
select ok(
  has_table_privilege('authenticated', 'public.' || t, 'SELECT'),
  format('clients can still read %s', t)
)
from unnest(array[
  'plans',
  'responsibilities',
  'insights',
  'insight_consent',
  'responses',
  'relationship_events',
  'seasons',
  'anchors'
]) as t;

-- Regression: `plans` has no owner_id, and the shared BEFORE trigger used to
-- reference new.owner_id in a condition plpgsql resolves for every row type.
-- That made every plan write raise 42703, which took out the entire
-- "Add something ahead" path and left the Ahead tab permanently locked.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '80000000-0000-0000-0000-000000000001',
   'authenticated', 'authenticated', 'boundary-a@example.test',
   extensions.crypt('password-a', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"name":"Partner A"}',
   now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '80000000-0000-0000-0000-000000000002',
   'authenticated', 'authenticated', 'boundary-b@example.test',
   extensions.crypt('password-b', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"name":"Partner B"}',
   now(), now());

insert into public.couples (id, join_code, created_by)
values (
  '80000000-0000-0000-0000-0000000000cc',
  'BOUNDARY',
  '80000000-0000-0000-0000-000000000001'
);

insert into public.couple_members (
  couple_id, profile_id, hue, hue_chosen_at, member_slot
) values
  ('80000000-0000-0000-0000-0000000000cc',
   '80000000-0000-0000-0000-000000000001', 'burgundy', now(), 1),
  ('80000000-0000-0000-0000-0000000000cc',
   '80000000-0000-0000-0000-000000000002', 'sage', now(), 2);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_plan(
      '80000000-0000-0000-0000-0000000000cc',
      'Saturday''s party',
      'A few friends for dinner.',
      current_date + 7
    )$$,
  'a plan can be created — the shared trigger tolerates a row with no owner_id'
);

select lives_ok(
  $$select public.update_plan(
      (select id from public.plans where title = 'Saturday''s party'),
      'Saturday''s dinner',
      null,
      current_date + 7
    )$$,
  'a plan can be edited'
);

select lives_ok(
  $$select public.set_plan_status(
      (select id from public.plans where title = 'Saturday''s dinner'),
      'completed'
    )$$,
  'a plan can be completed'
);

select is(
  (select count(*)::integer from public.plans),
  1,
  'the plan is really there, not silently swallowed'
);

select is(
  (
    select created_by
    from public.plans
    where title = 'Saturday''s dinner'
  ),
  '80000000-0000-0000-0000-000000000001'::uuid,
  'attribution is still server controlled'
);

-- The ownership check the trigger performs for responsibilities still bites.
select throws_ok(
  $$select public.create_responsibility(
      '80000000-0000-0000-0000-0000000000cc',
      'Call the landlord',
      null,
      '80000000-0000-0000-0000-00000000dead'
    )$$,
  'responsibility owner is not in this WE space',
  'care cannot be assigned to someone outside the relationship'
);

select lives_ok(
  $$select public.create_responsibility(
      '80000000-0000-0000-0000-0000000000cc',
      'Call the landlord',
      null,
      '80000000-0000-0000-0000-000000000002'
    )$$,
  'care can be assigned to the partner'
);

select * from finish();
rollback;
