-- ○ Yours — the personal space. Schema, and the one door that deletes.
--
-- See `CIRCLE.md`. The thesis is that nothing becomes history by accident: an
-- entry has a natural life, returns once to ask whether it should continue,
-- and is deleted if the answer is silence. Continued storage is an act of
-- consent, not a side effect of having once typed something.
--
-- WHY THIS IS NOT A FIELD TABLE
--
-- Every `field_*` table is couple-scoped — `couple_id = public.my_couple_id()`
-- is the entire read grant, and `20260803180000_field_solo_visibility.sql`
-- added a per-author exception on top of it. Yours does not belong in that
-- shape, for four separate reasons, any one of which would be enough:
--
--   1. CIRCLE.md §10 forbids a partner-accessible event for creation,
--      renewal, expiry or deletion — "not a row, not a timestamp, not a
--      changed `updated_at` on any shared object". The app subscribes to a
--      realtime channel keyed `field:<coupleID>`, so a couple-scoped table
--      announces every one of those to the other person by existing.
--   2. Yours works before pairing and after a relationship ends. It is owned
--      by a person, not by a couple. `private_proposals` is the precedent.
--   3. The client caches `FieldState` to disk. Entry text does not go there.
--   4. §10: raw text never reaches the shared intelligence layer, and that
--      layer reads `FieldState`.
--
-- So: owner-scoped tables, `owner_id = auth.uid()`, no realtime publication,
-- and no foreign key to `couples` anywhere in this file.
--
-- WHAT THE CONSTRAINTS ARE FOR
--
-- Four of the nine locked decisions are enforced by the schema rather than by
-- the client, because they are the ones a well-meaning change would quietly
-- break:
--
--   #5  a decision window cannot exist without a presentation — the grace
--       period starts when the entry is shown, never before
--   #6  the outer bound always tracks `ready_at`
--   #8  one snooze, once
--   #4  six weeks then twelve, and no third living interval
--
-- WHAT IS NOT HERE YET
--
-- §14's key service. `private.yours_destroy()` below is the single seam it
-- will land in. Until then this is ordinary row deletion, and the product must
-- say "unrecoverable within 24 hours" rather than claiming the row is gone the
-- instant it is asked to be. A promise the infrastructure cannot demonstrate
-- is the footnote that would destroy this concept.

begin;

-- MARK: How long a life is --------------------------------------------------
--
-- One function, so §3's "any future change is one account-level setting,
-- never per-entry scheduling" stays true. There is deliberately no per-entry
-- duration column: a duration control makes someone plan document retention
-- at the exact moment they are trying to put down a thought.
--
-- Two stages and no more. At the second return the entry is offered
-- permanence, so there is no third living interval to name — which is why
-- `renewal_count` is constrained to 0 or 1 below rather than left open.

create or replace function private.yours_interval(p_renewal_count int)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case p_renewal_count
    when 0 then interval '6 weeks'
    when 1 then interval '12 weeks'
  end;
$$;

revoke all on function private.yours_interval(int)
  from public, anon, authenticated;

-- MARK: The entries ---------------------------------------------------------

