-- Shared Journeys v1
--
-- Restores the complete private-answer loop on the existing insight system:
-- evidence -> private answers -> protected synthesis -> private confirmations
-- -> one shared journey. Raw answers never become couple-readable.

begin;

-- MARK: Evidence-backed questions ------------------------------------------

alter table public.insights
  add column if not exists journey_scope text
    check (journey_scope in ('immediate', 'nearTerm', 'longTerm')),
  add column if not exists trigger_provenance text
    check (
      trigger_provenance in (
        'repeatedAspiration', 'upcomingPlan', 'unresolvedChoice',
        'slippingRhythm', 'meaningfulCluster', 'legacyHorizon'
      )
    ),
  add column if not exists subject_references jsonb not null default '[]'::jsonb,
  add column if not exists expires_at timestamptz,
  add column if not exists context_snapshot jsonb;

alter table public.insights
  drop constraint if exists insights_journey_subjects_array;
alter table public.insights
  add constraint insights_journey_subjects_array
  check (jsonb_typeof(subject_references) = 'array') not valid;

alter table public.insights
  drop constraint if exists insights_journey_options_count;
alter table public.insights
  add constraint insights_journey_options_count
  check (journey_scope is null or cardinality(options) between 2 and 4)
  not valid;

-- Retire the cadence-generated moments. They are evidence-free by definition.
update public.insights
set present = false
where seed_key like 'tonight-%'
   or seed_key like 'weekend-%'
   or seed_key like 'load-%'
   or seed_key like 'plan-%';

-- If an earlier build left several journey candidates visible, preserve only
-- the highest-ranked one before enforcing the product invariant.
with ranked as (
  select id,
         row_number() over (
           partition by couple_id
           order by
             case journey_scope
               when 'immediate' then 0
               when 'nearTerm' then 1
               else 2
             end,
             sort,
             id
         ) as position
  from public.insights
  where present and journey_scope is not null
)
update public.insights i
set present = false
from ranked r
where i.id = r.id and r.position > 1;

create unique index if not exists insights_one_active_journey_question_idx
  on public.insights(couple_id)
  where present and journey_scope is not null;

