-- The acceptance test for ○ Yours.
--
-- The bar, stated the same way `field_solo_visibility.test.sql` states its
-- own: if any entry is readable by anyone but its owner, the phase is not
-- done. And a second bar this feature adds, because its whole claim rests on
-- it: if anything other than `private.yours_destroy` can remove an entry row,
-- the promise that deletion goes through one auditable door is false.
--
-- ON TIME
--
-- `now()` is frozen for the length of a transaction, so nothing here can wait
-- six weeks. Instead the tests move the entry rather than the clock: they set
-- `ready_at`, `decide_by` and `last_opened_at` into the past directly, as the
-- table owner, with `we.yours_lifecycle` announced. That is the same door the
-- RPCs use, which is the point — if it were possible to backdate an entry any
-- other way, that would itself be the bug.
--
-- The setting is turned off again immediately afterwards, because several
-- assertions below depend on a *client* being unable to do what the preceding
-- lines just did.

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
    '92000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'yours-a@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner A"}', now(), now()
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'yours-b@example.com', 'x',
    now(), '{"provider":"email","providers":["email"]}',
    '{"name":"Partner B"}', now(), now()
  );

-- MARK: The shape of the thing ----------------------------------------------
--
-- Asserted rather than assumed, so that adding a couple to this schema later
-- is a deliberate act and not a silent one. Yours is owner-scoped. There is no
-- couple in it and there must never be one.

select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'yours_entries', 'yours_owner_state',
        'yours_prepared_offers', 'yours_releases'
      )
      and column_name = 'couple_id'
  ),
  0::bigint,
  'no yours table is couple-scoped'
);

select is(
  (
    select count(*) from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename like 'yours\_%'
  ),
  0::bigint,
  'nothing in yours is published to realtime — §10 forbids the event'
);

-- Locked #5, as a table constraint rather than a convention.
select is(
  (
    select count(*) from pg_constraint
    where conrelid = 'public.yours_entries'::regclass
      and conname = 'yours_entries_window_needs_presentation'
  ),
  1::bigint,
  'a decision window cannot exist without a presentation'
);

-- The one door. No delete policy on any yours table means RLS denies the verb
-- outright, which is what routes "let go" through `private.yours_destroy`.
select is(
  (
    select count(*) from pg_policies
    where schemaname = 'public'
      and tablename like 'yours\_%'
      and cmd = 'DELETE'
  ),
  0::bigint,
  'no client-reachable delete policy exists on any yours table'
);

-- MARK: A, writing -----------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

insert into public.yours_entries (client_id, body)
values
  ('92100000-0000-0000-0000-000000000001', 'The thing I have not said'),
  ('92100000-0000-0000-0000-000000000002', 'The second thing');

select is(
  (select count(*) from public.yours_entries), 2::bigint,
  'A can read what A wrote'
);