create table public.yours_entries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null
    references public.profiles(id) on delete cascade,

  -- The id the client made offline, so a retried save is the same entry
  -- rather than a second copy of somebody's private writing. Frozen on
  -- update, like `field_*.client_id` in `20260803120000`.
  client_id uuid not null,

  body text not null
    check (char_length(body) between 1 and 20000),

  state text not null default 'living'
    check (state in ('living', 'ready', 'presented', 'held')),

  -- 0 in first life, 1 in first renewal. Never exposed to the partner, never
  -- shown to the owner as a number, never fed to ranking or suggestion — see
  -- §3, which is emphatic about this. It exists to decide which of two
  -- questions to ask, and for nothing else.
  renewal_count int not null default 0
    check (renewal_count between 0 and 1),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- When it becomes presentable. Computed by the trigger below, never sent by
  -- a client.
  ready_at timestamptz not null,

  -- The outer bound: one year after `ready_at`, for an entry that is never
  -- reached. §5 is explicit that this follows the entry's state and not the
  -- person's behaviour — it is not one year of inactivity, and it must never
  -- be described that way. A space-level dormancy rule was rejected because it
  -- would make visiting the space feel like maintenance.
  unseen_delete_at timestamptz not null,

  -- Null until the entry has actually been shown. Locked #5 lives in the two
  -- checks at the bottom of this table.
  presented_at timestamptz,
  decide_by timestamptz,

  -- Locked #8. Set once; the trigger refuses a second value.
  snoozed_at timestamptz,

  held_at timestamptz,

  unique (owner_id, client_id),

  -- Locked #5, as a constraint rather than a convention: silence can only mean
  -- release after the question was presented.
  constraint yours_entries_window_needs_presentation
    check (decide_by is null or presented_at is not null),
  constraint yours_entries_presented_is_complete
    check (
      state <> 'presented'
      or (presented_at is not null and decide_by is not null)
    ),
  constraint yours_entries_held_is_dated
    check (state <> 'held' or held_at is not null)
);

-- Deliberately not a check constraint.
--
-- `unseen_delete_at = ready_at + interval '1 year'` is the invariant, and it
-- is the first thing anybody would reach for. Postgres rejects it: adding a
-- year to a timestamptz depends on the session timezone, so the operator is
-- STABLE and a check constraint needs IMMUTABLE. The trigger below recomputes
-- the column on every insert and every update instead, which makes the
-- invariant hold by construction rather than by assertion, and the pgTAP
-- suite checks it directly.

create index yours_entries_queue_idx
  on public.yours_entries(owner_id, state, ready_at);

create index yours_entries_outer_bound_idx
  on public.yours_entries(unseen_delete_at)
  where state <> 'held';

comment on table public.yours_entries is
  'Personal entries with a natural life. Owner-scoped, never couple-scoped, '
  'never published to realtime. See CIRCLE.md.';

-- MARK: What the server decides, not the client -----------------------------
--
-- §11: the server holds authoritative state. Everything computed here is
-- something a client must not be able to assert — a lifetime it granted
-- itself, a second snooze, an author it is not.

-- The lifecycle columns are not the client's to write.
--
-- A plain `update yours_entries set ready_at = ...` from an authenticated
-- client would buy an entry an unbounded life, which is the entire mechanism
-- defeated by one PATCH. So the trigger recognises two kinds of update:
--
--   an edit          the person changed the words; §3 applies
--   a lifecycle move an RPC in the next migration, which announces itself
--
-- The announcement is a session setting, the same device
-- `private.field_stamp_visibility()` uses for `we.crossing_solo_history`.
-- A client cannot set it: `set_config` inside a request runs in the request's
-- transaction, and the RPCs that set it are `security definer` functions whose
-- bodies the client does not choose.

create or replace function private.yours_stamp_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lifecycle boolean :=
    nullif(current_setting('we.yours_lifecycle', true), '') = 'on';
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

create trigger yours_entries_stamp
  before insert or update on public.yours_entries
  for each row execute function private.yours_stamp_entry();

-- MARK: The one door that deletes -------------------------------------------
--
-- §10, and the reason this function exists on its own rather than as five
-- inline `delete` statements: the claim "it is gone" has to survive a
-- skeptical reading, and it can only be made true in one place.
--
-- Today this removes rows. When §14 closes it will, in order: destroy the
-- entry's data key in a service outside Supabase's backup domain, verify the
-- destruction, and only then remove the ciphertext. That ordering is the whole
-- design — Vault keeps its root key in Supabase's backend precisely so a
-- restore can bring data back, which is excellent disaster recovery and the
-- exact opposite of what this needs.
--
-- The invariant the pgTAP suite asserts: nothing else in this schema deletes a
-- `yours_entries` row.