create table if not exists public.journey_passes (
  insight_id uuid not null references public.insights(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  passed_at timestamptz not null default now(),
  primary key (insight_id, profile_id)
);

alter table public.journey_passes enable row level security;
drop policy if exists journey_passes_select_own on public.journey_passes;
create policy journey_passes_select_own on public.journey_passes
  for select to authenticated
  using (profile_id = (select auth.uid()));
grant select on public.journey_passes to authenticated;

-- Keep only when each person submitted and when the private payload was
-- destroyed. This preserves an owner-readable receipt without retaining the
-- choice or note, and cannot disclose the other person's status through RLS.
create table if not exists public.journey_response_receipts (
  insight_id uuid not null references public.insights(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  submitted_at timestamptz not null default now(),
  resolved_at timestamptz,
  primary key (insight_id, profile_id)
);
alter table public.journey_response_receipts enable row level security;
drop policy if exists journey_response_receipts_select_own
  on public.journey_response_receipts;
create policy journey_response_receipts_select_own
  on public.journey_response_receipts for select to authenticated
  using (profile_id = (select auth.uid()));
grant select on public.journey_response_receipts to authenticated;

-- The retired UI used this RPC to expose whether the other person had
-- answered. Held is intentionally pressure-free now, so even that boolean is
-- no longer part of the authenticated contract.
revoke execute on function public.partner_answer_statuses()
  from authenticated;

-- MARK: Validated proposals ------------------------------------------------

alter table public.shared_directions
  add column if not exists summary text,
  add column if not exists rationale text,
  add column if not exists proposed_actions jsonb not null default '[]'::jsonb,
  add column if not exists synthesis_version text not null default 'legacy',
  add column if not exists expires_at timestamptz,
  add column if not exists status text not null default 'proposed'
    check (status in ('proposed', 'no_safe_direction', 'active'));

alter table public.shared_directions
  drop constraint if exists shared_directions_actions_shape;
alter table public.shared_directions
  add constraint shared_directions_actions_shape
  check (
    jsonb_typeof(proposed_actions) = 'array'
    and jsonb_array_length(proposed_actions) <= 3
  ) not valid;

create table if not exists public.direction_confirmations (
  insight_id uuid not null
    references public.shared_directions(insight_id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  decision text not null check (decision in ('choose', 'rest')),
  decided_at timestamptz not null default now(),
  primary key (insight_id, profile_id)
);

alter table public.direction_confirmations enable row level security;
drop policy if exists direction_confirmations_select_own
  on public.direction_confirmations;
create policy direction_confirmations_select_own
  on public.direction_confirmations for select to authenticated
  using (profile_id = (select auth.uid()));
grant select on public.direction_confirmations to authenticated;

create table if not exists public.journey_synthesis_jobs (
  insight_id uuid primary key references public.insights(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'processing')),
  attempts integer not null default 0 check (attempts between 0 and 2),
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.journey_synthesis_jobs enable row level security;
-- No authenticated policies or grants. Only service-role worker RPCs touch it.

-- MARK: Activated journeys -------------------------------------------------

create table if not exists public.field_journeys (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  insight_id uuid not null unique references public.insights(id) on delete cascade,
  direction_id uuid not null unique
    references public.shared_directions(insight_id) on delete cascade,
  scope text not null check (scope in ('immediate', 'nearTerm', 'longTerm')),
  title text not null check (char_length(title) between 1 and 120),
  summary text not null check (char_length(summary) between 1 and 240),
  rationale text not null check (char_length(rationale) between 1 and 500),
  evidence text[] not null default '{}',
  next_move text,
  horizon_id uuid references public.field_horizons(id) on delete set null,
  status text not null default 'active' check (status in ('active', 'completed')),
  activated_at timestamptz not null default now(),
  completed_at timestamptz,
  -- What the journey was read from. Carried so the room can bind to the
  -- couple's existing records rather than copying them, and so a surface that
  -- grows here can name its exact sources.
  subject_references jsonb not null default '[]'::jsonb
);

-- A couple may hold several living journeys at once. There is no one-active
-- index: an undertaking that lasts months cannot be displaced by whatever was
-- confirmed most recently, and "we are finding a home" and "we are planning
-- the wedding" are not competing for a single slot.
--
-- Scarcity is still enforced, but as a ceiling rather than a slot. Four is a
-- judgement about how many open undertakings a couple can actually hold in
-- mind, not a storage limit.
create or replace function private.field_journeys_cap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
    select count(*) from public.field_journeys
    where couple_id = new.couple_id and status = 'active'
  ) >= 4 then
    raise exception 'this couple already holds as many journeys as Us can carry';
  end if;
  return new;
end;
$$;

drop trigger if exists field_journeys_cap on public.field_journeys;
create trigger field_journeys_cap
  before insert on public.field_journeys
  for each row execute function private.field_journeys_cap();

alter table public.field_journeys enable row level security;
drop policy if exists field_journeys_select on public.field_journeys;
create policy field_journeys_select on public.field_journeys
  for select to authenticated
  using (couple_id = (select public.my_couple_id()));
grant select on public.field_journeys to authenticated;

alter table public.field_life_items
  add column if not exists journey_id uuid
    references public.field_journeys(id) on delete set null,
  add column if not exists journey_action_id text;
create unique index if not exists field_life_items_journey_action_idx
  on public.field_life_items(journey_id, journey_action_id)
  where journey_id is not null and journey_action_id is not null;

alter table public.field_evidence
  add column if not exists journey_id uuid
    references public.field_journeys(id) on delete set null;
create unique index if not exists field_evidence_journey_statement_idx
  on public.field_evidence(journey_id, statement)
  where journey_id is not null;

-- Content-free lifecycle instrumentation. No answer, note, question, or
-- proposal fields exist here, so an analytics query cannot accidentally read
-- them later.
create table if not exists public.journey_lifecycle_events (
  insight_id uuid not null references public.insights(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade,
  event text not null
    check (event in ('shown','answered','synthesized','confirmed','activated','expired','completed')),
  occurred_at timestamptz not null default now(),
  primary key (insight_id, event)
);
alter table public.journey_lifecycle_events enable row level security;

create or replace function private.record_journey_event(
  p_insight uuid,
  p_event text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.journey_lifecycle_events (insight_id, couple_id, event)
  select i.id, i.couple_id, p_event
  from public.insights i
  where i.id = p_insight
    and p_event in ('shown','answered','synthesized','confirmed','activated','expired','completed')
  on conflict (insight_id, event) do nothing;
$$;

-- MARK: Deterministic evidence ranking -------------------------------------

create or replace function public.refresh_shared_journey_question()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
  c record;
  v_expiry timestamptz;
begin
  if v_couple is null then return; end if;

  for c in
    select id from public.insights
    where couple_id = v_couple
      and journey_scope is not null
      and present
      and expires_at <= now()
  loop
    update public.insights set present = false where id = c.id;
    update public.journey_response_receipts
      set resolved_at = coalesce(resolved_at, now())
      where insight_id = c.id;
    delete from public.responses where insight_id = c.id;
    delete from public.journey_synthesis_jobs where insight_id = c.id;
    delete from public.shared_directions
      where insight_id = c.id and status <> 'active';
    perform private.record_journey_event(c.id, 'expired');
  end loop;

  if exists (
    select 1 from public.insights
    where couple_id = v_couple
      and journey_scope is not null
      and present
      and (expires_at is null or expires_at > now())
  ) then return; end if;

  -- Every candidate is grounded in a persisted shared object. No date or
  -- weekday alone creates a question.
  select * into c from (
    select
      'horizon:' || h.id::text as trigger_key,
      h.id::text as subject_id,
      'horizon'::text as subject_kind,
      case
        when h.target_date <= current_date + 1 then 'immediate'
        when h.target_date <= current_date + 7 then 'nearTerm'
        else 'longTerm'
      end as scope,
      case when h.target_date is null then 'legacyHorizon' else 'upcomingPlan' end
        as provenance,
      format('Does “%s” belong in the season ahead?', h.title) as title,
      coalesce(h.thesis, h.window_label, 'This direction already appears in Us.')
        as evidence,
      'Us · an existing horizon'::text as source,
      array['Make room for this','Shape it differently','Let it rest']::text[]
        as options,
      case when h.target_date is not null
        then ((h.target_date + 1)::timestamp at time zone 'UTC')
        else null::timestamptz
      end as source_expires_at,
      case
        when h.target_date <= current_date + 1 then 0
        when h.target_date <= current_date + 7 then 10
        else 30
      end as rank
    from public.field_horizons h
    where h.couple_id = v_couple
      and (h.target_date is null or h.target_date >= current_date)
      and not exists (
        select 1 from public.insights prior
        where prior.couple_id = v_couple
          and prior.seed_key = 'journey:horizon:' || h.id::text
      )

    union all

    select
      'question:' || q.id::text,
      q.id::text,
      'field_question',
      'nearTerm',
      'unresolvedChoice',
      q.prompt,
      q.reasoning,
      'Us · an unresolved choice',
      array[q.choice_a, q.choice_b]::text[],
      null::timestamptz,
      12
    from public.field_questions q
    where q.couple_id = v_couple and q.answered_at is null
      and not exists (
        select 1 from public.insights prior
        where prior.couple_id = v_couple
          and prior.seed_key = 'journey:question:' || q.id::text
      )

    union all

    select
      'rhythm:' || r.id::text,
      r.id::text,
      'rhythm',
      'nearTerm',
      'slippingRhythm',
      format('What would help “%s” find its place again?', r.title),
      format('The shared rhythm “%s” has been slipping.', r.title),
      'Life · a shared rhythm',
      array['Make it smaller','Choose a new time','Let it rest']::text[],
      null::timestamptz,
      14
    from public.field_rhythms r
    where r.couple_id = v_couple and r.health = 'slipping'
      and not exists (
        select 1 from public.insights prior
        where prior.couple_id = v_couple
          and prior.seed_key = 'journey:rhythm:' || r.id::text
      )

    union all

    select
      'cluster:' || cl.id::text,
      cl.id::text,
      'cluster',
      'nearTerm',
      'meaningfulCluster',
      format('What shape should “%s” take?', cl.title),
      cl.rationale,
      'Life · a meaningful cluster',
      array['Choose one next move','Leave the shape open','Let it rest']::text[],
      null::timestamptz,
      18
    from public.field_clusters cl
    where cl.couple_id = v_couple
      and (select count(*) from public.field_life_items li
           where li.cluster_id = cl.id and not li.is_done) >= 2
      and not exists (
        select 1 from public.insights prior
        where prior.couple_id = v_couple
          and prior.seed_key = 'journey:cluster:' || cl.id::text
      )

    union all

    -- `both_added` is the persisted proof that the aspiration arose on both
    -- sides independently. It is stronger evidence than text similarity and
    -- needs no model or account-wide scan to rank.
    select
      'aspiration:' || oi.id::text,
      oi.id::text,
      'ours_item',
      'longTerm',
      'repeatedAspiration',
      format('Does “%s” belong in the season ahead?', oi.title),
      format('This has appeared independently for both of you in %s.', oi.list),
      'Life · a repeated aspiration',
      array['Make room for this','Keep noticing it','Let it rest']::text[],
      null::timestamptz,
      24
    from public.field_ours_items oi
    where oi.couple_id = v_couple
      and oi.both_added
      and not oi.is_standing_note
      and not exists (
        select 1 from public.insights prior
        where prior.couple_id = v_couple
          and prior.seed_key = 'journey:aspiration:' || oi.id::text
      )
  ) candidates
  order by rank, trigger_key
  limit 1;

  if c.trigger_key is null then return; end if;

  v_expiry := now() + case c.scope
    when 'immediate' then interval '24 hours'
    when 'nearTerm' then interval '7 days'
    else interval '30 days'
  end;
  if c.scope = 'immediate' and c.source_expires_at is not null then
    v_expiry := least(v_expiry, c.source_expires_at);
  end if;

  insert into public.insights (
    couple_id, seed_key, kind, domain, present, title, body, evidence,
    source, options, sort, journey_scope, trigger_provenance,
    subject_references, expires_at, context_snapshot
  ) values (
    v_couple,
    'journey:' || c.trigger_key,
    'unresolved',
    'us',
    true,
    c.title,
    'Choose privately. A shared direction appears only if both answers can honestly support one.',
    c.evidence,
    c.source,
    c.options,
    c.rank,
    c.scope,
    c.provenance,
    jsonb_build_array(jsonb_build_object('kind', c.subject_kind, 'id', c.subject_id)),
    v_expiry,
    jsonb_build_object(
      'evidence', jsonb_build_array(c.evidence),
      'frozenAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    )
  )
  on conflict (couple_id, seed_key) do update
  set present = true,
      title = excluded.title,
      body = excluded.body,
      evidence = excluded.evidence,
      source = excluded.source,
      options = excluded.options,
      sort = excluded.sort,
      journey_scope = excluded.journey_scope,
      trigger_provenance = excluded.trigger_provenance,
      subject_references = excluded.subject_references,
      expires_at = excluded.expires_at,
      context_snapshot = excluded.context_snapshot;

  insert into public.insight_consent (
    insight_id, visibility, readiness, accepted_at
  )
  select id, 'mutual', 'accepted', now()
  from public.insights
  where couple_id = v_couple and seed_key = 'journey:' || c.trigger_key
  on conflict (insight_id) do update
  set visibility = 'mutual', readiness = 'accepted', accepted_at = now();
end;
$$;

revoke execute on function public.refresh_shared_journey_question()
  from public, anon;
grant execute on function public.refresh_shared_journey_question()
  to authenticated;

-- Preserve the old symbol for deployed clients, but remove every canned
-- daily/weekly behavior behind it.
create or replace function public.refresh_shared_moments(p_local_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_shared_journey_question();
end;
$$;

-- MARK: Owner actions ------------------------------------------------------

create or replace function public.pass_journey_question(p_insight uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  v_couple := public.assert_my_insight(p_insight);
  if not exists (
    select 1 from public.insights
    where id = p_insight and journey_scope is not null and present
  ) then raise exception 'question is not active'; end if;

  insert into public.journey_passes (insight_id, profile_id)
  values (p_insight, (select auth.uid()))
  on conflict (insight_id, profile_id) do nothing;
end;
$$;
revoke execute on function public.pass_journey_question(uuid)
  from public, anon;
grant execute on function public.pass_journey_question(uuid)
  to authenticated;

-- The UI records only that a journey question was actually presented. This
-- event carries no question, answer, proposal, or profile content.
create or replace function public.record_journey_question_shown(p_insight uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.assert_my_insight(p_insight);
  if exists (
    select 1 from public.insights
    where id = p_insight and journey_scope is not null and present
  ) then
    perform private.record_journey_event(p_insight, 'shown');
  end if;
end;
$$;
revoke execute on function public.record_journey_question_shown(uuid)
  from public, anon;
grant execute on function public.record_journey_question_shown(uuid)
  to authenticated;

create or replace function public.submit_response(
  p_insight uuid,
  p_choice text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.insight_consent;
  v_couple uuid;
  v_submitted integer;
begin
  v_couple := public.assert_my_insight(p_insight);
  select * into c from public.insight_consent
  where insight_id = p_insight for update;

  if c.visibility <> 'mutual' or c.readiness <> 'accepted' then
    raise exception 'question is not open';
  end if;
  if not exists (
    select 1 from public.insights i
    where i.id = p_insight
      and i.present
      and (i.expires_at is null or i.expires_at > now())
      and p_choice = any(i.options)
  ) then raise exception 'answer is not available'; end if;
  if p_note is not null and char_length(p_note) > 1200 then
    raise exception 'private note is too long';
  end if;
  if exists (
    select 1 from public.responses
    where insight_id = p_insight
      and profile_id = (select auth.uid())
      and status = 'submitted'
  ) then raise exception 'already submitted'; end if;

  insert into public.responses (
    insight_id, profile_id, status, choice, note, updated_at
  ) values (
    p_insight, (select auth.uid()), 'submitted', p_choice,
    nullif(btrim(p_note), ''), now()
  )
  on conflict (insight_id, profile_id) do update
  set status = 'submitted', choice = excluded.choice,
      note = excluded.note, updated_at = now();

  insert into public.journey_response_receipts (
    insight_id, profile_id, submitted_at, resolved_at
  ) values (
    p_insight, (select auth.uid()), now(), null
  )
  on conflict (insight_id, profile_id) do update
  set submitted_at = excluded.submitted_at, resolved_at = null;

  delete from public.journey_passes
  where insight_id = p_insight and profile_id = (select auth.uid());
  perform private.record_journey_event(p_insight, 'answered');

  select count(*)::integer into v_submitted
  from public.responses
  where insight_id = p_insight and status = 'submitted';

  if v_submitted >= 2 then
    insert into public.journey_synthesis_jobs (insight_id, couple_id)
    values (p_insight, v_couple)
    on conflict (insight_id) do nothing;
  end if;
end;
$$;

-- No deployed path may fall back to the answer-blind canned direction
-- generator. Historical rows were already backfilled by its original
-- migration; new rows must cross the protected synthesis boundary above.
drop function if exists private.shared_direction_values(uuid);

-- MARK: Protected worker boundary -----------------------------------------

create or replace function public.claim_journey_synthesis_jobs(p_limit integer)
returns table (insight_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with candidates as (
    select j.insight_id
    from public.journey_synthesis_jobs j
    where j.status = 'queued' and j.available_at <= now()
    order by j.created_at
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 10), 25))
  ), claimed as (
    update public.journey_synthesis_jobs j
    set status = 'processing', claimed_at = now(), updated_at = now()
    from candidates c
    where j.insight_id = c.insight_id
    returning j.insight_id
  )
  select claimed.insight_id from claimed;
end;
$$;

create or replace function public.complete_journey_synthesis(
  p_insight uuid,
  p_result jsonb,
  p_version text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.insights;
  v_status text := p_result->>'status';
  v_summary text := btrim(coalesce(p_result->>'summary', ''));
  v_rationale text := btrim(coalesce(p_result->>'rationale', ''));
  v_actions jsonb := coalesce(p_result->'proposed_actions', '[]'::jsonb);
begin
  select * into i from public.insights where id = p_insight for update;
  if i.id is null then raise exception 'unknown insight'; end if;
  if v_status not in ('proposed', 'no_safe_direction') then
    raise exception 'invalid synthesis status';
  end if;
  if jsonb_typeof(v_actions) <> 'array' or jsonb_array_length(v_actions) > 3 then
    raise exception 'invalid action count';
  end if;
  if v_status = 'proposed' and (
    char_length(v_summary) not between 1 and 240
    or char_length(v_rationale) not between 1 and 500
  ) then raise exception 'invalid proposal copy'; end if;
  if exists (
    select 1
    from jsonb_array_elements(v_actions) action
    where coalesce(action->>'kind', '') <> 'lifeItem'
       or nullif(btrim(action->>'id'), '') is null
       or nullif(btrim(action->>'title'), '') is null
       or coalesce(action->>'category', '') !~ '^[a-z]+( [a-z]+)?$'
       or char_length(coalesce(action->>'category', '')) not between 3 and 18
  ) then raise exception 'invalid proposal action'; end if;

  if v_status = 'no_safe_direction' then
    v_summary := 'Let this rest';
    v_rationale := 'The private answers did not support one honest shared direction.';
    v_actions := '[]'::jsonb;
  end if;

  insert into public.shared_directions (
    insight_id, couple_id, direction_key, eyebrow, title, message, symbol,
    summary, rationale, proposed_actions, synthesis_version, expires_at, status
  ) values (
    p_insight, i.couple_id, 'synthesized-v1', 'A DIRECTION TO CHOOSE',
    v_summary, v_rationale, 'circle.circle', v_summary, v_rationale,
    v_actions, left(p_version, 80), i.expires_at, v_status
  )
  on conflict (insight_id) do nothing;

  -- Resolution destroys raw content. Submission timestamps remain available
  -- only in owner-readable, content-free receipts.
  update public.journey_response_receipts
  set resolved_at = coalesce(resolved_at, now())
  where insight_id = p_insight;
  delete from public.responses where insight_id = p_insight;
  delete from public.journey_synthesis_jobs where insight_id = p_insight;
  perform private.record_journey_event(p_insight, 'synthesized');
end;
$$;

create or replace function public.fail_journey_synthesis_job(
  p_insight uuid,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts integer;
begin
  update public.journey_synthesis_jobs
  set attempts = attempts + 1,
      status = 'queued',
      available_at = now() + interval '2 minutes',
      claimed_at = null,
      last_error_code = left(p_error_code, 80),
      updated_at = now()
  where insight_id = p_insight
  returning attempts into v_attempts;

  if v_attempts >= 2 then
    perform public.complete_journey_synthesis(
      p_insight,
      jsonb_build_object(
        'status', 'no_safe_direction',
        'summary', '',
        'rationale', '',
        'proposed_actions', '[]'::jsonb
      ),
      'deterministic-rest-v1'
    );
  end if;
end;
$$;

revoke execute on function public.claim_journey_synthesis_jobs(integer)
  from public, anon, authenticated;
revoke execute on function public.complete_journey_synthesis(uuid,jsonb,text)
  from public, anon, authenticated;
revoke execute on function public.fail_journey_synthesis_job(uuid,text)
  from public, anon, authenticated;
grant execute on function public.claim_journey_synthesis_jobs(integer)
  to service_role;
grant execute on function public.complete_journey_synthesis(uuid,jsonb,text)
  to service_role;
grant execute on function public.fail_journey_synthesis_job(uuid,text)
  to service_role;

-- MARK: Mutual confirmation and activation --------------------------------

create or replace function public.confirm_shared_direction(
  p_insight uuid,
  p_decision text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.shared_directions;
  i public.insights;
  v_accepts integer;
  v_journey uuid;
  v_horizon uuid;
  a jsonb;
  v_category text;
begin
  if p_decision not in ('choose', 'rest') then
    raise exception 'unknown direction decision';
  end if;
  perform public.assert_my_insight(p_insight);
  select * into d from public.shared_directions
    where insight_id = p_insight for update;
  select * into i from public.insights where id = p_insight;
  -- A retried client write after activation is a successful no-op. The two
  -- confirmations and every resulting Life row already exist.
  if d.status = 'active' then return; end if;
  if d.insight_id is null or d.status <> 'proposed'
     or (d.expires_at is not null and d.expires_at <= now()) then
    raise exception 'proposal is not available';
  end if;

  insert into public.direction_confirmations (
    insight_id, profile_id, decision
  ) values (p_insight, (select auth.uid()), p_decision)
  on conflict (insight_id, profile_id) do nothing;
  perform private.record_journey_event(p_insight, 'confirmed');

  select count(*)::integer into v_accepts
  from public.direction_confirmations dc
  join public.couple_members cm
    on cm.profile_id = dc.profile_id and cm.couple_id = d.couple_id
  where dc.insight_id = p_insight and dc.decision = 'choose';
  if v_accepts < 2 then return; end if;

  -- Nothing is displaced here. A journey ends when both people end it, through
  -- `complete_field_journey`; it does not end because another one began.
  insert into public.field_journeys (
    couple_id, insight_id, direction_id, scope, title, summary, rationale,
    evidence, next_move, subject_references
  ) values (
    d.couple_id, p_insight, p_insight, i.journey_scope,
    left(d.title, 120), coalesce(d.summary, d.title),
    coalesce(d.rationale, d.message),
    case
      when jsonb_array_length(coalesce(i.context_snapshot->'evidence', '[]'::jsonb)) > 0
      then array(select jsonb_array_elements_text(i.context_snapshot->'evidence') limit 3)
      else array[i.evidence]
    end,
    d.proposed_actions->0->>'title',
    coalesce(i.subject_references, '[]'::jsonb)
  )
  on conflict (insight_id) do update set insight_id = excluded.insight_id
  returning id into v_journey;

  for a in select value from jsonb_array_elements(d.proposed_actions)
  loop
    if a->>'kind' <> 'lifeItem' then continue; end if;
    v_category := lower(coalesce(a->>'category', 'notes'));
    if v_category = 'calendar'
       or v_category !~ '^[a-z]+( [a-z]+)?$'
       or char_length(v_category) not between 3 and 18 then
      v_category := 'notes';
    end if;
    insert into public.field_life_items (
      couple_id, title, category, owner, due_on, source, detail,
      is_time_critical, is_done, journey_id, journey_action_id
    ) values (
      d.couple_id,
      left(a->>'title', 240),
      v_category,
      'shared',
      case when coalesce(a->>'due_on', '') ~ '^\d{4}-\d{2}-\d{2}$'
          and a->>'due_on' between '1900-01-01' and '2200-12-31'
          and pg_catalog.pg_input_is_valid(a->>'due_on', 'date')
          then (a->>'due_on')::date else null end,
      'inferred',
      nullif(left(a->>'detail', 1000), ''),
      false,
      false,
      v_journey,
      left(a->>'id', 120)
    )
    on conflict (journey_id, journey_action_id)
      where journey_id is not null and journey_action_id is not null
      do nothing;
  end loop;

  insert into public.field_evidence (
    couple_id, statement, owner, journey_id
  )
  select d.couple_id, value, 'shared', v_journey
  from unnest(
    case
      when jsonb_array_length(coalesce(i.context_snapshot->'evidence', '[]'::jsonb)) > 0
      then array(select jsonb_array_elements_text(i.context_snapshot->'evidence') limit 3)
      else array[i.evidence]
    end
  ) value
  on conflict (journey_id, statement)
    where journey_id is not null do nothing;

  if i.journey_scope = 'longTerm' then
    if i.trigger_provenance = 'legacyHorizon'
       and i.subject_references->0->>'kind' = 'horizon' then
      update public.field_horizons
      set owner = 'shared', thesis = coalesce(d.summary, d.title)
      where id = (i.subject_references->0->>'id')::uuid
        and couple_id = d.couple_id
      returning id into v_horizon;
    end if;
    if v_horizon is null then
      insert into public.field_horizons (
        couple_id, title, owner, is_primary, thesis
      ) values (
        d.couple_id,
        d.title,
        'shared',
        not exists (
          select 1 from public.field_horizons
          where couple_id = d.couple_id and is_primary
        ),
        coalesce(d.summary, d.title)
      ) returning id into v_horizon;
    end if;
    update public.field_journeys set horizon_id = v_horizon
    where id = v_journey and horizon_id is null;
    update public.field_evidence set horizon_id = v_horizon
    where journey_id = v_journey and horizon_id is null;
  end if;

  update public.shared_directions set status = 'active'
  where insight_id = p_insight;
  update public.insights set present = false where id = p_insight;
  perform private.record_journey_event(p_insight, 'activated');
end;
$$;

revoke execute on function public.confirm_shared_direction(uuid,text)
  from public, anon;
grant execute on function public.confirm_shared_direction(uuid,text)
  to authenticated;

-- MARK: Ending a journey ----------------------------------------------------

-- A shared space closes the same way it opened: both people, neither able to
-- see the other's decision first. One person deciding alone would make ending
-- an undertaking easier than starting one, and the asymmetry would be felt.
create table if not exists public.journey_completions (
  journey_id uuid not null
    references public.field_journeys(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  decided_at timestamptz not null default now(),
  primary key (journey_id, profile_id)
);

alter table public.journey_completions enable row level security;
drop policy if exists journey_completions_select_own on public.journey_completions;
create policy journey_completions_select_own
  on public.journey_completions for select to authenticated
  using (profile_id = (select auth.uid()));
grant select on public.journey_completions to authenticated;

create or replace function public.complete_field_journey(p_journey uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.field_journeys;
  v_agreed integer;
begin
  select * into j from public.field_journeys
    where id = p_journey for update;
  if j.id is null or j.couple_id <> (select public.my_couple_id()) then
    raise exception 'journey is not available';
  end if;
  -- A retried write after completion is a successful no-op, exactly as
  -- `confirm_shared_direction` treats a retried activation.
  if j.status = 'completed' then return; end if;

  insert into public.journey_completions (journey_id, profile_id)
  values (p_journey, (select auth.uid()))
  on conflict (journey_id, profile_id) do nothing;

  select count(*)::integer into v_agreed
  from public.journey_completions jc
  join public.couple_members cm
    on cm.profile_id = jc.profile_id and cm.couple_id = j.couple_id
  where jc.journey_id = p_journey;
  if v_agreed < 2 then return; end if;

  update public.field_journeys
  set status = 'completed', completed_at = now()
  where id = p_journey;
  perform private.record_journey_event(j.insight_id, 'completed');
end;
$$;

revoke execute on function public.complete_field_journey(uuid) from public, anon;
grant execute on function public.complete_field_journey(uuid) to authenticated;

-- Expiry and lost-worker recovery. The Edge Function itself should be invoked
-- every minute by Supabase's function scheduler; this SQL sweep makes that
-- invocation idempotent after an outage.
create or replace function private.shared_journey_sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  update public.journey_synthesis_jobs
  set status = 'queued', claimed_at = null, available_at = now(), updated_at = now()
  where status = 'processing' and claimed_at < now() - interval '5 minutes';

  for r in select id from public.insights
    where journey_scope is not null and present and expires_at <= now()
  loop
    update public.insights set present = false where id = r.id;
    update public.journey_response_receipts
      set resolved_at = coalesce(resolved_at, now())
      where insight_id = r.id;
    delete from public.responses where insight_id = r.id;
    delete from public.journey_synthesis_jobs where insight_id = r.id;
    delete from public.shared_directions
      where insight_id = r.id and status <> 'active';
    perform private.record_journey_event(r.id, 'expired');
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema extensions;
    perform cron.unschedule(jobid)
    from cron.job where jobname = 'we-shared-journey-sweep';
    perform cron.schedule(
      'we-shared-journey-sweep',
      '*/5 * * * *',
      'select private.shared_journey_sweep()'
    );
  end if;
exception when others then
  raise notice 'pg_cron unavailable; private.shared_journey_sweep() must be scheduled externally';
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'shared_directions',
    'direction_confirmations',
    'journey_passes',
    'field_journeys'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end;
$$;

commit;
