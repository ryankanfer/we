begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- Structural contract: these are the live repository tables, not preview
-- fixtures. Actor attribution is protected at the database boundary and every
-- row that should arrive live is in the realtime publication.
select has_table('public', 'field_identity', 'Field identity is persisted');
select has_table('public', 'field_life_items', 'Life items are persisted');
select has_table('public', 'field_captures', 'captures are persisted');
select has_table('public', 'field_corrections', 'corrections are persisted');
select has_table('public', 'field_horizons', 'horizons are persisted');
select has_table('public', 'field_questions', 'questions are persisted');

-- Every field decoded by `FieldSupabaseBackend` is a PR-time schema
-- contract. The Swift adapter fixture proves decoding behavior; this catalog
-- check ties that fixture to the actual migrations so neither half can drift
-- while the other remains green.
select has_column(
  'public',
  projection.table_name,
  projection.column_name,
  format(
    '%s.%s remains in the live Field projection',
    projection.table_name,
    projection.column_name
  )
)
from (
  values
    ('field_identity', 'couple_id'),
    ('field_identity', 'swatch_a'),
    ('field_identity', 'swatch_b'),
    ('field_identity', 'lives_together'),
    ('field_identity', 'saving_for'),
    ('field_identity', 'looks_after'),
    ('field_away_windows', 'id'),
    ('field_away_windows', 'couple_id'),
    ('field_away_windows', 'profile_id'),
    ('field_away_windows', 'starts_at'),
    ('field_away_windows', 'ends_at'),
    ('field_away_windows', 'reason'),
    ('field_away_windows', 'place'),
    ('field_clusters', 'id'),
    ('field_clusters', 'couple_id'),
    ('field_clusters', 'title'),
    ('field_clusters', 'rationale'),
    ('field_clusters', 'tint'),
    ('field_clusters', 'timeframe'),
    ('field_clusters', 'anchor_date'),
    ('field_life_items', 'id'),
    ('field_life_items', 'couple_id'),
    ('field_life_items', 'title'),
    ('field_life_items', 'category'),
    ('field_life_items', 'owner'),
    ('field_life_items', 'due_on'),
    ('field_life_items', 'closes_at'),
    ('field_life_items', 'cluster_id'),
    ('field_life_items', 'source'),
    ('field_life_items', 'detail'),
    ('field_life_items', 'is_time_critical'),
    ('field_life_items', 'is_done'),
    ('field_life_items', 'created_by'),
    ('field_ours_items', 'added_by'),
    ('field_horizons', 'id'),
    ('field_horizons', 'couple_id'),
    ('field_horizons', 'title'),
    ('field_horizons', 'window_label'),
    ('field_horizons', 'owner'),
    ('field_horizons', 'is_primary'),
    ('field_horizons', 'thesis'),
    ('field_horizons', 'target_date'),
    ('field_horizons', 'linked_life_item_ids'),
    ('field_questions', 'id'),
    ('field_questions', 'couple_id'),
    ('field_questions', 'horizon_id'),
    ('field_questions', 'prompt'),
    ('field_questions', 'stakes'),
    ('field_questions', 'reasoning'),
    ('field_questions', 'choice_a'),
    ('field_questions', 'choice_b'),
    ('field_questions', 'answered_choice'),
    ('field_rhythms', 'id'),
    ('field_rhythms', 'couple_id'),
    ('field_rhythms', 'title'),
    ('field_rhythms', 'cadence'),
    ('field_rhythms', 'health'),
    ('field_rhythms', 'horizon_id'),
    ('field_rhythms', 'occurrences'),
    ('field_rhythms', 'last_occurred_at'),
    ('field_evidence', 'id'),
    ('field_evidence', 'couple_id'),
    ('field_evidence', 'statement'),
    ('field_evidence', 'owner'),
    ('field_evidence', 'horizon_id'),
    ('field_evidence', 'occurred_at'),
    ('field_held_topics', 'id'),
    ('field_held_topics', 'couple_id'),
    -- The app's own id for the topic — a route like `promote:japan`, not the
    -- row's uuid. `FieldSupabaseBackend` upserts and identifies on this.
    ('field_held_topics', 'client_id'),
    ('field_held_topics', 'title'),
    ('field_held_topics', 'timing'),
    ('field_held_topics', 'reason'),
    ('field_held_topics', 'surface_on'),
    ('field_held_topics', 'was_overridden'),
    ('field_held_topics', 'was_dismissed'),
    ('field_standing_rules', 'id'),
    ('field_standing_rules', 'couple_id'),
    ('field_standing_rules', 'text'),
    ('field_standing_rules', 'set_at'),
    ('field_standing_rules', 'set_by'),
    ('field_captures', 'id'),
    ('field_captures', 'couple_id'),
    ('field_captures', 'text'),
    ('field_captures', 'spoken_by'),
    ('field_captures', 'captured_at'),
    ('field_corrections', 'id'),
    ('field_corrections', 'couple_id'),
    ('field_corrections', 'input'),
    ('field_corrections', 'original_destination'),
    ('field_corrections', 'corrected_destination'),
    ('field_corrections', 'corrected_by'),
    ('field_corrections', 'corrected_at'),
    ('field_daily_moment', 'couple_id'),
    ('field_daily_moment', 'send_minute'),
    ('field_daily_moment', 'hour_rationale'),
    ('field_daily_moment', 'reply_rate_before'),
    ('field_daily_moment', 'reply_rate_after'),
    ('field_daily_moment', 'last_sent_on')
) as projection(table_name, column_name);

