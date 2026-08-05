-- The circle — mutual readiness, and the room it opens.
--
-- One person taps the intelligence mark. Nothing happens that anyone can see.
-- Their partner, independently, on their own device, on their own day, taps
-- theirs. Both screens bloom into one jointly visible prompt, they talk to
-- each other, and the room closes without residue.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--
-- WE does not collect two answers, compare them, or announce a match.
-- `20260729193000_private_answers_shared_directions.sql:130-133` establishes
-- the invariant this file inherits: a shared result may vary only with public
-- context, never with answer content or answer equality, because "you matched"
-- plus your own answer discloses your partner's. The room honours it by having
-- nothing to compare — one prompt, no answers, no storage.
--
-- WHY THERE ARE TWO TABLES
--
-- The first tap has to be invisible. Not "unshown by the client" — invisible,
-- so `field_readiness` is readable only by the person who wrote the row, and
-- nobody can read their partner's. That is what makes the design's central
-- promise ("there is no waiting state") true at the database rather than as a
-- rendering decision.
--
-- But realtime `postgres_changes` evaluates RLS per subscriber, so a partner's
-- insert into a table they alone can read will never be delivered to the other
-- device. Publishing `field_readiness` and waiting for the bloom would wait
-- forever.
--
-- So the bloom is *materialised*, exactly as `submit_response` materialises
-- `shared_directions` when the second response lands. `field_readiness_bloom`
-- is couple-visible and comes into existence only on the second mark — which
-- means its visibility discloses precisely "both of us are open today", and
-- nothing else. There is no row to see while only one person has tapped.
--
-- WHAT IS NOT HERE, ON PURPOSE
--
-- No transcript, no capture, no analytics on the content, no score, no
-- "partner marked" state anywhere in any response shape. Tapping means "I'm
-- open to meeting you", never "I consent to discuss the hardest thing between
-- us." Nothing in this file records that the room was opened, closed, or how
-- long it stayed open.
--
-- Reconciliation-safe: every statement is idempotent.

begin;

-- MARK: The private mark ----------------------------------------------------

-- One row per person per local day. `local_date` is the *client's* day, not
-- the server's: two people in different timezones each tap on their own day,
-- and forcing both onto UTC would make the circle unreachable for one of them
-- for part of every evening.
create table if not exists public.field_readiness (
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  local_date date not null,
  marked_at timestamptz not null default now(),
  primary key (couple_id, profile_id, local_date)
);

alter table public.field_readiness enable row level security;

-- Own rows only, in both directions. There is deliberately no policy that
-- would let a couple member read their partner's row: that absence is the
-- feature, and any future "just for the indicator" policy added here defeats
-- the entire design.
--
-- Multi-device is why select exists at all — the same person on a second
-- device must see that they already marked today, or the mark is not
-- idempotent from their point of view.
drop policy if exists field_readiness_select_own on public.field_readiness;
create policy field_readiness_select_own on public.field_readiness
  for select using (
    profile_id = (select auth.uid())
    and couple_id = (select public.my_couple_id())
  );

-- Writes go through `field_readiness_mark` rather than a direct insert, but
-- the policy is scoped anyway: a security definer function is not an excuse
-- for a table that would accept a row on somebody else's behalf.
drop policy if exists field_readiness_insert_own on public.field_readiness;
create policy field_readiness_insert_own on public.field_readiness
  for insert with check (
    profile_id = (select auth.uid())
    and couple_id = (select public.my_couple_id())
  );

-- MARK: The bloom -----------------------------------------------------------

-- Materialised on the second mark, and couple-visible. The prompt is stored
-- rather than recomputed so both devices render identical words even if they
-- read the row a day apart or the prompt list later changes.
create table if not exists public.field_readiness_bloom (
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  local_date date not null,
  prompt text not null,
  bloomed_at timestamptz not null default now(),
  primary key (couple_id, local_date)
);

alter table public.field_readiness_bloom enable row level security;

drop policy if exists field_readiness_bloom_select on public.field_readiness_bloom;
create policy field_readiness_bloom_select on public.field_readiness_bloom
  for select using (couple_id = (select public.my_couple_id()));

-- No insert, update, or delete policy. The only writer is
-- `field_readiness_mark` below, which runs as definer — a client that could
-- insert here could manufacture a bloom their partner never consented to.

-- MARK: The words -----------------------------------------------------------

