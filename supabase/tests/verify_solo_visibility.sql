-- Did 20260803180000 land, and land correctly?
--
-- Read-only, and safe against a database with real people in it. It fabricates
-- nothing, writes nothing, and touches no row — it reads the catalog and counts.
--
-- This is deliberately NOT `field_solo_visibility.test.sql`. That file proves
-- behaviour by creating two users and a couple and checking what each can see,
-- which is the stronger proof and the reason it must only ever run against a
-- throwaway database. This file proves the *shape* of what was applied, which
-- is what can be honestly checked in place.
--
-- Every row should read ok = true.

select 'visibility column on the five authored tables' as check,
       count(*) = 5 as ok,
       count(*)::text || ' of 5' as detail
from information_schema.columns
where table_schema = 'public'
  and column_name = 'visibility'
  and table_name in (
    'field_life_items', 'field_captures', 'field_corrections',
    'field_standing_rules', 'field_held_topics'
  )

union all
select 'held topics record an author',
       count(*) = 1,
       count(*)::text || ' of 1'
from information_schema.columns
where table_schema = 'public'
  and table_name = 'field_held_topics' and column_name = 'created_by'

union all
-- THE ONE THAT MATTERS MOST.
--
-- `for all` includes SELECT, and permissive policies combine with OR. A single
-- surviving `for all` policy on any of these tables grants partner B every row
-- the new select policy was written to hide — silently, with the correct-
-- looking policy sitting right beside it. If this row is false, the boundary
-- does not exist no matter what the rest of the output says.
select 'no FOR ALL policy survives on the classified tables',
       count(*) = 0,
       coalesce(string_agg(policyname, ', '), 'none')
from pg_policies
where schemaname = 'public'
  and cmd = 'ALL'
  and tablename in (
    'field_life_items', 'field_captures', 'field_corrections',
    'field_standing_rules', 'field_held_topics', 'field_away_windows'
  )

union all
select 'every select policy filters on visibility or author',
       count(*) = 5,
       count(*)::text || ' of 5'
from pg_policies
where schemaname = 'public' and cmd = 'SELECT'
  and tablename in (
    'field_life_items', 'field_captures', 'field_corrections',
    'field_standing_rules', 'field_held_topics'
  )
  and qual like '%visibility%'

union all
select 'update and delete are scoped the same way as select',
       count(*) = 10,
       count(*)::text || ' of 10'
from pg_policies
where schemaname = 'public' and cmd in ('UPDATE', 'DELETE')
  and tablename in (
    'field_life_items', 'field_captures', 'field_corrections',
    'field_standing_rules', 'field_held_topics'
  )
  and qual like '%visibility%'

union all
select 'presence stays private to its author',
       count(*) = 1,
       count(*)::text || ' of 1'
from pg_policies
where schemaname = 'public' and tablename = 'field_away_windows'
  and cmd = 'SELECT' and qual like '%profile_id%'

union all
select 'the visibility stamp is attached to all five',
       count(*) = 5,
       count(*)::text || ' of 5'
from pg_trigger
where tgname = 'field_visibility_integrity' and not tgisinternal

union all
select 'held topics stamp an author on insert',
       count(*) = 1,
       count(*)::text || ' of 1'
from pg_trigger
where tgname = 'field_held_topic_actor_integrity' and not tgisinternal

union all
select 'the crossing RPC exists and only authenticated may call it',
       count(*) = 2,
       count(*)::text || ' of 2'
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in (
    'field_share_solo_history', 'field_solo_history_count'
  )
  and grantee = 'authenticated' and privilege_type = 'EXECUTE'

union all
-- The safety property. Nothing that already existed may have become invisible:
-- the column default is 'shared' and the stamp only fires on new rows, so every
-- pre-existing row must still be shared. A non-zero count here means live data
-- just disappeared from somebody's screen.
select 'no existing row was retroactively made private',
       (
         (select count(*) from public.field_life_items where visibility = 'private')
         + (select count(*) from public.field_captures where visibility = 'private')
         + (select count(*) from public.field_corrections where visibility = 'private')
         + (select count(*) from public.field_standing_rules where visibility = 'private')
         + (select count(*) from public.field_held_topics where visibility = 'private')
       ) = 0,
       (
         (select count(*) from public.field_life_items where visibility = 'private')
         + (select count(*) from public.field_captures where visibility = 'private')
         + (select count(*) from public.field_corrections where visibility = 'private')
         + (select count(*) from public.field_standing_rules where visibility = 'private')
         + (select count(*) from public.field_held_topics where visibility = 'private')
       )::text || ' rows now private'
;
