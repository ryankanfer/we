-- Field zones: the handoff's persisted domain.
--
-- Adds the tables behind LIFE / WE / US as specified in
-- design_handoff_we_app/README.md → "State management". Everything here is
-- couple-scoped and gated by public.my_couple_id(), matching the existing
-- schema's convention.
--
-- Two structural rules are enforced in SQL rather than left to the client,
-- because they are product constraints rather than preferences:
--
--   1. No table stores a score, streak, completion percentage, or any value
--      that compares the two partners. `rhythms.health` is a two-value enum
--      for exactly this reason, and `occurrences` exists only so a closed
--      season can say "63 Thursdays" in prose.
--   2. Exactly one horizon per couple may be primary. A partial unique index
--      makes a second one impossible.
--
-- Reconciliation-safe: every statement is idempotent.

-- MARK: Identity ------------------------------------------------------------

-- The two chosen swatches. Onboarding (6f) writes these, and every
-- person-coloured element in the app derives from them, so they are stored
-- rather than hard-coded.
create table if not exists public.field_identity (
  couple_id uuid primary key
    references public.couples(id) on delete cascade,
  swatch_a text not null default 'clay'
    check (swatch_a in ('clay', 'rust', 'amber', 'rose')),
  swatch_b text not null default 'slate'
    check (swatch_b in ('slate', 'teal', 'indigo', 'sage')),
  updated_at timestamptz not null default now()
);

-- Reachability windows. Presence (6b) reads these; nothing measures who is
-- more present.
create table if not exists public.field_away_windows (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null,
  place text,
  created_at timestamptz not null default now(),
  constraint field_away_window_ordered check (ends_at > starts_at)
);
create index if not exists field_away_windows_couple_idx
  on public.field_away_windows(couple_id, starts_at desc);

-- MARK: Life ----------------------------------------------------------------

-- Occasion-based groupings. Every cluster carries its own generated
-- rationale — that sentence is the feature, so it is not nullable.
create table if not exists public.field_clusters (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null,
  rationale text not null,
  tint text not null default 'shared' check (tint in ('a', 'b', 'shared')),
  timeframe text not null,
  anchor_date date,
  created_at timestamptz not null default now()
);
create index if not exists field_clusters_couple_idx
  on public.field_clusters(couple_id, anchor_date);

