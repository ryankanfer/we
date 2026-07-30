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
select unlike(
  pg_get_functiondef(
    'public.submit_response(uuid,text,text)'::regprocedure
  ),
  '%status = ''revealed''%',
  'submitting never reveals response rows'
);
select like(
  pg_get_functiondef(
    'public.resolve_insight(uuid,text,text)'::regprocedure
  ),
  '%v_direction.title%',
  'resolution persists only server-produced direction wording'
);
select unlike(
  pg_get_functiondef(
    'private.shared_direction_values(uuid)'::regprocedure
  ),
  '%public.responses%',
  'shared direction generation cannot query private response rows'
);
select unlike(
  pg_get_functiondef(
    'private.shared_direction_values(uuid)'::regprocedure
  ),
  '%v_aligned_choice%',
  'shared direction generation cannot vary with answer content or equality'
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

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
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
  sort
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
  1
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

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.submit_response(
    '73000000-0000-0000-0000-000000000001',
    'Quiet and close',
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
select is(
  (
    select count(*)
    from public.partner_answer_statuses()
    where insight_id = '73000000-0000-0000-0000-000000000001'
      and has_answered
  ),
  1::bigint,
  'the partner receives only a boolean held status'
);
select lives_ok(
  $$select public.submit_response(
    '73000000-0000-0000-0000-000000000001',
    'Out of the house',
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
  1::bigint,
  'the second submission creates one safe shared direction'
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
