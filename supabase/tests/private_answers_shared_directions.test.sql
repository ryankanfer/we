begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table(
  'public',
  'shared_directions',
  'shared directions have a dedicated shared table'
);
select has_table(
  'public',
  'journey_response_receipts',
  'private answers leave only owner-readable submission receipts'
);
select hasnt_column(
  'public',
  'journey_response_receipts',
  'choice',
  'submission receipts cannot retain a choice'
);
select hasnt_column(
  'public',
  'journey_response_receipts',
  'note',
  'submission receipts cannot retain a private note'
);
select has_table(
  'public',
  'private_proposals',
  'Soft Start proposals have owner-only storage'
);
select has_table(
  'public',
  'offered_topics',
  'approved offer previews have separate storage'
);
select ok(
  not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'responses'
  ),
  'raw responses are absent from realtime'
);
select ok(
  not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'plan_approaches'
  ),
  'owner-only plan approaches are absent from shared realtime'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_directions'
  ),
  'safe shared directions publish realtime changes'
);
select unialike(
  pg_get_functiondef(
    'public.submit_response(uuid,text,boolean,text)'::regprocedure
  ),
  '%status = ''revealed''%',
  'submitting never reveals response rows'
);
select ialike(
  pg_get_functiondef(
    'public.resolve_insight(uuid,text,text)'::regprocedure
  ),
  '%v_direction.title%',
  'resolution persists only server-produced direction wording'
);
select ok(
  to_regprocedure('private.shared_direction_values(uuid)') is null,
  'the answer-blind static direction generator is retired'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '71000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'direction-a@example.test',
    crypt('password-a', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Direction A"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '71000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'direction-b@example.test',
    crypt('password-b', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Direction B"}',
    now(),
    now()
  );

insert into public.couples (id, join_code, created_by)
values (
  '72000000-0000-0000-0000-000000000001',
  'DIRECTION',
  '71000000-0000-0000-0000-000000000001'
);

insert into public.couple_members (
  couple_id,
  profile_id,
  hue,
  hue_chosen_at,
  member_slot
) values
  (
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    'burgundy',
    now(),
    1
  ),
  (
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000002',
    'sage',
    now(),
    2
  );

-- Seeded before the role switch on purpose. `authenticated` has no INSERT
-- on `public.plans` — that is the guarantee `native_product.test.sql:52`
-- asserts — so a fixture that writes one has to do it as the owner.
insert into public.plans (
  id,
  couple_id,
  title,
  created_by,
  updated_by
) values (
  '72500000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  'A private approach test',
  '71000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000001'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
reset role;

insert into public.insights (
  id,
  couple_id,
  seed_key,
  kind,
  domain,
  present,
  title,
  body,
  evidence,
  source,
  options,
  sort,
  journey_scope,
  trigger_provenance,
  subject_references,
  expires_at,
  context_snapshot
) values (
  '73000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  'tonight-private-direction',
  'logistical',
  'us',
  true,
  'How should tonight feel?',
  'Choose separately.',
  'A small check-in.',
  'A moment for tonight',
  array['Quiet and close', 'Out of the house'],
  1,
  'immediate',
  'upcomingPlan',
  '[{"kind":"plan","id":"tonight"}]'::jsonb,
  now() + interval '24 hours',
  jsonb_build_object('evidence', jsonb_build_array('A small check-in.'))
);

insert into public.insight_consent (
  insight_id,
  visibility,
  readiness,
  accepted_at
) values (
  '73000000-0000-0000-0000-000000000001',
  'mutual',
  'accepted',
  now()
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.submit_response(
    '73000000-0000-0000-0000-000000000001',
    'Quiet and close',
    false,
    'MUST_NOT_BE_STORED'
  )$$,
  'P0001',
  'OpenAI processing permission is required',
  'an answer cannot submit without explicit OpenAI processing consent'
);
select is(
  (
    select count(*) from public.responses
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'declining OpenAI processing stores no answer or note'
);
select lives_ok(
  $$select public.submit_response(
    '73000000-0000-0000-0000-000000000001',
    'Quiet and close',
    true,
    'FIRST_PRIVATE_NOTE'
  )$$,
  'the first private answer submits'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the partner cannot select the first raw response'
);
select throws_ok(
  $$select * from public.partner_answer_statuses()$$,
  '42501',
  null,
  'the partner cannot inspect even a boolean answer status'
);
select lives_ok(
  $$select public.submit_response(
    '73000000-0000-0000-0000-000000000001',
    'Out of the house',
    true,
    'SECOND_PRIVATE_NOTE'
  )$$,
  'the second private answer submits'
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'after both submit, the viewer still sees only their own response'
);
select is(
  (
    select count(*)
    from public.shared_directions
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the second submission exposes no direction before protected synthesis'
);

reset role;
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '73000000-0000-0000-0000-000000000001'
      and status = 'submitted'
  ),
  2::bigint,
  'both source rows remain submitted and owner-only'
);
select is(
  (
    select count(*)
    from public.journey_response_receipts
    where insight_id = '73000000-0000-0000-0000-000000000001'
      and ai_processing_consented_at is not null
      and ai_processing_consent_version = '2026-08-20'
  ),
  2::bigint,
  'both content-free receipts retain the accepted disclosure version'
);
select is(
  (
    select count(*)
    from public.journey_synthesis_jobs
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the second answer enqueues synthesis exactly once'
);
select lives_ok(
  $$select public.complete_journey_synthesis(
    '73000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'status', 'proposed',
      'summary', 'Leave room for a gentle evening',
      'rationale', 'The open evening supports a smaller shared beginning.',
      'proposed_actions', jsonb_build_array(jsonb_build_object(
        'id', 'evening-space',
        'kind', 'lifeItem',
        'title', 'Make space for the evening',
        'category', 'plans',
        'detail', null,
        'due_on', null
      ))
    ),
    'contract-test-v1'
  )$$,
  'the protected worker can persist a validated shared proposal'
);
select is(
  (
    select count(*) from public.responses
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'raw answers are deleted when proposal resolution finishes'
);
select is(
  (
    select count(*) from public.journey_response_receipts
    where insight_id = '73000000-0000-0000-0000-000000000001'
      and resolved_at is not null
      and ai_processing_consented_at is not null
      and ai_processing_consent_version = '2026-08-20'
  ),
  2::bigint,
  'only two content-free, versioned consent receipts remain'
);
select ok(
  (
    select concat_ws(' ', title, message)
      not like '%FIRST_PRIVATE_NOTE%'
      and concat_ws(' ', title, message)
        not like '%SECOND_PRIVATE_NOTE%'
      and concat_ws(' ', title, message)
        not like '%Quiet and close%'
      and concat_ws(' ', title, message)
        not like '%Out of the house%'
    from public.shared_directions
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  'shared wording contains neither answer nor note'
);
select throws_ok(
  $$insert into public.responses (
      insight_id,
      profile_id,
      status,
      choice
    ) values (
      '73000000-0000-0000-0000-000000000001',
      '71000000-0000-0000-0000-000000000001',
      'revealed',
      'Quiet and close'
    )
    on conflict (insight_id, profile_id)
    do update set status = excluded.status$$,
  '23514',
  null,
  'the legacy revealed status cannot be written'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.resolve_insight(
    '73000000-0000-0000-0000-000000000001',
    'settled',
    'RAW_RESOLUTION_SECRET'
  )$$,
  'a shared direction can be resolved'
);

reset role;
select ok(
  (
    select resolution_choice <> 'RAW_RESOLUTION_SECRET'
    from public.insight_consent
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  'caller-provided resolution wording is never persisted'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.confirm_shared_direction(
    '73000000-0000-0000-0000-000000000001', 'choose'
  )$$,
  'one person can privately choose the proposal'
);
select is(
  (select count(*) from public.field_journeys),
  0::bigint,
  'one acceptance cannot activate a journey'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select count(*) from public.direction_confirmations
    where insight_id = '73000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the second person cannot inspect the first confirmation'
);
select lives_ok(
  $$select public.confirm_shared_direction(
    '73000000-0000-0000-0000-000000000001', 'choose'
  )$$,
  'the second independent acceptance activates the journey'
);
select is(
  (select count(*) from public.field_journeys),
  1::bigint,
  'both acceptances expose one active journey'
);
select is(
  (
    select count(*) from public.field_life_items
    where journey_action_id = 'evening-space'
  ),
  1::bigint,
  'the reviewed Life action is created exactly once'
);
select lives_ok(
  $$select public.confirm_shared_direction(
    '73000000-0000-0000-0000-000000000001', 'choose'
  )$$,
  'a retried acceptance is idempotent'
);
select is(
  (
    select count(*) from public.field_life_items
    where journey_action_id = 'evening-space'
  ),
  1::bigint,
  'a retry cannot duplicate the reviewed Life action'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.set_plan_approach(
    '72500000-0000-0000-0000-000000000001',
    'gently',
    'FIRST_PRIVATE_APPROACH_NOTE'
  )$$,
  'the first plan approach stays on its owner side'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.plan_approaches
    where plan_id = '72500000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the partner cannot select the first raw plan approach'
);
select lives_ok(
  $$select public.set_plan_approach(
    '72500000-0000-0000-0000-000000000001',
    'directly',
    'SECOND_PRIVATE_APPROACH_NOTE'
  )$$,
  'the second partner can save an independent owner-only approach'
);
select is(
  (
    select count(*)
    from public.plan_approaches
    where plan_id = '72500000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'after both save, the viewer still sees only their own approach'
);

reset role;
select is(
  (
    select count(*)
    from public.plan_approaches
    where plan_id = '72500000-0000-0000-0000-000000000001'
      and revealed_at is not null
  ),
  0::bigint,
  'plan approaches can never enter the legacy revealed state'
);
select throws_ok(
  $$update public.plan_approaches
    set revealed_at = now()
    where plan_id = '72500000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'the database rejects any future attempt to reveal a plan approach'
);

insert into public.relationship_archives (
  owner_id,
  ended_at,
  snapshot_version,
  snapshot
) values (
  '71000000-0000-0000-0000-000000000002',
  now(),
  2,
  jsonb_build_object(
    'plans', '[]'::jsonb,
    'responsibilities', '[]'::jsonb,
    'resolutions', '[]'::jsonb,
    'approaches', jsonb_build_array(jsonb_build_object(
      'note', 'ARCHIVED_PRIVATE_APPROACH_NOTE'
    ))
  )
);
select ok(
  (
    select not (snapshot ? 'approaches')
    from public.relationship_archives
    where owner_id = '71000000-0000-0000-0000-000000000002'
    order by created_at desc
    limit 1
  ),
  'future relationship archives strip private plan approaches'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.claim_private_proposal(
    '74000000-0000-0000-0000-000000000001',
    'SOFT_START_PRIVATE_NOTE',
    'Protect Friday evening',
    'A quieter Friday',
    'How should Friday feel?',
    array['Quiet', 'Open', 'Social'],
    'deterministicFallback',
    now()
  )$$,
  'an account owner can claim a protected local proposal'
);
select lives_ok(
  $$select public.offer_private_proposal(
    (
      select id
      from public.private_proposals
      where local_id = '74000000-0000-0000-0000-000000000001'
    )
  )$$,
  'the owner can offer the frozen safe preview'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.private_proposals
    where local_id = '74000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the partner cannot read the source proposal'
);
select is(
  (
    select title
    from public.offered_topics
    where private_proposal_id = (
      select id
      from public.private_proposals
      where local_id = '74000000-0000-0000-0000-000000000001'
    )
  ),
  null::text,
  'private proposal IDs cannot be recovered through the owner-only table'
);
select is(
  (
    select title
    from public.offered_topics
    where couple_id = '72000000-0000-0000-0000-000000000001'
  ),
  'A quieter Friday',
  'the partner sees exactly the approved safe title'
);
select ok(
  (
    select row_to_json(ot)::text not like '%SOFT_START_PRIVATE_NOTE%'
    from public.offered_topics ot
    where couple_id = '72000000-0000-0000-0000-000000000001'
  ),
  'the offered row contains no private source note'
);

select * from finish();
rollback;