-- Warm and generative only, per the design. There is no prompt here about a
-- disagreement, a grievance, or anything either person would need to brace
-- for: consenting to meet is not consenting to a hard conversation.
--
-- Deterministic in the couple and the day, so a couple does not get the same
-- words two evenings running, and so the choice never depends on anything
-- either person wrote.
create or replace function private.field_readiness_prompt(
  p_couple uuid,
  p_local_date date
)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array[
    'What would make tonight feel a little more like yours?',
    'What would feel kind tonight?',
    'What could make this week lighter?',
    'What would you love to have ahead of you?',
    'Is there something small worth making room for?'
  ])[
    (abs(hashtext(p_couple::text || ':' || p_local_date::text)) % 5) + 1
  ];
$$;

revoke all on function private.field_readiness_prompt(uuid, date)
  from public, anon, authenticated;

-- MARK: Marking -------------------------------------------------------------

-- Returns the caller's resulting state, so the tap does not need a second
-- round trip to know whether it bloomed.
--
-- Note what it cannot return: there is no value meaning "your partner has
-- marked and you have not", because the caller has just marked. The only two
-- answers are `you` and `both`.
--
-- Idempotent. Tapping twice in one day inserts nothing the second time, blooms
-- nothing a second time, and records nothing about the repeat — an
-- uninstructed person re-tapping must not become covert pressure, and a
-- counter would be exactly that.
create or replace function public.field_readiness_mark(p_local_date date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_marked integer;
  v_prompt text;
begin
  v_couple := (select public.my_couple_id());
  if v_couple is null then
    raise exception 'not in a couple';
  end if;

  -- The client's day, bounded by the server's. A day either side covers every
  -- real timezone offset and a hand-set clock within reason; beyond that this
  -- would be a way to pre-mark an arbitrary future, which is not a thing
  -- "I'm open today" can mean.
  if p_local_date < current_date - 1 or p_local_date > current_date + 1 then
    raise exception 'readiness is about today';
  end if;

  insert into public.field_readiness (couple_id, profile_id, local_date)
  values (v_couple, (select auth.uid()), p_local_date)
  on conflict (couple_id, profile_id, local_date) do nothing;

  select count(*)::integer
  into v_marked
  from public.field_readiness r
  where r.couple_id = v_couple
    and r.local_date = p_local_date;

  if v_marked >= 2 then
    v_prompt := private.field_readiness_prompt(v_couple, p_local_date);
    insert into public.field_readiness_bloom (couple_id, local_date, prompt)
    values (v_couple, p_local_date, v_prompt)
    on conflict (couple_id, local_date) do nothing;
    return 'both';
  end if;

  return 'you';
end;
$$;

grant execute on function public.field_readiness_mark(date) to authenticated;

-- MARK: Reading -------------------------------------------------------------

-- The reveal is an RPC and not a select, because a select over
-- `field_readiness` would have to be shaped so that "no rows" and "my
-- partner's row, hidden" are the same answer — and the moment somebody adds
-- a count or a policy for a benign-looking reason, they are not.
--
-- Three values, and there is no fourth. `partner` would recreate the waiting
-- indicator this design forbids: knowing your partner is open while you have
-- not answered turns an invitation into a request.
create or replace function public.field_readiness_state(p_local_date date)
returns table (state text, prompt text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_mine boolean;
  v_prompt text;
begin
  v_couple := (select public.my_couple_id());
  if v_couple is null then
    -- Not a failure. Somebody who is not paired has no circle, and saying so
    -- is the same shape as saying nobody has marked.
    return query select 'neither'::text, null::text;
    return;
  end if;

  select b.prompt
  into v_prompt
  from public.field_readiness_bloom b
  where b.couple_id = v_couple
    and b.local_date = p_local_date;

  if v_prompt is not null then
    return query select 'both'::text, v_prompt;
    return;
  end if;

  select exists (
    select 1
    from public.field_readiness r
    where r.couple_id = v_couple
      and r.profile_id = (select auth.uid())
      and r.local_date = p_local_date
  )
  into v_mine;

  -- Both remaining branches read only the caller's own row. A partner who has
  -- marked alone is indistinguishable from a partner who has not, which is the
  -- single property this whole file exists to guarantee.
  return query select
    case when v_mine then 'you' else 'neither' end::text,
    null::text;
end;
$$;

grant execute on function public.field_readiness_state(date) to authenticated;

-- MARK: Realtime ------------------------------------------------------------

-- `field_readiness_bloom` is the one that matters: it is how the second tap
-- reaches the first person's screen without a foreground. `field_readiness`
-- is published too, and only for multi-device — RLS means it delivers a
-- person their own mark on their other device, never their partner's.
--
-- Both are needed. Several existing tables sit in `observedTables` without
-- being published and therefore never fire; do not add a third.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_readiness',
    'field_readiness_bloom'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', v_table
      );
    end if;
  end loop;
end;
$$;

commit;
