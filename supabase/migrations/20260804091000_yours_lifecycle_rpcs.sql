-- ○ Yours — the lifecycle, and the gate that decides when a return is a return.
--
-- Every write that moves an entry through its life is here rather than in the
-- client, for the reason CIRCLE.md §11 gives: the server holds authoritative
-- state, the first successfully saved action wins, and other devices dismiss
-- their stale copy on reconnect. A client that could set `ready_at` could buy
-- itself an unbounded life, and the previous migration's trigger refuses to
-- let it — these functions are the only things that announce themselves with
-- `we.yours_lifecycle`.
--
-- THE GATE (§5, locked #5)
--
-- Concurrent timers must never cause an entry to disappear before it was
-- actually shown. Silence can only mean release *after the question was
-- presented*. So:
--
--   an entry becomes presentable at `ready_at`
--   the oldest one appears when the owner next opens the space
--   only then does its seven-day decision window begin
--   only one entry is presented at a time
--   the next appears on the owner's *next visit*, not immediately
--   ordering is strictly chronological, never by content, length or behaviour
--
-- The last of those is what `p_visit` is for. The client mints one uuid per
-- foreground session. `yours_present_next` is idempotent within a visit — it
-- returns the entry already under question rather than promoting a second one
-- — so a client that calls it twice cannot walk the queue, and a client that
-- calls it on every render cannot either.
--
-- An entry can therefore sit ready for a long time without being at risk. The
-- clock that can *release* something only ever runs while the person has been
-- asked. The one deliberate exception is the snooze, and it is documented
-- where it happens.

begin;

-- MARK: The crossing door ---------------------------------------------------
--
-- One door, not two. `offered_topics` already is the frozen artifact that
-- crosses from a private proposal; a prepared offer is the same kind of thing
-- arriving from the other private surface, so it widens rather than forks.
--
-- Both source columns are nullable and both are `on delete set null`, and
-- there is deliberately no constraint requiring one of them to survive. What
-- crossed to the partner must not depend on the owner's private records
-- continuing to exist — the whole point of a frozen artifact is that letting
-- go of the source leaves the offer standing on its own, and a check
-- demanding a live source would turn "I let that go" into a foreign-key error
-- on the partner's screen.
--
-- First in the file, before the functions that write it: plpgsql does not
-- resolve column references until a function first runs, so a function
-- created above this would work and then fail at runtime on somebody's phone.

alter table public.offered_topics
  alter column private_proposal_id drop not null;

alter table public.offered_topics
  add column if not exists yours_offer_id uuid unique
    references public.yours_prepared_offers(id) on delete set null;

-- MARK: Shared parts --------------------------------------------------------

create or replace function private.yours_require_user()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;
  return v_user;
end;
$$;

revoke all on function private.yours_require_user()
  from public, anon, authenticated;

-- Something was decided in this visit, so the next thing waits for the next
-- one. §5: "After it is resolved or expires, the next ready entry appears on
-- the owner's next visit, not immediately."
create or replace function private.yours_close_visit(
  p_user uuid,
  p_visit uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.yours_owner_state as s (
    owner_id, last_visit, last_resolution_visit
  )
  values (p_user, p_visit, p_visit)
  on conflict (owner_id) do update
    set last_visit = coalesce(excluded.last_visit, s.last_visit),
        last_resolution_visit = coalesce(
          excluded.last_resolution_visit, s.last_resolution_visit
        );
$$;

revoke all on function private.yours_close_visit(uuid, uuid)
  from public, anon, authenticated;

-- §13. Written before the row is destroyed, and carrying nothing that could
-- bring it back — no id, no title, no text. `object_kind` is not optional
-- because a pooled release rate across both kinds is a number that reads as
-- healthy while meaning nothing: a prepared offer is already partner-directed,
-- so letting one go is avoidance-shaped, and free personal writing is a
-- different emotional object entirely.
create or replace function private.yours_record_release(
  p_user uuid,
  p_kind text,
  p_reason text,
  p_renewal_count int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Declining to say why is the normal case and writes nothing. Letting go
  -- must never become a form.
  if p_reason is null then
    return;
  end if;

  insert into public.yours_releases (
    owner_id, object_kind, reason, renewal_count_at_release
  )
  values (p_user, p_kind, p_reason, coalesce(p_renewal_count, 0));
end;
$$;

revoke all on function private.yours_record_release(uuid, text, text, int)
  from public, anon, authenticated;

-- MARK: Opening the space, and what is waiting ------------------------------

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

  perform set_config('we.yours_lifecycle', 'on', true);

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
    return v_entry;
  end if;

  -- Something was already resolved in this visit. The next one waits.
  if v_state.last_resolution_visit is not distinct from p_visit then
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

  -- A record variable whose fields are all null is not NULL, and a caller
  -- reading "nothing is waiting for you" out of a row of nulls would be one
  -- `if let` away from showing an empty return as a real one.
  if v_entry.id is null then
    return null;
  end if;
  return v_entry;
end;
$$;

-- MARK: Answering a return --------------------------------------------------

-- "Keep for now" — the first return only. At the second return the choice is
-- keep-only-for-me, prepare an offer, or let it go, and the first of those is
-- permanence rather than a third interval. Renewal is permission to ask, never
-- permission to infer: keeping something twice does not make it load-bearing,
-- and this count may never leave the row it is on.
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
  perform set_config('we.yours_lifecycle', 'on', true);

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
  return v_entry;
end;
$$;

-- "Keep indefinitely" / "Keep this only for me". Available from the first save
-- and visually secondary there — somebody who knows on day one that a thing is
-- permanent should not have to wait eighteen weeks to say so — and it is the
-- permanence offered at the second return.
--
-- Held is a state, not a destination. `yours_let_this_return` below is the way
-- back, and it exists because permanence people cannot undo is permanence they
-- hesitate to use.
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
  perform set_config('we.yours_lifecycle', 'on', true);

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
  return v_entry;
end;
$$;

-- "Let go". Immediate, separate, unambiguous, and the only client-reachable
-- path to `private.yours_destroy`.
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
  perform set_config('we.yours_lifecycle', 'on', true);

  select * into v_entry
  from public.yours_entries e
  where e.id = p_entry and e.owner_id = v_user
  for update;

  if v_entry.id is null then
    -- Already gone. Silent, because "nothing can resurrect an entry once
    -- destruction has begun" (§11) means a second attempt is a success.
    return;
  end if;

  perform private.yours_record_release(
    v_user, 'entry', p_reason, v_entry.renewal_count
  );
  perform private.yours_destroy(array[p_entry]);

  if p_visit is not null then
    perform private.yours_close_visit(v_user, p_visit);
  end if;
end;
$$;

-- "Give me a week." One action, one week, once.
--
-- The one place in this design where a clock that can release something runs
-- while the person is not looking. That is deliberate and it is not an
-- oversight to be tidied away later: the exact final date is shown before the
-- action is confirmed, so consent was obtained for this specific outcome —
-- "This will return on 21 September. If you do nothing, it will be let go on
-- 28 September."
--
-- Mechanically: the entry stops being presented and becomes presentable again
-- in exactly seven days, but `decide_by` is set now, to fourteen days out, and
-- the sweep honours it whether or not the entry is ever shown again. If the
-- person does open the space on day seven, the ordinary presentation path sets
-- the same final date it already has.
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
  perform set_config('we.yours_lifecycle', 'on', true);

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
  return v_entry;
end;
$$;

-- "Let this return." Held back into a natural life.
--
-- A fresh first-life interval, prior renewal history cleared, and it does not
-- itself count as a renewal. `p_body` carries the edited text when this is the
-- answer to §4's held-edit question — "You changed something held. Should this
-- version stay held, or return to a natural life?" — and there is no version
-- history anywhere in this file, deliberately: a revision log would be an
-- accumulating, undeletable record of exactly the material this design exists
-- to let go of.
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
  perform set_config('we.yours_lifecycle', 'on', true);

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
  return v_entry;
end;
$$;

-- "Update Held." Overwrites, and explicitly keeps the new version permanent.
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

  perform set_config('we.yours_lifecycle', 'on', true);

  update public.yours_entries e
  set body = p_body,
      state = 'held',
      held_at = coalesce(e.held_at, now())
  where e.id = p_entry and e.owner_id = v_user
  returning * into v_entry;

  if v_entry.id is null then
    raise exception 'entry not found';
  end if;
  return v_entry;
end;
$$;

-- MARK: Prepared offers -----------------------------------------------------

-- §6. A separate, frozen artifact with the exact wording the person approves.
--
-- What happens to the *source* entry is the one thing CIRCLE.md leaves open.
-- §3 lists "Prepare something I could offer" beside "Keep this only for me"
-- and "Let it go" as if it were terminal, but says nothing about the entry's
-- fate, and the two obvious readings are both wrong: destroying the source
-- would delete somebody's private writing as a side effect of an unrelated
-- decision, and holding it would grant permanence nobody asked for.
--
-- So preparing gives the source a fresh interval at its current stage and
-- leaves the renewal count alone — which is what §3 literally says should
-- happen, since "renewal count increments only on an explicit renewal
-- decision" and this is not one. The entry stays mortal and will ask again.
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

  perform set_config('we.yours_lifecycle', 'on', true);

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
  return v_offer;
end;
$$;

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

  perform set_config('we.yours_lifecycle', 'on', true);

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

-- Send it. The partner sees an `offered_topics` row and nothing else: not the
-- source entry, not the renewal count, not the dates, not the fact that
-- anything matured. Indistinguishable from a topic composed from scratch that
-- morning.
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

  perform set_config('we.yours_lifecycle', 'on', true);

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
  perform set_config('we.yours_lifecycle', 'on', true);

  perform private.yours_record_release(v_user, 'prepared_offer', p_reason, 0);

  delete from public.yours_prepared_offers o
  where o.id = p_offer and o.owner_id = v_user and o.sent_at is null;

  if p_visit is not null then
    perform private.yours_close_visit(v_user, p_visit);
  end if;
end;
$$;

-- MARK: Still here ----------------------------------------------------------
--
-- §5's dormancy rule is about the *product*, not this space: "If the product
-- has not been opened for 90 days, every unheld entry is deleted." So the
-- timestamp the sweep reads cannot only be written when somebody opens Yours,
-- or a person who uses the shared side every day would have their private
-- writing deleted out from under them at ninety days.
--
-- The app calls this on foreground, whether or not this space is opened. It
-- lives on `yours_owner_state` rather than on `profiles` because when somebody
-- last opened the app is not their partner's business, and `profiles` is
-- partner-readable.
create or replace function public.yours_touch()
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.yours_owner_state as s (owner_id, last_opened_at)
  values ((select auth.uid()), now())
  on conflict (owner_id) do update set last_opened_at = now();
$$;

-- MARK: The teaching moment -------------------------------------------------
--
-- §2 allows the word "Yours" to appear exactly twice in a person's lifetime.
-- Server-side because a lifetime belongs to the person and `@AppStorage`
-- belongs to a device.
create or replace function public.yours_mark_taught(p_which text)
returns public.yours_owner_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.yours_require_user();
  v_state public.yours_owner_state;
begin
  if p_which not in ('promise', 'firstEntry') then
    raise exception 'unknown teaching moment';
  end if;

  insert into public.yours_owner_state as s (
    owner_id, taught_in_promise, taught_on_first_entry
  )
  values (
    v_user, p_which = 'promise', p_which = 'firstEntry'
  )
  on conflict (owner_id) do update
    -- Only ever set. A flag that could be cleared is a word that could be
    -- taught a third time.
    set taught_in_promise = s.taught_in_promise or p_which = 'promise',
        taught_on_first_entry =
          s.taught_on_first_entry or p_which = 'firstEntry'
  returning * into v_state;

  return v_state;
end;
$$;

-- MARK: Grants --------------------------------------------------------------

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
    'public.yours_offer_let_go(uuid,uuid,text)',
    'public.yours_touch()',
    'public.yours_mark_taught(text)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end;
$$;

commit;
