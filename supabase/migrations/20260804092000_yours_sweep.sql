-- ○ Yours — expiry, which is the server's job and nobody else's.
--
-- CIRCLE.md §10: "Expiry is server-side, never dependent on the owner
-- reopening the app." Everything scheduled in this project until now has been
-- client-side and on-device — `FieldMomentScheduler` decides whether to speak,
-- `FieldMomentDelivery` schedules a local notification, `FieldStore` watches
-- for the day to change. All of that is fine for a nudge and none of it is
-- fine for a deletion. An entry whose life ends only when its owner next
-- launches the app is an entry that outlives its promise for as long as
-- somebody stays away, which is exactly the person the promise is for.
--
-- WHAT RUNS
--
-- One function, hourly. Hourly rather than daily so a seven-day window means
-- seven days rather than somewhere in the following twenty-four, and because
-- the alternative is a batch large enough to notice.
--
-- Every statement is idempotent and the whole thing is safe to run twice, back
-- to back, or after an outage that skipped a day. It has to be: `pg_cron` will
-- happily miss runs, and a sweep that behaved differently on its second
-- invocation would make the difference between "deleted on time" and "deleted
-- twice as fast" a matter of infrastructure luck.
--
-- WHAT IT MAY NOT DO
--
-- It never touches `public.yours_releases` — that table records that somebody
-- let something go and must survive the thing it describes. It never deletes a
-- held entry except on the dormancy path, which is disclosed. And it removes
-- rows only through `private.yours_destroy`, because that is where key
-- destruction lands when §14 closes.

begin;

create or replace function private.yours_sweep()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destroyed int := 0;
  v_ids uuid[];
begin
  -- The trigger refuses lifecycle changes that do not announce themselves.
  -- This is the announcement, and it is transaction-local.
  perform set_config('we.yours_lifecycle', 'on', true);

  -- 1. Anything whose interval has elapsed becomes presentable.
  --
  -- `yours_present_next` accepts `living` alongside `ready` for exactly this
  -- reason, so a person opening the space thirty seconds after an interval
  -- elapses is not told nothing is waiting. This step keeps the column honest
  -- for the queries below; it is not what makes a return possible.
  update public.yours_entries e
  set state = 'ready'
  where e.state = 'living'
    and e.ready_at <= now();

  -- 2. Silence, after the question was asked.
  --
  -- Covers both shapes of an open window: an entry currently presented whose
  -- seven days ran out, and a snoozed entry whose final fourteen did. The
  -- snooze is the one case where this fires without the entry being on screen,
  -- and that is deliberate — the exact date was shown and confirmed before the
  -- week was granted. See `public.yours_snooze`.
  select array_agg(e.id) into v_ids
  from public.yours_entries e
  where e.decide_by is not null
    and e.decide_by <= now()
    and e.state <> 'held';

  v_destroyed := v_destroyed + private.yours_destroy(v_ids);

  -- 3. The outer bound (§5, locked #6).
  --
  -- Presentation-gating means an entry is only at risk while somebody is
  -- looking at it, so without this a person who uses the shared side daily and
  -- never opens this space would accumulate an unbounded set of ready entries
  -- — the exact vault this design exists to prevent, reached by the one path
  -- the mechanism cannot see.
  --
  -- This is not "silence means release". It is a separate rule: unrenewed
  -- private storage has a maximum life, even when the renewal moment cannot
  -- reach its owner. It follows the entry's state, never the person's
  -- behaviour, and it must never be described as a year of inactivity.
  select array_agg(e.id) into v_ids
  from public.yours_entries e
  where e.state <> 'held'
    and e.unseen_delete_at <= now();

  v_destroyed := v_destroyed + private.yours_destroy(v_ids);

  -- 4. Prepared offers. Two weeks, one return, send or let go (§6).
  --
  -- No held state and no renewal, so an offer that was not sent simply ends.
  -- If it did not cross in two weeks, the preparation was the work.
  delete from public.yours_prepared_offers o
  where o.sent_at is null
    and o.decide_by is not null
    and o.decide_by <= now();

  -- An offer nobody ever came back to. The same outer-bound reasoning as
  -- step 3, at the offer's own scale.
  delete from public.yours_prepared_offers o
  where o.sent_at is null
    and o.presented_at is null
    and o.ready_at + interval '8 weeks' <= now();

  -- 5. Dormancy (§5).
  --
  -- An abandoned account must not quietly become the vault this design exists
  -- to prevent. Ninety days without opening the product and every unheld entry
  -- goes, including entries waiting to return. Disclosed once in privacy
  -- settings and never repeated on individual entries.
  --
  -- Held is exempt here as everywhere: its defining property is that every
  -- item in it entered deliberately.
  select array_agg(e.id) into v_ids
  from public.yours_entries e
  join public.yours_owner_state s on s.owner_id = e.owner_id
  where e.state <> 'held'
    and s.last_opened_at <= now() - interval '90 days';

  v_destroyed := v_destroyed + private.yours_destroy(v_ids);

  delete from public.yours_prepared_offers o
  using public.yours_owner_state s
  where s.owner_id = o.owner_id
    and o.sent_at is null
    and s.last_opened_at <= now() - interval '90 days';

  return v_destroyed;
end;
$$;

revoke all on function private.yours_sweep()
  from public, anon, authenticated;

-- MARK: The schedule --------------------------------------------------------
--
-- Guarded, because `pg_cron` is a hosted-platform extension and this file also
-- has to apply on a developer's machine and in CI, where the sweep is driven
-- directly by the pgTAP suite instead. A migration that cannot run without a
-- superuser extension is a migration nobody can test.
--
-- Seventeen past the hour for no better reason than that it is not zero: every
-- scheduled job in every system lands on the hour, and this one has no reason
-- to queue behind them.

do $$
begin
  if exists (
    select 1 from pg_available_extensions where name = 'pg_cron'
  ) then
    create extension if not exists pg_cron with schema extensions;

    -- Idempotent: re-running this migration reschedules rather than
    -- accumulating a second job that would double the sweep.
    if exists (
      select 1 from cron.job where jobname = 'yours-sweep'
    ) then
      perform cron.unschedule('yours-sweep');
    end if;

    perform cron.schedule(
      'yours-sweep',
      '17 * * * *',
      'select private.yours_sweep();'
    );
  else
    raise notice
      'pg_cron unavailable; private.yours_sweep() must be driven manually here';
  end if;
end;
$$;

commit;
