begin;

-- A lifecycle announcement outlived the RPC that made it.
--
-- `private.yours_stamp_entry()` neutralises a client's writes to `state`,
-- `ready_at`, `renewal_count`, `presented_at`, `decide_by`, `held_at` and
-- `snoozed_at`, and refuses an edit to a held entry, unless
-- `we.yours_lifecycle` is announced. Every lifecycle RPC announces it with
-- `set_config(..., true)` — which is transaction-local, not function-local,
-- and nothing ever set it back. So once any one of them had run, the guard
-- was open for the rest of the transaction and a direct write could set its
-- own `state` to 'held' or buy itself ten more years of `ready_at`.
--
-- TWO EARLIER ATTEMPTS, AND WHY BOTH FAILED
--
-- The first scoped the door by role, which does nothing: the trigger is
-- `security definer`, so `current_user` inside it is the function's owner
-- whoever called it. The test proved it a no-op.
--
-- The second scoped the door to a *statement*, keyed on `statement_timestamp()`
-- — and its own header admitted the residual while getting the mechanism
-- backwards. `statement_timestamp()` does not advance per statement. It is set
-- once per client Query message, so every statement in one multi-statement
-- submission shares it. That is not a microsecond-identical clock race the
-- writer cannot arrange; it is the ordinary behaviour of
--
--     select public.yours_hold('...'); update public.yours_entries
--       set state = 'held', ready_at = now() + interval '10 years';
--
-- sent as one body. Both statements read the same timestamp, the second
-- matches the door the first opened, and the guard is gone. It is also
-- precisely why the design appeared to work: the several statements inside an
-- RPC body share a timestamp for the same reason, so the sweep kept passing
-- while the hole stayed open.
--
-- WHAT THIS DOES INSTEAD
--
-- Two layers, and the first does not involve ambient state at all.
--
-- 1. Column privileges. `authenticated` loses the privilege to *name* a
--    lifecycle column in an INSERT or UPDATE. No setting, nonce or timestamp
--    participates in that decision, so no sequence of statements can talk its
--    way past it. This is the layer that is actually load-bearing.
--
-- 2. The announcement becomes function-local, by being closed rather than
--    cleverly scoped. Each RPC that writes a lifecycle column opens the door,
--    does its work, and closes it before returning — on every path. Three
--    RPCs that never write one stop opening it at all.
--
-- Asserted by yours_personal_space.test.sql, which now checks refusal rather
-- than silent neutralisation, checks the multi-statement bypass above
-- directly, and checks that the door is shut after an RPC returns — including
-- the zero-row path, where the RPC's UPDATE matched nothing.

-- MARK: The door ------------------------------------------------------------

-- A nonce rather than 'on', so a leaked value from one call cannot be replayed
-- into another, and so a stray `set_config('we.yours_lifecycle', 'on')` in
-- somebody's psql session is not a master key. The trigger accepts any
-- non-empty value, so the nonce is defence rather than authentication — the
-- privileges above are the authentication.
create or replace function private.yours_open_lifecycle()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config(
    'we.yours_lifecycle', gen_random_uuid()::text, true
  );
end;
$$;

-- Closed explicitly, because there is no other moment that can close it. An
-- exception needs no handling here: it aborts the transaction, and the setting
-- was transaction-local, so it rolls back with everything else.
create or replace function private.yours_close_lifecycle()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('we.yours_lifecycle', '', true);
end;
$$;

revoke all on function private.yours_open_lifecycle()
  from public, anon, authenticated;
revoke all on function private.yours_close_lifecycle()
  from public, anon, authenticated;

-- MARK: The privileges that do the work -------------------------------------

-- `20260804090000` created this table and never granted anything on it,
-- relying on Supabase's bootstrap grant of all privileges on new public tables
-- to `authenticated`. That grant is what let a client name a lifecycle column
-- in the first place. The RLS policies were doing the whole job alone, and
-- they are about *rows*, not columns.
--
-- The client writes exactly two shapes, and this is the complete list:
--
--   `YoursSupabaseBackend.save`  insert (client_id, body)
--   `YoursSupabaseBackend.edit`  update (body)
--
-- `owner_id` is deliberately not grantable even on insert: the trigger fills
-- it from `auth.uid()`, and the RLS insert policy checks the result. The same
-- posture `public.plans` has had since 20260725062000 — revoke the writes and
-- let the definer RPCs be the only way in.
--
-- `select` is untouched. `delete` was never permitted: there is no delete
-- policy on this table, deliberately, so that `private.yours_destroy` stays
-- the one way out.
revoke insert, update on public.yours_entries from anon, authenticated;
grant insert (client_id, body) on public.yours_entries to authenticated;
grant update (body) on public.yours_entries to authenticated;

