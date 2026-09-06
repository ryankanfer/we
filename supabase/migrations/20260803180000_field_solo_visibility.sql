-- The solo-to-shared boundary. Phase 2a, and a P0.
--
-- WHAT IS WRONG TODAY
--
-- `20260730120000_field_zones.sql:321-368` generates one identical policy pair
-- for all fourteen field tables:
--
--   for select using (couple_id = public.my_couple_id())
--   for all    using (couple_id = public.my_couple_id())
--
-- Membership in the couple is the entire read grant. There is no per-member
-- distinction anywhere in it.
--
-- `create_couple()` already gives an unpaired person a real couple row, so
-- everything they write while alone is already stamped with that couple_id.
-- The instant partner B's `couple_members` row appears, `my_couple_id()`
-- returns the same id for B — and every capture, correction, dismissal and
-- item A wrote while alone becomes readable by B. Retroactively, with no
-- event, and with nothing on screen to mark it.
--
-- The app meanwhile says, on the solo screen and in its own voice:
--
--   "Your side is ready. You can keep what you began here. Invite your
--    partner only when a shared space would be useful."
--
-- and files what is already there under a card headed "Saved on your side."
-- Those sentences and that policy pair cannot both be true. This migration
-- makes the database agree with the sentences.
--
-- THE CLASSIFICATION
--
-- Not every table needs one, and pretending otherwise is how this becomes
-- unshippable. Three groups:
--
--   1. Couple configuration — one row per couple, no author, nothing to
--      classify. `field_identity`, `field_daily_moment`.
--
--   2. Derived by the app about the relationship — occasions, horizons, the
--      questions generated from them, rhythms, evidence. These describe the
--      couple rather than a person, several already carry an a/b/shared side,
--      and none is authored privately. Joint.
--
--   3. Authored directly by one person — captures, life items, corrections,
--      standing rules, held topics. These are the ones the promise is about,
--      and the only ones that get a visibility column.
--
-- Plus `field_away_windows`, which is somebody's own presence and is private
-- to its author permanently rather than by era, and `field_ours_items`, which
-- is deprecated.
--
-- WHEN A ROW IS PRIVATE
--
-- Visibility is decided by the era it was written in, not by asking. A row
-- written while the couple has one member is private to its author. A row
-- written after the second person joins is shared, because at that point a
-- shared field is the entire product and asking per-capture would be a
-- confirmation dialog on a text box.
--
-- The solo backlog then crosses only when its author says so, once, having
-- been shown what will cross — `public.field_share_solo_history()` below,
-- called from the pairing disclosure before the invitation is redeemed.
--
-- REVERSIBILITY
--
-- Every policy here is a `drop policy if exists` followed by a create, and
-- reverting is re-running the generator block in `20260730120000`. The columns
-- are additive; a client that does not know about `visibility` keeps working,
-- and its inserts get the trigger's default.

-- Wrapped in one transaction, so this is all-or-nothing.
--
-- Worth doing because the middle of this migration is the dangerous part: the
-- generated `_write` policy is dropped before the three that replace it exist.
-- A failure in that window, uncommitted, leaves the old policies exactly as
-- they were. A failure in that window *committed* leaves six tables writable
-- by nobody.
--
-- `supabase db push` wraps migrations already. This matters when the file is
-- run by hand in the SQL editor, which is how it is being applied today.
begin;

-- MARK: Who wrote it --------------------------------------------------------
--
-- Four of the five authored tables already carry an actor, frozen after insert
-- by `private.field_preserve_actor()`. `field_held_topics` carries none — it
-- was written as couple-scoped — so it gets one.

alter table public.field_held_topics
  add column if not exists created_by uuid
    references public.profiles(id) on delete set null;

