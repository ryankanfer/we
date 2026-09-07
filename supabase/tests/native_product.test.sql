begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table('public', 'plans', 'plans table exists');
select has_table('public', 'responsibilities', 'responsibilities table exists');
select has_table('public', 'relationship_archives', 'relationship archives table exists');
select has_table('public', 'insight_declines', 'private insight declines table exists');
select has_column('public', 'couple_members', 'hue_chosen_at', 'membership stores hue completion');
select has_column('public', 'couple_members', 'member_slot', 'membership has a two-person slot');
select ok(
  exists (
    select 1 from pg_constraint
    where conname = 'couple_members_couple_slot_key'
  ),
  'database enforces one member per couple slot'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conname = 'couple_members_profile_id_key'
  ),
  'database enforces one active couple per profile'
);
select ialike(
  pg_get_functiondef('public.join_couple(text)'::regprocedure),
  '%FOR UPDATE%',
  'join code redemption serializes concurrent callers'
);
select ialike(
  pg_get_functiondef('public.gen_join_code()'::regprocedure),
  '%gen_random_bytes%',
  'join codes use cryptographic entropy'
);
select ialike(
  pg_get_functiondef('private.prepare_shared_item()'::regprocedure),
  '%FOR KEY SHARE%',
  'shared item mutations serialize with relationship deletion'
);
select ialike(
  pg_get_functiondef('public.create_plan(uuid,text,text,date)'::regprocedure),
  '%lock_relationship%',
  'plan writes take the relationship advisory lock'
);
select ialike(
  pg_get_functiondef('public.delete_my_account()'::regprocedure),
  '%lock_relationship%',
  'account deletion takes the relationship advisory lock first'
);
select ok(
  not has_table_privilege('authenticated', 'public.plans', 'INSERT'),
  'authenticated clients cannot bypass plan RPCs'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.responsibilities',
    'UPDATE'
  ),
  'authenticated clients cannot bypass responsibility RPCs'
);
select ialike(
  pg_get_functiondef('public.assert_my_insight(uuid)'::regprocedure),
  '%FOR KEY SHARE%',
  'trust mutations serialize with relationship deletion'
);
select is(
  (
    -- `pronargdefaults` is smallint; the literal below is integer, and
    -- pgTAP's `is()` needs both sides to agree or the file aborts here.
    select pronargdefaults::integer
    from pg_proc
    where oid = 'public.submit_response(uuid,text,boolean,text)'::regprocedure
  ),
  1,
  'response notes remain optional while AI consent is required'
);
select is(
  (
    -- `pronargdefaults` is smallint; the literal below is integer, and
    -- pgTAP's `is()` needs both sides to agree or the file aborts here.
    select pronargdefaults::integer
    from pg_proc
    where oid = 'public.resolve_insight(uuid,text,text)'::regprocedure
  ),
  1,
  'resolution choices are optional at the PostgREST RPC boundary'
);
select ok(
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'plans'),
  'plans publish realtime changes'
);
select ok(
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'responsibilities'),
  'responsibilities publish realtime changes'
);
select ok(
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'relationship_archives'),
  'archives publish relationship-ended changes'
);
select ok(
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'insight_declines'),
  'private declines publish owner-visible changes'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'native-a@example.test', crypt('password-a', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name":"Partner A"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'native-b@example.test', crypt('password-b', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name":"Partner B"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'native-outsider@example.test', crypt('password-c', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name":"Outsider"}', now(), now());

insert into public.couples (id, join_code, created_by)
values ('20000000-0000-0000-0000-000000000001', 'NATIVE', '10000000-0000-0000-0000-000000000001');

insert into public.couple_members (
  couple_id, profile_id, hue, hue_chosen_at, member_slot
) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'burgundy', now(), 1),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'sage', now(), 2);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$select public.create_plan(
    '20000000-0000-0000-0000-000000000001',
    'Shared plan',
    'Safe archive note',
    null
  )$$,
  'a partner creates a plan through the mutation RPC'
);

select lives_ok(
  $$select public.create_responsibility(
    '20000000-0000-0000-0000-000000000001',
    'Shared responsibility',
    'Safe responsibility note',
    null
  )$$,
  'a partner creates a responsibility through the mutation RPC'
);

select is((select count(*) from public.plans), 1::bigint, 'first partner reads shared plans');
select is((select count(*) from public.responsibilities), 1::bigint, 'first partner reads shared responsibilities');

