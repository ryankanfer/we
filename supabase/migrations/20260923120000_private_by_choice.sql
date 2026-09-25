-- Private by choice, not only by era.
--
-- WHY
--
-- `20260803180000_field_solo_visibility.sql` made a row private when it was
-- written while its couple had one member, and shared otherwise. That was
-- the whole privacy model for the field, and the personal space (Yours)
-- carried everything else a person wanted kept to themselves. Yours is being
-- retired as a destination (see `20260923130000_retire_yours.sql`); privacy is
-- not. It becomes a property of an item: any capture can be "Only me".
--
-- WHAT CHANGES
--
-- `private.field_stamp_visibility()` gains exactly two behaviours:
--
--   1. INSERT: a client may *request* `private`. It may never request
--      `shared` over the era rule, because the column default already is
--      `shared` and the era rule only ever narrows. A request for `private`
--      is honoured whatever the couple size.
--
--   2. UPDATE: the column stays frozen, with one exception. The row's own
--      author may move it from `private` to `shared`. Nothing moves it back:
--      something a partner has been able to read cannot be un-read, and the
--      database refuses to pretend otherwise. A partner can never flip a row,
--      because they cannot see a private row to begin with (the select and
--      update policies from `20260803180000` already require authorship for
--      private rows), and the author check below holds even if they could.
--
-- Why a trigger transition rather than a dedicated RPC: the client writes
-- items as whole-row upserts through an offline outbox that compacts queued
-- writes per item. A separate "share" call could be reordered ahead of the
-- create it depends on, or dropped by a later edit of the same item. Carried
-- on the row, the share is simply the row's latest value.
--
-- When a life item crosses, the capture it was filed from (same id) crosses
-- with it, so the chip under the partner's capture field and the item agree.
--
-- And the solo-era crossing (`field_share_solo_history()`) is narrowed to the
-- solo era by time, because visibility alone no longer means "written before
-- the partner arrived". See the section at the bottom.

begin;

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
  v_user uuid := (select auth.uid());
  v_members integer;
  v_actor_column text;
  v_author uuid;
begin
  if v_claims_text is not null then
    v_request_role := v_claims_text::jsonb ->> 'role';
  end if;
  v_request_role := coalesce(
    v_request_role,
    nullif(current_setting('request.jwt.claim.role', true), '')
  );

  -- Migration and service-role connections are trusted to say what they mean,
  -- exactly as in `private.field_preserve_actor()`.
  if v_request_role is null or v_request_role = 'service_role' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    -- The bulk crossing announces itself and is trusted, as before.
    if nullif(
      current_setting('we.crossing_solo_history', true), ''
    ) = 'on' then
      return new;
    end if;

    -- The one permitted transition: the author sharing their own row.
    --
    -- The actor column differs per table, and it is read through `to_jsonb`
    -- rather than as `old.<column>` because PL/pgSQL resolves record fields
    -- when the expression is planned, not when the branch runs — naming a
    -- column one of these tables lacks would fail on every write to it. See
    -- `20260904120000_shared_item_and_space_guards.sql` for that exact bug.
    if old.visibility = 'private' and new.visibility = 'shared' then
      v_actor_column := case tg_table_name
        when 'field_life_items' then 'created_by'
        when 'field_captures' then 'spoken_by'
        when 'field_corrections' then 'corrected_by'
        when 'field_standing_rules' then 'set_by'
        when 'field_held_topics' then 'created_by'
      end;
      v_author := nullif(to_jsonb(old) ->> v_actor_column, '')::uuid;

      if v_author is not null and v_author = v_user then
        return new;
      end if;
    end if;

    new.visibility := old.visibility;
    return new;
  end if;

  -- INSERT. A requested `private` is honoured as asked.
  if new.visibility = 'private' then
    return new;
  end if;

  select count(*) into v_members
  from public.couple_members cm
  where cm.couple_id = new.couple_id;

  new.visibility := case when v_members < 2 then 'private' else 'shared' end;
  return new;
end;
$$;

revoke all on function private.field_stamp_visibility()
  from public, anon, authenticated;

-- MARK: The capture follows its item ------------------------------------------

create or replace function private.field_share_capture_with_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Inside `field_share_solo_history()` the bulk crossing moves captures
  -- itself, and counts them. Moving them here first would make what crossed
  -- disagree with what the disclosure named.
  if nullif(
    current_setting('we.crossing_solo_history', true), ''
  ) = 'on' then
    return null;
  end if;

  if old.visibility = 'private' and new.visibility = 'shared' then
    -- Announced, so the capture's own visibility trigger lets it through.
    -- Transaction-local, and turned back off before returning.
    perform set_config('we.crossing_solo_history', 'on', true);

    update public.field_captures c
    set visibility = 'shared'
    where c.id = new.id
      and c.couple_id = new.couple_id
      and c.spoken_by is not distinct from new.created_by
      and c.visibility = 'private';

    perform set_config('we.crossing_solo_history', 'off', true);
  end if;
  return null;