create or replace function private.yours_destroy(p_entry_ids uuid[])
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destroyed int;
begin
  if p_entry_ids is null or cardinality(p_entry_ids) = 0 then
    return 0;
  end if;

  -- The §14 seam. Key destruction and its verification go here, before the
  -- ciphertext is touched, and a failure must raise rather than fall through
  -- to the delete — a row removed while its key survives is the one outcome
  -- this design cannot tolerate.

  delete from public.yours_entries e
  where e.id = any(p_entry_ids);

  get diagnostics v_destroyed = row_count;
  return v_destroyed;
end;
$$;

revoke all on function private.yours_destroy(uuid[])
  from public, anon, authenticated;

-- MARK: What belongs to the person, not the device --------------------------
--
-- Three things that would be wrong in `@AppStorage`:
--
--   The teaching moment. §2 allows the word "Yours" to appear exactly twice in
--   a person's lifetime — once during the Promise, once on first entry — and
--   then never again. `@AppStorage` is per device, so a second phone would
--   teach it a third and fourth time. "Lifetime" is a property of the person.
--
--   `last_opened_at`, which drives the 90-day dormancy sweep. It lives here
--   rather than on `profiles` because `profiles` is partner-readable and when
--   somebody last opened this space is not the partner's business.
--
--   The visit, which is what makes the presentation gate hold across devices.

create table public.yours_owner_state (
  owner_id uuid primary key
    references public.profiles(id) on delete cascade,

  taught_in_promise boolean not null default false,
  taught_on_first_entry boolean not null default false,

  last_opened_at timestamptz not null default now(),

  -- The current foreground session, and the session in which something was
  -- last resolved. Together these are §5's "the next entry appears on the
  -- owner's next visit, not immediately".
  last_visit uuid,
  last_resolution_visit uuid,

  created_at timestamptz not null default now()
);

-- MARK: Prepared offers -----------------------------------------------------
--
-- §6. "Prepare" creates a separate, frozen artifact with exact wording the
-- person approves. It is not a pointer to the entry and does not carry the
-- entry's text — which is why `source_entry_id` is `on delete set null` and
-- why there is no body column. The partner never sees the source entry, the
-- renewal count, the dates, or the fact that anything matured.
--
-- Its own, shorter life: two weeks, one return, send or let go. No third
-- option and no permanence. Without that this design rebuilds the pile one
-- room over with heavier objects, because an addressed unsent thing weighs
-- more than a private note.

create table public.yours_prepared_offers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null
    references public.profiles(id) on delete cascade,
  client_id uuid not null,

  -- Nullable and set-null on delete: the source entry reaching the end of its
  -- own life must not drag the offer with it, and the offer must not be a
  -- route back to words that were let go.
  source_entry_id uuid
    references public.yours_entries(id) on delete set null,

  title text not null
    check (char_length(title) between 1 and 120),
  question text not null
    check (char_length(question) between 1 and 180),
  options text[] not null
    check (
      cardinality(options) between 2 and 5
      and array_position(options, null) is null
    ),

  prepared_at timestamptz not null default now(),
  ready_at timestamptz not null,
  presented_at timestamptz,
  decide_by timestamptz,
  sent_at timestamptz,

  unique (owner_id, client_id),

  constraint yours_offers_window_needs_presentation
    check (decide_by is null or presented_at is not null)
);

create index yours_prepared_offers_queue_idx
  on public.yours_prepared_offers(owner_id, ready_at)
  where sent_at is null;

create or replace function private.yours_stamp_offer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.owner_id := coalesce(new.owner_id, (select auth.uid()));
    new.prepared_at := now();
    new.ready_at := now() + interval '2 weeks';
    new.presented_at := null;
    new.decide_by := null;
    new.sent_at := null;
  else
    new.id := old.id;
    new.owner_id := old.owner_id;
    new.client_id := old.client_id;
    new.prepared_at := old.prepared_at;
    -- The wording is what the person approved. Frozen, or "the exact wording
    -- the person approves" is not a promise.
    new.title := old.title;
    new.question := old.question;
    new.options := old.options;
  end if;
  return new;