select is(
  (
    select case
      when columns.data_type = 'ARRAY' then columns.udt_name
      else columns.data_type
    end
    from information_schema.columns
    where columns.table_schema = 'public'
      and columns.table_name = typed_projection.table_name
      and columns.column_name = typed_projection.column_name
  ),
  typed_projection.expected_type,
  format(
    '%s.%s keeps its adapter-compatible SQL type',
    typed_projection.table_name,
    typed_projection.column_name
  )
)
from (
  values
    ('field_clusters', 'anchor_date', 'date'),
    ('field_life_items', 'due_on', 'date'),
    ('field_life_items', 'closes_at', 'timestamp with time zone'),
    ('field_life_items', 'created_by', 'uuid'),
    ('field_ours_items', 'added_by', 'uuid'),
    ('field_away_windows', 'profile_id', 'uuid'),
    ('field_horizons', 'target_date', 'date'),
    ('field_horizons', 'linked_life_item_ids', '_text'),
    ('field_rhythms', 'last_occurred_at', 'timestamp with time zone'),
    ('field_evidence', 'occurred_at', 'timestamp with time zone'),
    ('field_held_topics', 'surface_on', 'date'),
    ('field_standing_rules', 'set_at', 'timestamp with time zone'),
    ('field_standing_rules', 'set_by', 'uuid'),
    ('field_captures', 'spoken_by', 'uuid'),
    ('field_captures', 'captured_at', 'timestamp with time zone'),
    ('field_corrections', 'corrected_by', 'uuid'),
    ('field_corrections', 'corrected_at', 'timestamp with time zone'),
    ('field_daily_moment', 'reply_rate_before', 'numeric'),
    ('field_daily_moment', 'reply_rate_after', 'numeric'),
    ('field_daily_moment', 'last_sent_on', 'date')
) as typed_projection(table_name, column_name, expected_type);

select is(
  (
    select count(*)
    from pg_catalog.pg_trigger
    where tgname = 'field_actor_integrity'
      and not tgisinternal
      and tgrelid in (
        'public.field_away_windows'::regclass,
        'public.field_life_items'::regclass,
        'public.field_ours_items'::regclass,
        'public.field_standing_rules'::regclass,
        'public.field_captures'::regclass,
        'public.field_corrections'::regclass,
        'public.field_horizons'::regclass,
        'public.field_evidence'::regclass,
        'public.field_clusters'::regclass,
        'public.field_identity'::regclass
      )
  ),
  10::bigint,
  'every Field actor column is protected by the shared integrity trigger'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'field_captures'
  ),
  'captures publish realtime arrival'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'field_corrections'
  ),
  'corrections publish realtime arrival'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'field_life_items'
  ),
  'sent Life items publish realtime arrival'
);
select ok(
  not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'responses'
  ),
  'private raw answers never publish realtime'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_directions'
  ),
  'the safe mutual result publishes realtime'
);

