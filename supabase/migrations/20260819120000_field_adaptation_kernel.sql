-- Field adaptation kernel.
--
-- Two tables that carry the marks an adaptive surface accumulates, and nothing
-- else. Neither holds any content: an adaptation is identified by a key built
-- from a kind and a record id (see `FieldAdaptationKey`), and a teaching
-- moment by a fixed string in the binary. Both tables are readable, so
-- anything descriptive in either would be a disclosure channel wearing a
-- bookkeeping costume.

-- MARK: Adaptations ---------------------------------------------------------
--
-- One row per adaptive surface a couple has met, carrying the two marks a
-- surface can hold:
--
--   `earned_at`  — the threshold has been crossed at least once. This is the
--                  persisted half of `FieldThreshold`'s hysteresis. It lives
--                  here rather than on the device precisely because both
--                  people have to gain and keep the same furniture at the same
--                  moment; a per-device flag would hand a room to whoever
--                  crossed the line first and leave their partner without it.
--
--   `set_down_*` — the couple has put the surface away. Reversible by
--                  construction: this table knows nothing about the records
--                  the surface was reading, so setting one down cannot reach
--                  them.
--
-- Couple-scoped rather than per-person for the same reason
-- `field_hidden_categories` is: there is no such thing here as a room one
-- partner can see and the other cannot.
create table if not exists public.field_adaptations (
  couple_id uuid not null references public.couples(id) on delete cascade,
  adaptation_key text not null check (
    char_length(adaptation_key) between 3 and 200
    -- Kind, name, and a uuid, colon separated. The shape is checked so a
    -- client cannot smuggle a title into the key.
    and adaptation_key ~ '^[a-z]+:[a-zA-Z]+:[0-9a-fA-F-]{36}$'
  ),
  earned_at timestamptz,
  set_down_by uuid references public.profiles(id) on delete set null,
  set_down_at timestamptz,
  primary key (couple_id, adaptation_key)
);

alter table public.field_adaptations enable row level security;

drop policy if exists field_adaptations_select on public.field_adaptations;
create policy field_adaptations_select
  on public.field_adaptations
  for select to authenticated
  using (couple_id = (select public.my_couple_id()));
grant select on public.field_adaptations to authenticated;

-- Writes go through the two RPCs below rather than a blanket write policy.
-- They are the only operations that exist, and routing them through functions
-- keeps `set_down_by` stamped by the database rather than trusted from the
-- client — the rule `private.field_preserve_actor()` established.

-- Idempotent. Called the first time a surface's threshold is met; every later
-- call is a no-op, which is what makes `earned_at` mean "first" rather than
-- "most recent".
create or replace function public.mark_adaptation_earned(p_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
begin
  if v_couple is null then raise exception 'no couple'; end if;
  insert into public.field_adaptations (couple_id, adaptation_key, earned_at)
  values (v_couple, p_key, now())
  on conflict (couple_id, adaptation_key) do update
    set earned_at = coalesce(public.field_adaptations.earned_at, now());
end;
$$;

revoke execute on function public.mark_adaptation_earned(text) from public, anon;
grant execute on function public.mark_adaptation_earned(text) to authenticated;

-- `p_set_down = false` takes a surface back up. The row is kept either way, so
-- a surface that was set down and taken up again does not have to re-earn its
-- place from zero.
create or replace function public.set_down_adaptation(
  p_key text,
  p_set_down boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
begin
  if v_couple is null then raise exception 'no couple'; end if;
  insert into public.field_adaptations (
    couple_id, adaptation_key, set_down_by, set_down_at
  )
  values (
    v_couple,
    p_key,
    case when p_set_down then (select auth.uid()) end,
    case when p_set_down then now() end
  )
  on conflict (couple_id, adaptation_key) do update
    set set_down_by = case when p_set_down then (select auth.uid()) end,
        set_down_at = case when p_set_down then now() end;
end;
$$;

revoke execute on function public.set_down_adaptation(text, boolean)
  from public, anon;
grant execute on function public.set_down_adaptation(text, boolean)
  to authenticated;

-- MARK: Teaching moments ----------------------------------------------------
--
-- What this person has already been shown once.
--
-- Per profile, not per device. The device-local `@AppStorage` flags this app
-- has used until now are wrong for anything that is meant to happen a fixed
-- number of times in a person's life rather than a fixed number of times per
-- phone — the distinction `CIRCLE.md` §2 draws for the word "Yours", and the
-- same distinction applies to "here is what just appeared and why".
--
-- Deliberately not couple-scoped: two people meet the product at different
-- moments, and a partner joining later has not seen anything yet.
create table if not exists public.field_teaching_moments (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  -- A fixed identifier from the binary, never a rendered string.
  moment_key text not null check (
    char_length(moment_key) between 3 and 80
    and moment_key ~ '^[a-z][a-zA-Z.]*$'
  ),
  taught_at timestamptz not null default now(),
  primary key (profile_id, moment_key)
);

alter table public.field_teaching_moments enable row level security;

drop policy if exists field_teaching_moments_select on public.field_teaching_moments;
create policy field_teaching_moments_select
  on public.field_teaching_moments
  for select to authenticated
  using (profile_id = (select auth.uid()));

-- Insert-only for the caller's own row. There is no update and no delete: a
-- moment that has happened has happened, and a client that could clear the
-- table could show a person their first-time explanation forever.
drop policy if exists field_teaching_moments_insert on public.field_teaching_moments;
create policy field_teaching_moments_insert
  on public.field_teaching_moments
  for insert to authenticated
  with check (profile_id = (select auth.uid()));

grant select, insert on public.field_teaching_moments to authenticated;

-- MARK: Realtime ------------------------------------------------------------
--
-- `field_adaptations` only. A surface appearing or being set down has to reach
-- the other person's screen without a relaunch, since they are looking at the
-- same room. `field_teaching_moments` is deliberately absent: it is a private,
-- per-person row, and publishing it would put one person's onboarding state on
-- a channel their partner shares.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'field_adaptations'
  ) then
    alter publication supabase_realtime add table public.field_adaptations;
  end if;
end;
$$;
