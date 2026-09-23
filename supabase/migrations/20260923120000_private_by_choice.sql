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
-- The crossing flag `we.crossing_solo_history` keeps working unchanged for
-- `field_share_solo_history()`.

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
declare
  v_previous text := current_setting('we.crossing_solo_history', true);
begin
  if old.visibility = 'private' and new.visibility = 'shared' then
    -- Announced, so the capture's own visibility trigger lets it through.
    -- Transaction-local, and restored afterwards rather than cleared: this
    -- also fires inside `field_share_solo_history()`'s own bulk update, where
    -- the flag is already on and clearing it would freeze every row after
    -- the first.
    perform set_config('we.crossing_solo_history', 'on', true);

    update public.field_captures c
    set visibility = 'shared'
    where c.id = new.id
      and c.couple_id = new.couple_id
      and c.spoken_by is not distinct from new.created_by
      and c.visibility = 'private';

    perform set_config(
      'we.crossing_solo_history', coalesce(v_previous, ''), true
    );
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

commit;