-- MARK: Visibility ----------------------------------------------------------
--
-- Default `shared`, so that any row inserted by a path that predates this
-- migration — or by an older client — behaves exactly as it does today. The
-- trigger below is what makes solo-era rows private; the column default is
-- deliberately the permissive one, because a column default that silently
-- hid rows from an existing couple would be a data-loss bug wearing a privacy
-- costume.

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_life_items',
    'field_captures',
    'field_corrections',
    'field_standing_rules',
    'field_held_topics'
  ]
  loop
    execute format(
      'alter table public.%I
         add column if not exists visibility text not null default ''shared''',
      v_table
    );
    execute format(
      'alter table public.%I
         drop constraint if exists %I',
      v_table, v_table || '_visibility_check'
    );
    execute format(
      'alter table public.%I
         add constraint %I check (visibility in (''private'', ''shared''))',
      v_table, v_table || '_visibility_check'
    );
    -- Every policy below filters on it.
    execute format(
      'create index if not exists %I on public.%I(couple_id, visibility)',
      v_table || '_visibility_idx', v_table
    );
  end loop;
end;
$$;

-- MARK: Stamping ------------------------------------------------------------
--
-- Set on insert from the size of the couple, then frozen. A person cannot
-- send `visibility` themselves for the same reason they cannot send
-- `created_by`: it would let one partner publish the other's private history
-- by writing a row over it.

create or replace function private.field_stamp_visibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims_text text :=
    nullif(current_setting('request.jwt.claims', true), '');
  v_request_role text;
  v_members integer;
begin
  if v_claims_text is not null then
    v_request_role := v_claims_text::jsonb ->> 'role';
  end if;
  v_request_role := coalesce(
    v_request_role,
    nullif(current_setting('request.jwt.claim.role', true), '')
  );

  -- Migration and service-role connections are trusted to say what they mean,
  -- exactly as in `private.field_preserve_actor()`. This is also the path the
  -- crossing RPC below takes.
  if v_request_role is null or v_request_role = 'service_role' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    -- Frozen. Crossing happens through the RPC, which announces itself.
    if nullif(
      current_setting('we.crossing_solo_history', true), ''
    ) is distinct from 'on' then
      new.visibility := old.visibility;
    end if;
    return new;
  end if;

  select count(*) into v_members
  from public.couple_members cm
  where cm.couple_id = new.couple_id;

  -- One member is the solo era. Two is a couple, and a couple's field is
  -- shared — that is the product, not a concession.
  new.visibility := case when v_members < 2 then 'private' else 'shared' end;
  return new;
end;
$$;

revoke all on function private.field_stamp_visibility()
  from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_life_items',
    'field_captures',
    'field_corrections',
    'field_standing_rules',
    'field_held_topics'
  ]
  loop
    execute format(
      'drop trigger if exists field_visibility_integrity on public.%I',
      v_table
    );
    -- Sorts after `field_actor_integrity`, so the author is settled before
    -- the era that author wrote in is recorded.
    execute format(
      'create trigger field_visibility_integrity
         before insert or update on public.%I
         for each row execute function private.field_stamp_visibility()',
      v_table
    );
  end loop;
end;
$$;

-- MARK: Held topics need an author too --------------------------------------
--
-- `private.field_preserve_actor()` raises on any table it does not recognise,
-- so `field_held_topics` cannot simply be added to its trigger list without
-- teaching it the column. A separate stamp keeps that function untouched, for
-- the reason `20260803120000` already gives: re-declaring two hundred lines to
-- add one branch is how a migration silently reverts the rest of it.

create or replace function private.field_stamp_held_topic_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims_text text :=
    nullif(current_setting('request.jwt.claims', true), '');
  v_request_role text;
  v_user uuid := (select auth.uid());
begin
  if v_claims_text is not null then
    v_request_role := v_claims_text::jsonb ->> 'role';
  end if;
  v_request_role := coalesce(
    v_request_role,
    nullif(current_setting('request.jwt.claim.role', true), '')
  );

  if v_request_role is null or v_request_role = 'service_role' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- The client upserts held topics on (couple_id, client_id), so an insert
    -- may resolve to an update of a row somebody else wrote. Preserve the
    -- original author when that happens, exactly as the life-item branch of
    -- `field_preserve_actor` does.
    select h.created_by into new.created_by
    from public.field_held_topics h
    where h.couple_id = new.couple_id and h.client_id = new.client_id;

    if new.created_by is null then
      new.created_by := v_user;
    end if;
  else
    new.created_by := old.created_by;
  end if;

  return new;
end;
$$;

revoke all on function private.field_stamp_held_topic_actor()
  from public, anon, authenticated;

drop trigger if exists field_held_topic_actor_integrity
  on public.field_held_topics;

create trigger field_held_topic_actor_integrity
  before insert or update on public.field_held_topics
  for each row execute function private.field_stamp_held_topic_actor();

-- MARK: The policies --------------------------------------------------------
--
-- Read: your couple's rows, minus your partner's private ones. Write: your
-- couple's rows, unchanged — the write side is deliberately *not* narrowed to
-- the author. Either partner editing a shared item is the product working, and
-- `field_preserve_actor` already stops an edit from rewriting who authored it.
--
-- `auth.uid()` rather than a side letter, because a uuid cannot be spoofed by
-- sending 'a'.

-- The `_write` policy generated by `20260730120000` is `for all`, and `for all`
-- includes SELECT. Permissive policies combine with OR, so leaving it in place
-- would grant read access to exactly the rows the select policy below excludes
-- — the narrowing would compile, deploy, and do nothing. It is replaced here by
-- three verb-specific policies, none of which mentions SELECT.
--
-- UPDATE and DELETE take the same visibility predicate as SELECT. A row you
-- cannot see is a row you cannot delete: without that, `delete where true`
-- destroys a partner's private history without ever reading it.

do $$
declare
  r record;
  v_visible text;
begin
  for r in
    select * from (values
      ('field_life_items', 'created_by'),
      ('field_captures', 'spoken_by'),
      ('field_corrections', 'corrected_by'),
      ('field_standing_rules', 'set_by'),
      ('field_held_topics', 'created_by')
    ) as t(tbl, actor)
  loop
    v_visible := format(
      'couple_id = public.my_couple_id()
         and (visibility = ''shared'' or %I = (select auth.uid()))',
      r.actor
    );

    execute format(
      'drop policy if exists %I on public.%I', r.tbl || '_select', r.tbl
    );
    execute format(
      'create policy %I on public.%I for select using (%s)',
      r.tbl || '_select', r.tbl, v_visible
    );

    execute format(
      'drop policy if exists %I on public.%I', r.tbl || '_write', r.tbl
    );

    execute format(
      'drop policy if exists %I on public.%I', r.tbl || '_insert', r.tbl
    );
    execute format(
      'create policy %I on public.%I for insert
         with check (couple_id = public.my_couple_id())',
      r.tbl || '_insert', r.tbl
    );

    execute format(
      'drop policy if exists %I on public.%I', r.tbl || '_update', r.tbl
    );
    execute format(
      'create policy %I on public.%I for update
         using (%s) with check (couple_id = public.my_couple_id())',
      r.tbl || '_update', r.tbl, v_visible
    );

    execute format(
      'drop policy if exists %I on public.%I', r.tbl || '_delete', r.tbl
    );
    execute format(
      'create policy %I on public.%I for delete using (%s)',
      r.tbl || '_delete', r.tbl, v_visible
    );
  end loop;
end;
$$;

-- Somebody's own presence, private to them permanently rather than by era.
-- It has carried `profile_id` since it was created and nothing has ever read
-- it across the pair. Same `for all` problem, same fix.
drop policy if exists field_away_windows_select on public.field_away_windows;
create policy field_away_windows_select on public.field_away_windows
  for select using (
    couple_id = public.my_couple_id()
    and profile_id = (select auth.uid())
  );

drop policy if exists field_away_windows_write on public.field_away_windows;

drop policy if exists field_away_windows_insert on public.field_away_windows;
create policy field_away_windows_insert on public.field_away_windows
  for insert with check (couple_id = public.my_couple_id());

drop policy if exists field_away_windows_update on public.field_away_windows;
create policy field_away_windows_update on public.field_away_windows
  for update
  using (
    couple_id = public.my_couple_id()
    and profile_id = (select auth.uid())
  )
  with check (couple_id = public.my_couple_id());

drop policy if exists field_away_windows_delete on public.field_away_windows;
create policy field_away_windows_delete on public.field_away_windows
  for delete using (
    couple_id = public.my_couple_id()
    and profile_id = (select auth.uid())
  );

-- MARK: Crossing ------------------------------------------------------------
--
-- The one way a private row becomes shared.
--
-- Scoped to the caller's own rows — `created_by = auth.uid()` on every
-- statement — so this can never publish a partner's history. It is called from
-- the pairing disclosure, after the person has been shown what will cross and
-- has said yes, and it is idempotent: running it twice shares the same rows
-- twice.

create or replace function public.field_share_solo_history()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid := public.my_couple_id();
  v_shared integer := 0;
  v_count integer;
begin
  if v_user is null or v_couple is null then
    raise exception 'a signed-in member is required to share solo history'
      using errcode = '42501';
  end if;

  -- Announces itself to `field_stamp_visibility`, which otherwise freezes
  -- this column. Transaction-local, so it cannot leak into another statement.
  perform set_config('we.crossing_solo_history', 'on', true);

  update public.field_life_items
  set visibility = 'shared'
  where couple_id = v_couple and created_by = v_user
    and visibility = 'private';
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_captures
  set visibility = 'shared'
  where couple_id = v_couple and spoken_by = v_user
    and visibility = 'private';
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_corrections
  set visibility = 'shared'
  where couple_id = v_couple and corrected_by = v_user
    and visibility = 'private';
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_standing_rules
  set visibility = 'shared'
  where couple_id = v_couple and set_by = v_user
    and visibility = 'private';
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_held_topics
  set visibility = 'shared'
  where couple_id = v_couple and created_by = v_user
    and visibility = 'private';
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  perform set_config('we.crossing_solo_history', 'off', true);
  return v_shared;
end;
$$;

revoke all on function public.field_share_solo_history() from public, anon;
grant execute on function public.field_share_solo_history() to authenticated;

-- MARK: What would cross ----------------------------------------------------
--
-- So the disclosure can name a number before anybody commits to it. Read-only,
-- and it counts only the caller's own rows.

create or replace function public.field_solo_history_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select count(*) from public.field_life_items
      where couple_id = public.my_couple_id()
        and created_by = (select auth.uid()) and visibility = 'private')
    + (select count(*) from public.field_captures
        where couple_id = public.my_couple_id()
          and spoken_by = (select auth.uid()) and visibility = 'private')
    + (select count(*) from public.field_standing_rules
        where couple_id = public.my_couple_id()
          and set_by = (select auth.uid()) and visibility = 'private'),
    0
  )::integer;
$$;

revoke all on function public.field_solo_history_count() from public, anon;
grant execute on function public.field_solo_history_count() to authenticated;

-- MARK: Existing rows -------------------------------------------------------
--
-- Everything written before this migration stays exactly as visible as it was.
-- The column default did that already; this is here to say it was a decision.
--
-- Retroactively privatising an existing couple's history would hide rows that
-- both people have been looking at for weeks, which is a worse failure than
-- the one being fixed — and there is no way to tell, after the fact, which of
-- those rows were written during a solo era that ended before anyone was
-- watching.

commit;