end;
$$;

revoke all on function private.field_share_capture_with_item()
  from public, anon, authenticated;

drop trigger if exists field_life_item_share_capture
  on public.field_life_items;

create trigger field_life_item_share_capture
  after update of visibility on public.field_life_items
  for each row execute function private.field_share_capture_with_item();

-- MARK: Solo history means the solo era, and only that -------------------------
--
-- Until now every private row *was* solo history, so the crossing could
-- select on visibility alone. It no longer is: "Only me" rows are private
-- because somebody chose it after pairing, and the crossing must never
-- publish them. That matters in practice, not in theory — the crossing
-- decision is remembered per device (`FieldCrossingDecision`), so a
-- reinstall asks again, and "Bring it across" would otherwise move every
-- private thing this person had ever chosen to keep.
--
-- The era ends when the partner joined. `<=` rather than `<` only so a
-- single-transaction test, where `now()` is constant, still sees rows written
-- before the join as solo; in production no row shares that microsecond.
--
-- Count and crossing stay table-for-table identical, as
-- `20260803210000_solo_history_count_matches_crossing.sql` requires.

create or replace function private.field_solo_era_ends(p_couple uuid, p_user uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select min(cm.joined_at)
      from public.couple_members cm
      where cm.couple_id = p_couple and cm.profile_id <> p_user
    ),
    'infinity'::timestamptz
  );
$$;

revoke all on function private.field_solo_era_ends(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.field_solo_history_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with era as (
    select private.field_solo_era_ends(
      public.my_couple_id(), (select auth.uid())
    ) as ends
  )
  select coalesce(
    (select count(*) from public.field_life_items, era
      where couple_id = public.my_couple_id()
        and created_by = (select auth.uid()) and visibility = 'private'
        and created_at <= era.ends)
    + (select count(*) from public.field_captures, era
        where couple_id = public.my_couple_id()
          and spoken_by = (select auth.uid()) and visibility = 'private'
          and captured_at <= era.ends)
    + (select count(*) from public.field_corrections, era
        where couple_id = public.my_couple_id()
          and corrected_by = (select auth.uid()) and visibility = 'private'
          and corrected_at <= era.ends)
    + (select count(*) from public.field_standing_rules, era
        where couple_id = public.my_couple_id()
          and set_by = (select auth.uid()) and visibility = 'private'
          and set_at <= era.ends)
    + (select count(*) from public.field_held_topics, era
        where couple_id = public.my_couple_id()
          and created_by = (select auth.uid()) and visibility = 'private'
          and created_at <= era.ends),
    0
  )::integer;
$$;

revoke all on function public.field_solo_history_count() from public, anon;
grant execute on function public.field_solo_history_count() to authenticated;

create or replace function public.field_share_solo_history()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid := public.my_couple_id();
  v_ends timestamptz;
  v_shared integer := 0;
  v_count integer;
begin
  if v_user is null or v_couple is null then
    raise exception 'a signed-in member is required to share solo history'
      using errcode = '42501';
  end if;

  v_ends := private.field_solo_era_ends(v_couple, v_user);

  perform set_config('we.crossing_solo_history', 'on', true);

  update public.field_life_items
  set visibility = 'shared'
  where couple_id = v_couple and created_by = v_user
    and visibility = 'private' and created_at <= v_ends;
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_captures
  set visibility = 'shared'
  where couple_id = v_couple and spoken_by = v_user
    and visibility = 'private' and captured_at <= v_ends;
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_corrections
  set visibility = 'shared'
  where couple_id = v_couple and corrected_by = v_user
    and visibility = 'private' and corrected_at <= v_ends;
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_standing_rules
  set visibility = 'shared'
  where couple_id = v_couple and set_by = v_user
    and visibility = 'private' and set_at <= v_ends;
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  update public.field_held_topics
  set visibility = 'shared'
  where couple_id = v_couple and created_by = v_user
    and visibility = 'private' and created_at <= v_ends;
  get diagnostics v_count = row_count;
  v_shared := v_shared + v_count;

  perform set_config('we.crossing_solo_history', 'off', true);
  return v_shared;
end;
$$;

revoke all on function public.field_share_solo_history() from public, anon;
grant execute on function public.field_share_solo_history() to authenticated;

commit;