end;
$$;

revoke all on function private.yours_stamp_offer()
  from public, anon, authenticated;

create trigger yours_prepared_offers_stamp
  before insert or update on public.yours_prepared_offers
  for each row execute function private.yours_stamp_offer();

-- MARK: Why somebody let something go ---------------------------------------
--
-- §13's sharpest measure, and the one this table exists to keep honest.
--
-- A prepared offer is already partner-directed, so releasing one is
-- avoidance-shaped — "I wasn't serious about that apartment anyway" — and will
-- read as relief for reasons that have nothing to do with the thesis. Free
-- writing about oneself is a different emotional object, and releasing that is
-- the only result that means anything. Hence `object_kind`, which must appear
-- in the group-by of every report ever run against this table: a single pooled
-- release rate would let proposal volume drown the signal and still look
-- healthy.
--
-- Four reasons, split along the line that matters:
--
--   resolved, neverMattered   relief from indecision
--   noLongerTrue, notReady    the personal register
--
-- A closed set, never free text, because §10 forbids raw text reaching
-- analytics. Optional and one tap — declining writes no row. Letting go must
-- never become a form.

create table public.yours_releases (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null
    references public.profiles(id) on delete cascade,

  object_kind text not null
    check (object_kind in ('entry', 'prepared_offer')),

  reason text not null
    check (
      reason in ('resolved', 'noLongerTrue', 'neverMattered', 'notReady')
    ),

  -- Kept for analysis and readable by nobody through the API — see the grants
  -- below. §3 forbids exposing renewal count to the partner or to the owner as
  -- a number, and this column is exactly that number.
  renewal_count_at_release int not null,

  released_at timestamptz not null default now()

  -- Deliberately no foreign key to the released row, and deliberately no
  -- title. This table can never resurrect content, and `yours_destroy` never
  -- touches it.
);

create index yours_releases_analysis_idx
  on public.yours_releases(object_kind, released_at);

-- MARK: Row level security --------------------------------------------------
--
-- `owner_id = auth.uid()`, and nothing else. There is no couple in this
-- predicate and there must never be one.

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'yours_entries',
    'yours_owner_state',
    'yours_prepared_offers'
  ]
  loop
    execute format(
      'alter table public.%I enable row level security', v_table
    );
    execute format(
      'create policy %I on public.%I for select
         using (owner_id = (select auth.uid()))',
      v_table || '_select', v_table
    );
    execute format(
      'create policy %I on public.%I for insert
         with check (owner_id = (select auth.uid()))',
      v_table || '_insert', v_table
    );
    execute format(
      'create policy %I on public.%I for update
         using (owner_id = (select auth.uid()))
         with check (owner_id = (select auth.uid()))',
      v_table || '_update', v_table
    );
  end loop;
end;
$$;

-- No delete policy, on any of them, deliberately.
--
-- "Let go" is not a DELETE from the client. It is `public.yours_let_go`, which
-- routes to `private.yours_destroy` — the one place that will destroy a key
-- before it removes ciphertext once §14 closes. A delete policy here would be
-- a second door around that seam, and the promise is only as good as the
-- number of ways out of the table. RLS denies what no policy permits, so this
-- is enforced by omission and asserted in the pgTAP suite.

-- Write-only, through the RPC in the next migration. RLS on with no policy at
-- all means no client reaches this table by any path, including its owner —
-- which is the point, since the row carries a renewal count that §3 says the
-- owner must never be shown. The tradeoff is deliberate and stated in
-- CIRCLE.md: this is measurement, not the person's record of themselves.
alter table public.yours_releases enable row level security;
revoke all on table public.yours_releases from anon, authenticated;

commit;