-- MARK: The trigger ---------------------------------------------------------

create or replace function private.yours_stamp_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Any non-empty announcement. It is opened and closed by the RPCs below
  -- rather than scoped by a timestamp, so there is nothing here to outsmart.
  v_lifecycle boolean :=
    nullif(current_setting('we.yours_lifecycle', true), '') is not null;
begin
  if tg_op = 'INSERT' then
    new.owner_id := coalesce(new.owner_id, (select auth.uid()));
    new.created_at := now();
    new.updated_at := now();
    new.renewal_count := 0;
    new.state := 'living';
    new.presented_at := null;
    new.decide_by := null;
    new.snoozed_at := null;
    new.held_at := null;
    new.ready_at := now() + private.yours_interval(0);
  else
    -- Identity is not editable. A row rewritten over somebody else's would be
    -- the one way private writing could change hands.
    new.id := old.id;
    new.owner_id := old.owner_id;
    new.client_id := old.client_id;
    new.created_at := old.created_at;
    new.updated_at := now();

    if not v_lifecycle then
      -- Locked #8, against the client. The RPCs manage this column
      -- themselves: `yours_snooze` refuses a second one, and
      -- `yours_let_this_return` clears it because a fresh first life is
      -- entitled to its own week.
      new.snoozed_at := old.snoozed_at;

      -- An edit. §4: held status must not silently transfer to newly written
      -- material — new words do not inherit permanence — so editing something
      -- held forces an explicit choice, which is an RPC, not this path.
      -- One literal, on one line, deliberately: plpgsql parses RAISE itself
      -- and the format is expected to be a single string, so the adjacent
      -- literals this comment used to sit above were a portability gamble for
      -- no benefit.
      if old.state = 'held' then
        raise exception 'a held entry is edited through yours_update_held or yours_let_this_return, not by writing over it';
      end if;

      new.state := old.state;
      new.renewal_count := old.renewal_count;
      new.presented_at := old.presented_at;
      new.decide_by := old.decide_by;
      new.held_at := old.held_at;

      if new.body is distinct from old.body then
        -- §3: editing restarts the *current* interval, not the lifecycle
        -- stage. An entry in its first renewal that is edited gets a fresh
        -- twelve weeks, not a demotion to six. Renewal count is preserved
        -- above, and this is the line that depends on it.
        new.ready_at := now() + private.yours_interval(old.renewal_count);
        -- It is living again, and its unanswered question goes with it.
        new.state := 'living';
        new.presented_at := null;
        new.decide_by := null;
      else
        new.ready_at := old.ready_at;
      end if;
    end if;
  end if;

  -- Locked #6, on every path into the table.
  new.unseen_delete_at := new.ready_at + interval '1 year';

  -- A held entry has no pending question. Leaving a stale window on it would
  -- let the sweep delete something a person deliberately made permanent.
  if new.state = 'held' then
    new.presented_at := null;
    new.decide_by := null;
  end if;

  return new;
end;
$$;

revoke all on function private.yours_stamp_entry()
  from public, anon, authenticated;

-- MARK: The RPCs that open the door, re-emitted so that they close it --------
--
-- `20260804091000` and `20260804092000` are deployed, so the closes cannot be
-- edited into them; these are the same bodies with the bracket added. The only
-- other differences are stated where they occur.

create or replace function public.yours_present_next(p_visit uuid)
returns public.yours_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_state public.yours_owner_state;
  v_entry public.yours_entries;