reset role;
insert into public.relationship_archives (
  id, owner_id, ended_at, snapshot_version, snapshot
) values (
  '50000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  now(),
  1,
  '{"plans":[],"responsibilities":[],"resolutions":[]}'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is((select count(*) from public.plans), 0::bigint, 'outsider cannot read plans');
select is((select count(*) from public.responsibilities), 0::bigint, 'outsider cannot read responsibilities');
select is((select count(*) from public.relationship_archives), 0::bigint, 'non-owner cannot read an archive');

select throws_like(
  $$insert into public.plans (couple_id, title)
    values ('20000000-0000-0000-0000-000000000001', 'Outsider plan')$$,
  '%permission denied%',
  'direct plan writes are unavailable'
);
select throws_like(
  $$insert into public.responsibilities (couple_id, title)
    values ('20000000-0000-0000-0000-000000000001', 'Outsider responsibility')$$,
  '%permission denied%',
  'direct responsibility writes are unavailable'
);
select throws_like(
  $$update public.plans set title = 'OUTSIDER EDIT'$$,
  '%permission denied%',
  'direct plan updates are unavailable'
);
select throws_like(
  $$update public.responsibilities set title = 'OUTSIDER EDIT'$$,
  '%permission denied%',
  'direct responsibility updates are unavailable'
);

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*) from public.relationship_archives), 1::bigint, 'archive owner can read an archive');

