begin;

create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '95000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'intake-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '95000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'intake-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  ),
  (
    '95000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'intake-c@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Stranger"}', now(), now()
  );

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok($$select public.create_couple()$$, 'A has a relationship');

reset role;
insert into public.couple_members (couple_id, profile_id, hue, member_slot)
select
  couple_id,
  '95000000-0000-0000-0000-000000000002',
  'sage',
  2
from public.couple_members
where profile_id = '95000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select lives_ok($$select public.create_couple()$$, 'the stranger has a space');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$
    select public.share_create_publication_session(
      '95100000-0000-4000-8000-000000000001',
      '95200000-0000-4000-8000-000000000001',
      1,
      'Dinner reservation',
      'Saturday at seven',
      'food',
      '[{
        "id":"95300000-0000-4000-8000-000000000001",
        "url":"https://example.com/reservation"
      }]'::jsonb,
      '[]'::jsonb
    )
  $$,
  'an exact reviewed session can be created'
);

select is(
  (
    select state
    from public.share_publication_sessions
    where id = '95100000-0000-4000-8000-000000000001'
  ),
  'created',
  'the session begins frozen and unfinalized'
);

select is(
  (
    select expected_resources
    from public.share_publication_sessions
    where id = '95100000-0000-4000-8000-000000000001'
  ),
  '[]'::jsonb,
  'resources remain absent when every toggle stayed off'
);

select lives_ok(
  $$
    select public.share_create_publication_session(
      '95100000-0000-4000-8000-000000000001',
      '95200000-0000-4000-8000-000000000001',
      1,
      'Dinner reservation',
      'Saturday at seven',
      'food',
      '[{
        "id":"95300000-0000-4000-8000-000000000001",
        "url":"https://example.com/reservation"
      }]'::jsonb,
      '[]'::jsonb
    )
  $$,
  'creating the same frozen revision is idempotent'
);

select throws_ok(
  $$
    select public.share_create_publication_session(
      '95100000-0000-4000-8000-000000000001',
      '95200000-0000-4000-8000-000000000001',
      1,
      'Different copy',
      '',
      'food',
      '[]'::jsonb,
      '[]'::jsonb
    )
  $$,
  'publication identity was reused with different content',
  'a snapshot id cannot be reused for different content'
);

reset role;
select public.share_finalize_publication(
  '95100000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (
    select title
    from public.field_life_items
    where id = (
      select life_item_id
      from public.share_publication_sessions
      where id = '95100000-0000-4000-8000-000000000001'
    )
  ),
  'Dinner reservation',
  'only the reviewed title enters LIFE'
);

select is(
  (
    select detail
    from public.field_life_items
    where id = (
      select life_item_id
      from public.share_publication_sessions
      where id = '95100000-0000-4000-8000-000000000001'
    )
  ),
  'Saturday at seven',
  'only the reviewed body enters LIFE'
);

select is(
  (
    public.share_finalize_publication(
      '95100000-0000-4000-8000-000000000001'
    ) ->> 'life_item_id'
  )::uuid,
  (
    select life_item_id
    from public.share_publication_sessions
    where id = '95100000-0000-4000-8000-000000000001'
  ),
  'a lost final response returns the same LIFE item'
);

select is(
  (
    select count(*)
    from public.field_life_resources
    where life_item_id = (
      select life_item_id
      from public.share_publication_sessions
      where id = '95100000-0000-4000-8000-000000000001'
    )
      and kind = 'url'
  ),
  1::bigint,
  'the one explicitly approved URL is attached'
);

select throws_ok(
  $$
    select public.share_create_publication_session(
      '95100000-0000-4000-8000-000000000002',
      '95200000-0000-4000-8000-000000000002',
      1,
      'Unsafe link',
      '',
      'notes',
      '[{
        "id":"95300000-0000-4000-8000-000000000002",
        "url":"http://example.com"
      }]'::jsonb,
      '[]'::jsonb
    )
  $$,
  'invalid reviewed url',
  'non-HTTPS links are rejected again at the server'
);

select throws_ok(
  $$
    select public.share_create_publication_session(
      '95100000-0000-4000-8000-000000000006',
      '95200000-0000-4000-8000-000000000006',
      1,
      'Strict link',
      '',
      'notes',
      '[{
        "id":"95300000-0000-4000-8000-000000000006",
        "url":"https://example.com",
        "private_text":"must not enter the session"
      }]'::jsonb,
      '[]'::jsonb
    )
  $$,
  'invalid reviewed url',
  'unreviewed fields cannot hide inside a URL manifest'
);