begin
  if p_visit is null then
    raise exception 'a visit is required';
  end if;

  perform private.yours_open_lifecycle();

  -- Opening the space is also what keeps the account out of the 90-day
  -- dormancy sweep. Note that it is *opening this space* — visiting the shared
  -- side does not count, and neither does it rescue a queued entry from its
  -- outer bound. §5 is emphatic that the bound follows the entry's state and
  -- not the person's behaviour.
  insert into public.yours_owner_state (owner_id, last_opened_at, last_visit)
  values (v_user, now(), p_visit)
  on conflict (owner_id) do update
    set last_opened_at = now(),
        last_visit = p_visit
  returning * into v_state;

  -- Already under question, and still inside its window. The same entry on
  -- every device, and the same entry however many times this is called.
  select * into v_entry
  from public.yours_entries e
  where e.owner_id = v_user
    and e.state = 'presented'
    and e.decide_by > now()
  limit 1;

  if v_entry.id is not null then
    perform private.yours_close_lifecycle();
    return v_entry;
  end if;

  -- Something was already resolved in this visit. The next one waits.
  if v_state.last_resolution_visit is not distinct from p_visit then
    perform private.yours_close_lifecycle();
    return null;
  end if;

  -- The oldest presentable entry, and only the oldest. `living` is accepted
  -- alongside `ready` so that an entry whose interval elapsed since the last
  -- sweep is not invisible for up to an hour — the sweep's promotion step is a
  -- convenience, not the thing that makes a return possible.
  update public.yours_entries e
  set state = 'presented',
      presented_at = now(),
      decide_by = now() + interval '7 days'
  where e.id = (
    select candidate.id
    from public.yours_entries candidate
    where candidate.owner_id = v_user
      and candidate.state in ('living', 'ready')
      and candidate.ready_at <= now()
    order by candidate.ready_at asc, candidate.created_at asc, candidate.id asc
    limit 1
    for update skip locked
  )
  returning * into v_entry;

  -- Closed before either answer, and this is the zero-row path the tests name:
  -- an UPDATE that matched nothing still opened the door, and still has to
  -- shut it.
  perform private.yours_close_lifecycle();

  -- A record variable whose fields are all null is not NULL, and a caller
  -- reading "nothing is waiting for you" out of a row of nulls would be one
  -- `if let` away from showing an empty return as a real one.
  if v_entry.id is null then
    return null;
  end if;
  return v_entry;
end;
$$;

create or replace function public.yours_keep_for_now(
  p_entry uuid,
  p_visit uuid
)
returns public.yours_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
begin
  perform private.yours_open_lifecycle();

  select * into v_entry
  from public.yours_entries e
  where e.id = p_entry and e.owner_id = v_user
  for update;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;
  if v_entry.state <> 'presented' then
    raise exception 'nothing was asked about this entry';
  end if;
  if v_entry.renewal_count >= 1 then
    raise exception 'the second return is answered with hold, prepare or let go';
  end if;

  update public.yours_entries e
  set renewal_count = v_entry.renewal_count + 1,
      state = 'living',
      ready_at = now() + private.yours_interval(v_entry.renewal_count + 1),
      presented_at = null,
      decide_by = null
  where e.id = p_entry
  returning * into v_entry;

  perform private.yours_close_visit(v_user, p_visit);
  perform private.yours_close_lifecycle();
  return v_entry;
end;
$$;

create or replace function public.yours_hold(
  p_entry uuid,
  p_visit uuid default null
)
returns public.yours_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
begin
  perform private.yours_open_lifecycle();

  update public.yours_entries e
  set state = 'held',
      held_at = now(),
      presented_at = null,
      decide_by = null
  where e.id = p_entry and e.owner_id = v_user
  returning * into v_entry;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;

  if p_visit is not null then
    perform private.yours_close_visit(v_user, p_visit);
  end if;
  perform private.yours_close_lifecycle();
  return v_entry;
end;
$$;