select is(
  (
    select state from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'living',
  'a new entry is living'
);

select is(
  (
    select renewal_count from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  0,
  'and has not been renewed'
);

-- Locked #4: six weeks, fixed, not sent by the client.
select ok(
  (
    select ready_at between
      now() + interval '6 weeks' - interval '1 minute'
      and now() + interval '6 weeks' + interval '1 minute'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'the first life is six weeks, computed by the server'
);

-- Locked #6.
select ok(
  (
    select unseen_delete_at = ready_at + interval '1 year'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'the outer bound is one year after ready_at'
);

-- MARK: What a client may not do --------------------------------------------

update public.yours_entries
set ready_at = now() + interval '10 years'
where client_id = '92100000-0000-0000-0000-000000000001';

select ok(
  (
    select ready_at < now() + interval '7 weeks'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'a client cannot buy itself a longer life by writing ready_at'
);

update public.yours_entries
set state = 'held', held_at = now()
where client_id = '92100000-0000-0000-0000-000000000001';

select is(
  (
    select state from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'living',
  'nor grant itself permanence by writing state'
);

delete from public.yours_entries
where client_id = '92100000-0000-0000-0000-000000000001';

select is(
  (select count(*) from public.yours_entries), 2::bigint,
  'nor delete a row around the destroy seam'
);

-- §3: editing restarts the *current* interval and does not demote the stage.
update public.yours_entries
set body = 'The thing I have not said, said differently'
where client_id = '92100000-0000-0000-0000-000000000001';

select ok(
  (
    select ready_at > now() + interval '5 weeks'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'editing restarts the interval'
);

-- MARK: B cannot see any of it ----------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.yours_entries), 0::bigint,
  'B sees nothing of A, with no couple between them'
);

-- Pair them, exactly as the solo-visibility suite does: the membership row
-- directly, so that a policy failure and an invitation failure cannot look
-- alike.
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

insert into public.couple_members (couple_id, profile_id, hue)
values (
  (select couple_id from ctx),
  '92000000-0000-0000-0000-000000000002',
  'sage'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.yours_entries), 0::bigint,
  'and still sees nothing after joining — this is the whole promise'
);

-- MARK: The presentation gate (§5, locked #5) --------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select ok(
  public.yours_present_next('92200000-0000-0000-0000-000000000001') is null,
  'nothing returns before its interval has elapsed'
);

-- Move the entries into the past. See the note at the top of this file.
reset role;
select set_config('we.yours_lifecycle', 'on', true);
update public.yours_entries
set ready_at = now() - interval '2 days', state = 'ready'
where client_id = '92100000-0000-0000-0000-000000000001';
update public.yours_entries
set ready_at = now() - interval '1 day', state = 'ready'
where client_id = '92100000-0000-0000-0000-000000000002';
select set_config('we.yours_lifecycle', '', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (public.yours_present_next('92200000-0000-0000-0000-000000000002')).client_id,
  '92100000-0000-0000-0000-000000000001'::uuid,
  'the oldest ready entry is the one presented — strictly chronological'
);

select is(
  (public.yours_present_next('92200000-0000-0000-0000-000000000002')).client_id,
  '92100000-0000-0000-0000-000000000001'::uuid,
  'asking twice in one visit presents the same entry, never a second'
);

select ok(
  (
    select decide_by between
      now() + interval '7 days' - interval '1 minute'
      and now() + interval '7 days' + interval '1 minute'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'and the seven days start now, because now is when it was shown'
);

select is(
  (select count(*) from public.yours_entries where state = 'presented'),
  1::bigint,
  'only one entry is under question at a time'
);

-- Answer it, in the same visit.
select public.yours_keep_for_now(
  (select id from public.yours_entries
     where client_id = '92100000-0000-0000-0000-000000000001'),
  '92200000-0000-0000-0000-000000000002'
);

select is(
  (
    select renewal_count from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  1,
  'keeping for now is the one thing that increments the renewal count'
);

select ok(
  (
    select ready_at > now() + interval '11 weeks'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'and the first renewal is twelve weeks, not another six'
);

select ok(
  public.yours_present_next('92200000-0000-0000-0000-000000000002') is null,
  'the next entry waits for the next visit, not for the next breath'
);

select is(
  (public.yours_present_next('92200000-0000-0000-0000-000000000003')).client_id,
  '92100000-0000-0000-0000-000000000002'::uuid,
  'and arrives on it'
);

-- MARK: One week, once (locked #8) ------------------------------------------

select ok(
  (
    select snoozed_at is not null from public.yours_snooze(
      (select id from public.yours_entries
         where client_id = '92100000-0000-0000-0000-000000000002'),
      '92200000-0000-0000-0000-000000000003'
    )
  ),
  'a week can be asked for'
);

select ok(
  (
    select ready_at > now() + interval '6 days'
      and decide_by < now() + interval '15 days'
    from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000002'
  ),
  'it returns in seven days and ends fourteen days out — exactly one week more'
);

select throws_ok(
  format(
    $$select public.yours_snooze(%L, '92200000-0000-0000-0000-000000000004')$$,
    (select id from public.yours_entries
       where client_id = '92100000-0000-0000-0000-000000000002')
  ),
  'one week, once',
  'and it cannot be asked for twice'
);

-- MARK: Held ----------------------------------------------------------------

select public.yours_hold(
  (select id from public.yours_entries
     where client_id = '92100000-0000-0000-0000-000000000001')
);

select is(
  (
    select state from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  'held',
  'permanence is available, and it is a state'
);

-- §4: new words do not inherit permanence.
select throws_ok(
  $$update public.yours_entries
      set body = 'quietly different'
      where client_id = '92100000-0000-0000-0000-000000000001'$$,
  'a held entry is edited through yours_update_held or yours_let_this_return, not by writing over it',
  'a held entry cannot be edited by writing over it'
);

select ok(
  (
    select state = 'living' and renewal_count = 0
    from public.yours_let_this_return(
      (select id from public.yours_entries
         where client_id = '92100000-0000-0000-0000-000000000001'),
      'a different version'
    )
  ),
  'letting it return gives a fresh first life and clears renewal history'
);

-- MARK: The sweep -----------------------------------------------------------

reset role;
select set_config('we.yours_lifecycle', 'on', true);

-- One entry whose question went unanswered, one held entry sitting well past
-- an outer bound it is exempt from.
update public.yours_entries
set state = 'presented',
    presented_at = now() - interval '8 days',
    decide_by = now() - interval '1 day'
where client_id = '92100000-0000-0000-0000-000000000002';

update public.yours_entries
set state = 'held',
    held_at = now(),
    ready_at = now() - interval '2 years'
where client_id = '92100000-0000-0000-0000-000000000001';

select set_config('we.yours_lifecycle', '', true);

select is(
  private.yours_sweep(), 1,
  'the sweep destroys exactly the entry whose window ran out'
);

select is(
  private.yours_sweep(), 0,
  'and running it again immediately does nothing at all'
);

select is(
  (
    select count(*) from public.yours_entries
    where client_id = '92100000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'held survives an outer bound two years past — held is exempt everywhere'
);

-- Dormancy (§5). Ninety days without opening the product.
select set_config('we.yours_lifecycle', 'on', true);
insert into public.yours_entries (owner_id, client_id, body)
values (
  '92000000-0000-0000-0000-000000000001',
  '92100000-0000-0000-0000-000000000003',
  'written and then abandoned'
);
update public.yours_owner_state
set last_opened_at = now() - interval '100 days'
where owner_id = '92000000-0000-0000-0000-000000000001';
select set_config('we.yours_lifecycle', '', true);

select is(
  private.yours_sweep(), 1,
  'an abandoned account does not quietly become a vault'
);

select is(
  (
    select count(*) from public.yours_entries
    where state = 'held'
  ),
  1::bigint,
  'and what was deliberately held is still exempt'
);

-- MARK: Prepared offers (§6) ------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

insert into public.yours_entries (client_id, body)
values ('92100000-0000-0000-0000-000000000004', 'the source of an offer');

select ok(
  (
    select id is not null from public.yours_prepare_offer(
      (select id from public.yours_entries
         where client_id = '92100000-0000-0000-0000-000000000004'),
      '92300000-0000-0000-0000-000000000001',
      'The move',
      'Where do you want to be next year?',
      array['Here', 'Somewhere else']
    )
  ),
  'an offer can be prepared'
);

select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'yours_prepared_offers'
      and column_name = 'body'
  ),
  0::bigint,
  'and it carries the approved wording only — never the source text'
);

select ok(
  (
    select ready_at < now() + interval '15 days'
    from public.yours_prepared_offers
    where client_id = '92300000-0000-0000-0000-000000000001'
  ),
  'an offer has its own, shorter life: two weeks'
);

-- The source entry ends. The offer must stand on its own.
select public.yours_let_go(
  (select id from public.yours_entries
     where client_id = '92100000-0000-0000-0000-000000000004'),
  null,
  'noLongerTrue'
);

select is(
  (
    select count(*) from public.yours_prepared_offers
    where client_id = '92300000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'letting the source go does not drag the offer with it'
);

select is(
  (
    select source_entry_id from public.yours_prepared_offers
    where client_id = '92300000-0000-0000-0000-000000000001'
  ),
  null,
  'and leaves no route back to the words that were let go'
);

-- MARK: Why somebody let go (§13) -------------------------------------------

select throws_ok(
  $$select count(*) from public.yours_releases$$,
  '42501',
  'no client reads the release table, including its owner'
);

reset role;

select is(
  (
    select count(*) from public.yours_releases
    where object_kind = 'entry' and reason = 'noLongerTrue'
  ),
  1::bigint,
  'the reason was recorded, kind-separated, with no text and no id'
);

select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'yours_releases'
      and column_name in ('body', 'title', 'entry_id', 'prepared_offer_id')
  ),
  0::bigint,
  'and nothing on that row could ever bring the entry back'
);

select * from finish();
rollback;
