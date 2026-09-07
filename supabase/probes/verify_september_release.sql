-- Did the September release land, and did the *right version* of it land?
--
-- `which_migrations_are_applied.sql` answers "is it there" by probing one
-- artifact per migration. That is enough for a migration that creates a table
-- and not enough for one that replaces a function body, because two different
-- versions of the same migration create the same artifact.
--
-- 20260907010000 is exactly that case. Its probe looks for
-- `private.is_departure_attribution`, which *both* versions create — the
-- original, which recognised the deletion cascade by its shape alone, and the
-- tightened one, which also requires the person each nulled column named to be
-- gone. Only the second closes the hole where either partner could run
--
--     update public.field_life_items set created_by = null where id = <theirs>
--
-- and strip authorship from the other's work. So this file reads bodies and
-- privileges rather than existence.
--
-- Read-only. Writes nothing, and touches no relationship content.
-- Every row must read ok = true.

select
  'attribution: a departure requires the profile to be gone' as check,
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'is_departure_attribution'
      and pg_get_functiondef(p.oid) ilike '%public.profiles%'
  ) as ok

union all
-- The load-bearing half of 20260907020000. If this is false the door is open
-- however good the function bodies look, because the client can simply name
-- the column.
select 'yours_entries: authenticated cannot UPDATE anything but body',
  not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'yours_entries'
      and grantee = 'authenticated' and privilege_type = 'UPDATE'
      and column_name <> 'body'
  )

union all
select 'yours_entries: authenticated cannot INSERT anything but client_id, body',
  not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'yours_entries'
      and grantee = 'authenticated' and privilege_type = 'INSERT'
      and column_name not in ('client_id', 'body')
  )

union all
-- The app still has to work. A revoke that took `body` with it would look
-- identical to success above and break every save.
select 'yours_entries: authenticated can still write body',
  exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'yours_entries'
      and grantee = 'authenticated' and privilege_type = 'UPDATE'
      and column_name = 'body'
  )

union all
-- The withdrawn second attempt. If this is false, production has the version
-- that scoped the door with statement_timestamp() and can be walked through
-- by two statements in one submission.
select 'the statement_timestamp door is not in production',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'yours_stamp_entry'
      and pg_get_functiondef(p.oid) ilike '%statement_timestamp%'
  )

union all
-- Nine functions write a lifecycle column and every one of them must close
-- the door it opened, on every path.
select 'all nine lifecycle writers close the door',
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in (
        'yours_present_next', 'yours_keep_for_now', 'yours_hold',
        'yours_let_go', 'yours_snooze', 'yours_let_this_return',
        'yours_update_held', 'yours_prepare_offer', 'yours_sweep'
      )
      and pg_get_functiondef(p.oid) ilike '%yours_close_lifecycle%'
  ) = 9

union all
-- And the three that never wrote one stopped opening it at all.
select 'the three that never needed the door stopped opening it',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'yours_present_next_offer', 'yours_send_offer', 'yours_offer_let_go'
      )
      and pg_get_functiondef(p.oid) ilike '%yours_lifecycle%'
  )

order by 1;