create or replace function public.yours_let_go(
  p_entry uuid,
  p_visit uuid default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
begin
  perform private.yours_open_lifecycle();

  select * into v_entry
  from public.yours_entries e
  where e.id = p_entry and e.owner_id = v_user
  for update;

  if v_entry.id is null then
    -- Already gone. Silent, because "nothing can resurrect an entry once
    -- destruction has begun" (§11) means a second attempt is a success.
    perform private.yours_close_lifecycle();
    return;
  end if;

  perform private.yours_record_release(
    v_user, 'entry', p_reason, v_entry.renewal_count
  );
  perform private.yours_destroy(array[p_entry]);

  if p_visit is not null then
    perform private.yours_close_visit(v_user, p_visit);
  end if;
  perform private.yours_close_lifecycle();
end;
$$;

create or replace function public.yours_snooze(
  p_entry uuid,
  p_visit uuid
)
returns public.yours_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
begin
  perform private.yours_open_lifecycle();

  select * into v_entry
  from public.yours_entries e
  where e.id = p_entry and e.owner_id = v_user
  for update;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;
  if v_entry.state <> 'presented' then
    raise exception 'nothing was asked about this entry';
  end if;
  if v_entry.snoozed_at is not null then
    raise exception 'one week, once';
  end if;

  update public.yours_entries e
  set state = 'ready',
      ready_at = now() + interval '7 days',
      snoozed_at = now(),
      decide_by = now() + interval '14 days'
  where e.id = p_entry
  returning * into v_entry;

  perform private.yours_close_visit(v_user, p_visit);
  perform private.yours_close_lifecycle();
  return v_entry;
end;
$$;

create or replace function public.yours_let_this_return(
  p_entry uuid,
  p_body text default null
)
returns public.yours_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
begin
  perform private.yours_open_lifecycle();

  update public.yours_entries e
  set body = coalesce(nullif(btrim(p_body), ''), e.body),
      state = 'living',
      renewal_count = 0,
      ready_at = now() + private.yours_interval(0),
      held_at = null,
      presented_at = null,
      decide_by = null,
      snoozed_at = null
  where e.id = p_entry and e.owner_id = v_user
  returning * into v_entry;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;
  perform private.yours_close_lifecycle();
  return v_entry;
end;
$$;

create or replace function public.yours_update_held(
  p_entry uuid,
  p_body text
)
returns public.yours_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
begin
  if nullif(btrim(p_body), '') is null then
    raise exception 'nothing to keep';
  end if;

  perform private.yours_open_lifecycle();

  update public.yours_entries e
  set body = p_body,
      state = 'held',
      held_at = coalesce(e.held_at, now())
  where e.id = p_entry and e.owner_id = v_user
  returning * into v_entry;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;
  perform private.yours_close_lifecycle();
  return v_entry;
end;
$$;

create or replace function public.yours_prepare_offer(
  p_entry uuid,
  p_client_id uuid,
  p_title text,
  p_question text,
  p_options text[],
  p_visit uuid default null
)
returns public.yours_prepared_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_entry public.yours_entries;
  v_offer public.yours_prepared_offers;
begin
  if nullif(btrim(p_title), '') is null
     or char_length(p_title) > 120
     or nullif(btrim(p_question), '') is null
     or char_length(p_question) > 180
     or cardinality(p_options) not between 2 and 5
     or exists (
       select 1
       from unnest(p_options) option_value
       where nullif(btrim(option_value), '') is null
          or char_length(option_value) > 80
     ) then
    raise exception 'invalid offer';
  end if;

  perform private.yours_open_lifecycle();

  select * into v_entry
  from public.yours_entries e
  where e.id = p_entry and e.owner_id = v_user
  for update;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;

  insert into public.yours_prepared_offers (
    owner_id, client_id, source_entry_id, title, question, options
  )
  values (v_user, p_client_id, p_entry, p_title, p_question, p_options)
  on conflict (owner_id, client_id) do update
    set source_entry_id = excluded.source_entry_id
  returning * into v_offer;

  if v_entry.state <> 'held' then
    update public.yours_entries e
    set state = 'living',
        ready_at = now() + private.yours_interval(v_entry.renewal_count),
        presented_at = null,
        decide_by = null
    where e.id = p_entry;
  end if;

  if p_visit is not null then
    perform private.yours_close_visit(v_user, p_visit);
  end if;
  perform private.yours_close_lifecycle();
  return v_offer;
end;
$$;

-- MARK: Three that never needed the door ------------------------------------
--
-- `yours_present_next_offer`, `yours_send_offer` and `yours_offer_let_go`
-- announced the lifecycle and then wrote only `yours_prepared_offers`,
-- `offered_topics` and `yours_releases`. None of those carries
-- `yours_stamp_entry`; `private.yours_stamp_offer()` freezes its own columns
-- unconditionally and has never read the setting. So the announcement bought
-- nothing and left the door standing open for the rest of the transaction.
--
-- The bodies are otherwise unchanged.

create or replace function public.yours_present_next_offer(p_visit uuid)
returns public.yours_prepared_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_state public.yours_owner_state;
  v_offer public.yours_prepared_offers;
begin
  if p_visit is null then
    raise exception 'a visit is required';
  end if;

  select * into v_state
  from public.yours_owner_state s
  where s.owner_id = v_user;

  select * into v_offer
  from public.yours_prepared_offers o
  where o.owner_id = v_user
    and o.sent_at is null
    and o.decide_by > now()
  limit 1;

  if v_offer.id is not null then
    return v_offer;
  end if;

  if v_state.last_resolution_visit is not distinct from p_visit then
    return null;
  end if;

  update public.yours_prepared_offers o
  set presented_at = now(),
      decide_by = now() + interval '7 days'
  where o.id = (
    select candidate.id
    from public.yours_prepared_offers candidate
    where candidate.owner_id = v_user
      and candidate.sent_at is null
      and candidate.presented_at is null
      and candidate.ready_at <= now()
    order by candidate.ready_at asc, candidate.id asc
    limit 1
    for update skip locked
  )
  returning * into v_offer;

  if v_offer.id is null then
    return null;
  end if;
  return v_offer;
end;
$$;

create or replace function public.yours_send_offer(p_offer uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_couple uuid := (select public.my_couple_id());
  v_offer public.yours_prepared_offers;
  v_topic uuid;
begin
  if v_couple is null then
    raise exception 'a WE space is required before offering this';
  end if;

  select * into v_offer
  from public.yours_prepared_offers o
  where o.id = p_offer and o.owner_id = v_user
  for update;

  if v_offer.id is null then
    raise exception 'offer not found';
  end if;

  -- Idempotent, exactly like `offer_private_proposal`: a retried send is the
  -- same crossing, not a second one.
  select t.id into v_topic
  from public.offered_topics t
  where t.yours_offer_id = p_offer;

  if v_topic is not null then
    return v_topic;
  end if;

  insert into public.offered_topics (
    yours_offer_id, owner_id, couple_id, title, question, options
  )
  values (
    v_offer.id, v_user, v_couple,
    v_offer.title, v_offer.question, v_offer.options
  )
  returning id into v_topic;

  update public.yours_prepared_offers o
  set sent_at = now(), presented_at = null, decide_by = null
  where o.id = p_offer;

  return v_topic;
end;
$$;

create or replace function public.yours_offer_let_go(
  p_offer uuid,
  p_visit uuid default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
begin
  perform private.yours_record_release(v_user, 'prepared_offer', p_reason, 0);

  delete from public.yours_prepared_offers o
  where o.id = p_offer and o.owner_id = v_user and o.sent_at is null;

  if p_visit is not null then
    perform private.yours_close_visit(v_user, p_visit);
  end if;
end;
$$;

-- MARK: The sweep -----------------------------------------------------------

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
  -- This is the announcement, and it is closed at the end rather than left
  -- standing: `pg_cron` runs this in a transaction of its own today, but a
  -- function that only behaves because of who calls it is a function waiting
  -- to be called by somebody else.
  perform private.yours_open_lifecycle();

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

  perform private.yours_close_lifecycle();
  return v_destroyed;
end;
$$;

revoke all on function private.yours_sweep()
  from public, anon, authenticated;

-- MARK: Grants --------------------------------------------------------------
--
-- `create or replace function` preserves privileges, so this is belt and
-- braces rather than a repair. It is cheap, and a Yours RPC that silently lost
-- its grant would look exactly like the app being broken.

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.yours_present_next(uuid)',
    'public.yours_keep_for_now(uuid,uuid)',
    'public.yours_hold(uuid,uuid)',
    'public.yours_let_go(uuid,uuid,text)',
    'public.yours_snooze(uuid,uuid)',
    'public.yours_let_this_return(uuid,text)',
    'public.yours_update_held(uuid,text)',
    'public.yours_prepare_offer(uuid,uuid,text,text,text[],uuid)',
    'public.yours_present_next_offer(uuid)',
    'public.yours_send_offer(uuid)',
    'public.yours_offer_let_go(uuid,uuid,text)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end;
$$;

commit;