reset role;
select is(
  (select title from public.plans where title = 'Shared plan'),
  'Shared plan',
  'outsider cannot update a plan'
);
select is(
  (select title from public.responsibilities where title = 'Shared responsibility'),
  'Shared responsibility',
  'outsider cannot update a responsibility'
);
select is(
  (select created_by from public.plans where title = 'Shared plan'),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'creator attribution is server controlled'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select lives_ok(
  $$select public.update_plan(
    (select id from public.plans where title = 'Shared plan'),
    'Shared plan edited',
    'Safe archive note',
    null
  )$$,
  'either partner may edit a plan through the RPC'
);
select lives_ok(
  $$select public.set_plan_status(
    (select id from public.plans where title = 'Shared plan edited'),
    'completed'
  )$$,
  'either partner may complete a plan through the RPC'
);

reset role;
select is(
  (select updated_by from public.plans where title = 'Shared plan edited'),
  '10000000-0000-0000-0000-000000000002'::uuid,
  'either partner may edit with server-controlled attribution'
);
select isnt(
  (select completed_at from public.plans where title = 'Shared plan edited'),
  null::timestamptz,
  'completing a shared item records server time'
);

insert into public.insights (
  id, couple_id, seed_key, kind, domain, present, title,
  body, evidence, source, options, sort
) values
  ('60000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'pending-secret', 'relational', 'us', true, 'Pending private title', 'body', 'evidence', 'source', array['secret-choice'], 20),
  ('60000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'resolved-safe', 'relational', 'us', true, 'Completed mutual title', 'body', 'evidence', 'source', array['safe-choice'], 21),
  ('60000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'owner-private', 'relational', 'us', true, 'OWNER_ONLY_INSIGHT', 'owner body', 'owner evidence', 'source', array['owner-choice'], 22);

insert into public.insight_consent (
  insight_id, visibility, owner_id, readiness, initiator_id,
  requested_at, resolution_type, resolution_choice, resolved_at
) values
  ('60000000-0000-0000-0000-000000000001', 'mutual', null, 'requested', '10000000-0000-0000-0000-000000000001', now(), null, null, null),
  ('60000000-0000-0000-0000-000000000002', 'mutual', null, 'accepted', '10000000-0000-0000-0000-000000000001', now(), 'settled', 'safe-choice', now()),
  ('60000000-0000-0000-0000-000000000003', 'private', '10000000-0000-0000-0000-000000000001', 'idle', null, null, null, null, null);

insert into public.responses (insight_id, profile_id, status, choice, note)
values ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'submitted', 'UNREVEALED_SECRET_CHOICE', 'UNREVEALED_SECRET_NOTE');

insert into public.reflections (couple_id, owner_id, domain, kind, text)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'us', 'reflection', 'PRIVATE_REFLECTION_SECRET');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(
  (select count(*) from public.insights where id = '60000000-0000-0000-0000-000000000003'),
  0::bigint,
  'partner cannot read an owner-private insight'
);
select is(
  (select count(*) from public.insight_consent where insight_id = '60000000-0000-0000-0000-000000000003'),
  0::bigint,
  'partner cannot read owner-private consent metadata'
);
select lives_ok(
  $$select public.decline_reveal('60000000-0000-0000-0000-000000000001')$$,
  'declining succeeds privately'
);
select is(
  (
    select count(*)
    from public.insight_declines
    where insight_id = '60000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the invitee can read their own private decline'
);

reset role;
select is(
  (select readiness from public.insight_consent where insight_id = '60000000-0000-0000-0000-000000000001'),
  'requested',
  'decline leaves no shared state change'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is(
  (
    select count(*)
    from public.insight_declines
    where insight_id = '60000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the initiator cannot read the invitee private decline'
);
select lives_ok(
  $$select public.withdraw_reveal('60000000-0000-0000-0000-000000000001')$$,
  'withdrawal succeeds'
);
reset role;
select is(
  (
    select count(*)
    from public.insight_declines
    where insight_id = '60000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'withdrawal removes the private decline marker'
);
select ok(
  not exists (
    select 1
    from public.insight_consent
    where insight_id = '60000000-0000-0000-0000-000000000001'
      and (
        readiness <> 'idle'
        or initiator_id is not null
        or requested_at is not null
      )
  ),
  'withdrawal leaves no persistent partner-side marker'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_like(
  $$select public.resolve_insight(
    '60000000-0000-0000-0000-000000000002',
    'released',
    null
  )$$,
  '%already resolved%',
  'a completed mutual resolution cannot be overwritten'
);
select lives_ok('select public.delete_my_account()', 'account deletion completes as the requesting user');

reset role;
select ialike(
  pg_get_functiondef('private.delete_my_account()'::regprocedure),
  '%from public.couples%for update%',
  'account deletion serializes on the relationship'
);
select is((select count(*) from auth.users where id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'requesting auth account is deleted');
-- MARK: What departure leaves standing --------------------------------------
--
-- The nine assertions that used to sit here asserted the 2026-07-25 design:
-- the couple deleted outright and a sanitized `relationship_archives` snapshot
-- handed to the survivor as consolation. `20260808000000_account_departure.sql`
-- replaced it deliberately, and its header says why — deleting the couple
-- "destroys the *entire shared field*" belonging to somebody who was never
-- party to the decision, and the archive that softened it was "empty in
-- practice and unreachable in fact", written from tables the v2 rewrite
-- stopped using and read back only by a screen the Field shell replaced.
--
-- These assertions never ran: the schema lane died at 20260820161957 long
-- before pgTAP, so nothing caught them still describing the old contract.
-- They are rewritten to the one that shipped, which is the stronger promise:
-- the leaver takes their own material and the shared record stays.

select is(
  (select count(*) from public.couples where id = '20000000-0000-0000-0000-000000000001'),
  1::bigint,
  'the shared field survives one person leaving it'
);
select isnt(
  (select departed_at from public.couples where id = '20000000-0000-0000-0000-000000000001'),
  null,
  'and it is marked as departed, so the survivor can be told'
);
select is((select count(*) from public.profiles where id = '10000000-0000-0000-0000-000000000002'), 1::bigint, 'surviving profile remains');
select is(
  (select count(*) from public.couple_members where profile_id = '10000000-0000-0000-0000-000000000002'),
  1::bigint,
  'the survivor keeps their membership, and their A/B side with it'
);
select is(
  (select count(*) from public.couple_members where profile_id = '10000000-0000-0000-0000-000000000001'),
  0::bigint,
  'the leaver vacates their slot'
);
select is(
  (select count(*) from public.relationship_archives where owner_id = '10000000-0000-0000-0000-000000000002'),
  0::bigint,
  'no consolation archive is written, because there is nothing to console'
);

-- The leaver's own material, and only the leaver's own material.
select is(
  (select count(*) from public.insights where id = '60000000-0000-0000-0000-000000000003'),
  0::bigint,
  'the private insight goes with the person whose it was'
);
select is(
  (select count(*) from public.reflections where text = 'PRIVATE_REFLECTION_SECRET'),
  0::bigint,
  'so does the private reflection'
);
select is(
  (select count(*) from public.responses where choice = 'UNREVEALED_SECRET_CHOICE'),
  0::bigint,
  'and the response that was never revealed'
);
select ok(
  (
    select readiness = 'withdrawn' and initiator_id is null
    from public.insight_consent
    where insight_id = '60000000-0000-0000-0000-000000000001'
  ),
  'a crossing asked for by somebody no longer here is withdrawn, not left acceptable'
);
select is(
  (
    select resolution_choice from public.insight_consent
    where insight_id = '60000000-0000-0000-0000-000000000002'
  ),
  'safe-choice',
  'what the two of them settled together stands'
);

select * from finish();
rollback;
