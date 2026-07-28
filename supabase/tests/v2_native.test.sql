begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'public',
  'relationship_presence',
  'presence is persisted'
);
select has_table(
  'public',
  'signal_consents',
  'signal consent is persisted'
);
select has_table('public', 'anchors', 'Anchors are persisted');
select has_table(
  'public',
  'responsibility_handoffs',
  'handoffs are persisted'
);
select has_table(
  'public',
  'plan_approaches',
  'Approach is persisted'
);
select has_table(
  'public',
  'relationship_events',
  'Thread events are persisted'
);
select has_table('public', 'seasons', 'Seasons are persisted');
select has_table(
  'public',
  'contextual_suggestions',
  'contextual suggestions are persisted'
);
select has_table(
  'public',
  'contextual_suggestion_dismissals',
  'suggestion dismissals are persisted privately'
);
select has_table(
  'public',
  'insight_grace',
  'decline grace survives invitation state changes'
);

select has_column(
  'public',
  'responsibilities',
  'related_plan_id',
  'responsibility keeps its related plan'
);
select has_column(
  'public',
  'responsibilities',
  'suggestion_provenance',
  'responsibility keeps suggestion provenance'
);
select has_column(
  'public',
  'responsibilities',
  'scheduled_on',
  'suggested shared care may have a date'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_trigger
    where tgrelid = 'public.insight_declines'::regclass
      and tgname = 'insight_declines_record_grace'
      and not tgisinternal
  ),
  1::bigint,
  'reconciliation leaves exactly one decline-grace trigger'
);
select ok(
  (
    select
      (tgtype & 4) <> 0
      and (tgtype & 16) <> 0
    from pg_catalog.pg_trigger
    where tgrelid = 'public.insight_declines'::regclass
      and tgname = 'insight_declines_record_grace'
      and not tgisinternal
  ),
  'the reconciled grace trigger handles both insert and update'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and policyname = 'contextual_suggestions_select'
  ),
  1::bigint,
  'reconciliation leaves one contextual-suggestion policy'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'contextual_suggestions'
  ),
  1::bigint,
  'reconciliation leaves one realtime publication membership'
);
select has_function(
  'public',
  'partner_answer_statuses',
  array[]::text[],
  'partner answer state has a status-only interface'
);
select is(
  (
    select string_agg(p.proargnames[position], ',' order by position)
    from pg_proc p,
      generate_subscripts(p.proallargtypes, 1) as position
    where p.oid = 'public.partner_answer_statuses()'::regprocedure
      and p.proargmodes[position] = 't'
  ),
  'insight_id,profile_id,has_answered',
  'status-only interface cannot return a private choice or note'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.contextual_suggestions',
    'INSERT'
  ),
  'clients cannot write suggestion rows directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.relationship_events',
    'INSERT'
  ),
  'clients cannot forge Thread events'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.seasons',
    'INSERT'
  ),
  'clients cannot forge Seasons'
);