-- The fixture table carries the random code returned by the real pairing RPC
-- across three authenticated request contexts. It exists only for this
-- transaction.
create temporary table field_contract_context (
  couple_id uuid not null,
  join_code text not null
) on commit drop;
grant select, insert, update, delete
  on table field_contract_context to authenticated;

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
    '81000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'field-contract-a@example.test',
    crypt('password-a', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Field Partner A"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '81000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'field-contract-b@example.test',
    crypt('password-b', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Field Partner B"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '81000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'field-contract-outsider@example.test',
    crypt('password-c', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Field Outsider"}',
    now(),
    now()
  );

-- Partner A creates the relationship through the production RPC.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.create_couple()$$,
  'Partner A creates a real two-person space'
);
insert into field_contract_context (couple_id, join_code)
select id, join_code
from public.couples;
select is(
  (
    select member_slot
    from public.couple_members
    where profile_id = '81000000-0000-0000-0000-000000000001'
  ),
  1::smallint,
  'the creator has stable side A'
);
select is(
  (select count(*) from public.couple_members),
  1::bigint,
  'Partner A sees only the first membership before pairing'
);

reset role;

-- Partner B sees none of A's relationship before redeeming the real code,
-- then joins through the production RPC and receives stable side B.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.couples),
  0::bigint,
  'Partner B cannot see the space before pairing'
);
select is(
  (select count(*) from public.couple_members),
  0::bigint,
  'Partner B cannot see either membership before pairing'
);
select lives_ok(
  $$select public.join_couple(
    (select join_code from field_contract_context limit 1)
  )$$,
  'Partner B redeems the real pairing code'
);
select is(
  public.my_couple_id(),
  (select couple_id from field_contract_context limit 1),
  'Partner B is joined to the same relationship'
);
select is(
  (
    select member_slot
    from public.couple_members
    where profile_id = '81000000-0000-0000-0000-000000000002'
  ),
  2::smallint,
  'the joiner has stable side B'
);
select is(
  (select count(*) from public.couple_members),
  2::bigint,
  'Partner B sees exactly the two paired profiles'
);

reset role;

-- A third authenticated person cannot join or discover the relationship.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.couples),
  0::bigint,
  'the outsider cannot discover the paired relationship'
);
select throws_like(
  $$select public.join_couple(
    (select join_code from field_contract_context limit 1)
  )$$,
  '%already has two people%',
  'the outsider cannot become a third partner'
);
select is(
  public.my_couple_id(),
  null::uuid,
  'the rejected outsider remains unpaired'
);

reset role;

-- Partner A completes the cold-start identity and authors one Life row. The
-- actor UUID and side are both controlled by the database contract.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
insert into public.field_identity (
  couple_id,
  swatch_a,
  swatch_b,
  lives_together,
  saving_for,
  looks_after
) values (
  (select couple_id from field_contract_context limit 1),
  'clay',
  'slate',
  true,
  'a quiet trip',
  'the dog'
);
insert into public.field_life_items (
  id,
  couple_id,
  title,
  category,
  owner,
  source,
  detail,
  created_by
) values (
  '84000000-0000-0000-0000-000000000001',
  (select couple_id from field_contract_context limit 1),
  'A shared grocery beginning',
  'food',
  'a',
  'captured',
  'authored by A',
  '81000000-0000-0000-0000-000000000002'
);
insert into public.field_horizons (
  id,
  couple_id,
  title,
  owner,
  thesis
) values (
  '84000000-0000-0000-0000-000000000009',
  (select couple_id from field_contract_context limit 1),
  'A authored horizon',
  'a',
  'Original thesis'
);
select is(
  (
    select created_by
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000001'
  ),
  '81000000-0000-0000-0000-000000000001'::uuid,
  'the server stamps Partner A even when A submits Partner B as created_by'
);
select throws_ok(
  $$insert into public.field_life_items (
      couple_id, title, category, owner, source
    ) values (
      (select couple_id from field_contract_context limit 1),
      'A cannot author as B',
      'notes',
      'b',
      'captured'
    )$$,
  '42501',
  null,
  'Partner A cannot insert a Life item attributed to side B'
);

reset role;

-- Partner B sees A's onboarding and shared state, then executes the
-- capture/correct/send path. Every attempted UUID spoof is rewritten to B,
-- while every attempted side-A insert is rejected.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select saving_for from public.field_identity),
  'a quiet trip',
  'Partner B sees the completed onboarding identity'
);
insert into public.field_identity (
  couple_id,
  swatch_a,
  swatch_b
) values (
  (select couple_id from field_contract_context limit 1),
  'rust',
  'teal'
)
on conflict (couple_id) do update
set swatch_a = excluded.swatch_a,
    swatch_b = excluded.swatch_b;