create table if not exists public.field_life_items (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null,
  category text not null
    check (category in ('food', 'care', 'calendar', 'money', 'home')),
  owner text not null default 'shared' check (owner in ('a', 'b', 'shared')),
  due_on date,
  closes_at timestamptz,
  cluster_id uuid references public.field_clusters(id) on delete set null,
  source text not null default 'captured'
    check (source in ('captured', 'inferred', 'imported')),
  detail text,
  is_time_critical boolean not null default false,
  is_done boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists field_life_items_couple_open_idx
  on public.field_life_items(couple_id, due_on)
  where is_done = false;
create index if not exists field_life_items_cluster_idx
  on public.field_life_items(cluster_id);

-- MARK: Ours ----------------------------------------------------------------

-- Appetite, not to-dos. Note the absence of a due date, a status, and a
-- completed_at — their absence is the design.
create table if not exists public.field_ours_items (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null,
  list text not null
    check (list in ('watchlist', 'eating', 'places', 'someday')),
  added_by uuid references public.profiles(id) on delete set null,
  added_at timestamptz not null default now(),
  -- Set by the trigger below when both partners add the same thing
  -- independently. The highest-value inference in the app.
  both_added boolean not null default false,
  coincidence_note text,
  horizon_id uuid,
  -- A standing negative preference is a first-class entry.
  is_standing_note boolean not null default false
);
create index if not exists field_ours_items_couple_list_idx
  on public.field_ours_items(couple_id, list, added_at desc);
create index if not exists field_ours_items_horizon_idx
  on public.field_ours_items(horizon_id);

-- MARK: Us ------------------------------------------------------------------

create table if not exists public.field_horizons (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null,
  window_label text,
  owner text not null default 'shared' check (owner in ('a', 'b', 'shared')),
  is_primary boolean not null default false,
  thesis text,
  target_date date,
  created_at timestamptz not null default now()
);

-- Us leads with exactly one horizon. A second primary is not a UI bug to
-- guard against — it is impossible.
create unique index if not exists field_horizons_one_primary_idx
  on public.field_horizons(couple_id)
  where is_primary = true;

alter table public.field_ours_items
  drop constraint if exists field_ours_items_horizon_id_fkey;
alter table public.field_ours_items
  add constraint field_ours_items_horizon_id_fkey
  foreign key (horizon_id)
  references public.field_horizons(id) on delete set null;

-- Us asks at most one question at a time, so a horizon has at most one open
-- question.
create table if not exists public.field_questions (
  id uuid primary key default gen_random_uuid(),
  horizon_id uuid not null unique
    references public.field_horizons(id) on delete cascade,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  prompt text not null,
  stakes text not null,
  -- Always present. A question without a reason is not shippable.
  reasoning text not null,
  choice_a text not null,
  choice_b text not null,
  answered_choice text,
  answered_at timestamptz,
  created_at timestamptz not null default now()
);

-- Streak-free by construction: health is a two-value signal.
create table if not exists public.field_rhythms (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null,
  cadence text not null,
  health text not null default 'running'
    check (health in ('running', 'slipping')),
  horizon_id uuid references public.field_horizons(id) on delete set null,
  occurrences integer not null default 0,
  last_occurred_at timestamptz
);

-- Plain sentences about real events. Never a percentage, never a chart.
create table if not exists public.field_evidence (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  statement text not null,
  owner text not null default 'shared' check (owner in ('a', 'b', 'shared')),
  horizon_id uuid references public.field_horizons(id) on delete set null,
  occurred_at timestamptz not null default now()
);
create index if not exists field_evidence_horizon_idx
  on public.field_evidence(horizon_id, occurred_at desc);

-- MARK: Deferral and rules --------------------------------------------------

create table if not exists public.field_held_topics (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null,
  timing text not null,
  reason text not null,
  surface_on date,
  was_overridden boolean not null default false,
  was_dismissed boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists field_held_topics_couple_idx
  on public.field_held_topics(couple_id, surface_on);

-- User-authored constraints on the intelligence's behaviour. A real data
-- type, not a setting.
create table if not exists public.field_standing_rules (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  text text not null,
  set_by uuid references public.profiles(id) on delete set null,
  set_at timestamptz not null default now(),
  retired_at timestamptz
);

-- MARK: Capture and corrections ---------------------------------------------

create table if not exists public.field_captures (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  text text not null,
  spoken_by uuid references public.profiles(id) on delete set null,
  captured_at timestamptz not null default now(),
  destination text not null,
  reasoning text not null
);
create index if not exists field_captures_couple_idx
  on public.field_captures(couple_id, captured_at desc);

-- Every correction is training signal that surfaces later in 6a.
create table if not exists public.field_corrections (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  input text not null,
  original_destination text not null,
  corrected_destination text not null,
  corrected_by uuid references public.profiles(id) on delete set null,
  corrected_at timestamptz not null default now()
);
create index if not exists field_corrections_couple_idx
  on public.field_corrections(couple_id, corrected_at desc);

-- MARK: The daily moment ----------------------------------------------------

-- One row per couple. One push per day, at a learned hour.
create table if not exists public.field_daily_moment (
  couple_id uuid primary key
    references public.couples(id) on delete cascade,
  send_minute integer not null default 492
    check (send_minute between 0 and 1439),
  hour_rationale text not null default
    'It''s when you both actually reply.',
  reply_rate_before numeric(4, 3) not null default 0,
  reply_rate_after numeric(4, 3) not null default 0,
  last_sent_on date,
  updated_at timestamptz not null default now()
);

-- MARK: Cross-partner coincidence -------------------------------------------

-- When both partners add the same thing independently, mark it. Neither of
-- them knew, and surfacing it is the app's single most persuasive inference.
create or replace function private.field_mark_coincidence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.field_ours_items%rowtype;
begin
  select * into v_existing
  from public.field_ours_items
  where couple_id = new.couple_id
    and id <> new.id
    and added_by is distinct from new.added_by
    and lower(title) = lower(new.title)
  limit 1;

  if found then
    new.both_added := true;
    new.coincidence_note := 'Both added it, '
      || case
           when abs(extract(day from (new.added_at - v_existing.added_at))) < 1
             then 'the same day'
           when abs(extract(day from (new.added_at - v_existing.added_at))) < 14
             then 'a week apart'
           else 'months apart'
         end;

    update public.field_ours_items
    set both_added = true,
        coincidence_note = new.coincidence_note
    where id = v_existing.id;
  end if;

  return new;
end;
$$;

drop trigger if exists field_ours_items_coincidence
  on public.field_ours_items;
create trigger field_ours_items_coincidence
  before insert on public.field_ours_items
  for each row execute function private.field_mark_coincidence();

-- MARK: Row level security --------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_identity',
    'field_away_windows',
    'field_clusters',
    'field_life_items',
    'field_ours_items',
    'field_horizons',
    'field_questions',
    'field_rhythms',
    'field_evidence',
    'field_held_topics',
    'field_standing_rules',
    'field_captures',
    'field_corrections',
    'field_daily_moment'
  ]
  loop
    execute format(
      'alter table public.%I enable row level security', v_table
    );

    execute format(
      'drop policy if exists %I on public.%I',
      v_table || '_select', v_table
    );
    execute format(
      'create policy %I on public.%I for select
         using (couple_id = public.my_couple_id())',
      v_table || '_select', v_table
    );

    execute format(
      'drop policy if exists %I on public.%I',
      v_table || '_write', v_table
    );
    execute format(
      'create policy %I on public.%I for all
         using (couple_id = public.my_couple_id())
         with check (couple_id = public.my_couple_id())',
      v_table || '_write', v_table
    );
  end loop;
end;
$$;

-- MARK: Realtime ------------------------------------------------------------

-- The zones need to see the other partner's captures and corrections land
-- without a refresh.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_life_items',
    'field_ours_items',
    'field_horizons',
    'field_questions',
    'field_evidence',
    'field_held_topics',
    'field_captures'
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