select like(
  pg_get_functiondef(
    'public.confirm_contextual_suggestion(uuid,text,text,uuid,date)'
      ::regprocedure
  ),
  '%lock_relationship%',
  'suggestion confirmation takes the relationship lock'
);
select like(
  pg_get_functiondef(
    'public.confirm_contextual_suggestion(uuid,text,text,uuid,date)'
      ::regprocedure
  ),
  '%for update%',
  'suggestion confirmation locks its suggestion row'
);
select unlike(
  pg_get_functiondef(
    'public.refresh_contextual_suggestions(date)'::regprocedure
  ),
  '%reflections%',
  'suggestion generation cannot query private reflections'
);
select unlike(
  pg_get_functiondef(
    'public.refresh_contextual_suggestions(date)'::regprocedure
  ),
  '%responses%',
  'suggestion generation cannot query unrevealed responses'
);
select like(
  pg_get_functiondef(
    'public.create_ready_season()'::regprocedure
  ),
  '%interval ''6 weeks''%',
  'Season readiness enforces six weeks'
);
select like(
  pg_get_functiondef(
    'public.create_ready_season()'::regprocedure
  ),
  '%v_count < 6%',
  'Season readiness enforces six events'
);
select like(
  pg_get_functiondef(
    'public.create_ready_season()'::regprocedure
  ),
  '%v_types < 2%',
  'Season readiness enforces two event types'
);
select like(
  pg_get_functiondef(
    'public.create_ready_season()'::regprocedure
  ),
  '%v_months < 2%',
  'Season readiness enforces two calendar months'
);
select unlike(
  pg_get_functiondef(
    'private.enrich_v2_relationship_archive()'::regprocedure
  ),
  '%signal_consents%',
  'account archives exclude private signal choices'
);
select unlike(
  pg_get_functiondef(
    'private.enrich_v2_relationship_archive()'::regprocedure
  ),
  '%contextual_suggestion_dismissals%',
  'account archives exclude private suggestion dismissals'
);
select unlike(
  pg_get_functiondef(
    'private.enrich_v2_relationship_archive()'::regprocedure
  ),
  '%insight_grace%',
  'account archives exclude private decline grace'
);
select like(
  pg_get_functiondef(
    'private.enrich_v2_relationship_archive()'::regprocedure
  ),
  '%revealed_at is not null%',
  'account archives include only revealed Approaches'
);
select like(
  pg_get_functiondef(
    'private.enrich_v2_relationship_archive()'::regprocedure
  ),
  '%''responsibilities''%',
  'the reconciled archive includes responsibilities'
);
select like(
  pg_get_functiondef(
    'private.enrich_v2_relationship_archive()'::regprocedure
  ),
  '%relatedPlanID%',
  'the reconciled archive preserves related-plan provenance'
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
    'v2-a@example.test',
    crypt('password-a', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Ryan"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '71000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'v2-b@example.test',
    crypt('password-b', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Dylan"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '71000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'v2-outsider@example.test',
    crypt('password-c', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Outsider"}',
    now(),
    now()
  );

insert into public.couples (id, join_code, created_by)
values (
  '72000000-0000-0000-0000-000000000001',
  'V2TEST',
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

select is(
  (
    select count(*)
    from public.signal_consents
    where couple_id = '72000000-0000-0000-0000-000000000001'
  ),
  8::bigint,
  'each partner receives four explicit signal choices'
);
select is(
  (
    select count(*)
    from public.signal_consents
    where couple_id = '72000000-0000-0000-0000-000000000001'
      and signal = 'private_reflections'
      and enabled
  ),
  0::bigint,
  'private reflection starts and remains off'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.create_plan(
    '72000000-0000-0000-0000-000000000001',
    'Saturday''s party',
    'Hosting friends for dinner',
    current_date + 7
  )$$,
  'Ryan can create the upcoming party plan'
);
select lives_ok(
  'select public.refresh_contextual_suggestions(current_date)',
  'the deterministic suggestion refresh succeeds'
);
select is(
  (select count(*) from public.contextual_suggestions),
  1::bigint,
  'one party-derived grocery suggestion appears'
);
select is(
  (
    select evidence->>'context'
    from public.contextual_suggestions
  ),
  'For Saturday''s party',
  'suggestion names the exact related plan'
);

select lives_ok(
  $$select public.dismiss_contextual_suggestion(
    (select id from public.contextual_suggestions limit 1)
  )$$,
  'Ryan can dismiss the suggestion privately'
);
select is(
  (select count(*) from public.contextual_suggestion_dismissals),
  1::bigint,
  'Ryan can read Ryan''s dismissal'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.contextual_suggestion_dismissals),
  0::bigint,
  'Dylan cannot read Ryan''s dismissal'
);
select is(
  (select count(*) from public.contextual_suggestions),
  1::bigint,
  'Ryan''s private dismissal does not hide Dylan''s suggestion'
);

select lives_ok(
  $$select public.confirm_contextual_suggestion(
    (select id from public.contextual_suggestions limit 1),
    'Grocery run and ice',
    'Review before adding',
    null,
    current_date + 6
  )$$,
  'Dylan can review, edit, and confirm the suggestion'
);
select is(
  (
    select count(*)
    from public.responsibilities
    where related_plan_id = (
      select id from public.plans where title = 'Saturday''s party'
    )
  ),
  1::bigint,
  'confirmation creates exactly one related responsibility'
);
select isnt(
  (
    select suggestion_provenance
    from public.responsibilities
    where title = 'Grocery run and ice'
  ),
  null::jsonb,
  'confirmed care keeps auditable provenance'
);
select lives_ok(
  $$select public.confirm_contextual_suggestion(
    (select id from public.contextual_suggestions limit 1),
    'Duplicate grocery run',
    null,
    null,
    current_date + 6
  )$$,
  'a concurrent-equivalent second confirmation is idempotent'
);
select is(
  (
    select count(*)
    from public.responsibilities
    where related_plan_id is not null
  ),
  1::bigint,
  'duplicate confirmation never creates duplicate care'
);
select is(
  (
    select count(*)
    from public.contextual_suggestions
    where confirmed_responsibility_id is null
  ),
  0::bigint,
  'confirmed suggestions disappear for both partners'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.contextual_suggestions),
  0::bigint,
  'an outsider cannot read suggestions'
);
select is(
  (select count(*) from public.relationship_events),
  0::bigint,
  'an outsider cannot read Thread'
);

reset role;

insert into public.relationship_events (
  id,
  couple_id,
  event_type,
  source_id,
  title,
  occurred_at,
  provenance
)
select
  (
    '73000000-0000-0000-0000-00000000000' || value::text
  )::uuid,
  '72000000-0000-0000-0000-000000000001',
  case
    when value % 2 = 0 then 'plan_completed'
    else 'responsibility_completed'
  end,
  (
    '74000000-0000-0000-0000-00000000000' || value::text
  )::uuid,
  'Shared closure ' || value,
  now() - interval '100 days' + (value * interval '10 days'),
  jsonb_build_array(jsonb_build_object(
    'kind', 'relationship_event',
    'id', (
      '74000000-0000-0000-0000-00000000000' || value::text
    )::uuid,
    'label', 'Shared closure ' || value,
    'shared', true
  ))
from generate_series(1, 6) as value;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  'select public.create_ready_season()',
  'six weeks, six events, two types, and two months make a Season'
);
select is(
  (select cardinality(event_ids) from public.seasons limit 1),
  6,
  'the Season records the exact six evidence events'
);
select throws_like(
  'select public.create_ready_season()',
  '%a season is not ready%',
  'events before the previous cutoff cannot form another Season'
);

select * from finish();
rollback;