select is(
  (
    select concat(swatch_a, ':', swatch_b)
    from public.field_identity
  ),
  'clay:teal',
  'Partner B can choose side B but cannot overwrite Partner A''s swatch'
);
select is(
  (
    select title
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000001'
  ),
  'A shared grocery beginning',
  'Partner B sees Partner A''s Life row'
);

insert into public.field_captures (
  id,
  couple_id,
  text,
  spoken_by,
  destination,
  reasoning
) values (
  '84000000-0000-0000-0000-000000000002',
  (select couple_id from field_contract_context limit 1),
  'Book the cabin Sunday',
  '81000000-0000-0000-0000-000000000001',
  'trips',
  'Sunday gives this a real date.'
);
insert into public.field_corrections (
  id,
  couple_id,
  input,
  original_destination,
  corrected_destination,
  corrected_by
) values (
  '84000000-0000-0000-0000-000000000003',
  (select couple_id from field_contract_context limit 1),
  'Book the cabin Sunday',
  'notes',
  'trips',
  '81000000-0000-0000-0000-000000000001'
);
insert into public.field_life_items (
  id,
  couple_id,
  title,
  category,
  owner,
  due_on,
  source,
  detail,
  created_by
) values (
  '84000000-0000-0000-0000-000000000004',
  (select couple_id from field_contract_context limit 1),
  'Book the cabin',
  'trips',
  'b',
  current_date + 2,
  'captured',
  'Filed after correction',
  '81000000-0000-0000-0000-000000000001'
);
insert into public.field_away_windows (
  id,
  couple_id,
  profile_id,
  starts_at,
  ends_at,
  reason
) values (
  '84000000-0000-0000-0000-000000000005',
  (select couple_id from field_contract_context limit 1),
  '81000000-0000-0000-0000-000000000001',
  now(),
  now() + interval '1 hour',
  'Focus time'
);
insert into public.field_standing_rules (
  id,
  couple_id,
  text,
  set_by
) values (
  '84000000-0000-0000-0000-000000000006',
  (select couple_id from field_contract_context limit 1),
  'Keep Sunday mornings open.',
  '81000000-0000-0000-0000-000000000001'
);
insert into public.field_ours_items (
  id,
  couple_id,
  title,
  list,
  added_by
) values (
  '84000000-0000-0000-0000-000000000007',
  (select couple_id from field_contract_context limit 1),
  'A legacy watch item',
  'watchlist',
  '81000000-0000-0000-0000-000000000001'
);