select lives_ok(
  $$
    select public.share_create_publication_session(
      '95100000-0000-4000-8000-000000000003',
      '95200000-0000-4000-8000-000000000003',
      1,
      'One photo',
      '',
      'notes',
      '[]'::jsonb,
      '[{
        "id":"95300000-0000-4000-8000-000000000003",
        "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "content_type":"image/jpeg",
        "byte_count":100
      }]'::jsonb
    )
  $$,
  'an image session receives a server-owned path'
);

select throws_ok(
  $$
    select public.share_finalize_publication(
      '95100000-0000-4000-8000-000000000003'
    )
  $$,
  'uploaded resource set does not match review',
  'finalization refuses a missing object'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  $$
    select public.share_retire_publication_session(
      '95100000-0000-4000-8000-000000000003'
    )
  $$,
  'publication session unavailable',
  'a partner cannot retire the other person’s private attempt'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.share_publication_sessions
    where id = '95100000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'a stranger cannot read the session'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"95000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$
    select public.share_retire_publication_session(
      '95100000-0000-4000-8000-000000000003'
    )
  $$,
  'the creator can retire a failed frozen revision'
);

reset role;
select is(
  (
    select state
    from public.share_publication_sessions
    where id = '95100000-0000-4000-8000-000000000003'
  ),
  'retired',
  'retirement freezes the failed session closed'
);
select is(
  (
    select count(*)
    from private.share_storage_cleanup_jobs
    where resource_id = '95300000-0000-4000-8000-000000000003'
  ),
  1::bigint,
  'retirement queues only the server-owned object path'
);

insert into public.share_publication_sessions (
  id, couple_id, created_by, draft_id, revision, title, body, category,
  expected_resources
)
select
  '95100000-0000-4000-8000-000000000004',
  couple_id,
  '95000000-0000-0000-0000-000000000001',
  '95200000-0000-4000-8000-000000000004',
  1,
  'Unreleased image',
  '',
  'notes',
  jsonb_build_array(jsonb_build_object(
    'resource_id', '95300000-0000-4000-8000-000000000004',
    'sha256', repeat('b', 64),
    'content_type', 'image/jpeg',
    'byte_count', 100,
    'object_path',
      couple_id::text
      || '/95100000-0000-4000-8000-000000000004/'
      || '95300000-0000-4000-8000-000000000004.jpg'
  ))
from public.couple_members
where profile_id = '95000000-0000-0000-0000-000000000001';

delete from public.share_publication_sessions
where id = '95100000-0000-4000-8000-000000000004';

select is(
  (
    select count(*)
    from private.share_storage_cleanup_jobs
    where resource_id = '95300000-0000-4000-8000-000000000004'
  ),
  1::bigint,
  'account or relationship cascades queue unreleased objects'
);

insert into public.share_publication_sessions (
  id, couple_id, created_by, draft_id, revision, title, body, category,
  expected_resources, state, finalized_at
)
select
  '95100000-0000-4000-8000-000000000005',
  couple_id,
  '95000000-0000-0000-0000-000000000001',
  '95200000-0000-4000-8000-000000000005',
  1,
  'Released image',
  '',
  'notes',
  jsonb_build_array(jsonb_build_object(
    'resource_id', '95300000-0000-4000-8000-000000000005',
    'sha256', repeat('c', 64),
    'content_type', 'image/jpeg',
    'byte_count', 100,
    'object_path',
      couple_id::text
      || '/95100000-0000-4000-8000-000000000005/'
      || '95300000-0000-4000-8000-000000000005.jpg'
  )),
  'finalized',
  now()
from public.couple_members
where profile_id = '95000000-0000-0000-0000-000000000001';

delete from public.share_publication_sessions
where id = '95100000-0000-4000-8000-000000000005';

select is(
  (
    select count(*)
    from private.share_storage_cleanup_jobs
    where resource_id = '95300000-0000-4000-8000-000000000005'
  ),
  0::bigint,
  'creator deletion never queues deliberately released shared resources'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.share_finalize_publication(uuid)',
    'EXECUTE'
  ),
  'authenticated people may finalize their own reviewed session'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.share_finalize_publication(uuid)',
    'EXECUTE'
  ),
  'anonymous callers cannot finalize'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.share_claim_cleanup_jobs(integer)',
    'EXECUTE'
  ),
  'clients cannot claim trusted cleanup paths'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.share_claim_cleanup_jobs(integer)',
    'EXECUTE'
  ),
  'only the service worker can claim cleanup paths'
);
select ok(
  coalesce(
    (
      select c.relrowsecurity
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'private'
        and c.relname = 'share_storage_cleanup_jobs'
    ),
    false
  ),
  'the private cleanup queue keeps RLS enabled as defense in depth'
);

select * from finish();
rollback;