select is(
  (
    select spoken_by
    from public.field_captures
    where id = '84000000-0000-0000-0000-000000000002'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner B cannot persist a capture as Partner A'
);
select is(
  (
    select corrected_by
    from public.field_corrections
    where id = '84000000-0000-0000-0000-000000000003'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner B cannot persist a correction as Partner A'
);
select is(
  (
    select created_by
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000004'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner B cannot persist a sent Life item as Partner A'
);
select is(
  (
    select profile_id
    from public.field_away_windows
    where id = '84000000-0000-0000-0000-000000000005'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner B cannot persist an away window as Partner A'
);
select is(
  (
    select set_by
    from public.field_standing_rules
    where id = '84000000-0000-0000-0000-000000000006'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner B cannot persist a standing rule as Partner A'
);
select is(
  (
    select added_by
    from public.field_ours_items
    where id = '84000000-0000-0000-0000-000000000007'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'legacy Ours writes also cannot impersonate Partner A'
);

select throws_ok(
  $$insert into public.field_life_items (
      couple_id, title, category, owner, source
    ) values (
      (select couple_id from field_contract_context limit 1),
      'B cannot author as A',
      'notes',
      'a',
      'captured'
    )$$,
  '42501',
  null,
  'Partner B cannot insert a Life item attributed to side A'
);
select lives_ok(
  $$insert into public.field_life_items (
      id, couple_id, title, category, owner, source
    ) values (
      '84000000-0000-0000-0000-000000000008',
      (select couple_id from field_contract_context limit 1),
      'A genuinely shared note',
      'notes',
      'shared',
      'captured'
    )$$,
  'Partner B may create explicitly shared state'
);
update public.field_life_items
set detail = 'Still shared after an edit',
    owner = 'a',
    created_by = '81000000-0000-0000-0000-000000000001'
where id = '84000000-0000-0000-0000-000000000008';
select is(
  (
    select concat(owner, ':', created_by::text)
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000008'
  ),
  'shared:81000000-0000-0000-0000-000000000002',
  'an edit preserves legitimate shared ownership and its original creator'
);
select throws_ok(
  $$insert into public.field_horizons (
      couple_id, title, owner
    ) values (
      (select couple_id from field_contract_context limit 1),
      'A spoofed horizon',
      'a'
    )$$,
  '42501',
  null,
  'Partner B cannot insert a horizon attributed to side A'
);
select throws_ok(
  $$insert into public.field_evidence (
      couple_id, statement, owner
    ) values (
      (select couple_id from field_contract_context limit 1),
      'A spoofed piece of evidence',
      'a'
    )$$,
  '42501',
  null,
  'Partner B cannot insert evidence attributed to side A'
);
select throws_ok(
  $$insert into public.field_clusters (
      couple_id, title, rationale, tint, timeframe
    ) values (
      (select couple_id from field_contract_context limit 1),
      'A spoofed cluster',
      'This should be rejected.',
      'a',
      'Soon'
    )$$,
  '42501',
  null,
  'Partner B cannot insert a cluster tinted as side A'
);

-- A partner may edit existing shared state. Authorship and side attribution
-- stay immutable even if the update payload tries to rewrite them.
select lives_ok(
  $$update public.field_life_items
    set detail = 'Partner B added a useful detail',
        owner = 'b',
        created_by = '81000000-0000-0000-0000-000000000002'
    where id = '84000000-0000-0000-0000-000000000001'$$,
  'Partner B may edit Partner A''s existing shared Life state'
);
select is(
  (
    select concat(owner, ':', created_by::text)
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000001'
  ),
  'a:81000000-0000-0000-0000-000000000001',
  'a shared edit cannot rewrite original side or creator'
);
select lives_ok(
  $$insert into public.field_life_items (
      id, couple_id, title, category, owner, source, detail, is_done, created_by
    ) values (
      '84000000-0000-0000-0000-000000000001',
      (select couple_id from field_contract_context limit 1),
      'A shared grocery beginning',
      'food',
      'a',
      'captured',
      'Partner B edited through adapter upsert',
      true,
      '81000000-0000-0000-0000-000000000002'
    )
    on conflict (id) do update
    set detail = excluded.detail,
        is_done = excluded.is_done,
        owner = excluded.owner,
        created_by = excluded.created_by$$,
  'Partner B may edit Partner A''s item through the real upsert shape'
);
select is(
  (
    select concat(
      owner,
      ':',
      created_by::text,
      ':',
      is_done::text,
      ':',
      detail
    )
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000001'
  ),
  'a:81000000-0000-0000-0000-000000000001:true:Partner B edited through adapter upsert',
  'adapter upsert changes content but preserves original owner and creator'
);
select lives_ok(
  $$insert into public.field_horizons (
      id, couple_id, title, owner, thesis
    ) values (
      '84000000-0000-0000-0000-000000000009',
      (select couple_id from field_contract_context limit 1),
      'A authored horizon',
      'a',
      'Partner B refined the thesis'
    )
    on conflict (id) do update
    set thesis = excluded.thesis,
        owner = excluded.owner$$,
  'Partner B may edit Partner A''s horizon through adapter upsert'
);
select is(
  (
    select concat(owner, ':', thesis)
    from public.field_horizons
    where id = '84000000-0000-0000-0000-000000000009'
  ),
  'a:Partner B refined the thesis',
  'horizon upsert preserves original side attribution'
);
update public.field_captures
set text = 'Book the cabin this Sunday',
    spoken_by = '81000000-0000-0000-0000-000000000001'
where id = '84000000-0000-0000-0000-000000000002';
select is(
  (
    select spoken_by
    from public.field_captures
    where id = '84000000-0000-0000-0000-000000000002'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'an update cannot rewrite a capture''s original speaker'
);

reset role;

-- Both database truth and the other partner's RLS view contain B's capture,
-- correction, and sent item with B attribution.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
insert into public.field_identity (
  couple_id,
  swatch_a,
  swatch_b
) values (
  (select couple_id from field_contract_context limit 1),
  'amber',
  'indigo'
)
on conflict (couple_id) do update
set swatch_a = excluded.swatch_a,
    swatch_b = excluded.swatch_b;
select is(
  (
    select concat(swatch_a, ':', swatch_b)
    from public.field_identity
  ),
  'amber:teal',
  'Partner A can choose side A but cannot overwrite Partner B''s swatch'
);
select is(
  (
    select spoken_by
    from public.field_captures
    where id = '84000000-0000-0000-0000-000000000002'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner A receives Partner B''s corrected capture'
);
select is(
  (
    select corrected_by
    from public.field_corrections
    where id = '84000000-0000-0000-0000-000000000003'
  ),
  '81000000-0000-0000-0000-000000000002'::uuid,
  'Partner A receives Partner B''s correction'
);
select is(
  (
    select concat(owner, ':', created_by::text)
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000004'
  ),
  'b:81000000-0000-0000-0000-000000000002',
  'Partner A receives the sent item as Partner B''s'
);

reset role;

-- Seed one mutual prompt for the paired couple. Its two raw answers remain
-- private forever; after both submit, only reviewed shared wording is
-- revealed to the couple.
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
  '83000000-0000-0000-0000-000000000001',
  (select couple_id from field_contract_context limit 1),
  'tonight-field-contract',
  'relational',
  'us',
  true,
  'How should tonight feel?',
  'Choose separately.',
  'A small check-in.',
  'A moment for tonight',
  array['Quiet and close', 'Out of the house'],
  50
);
insert into public.insight_consent (
  insight_id,
  visibility,
  readiness,
  accepted_at
) values (
  '83000000-0000-0000-0000-000000000001',
  'mutual',
  'accepted',
  now()
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.submit_response(
    '83000000-0000-0000-0000-000000000001',
    'Quiet and close',
    'A_PRIVATE_FIELD_NOTE'
  )$$,
  'Partner A submits a private answer'
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'Partner A sees exactly their own raw answer'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'Partner B cannot see Partner A''s raw answer'
);
select is(
  (
    select count(*)
    from public.partner_answer_statuses()
    where insight_id = '83000000-0000-0000-0000-000000000001'
      and profile_id = '81000000-0000-0000-0000-000000000001'
      and has_answered
  ),
  1::bigint,
  'Partner B sees only that Partner A has answered'
);
select lives_ok(
  $$select public.submit_response(
    '83000000-0000-0000-0000-000000000001',
    'Out of the house',
    'B_PRIVATE_FIELD_NOTE'
  )$$,
  'Partner B submits an independent private answer'
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'after mutual submission Partner B still sees only their raw answer'
);
select is(
  (
    select count(*)
    from public.shared_directions
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'mutual submission reveals one safe shared direction'
);
select ok(
  (
    select concat_ws(' ', title, message)
        not like '%A_PRIVATE_FIELD_NOTE%'
      and concat_ws(' ', title, message)
        not like '%B_PRIVATE_FIELD_NOTE%'
      and concat_ws(' ', title, message)
        not like '%Quiet and close%'
      and concat_ws(' ', title, message)
        not like '%Out of the house%'
    from public.shared_directions
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  'the mutual result leaks neither private answer nor note'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'Partner A still cannot see Partner B''s raw answer'
);
select is(
  (
    select count(*)
    from public.shared_directions
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'Partner A sees the same mutual shared direction'
);

reset role;

-- The outsider can neither observe Field/shared-answer state nor write into
-- the couple by guessing its UUID.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.field_identity),
  0::bigint,
  'the outsider cannot read onboarding answers'
);
select is(
  (select count(*) from public.field_captures),
  0::bigint,
  'the outsider cannot read either partner''s captures'
);
select is(
  (select count(*) from public.field_corrections),
  0::bigint,
  'the outsider cannot read either partner''s corrections'
);
select is(
  (select count(*) from public.field_life_items),
  0::bigint,
  'the outsider cannot read Life state'
);
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the outsider cannot read either private answer'
);
select is(
  (
    select count(*)
    from public.shared_directions
    where insight_id = '83000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'the outsider cannot read the couple''s mutual result'
);
select throws_ok(
  $$insert into public.field_captures (
      couple_id, text, spoken_by, destination, reasoning
    ) values (
      (select couple_id from field_contract_context limit 1),
      'Outsider injection',
      '81000000-0000-0000-0000-000000000001',
      'notes',
      'This must never land.'
    )$$,
  '42501',
  null,
  'the outsider cannot write a capture into the relationship'
);
select throws_ok(
  $$insert into public.field_life_items (
      couple_id, title, category, owner, source
    ) values (
      (select couple_id from field_contract_context limit 1),
      'Outsider item',
      'notes',
      'shared',
      'captured'
    )$$,
  '42501',
  null,
  'the outsider cannot write a Life item into the relationship'
);
select throws_like(
  $$select public.submit_response(
    '83000000-0000-0000-0000-000000000001',
    'Quiet and close',
    'OUTSIDER_PRIVATE_NOTE'
  )$$,
  '%not yours%',
  'the outsider cannot answer the couple''s private prompt'
);

reset role;

-- Superuser truth confirms both answer rows exist but every user-facing
-- contract above returned only the caller's own row.
select is(
  (
    select count(*)
    from public.responses
    where insight_id = '83000000-0000-0000-0000-000000000001'
      and status = 'submitted'
  ),
  2::bigint,
  'database truth retains exactly two owner-only submitted answers'
);
select is(
  (
    select concat(owner, ':', created_by::text)
    from public.field_life_items
    where id = '84000000-0000-0000-0000-000000000004'
  ),
  'b:81000000-0000-0000-0000-000000000002',
  'database truth attributes Partner B''s sent item to Partner B'
);
select is(
  (
    select count(*)
    from public.field_life_items
    where source = 'captured'
      and created_by is null
      and owner <> 'shared'
  ),
  0::bigint,
  'the completed contract leaves no unattributed capture on a guessed side'
);

-- MARK: A held topic survives a round trip ----------------------------------
--
-- The app's one promise in its own voice is that it does not ask twice, and
-- the table backing it had no insert path at all: `setHeld` was an UPDATE
-- guarded on a uuid, and the ids the app holds under are routes
-- (`promote:japan`). Every hold was dropped in silence, so "Not this year" was
-- forgotten on relaunch. These assertions are the shape of the write the
-- client now makes.
--
-- Run as Partner A rather than as superuser, so the write is judged by the
-- same RLS policy the app meets.

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$insert into public.field_held_topics (
      couple_id, client_id, title, timing, reason, surface_on
    )
    select couple_id, 'promote:japan', 'Japan', 'NOT NOW',
           'Asked and answered.', null
    from field_contract_context$$,
  'a route-shaped id can be held at all'
);

-- The upsert the client issues, restated: same couple, same client_id.
select lives_ok(
  $$insert into public.field_held_topics (
      couple_id, client_id, title, timing, reason, surface_on, was_dismissed
    )
    select couple_id, 'promote:japan', 'Japan', 'TONIGHT',
           'Ask me again tonight.', date '2026-08-04', false
    from field_contract_context
    on conflict (couple_id, client_id) do update set
      timing = excluded.timing,
      reason = excluded.reason,
      surface_on = excluded.surface_on,
      was_dismissed = excluded.was_dismissed$$,
  'holding the same topic again restates one decision rather than making two'
);

select is(
  (select count(*) from public.field_held_topics
    where client_id = 'promote:japan'),
  1::bigint,
  'the same topic held twice is still one row'
);

-- `surface_on` was never in the old payload at all, so a deferral had no date
-- to come back on. This is the assertion that it now does.
select is(
  (select surface_on from public.field_held_topics
    where client_id = 'promote:japan'),
  date '2026-08-04',
  'a deferral records the day it is due back'
);

select is(
  (select client_id from public.field_held_topics
    where client_id = 'promote:japan'),
  'promote:japan',
  'the route id survives the round trip and is what the app reads back'
);

-- Immutable: a decision cannot be reattached to a different question.
update public.field_held_topics
set client_id = 'promote:something-else'
where client_id = 'promote:japan';

select is(
  (select count(*) from public.field_held_topics
    where client_id = 'promote:japan'),
  1::bigint,
  'client_id is frozen once the topic exists'
);

reset role;

select * from finish();
rollback;
