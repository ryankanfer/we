-- Field actor integrity.
--
-- Field rows are couple-visible, but the UUID columns that say who authored
-- them must not be caller-controlled. Without this guard, an authenticated
-- partner can send the other partner's profile UUID and persist a capture,
-- correction, rule, or item as them. The same boundary protects the stable
-- A/B side on authored rows and keeps each person's swatch independently
-- writable.
--
-- Trusted migration connections and service-role jobs are deliberately left
-- alone. Authenticated requests are stamped from auth.uid() on insert, and an
-- existing actor is immutable on update. This keeps shared rows editable by
-- either partner without allowing an edit to rewrite their history.

create or replace function private.field_preserve_actor()
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
  v_side text;
  v_existing_actor uuid;
  v_existing_side text;
begin
  if v_claims_text is not null then
    v_request_role := v_claims_text::jsonb ->> 'role';
  end if;
  v_request_role := coalesce(
    v_request_role,
    nullif(current_setting('request.jwt.claim.role', true), '')
  );

  -- Direct migration/maintenance connections have no request claims. A
  -- service-role request is trusted explicitly; both need to preserve actors
  -- when importing or repairing historical data.
  if v_request_role is null or v_request_role = 'service_role' then
    return new;
  end if;

  if v_user is null then
    raise exception 'a signed-in profile is required for Field writes'
      using errcode = '42501';
  end if;

  select case cm.member_slot when 1 then 'a' when 2 then 'b' end
  into v_side
  from public.couple_members cm
  where cm.profile_id = v_user;

  if v_side is null then
    raise exception 'an active WE membership is required for Field writes'
      using errcode = '42501';
  end if;

  if tg_table_name = 'field_away_windows' then
    if tg_op = 'INSERT' then
      new.profile_id := v_user;
    else
      new.profile_id := old.profile_id;
    end if;
  elsif tg_table_name = 'field_life_items' then
    if tg_op = 'INSERT' then
      -- The client uses INSERT .. ON CONFLICT for both new rows and edits.
      -- PostgreSQL fires BEFORE INSERT before it resolves that conflict, so
      -- preserve an existing row here or a Partner B edit of A's item would
      -- be rejected before the UPDATE branch ever runs.
      select l.created_by, l.owner
      into v_existing_actor, v_existing_side
      from public.field_life_items l
      where l.id = new.id;

      if found then
        new.created_by := v_existing_actor;
        new.owner := v_existing_side;
      else
        new.created_by := v_user;
        if new.owner <> 'shared' and new.owner <> v_side then
          raise exception 'a Field item cannot be authored as the other partner'
            using errcode = '42501';
        end if;
      end if;
    else
      new.created_by := old.created_by;
      new.owner := old.owner;
    end if;
  elsif tg_table_name = 'field_ours_items' then
    if tg_op = 'INSERT' then
      new.added_by := v_user;
    else
      new.added_by := old.added_by;
    end if;
  elsif tg_table_name = 'field_standing_rules' then
    if tg_op = 'INSERT' then
      new.set_by := v_user;
    else
      new.set_by := old.set_by;
    end if;
  elsif tg_table_name = 'field_captures' then
    if tg_op = 'INSERT' then
      new.spoken_by := v_user;
    else
      new.spoken_by := old.spoken_by;
    end if;
  elsif tg_table_name = 'field_corrections' then
    if tg_op = 'INSERT' then
      new.corrected_by := v_user;
    else
      new.corrected_by := old.corrected_by;
    end if;
  elsif tg_table_name = 'field_horizons' then
    if tg_op = 'INSERT' then
      select h.owner
      into v_existing_side
      from public.field_horizons h
      where h.id = new.id;

      if found then
        new.owner := v_existing_side;
      elsif new.owner <> 'shared' and new.owner <> v_side then
        raise exception 'a Field horizon cannot be authored as the other partner'
          using errcode = '42501';
      end if;
    else
      new.owner := old.owner;
    end if;
  elsif tg_table_name = 'field_evidence' then
    if tg_op = 'INSERT' then
      if new.owner <> 'shared' and new.owner <> v_side then
        raise exception 'Field evidence cannot be authored as the other partner'
          using errcode = '42501';
      end if;
    else
      new.owner := old.owner;
    end if;
  elsif tg_table_name = 'field_clusters' then
    if tg_op = 'INSERT' then
      if new.tint <> 'shared' and new.tint <> v_side then
        raise exception 'a Field cluster cannot be authored as the other partner'
          using errcode = '42501';
      end if;
    else
      new.tint := old.tint;
    end if;
  elsif tg_table_name = 'field_identity' then
    if tg_op = 'INSERT' then
      -- Either partner may be the first person to finish onboarding. The
      -- other side starts from the schema default until that person chooses
      -- their own swatch.
      if v_side = 'a' then
        new.swatch_b := 'slate';
      else
        new.swatch_a := 'clay';
      end if;
    elsif v_side = 'a' then
      new.swatch_b := old.swatch_b;
    else
      new.swatch_a := old.swatch_a;
    end if;
  else
    raise exception 'field_preserve_actor is attached to an unknown table: %',
      tg_table_name;
  end if;

  return new;
end;
$$;

-- Repair rows written before the client began resolving the viewer's real
-- A/B side. Captures already stored the authenticated profile UUID, while the
-- old Life adapter left `created_by` null and always supplied owner A.
--
-- Attribution must fail closed. Two people can file the same wording close
-- together, and the old capture rows did not retain the receipt UUID. Restore
-- A/B only when the text/time relationship is one-to-one in both directions,
-- then neutralize every remaining unattributed captured row. Ambiguous history
-- stays shared rather than guessing that Partner B was Partner A.
with capture_candidates as (
  select
    l.id as life_item_id,
    c.id as capture_id,
    c.spoken_by,
    cm.member_slot,
    count(*) over (partition by l.id) as candidates_for_item,
    count(*) over (partition by c.id) as candidates_for_capture
  from public.field_life_items l
  join public.field_captures c
    on c.couple_id = l.couple_id
   and lower(btrim(c.text)) = lower(btrim(l.title))
   and c.captured_at between
     l.created_at - interval '10 minutes'
     and l.created_at + interval '10 minutes'
  join public.couple_members cm
    on cm.couple_id = l.couple_id
   and cm.profile_id = c.spoken_by
  where l.source = 'captured'
    and l.created_by is null
),
matched_capture as (
  select life_item_id, spoken_by, member_slot
  from capture_candidates
  where candidates_for_item = 1
    and candidates_for_capture = 1
)
update public.field_life_items l
set
  created_by = matched_capture.spoken_by,
  owner = case
    when l.owner = 'shared' then 'shared'
    when matched_capture.member_slot = 1 then 'a'
    else 'b'
  end
from matched_capture
where l.id = matched_capture.life_item_id;

-- Anything the one-to-one repair could not prove is deliberately neutral.
-- This runs after restoration so a uniquely attributable A/B row keeps its
-- recovered side, while ambiguous legacy Partner B data can never remain A.
update public.field_life_items
set owner = 'shared'
where source = 'captured'
  and created_by is null
  and owner <> 'shared';

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_away_windows',
    'field_life_items',
    'field_ours_items',
    'field_standing_rules',
    'field_captures',
    'field_corrections',
    'field_horizons',
    'field_evidence',
    'field_clusters',
    'field_identity'
  ]
  loop
    execute format(
      'drop trigger if exists field_preserve_actor on public.%I',
      v_table
    );
    execute format(
      'drop trigger if exists field_actor_integrity on public.%I',
      v_table
    );
    -- This name sorts before field_ours_items_coincidence, so a spoofed
    -- added_by value is corrected before coincidence inference runs.
    execute format(
      'create trigger field_actor_integrity
         before insert or update on public.%I
         for each row execute function private.field_preserve_actor()',
      v_table
    );
  end loop;
end;
$$;

revoke all on function private.field_preserve_actor()
  from public, anon, authenticated;

-- Corrections are part of the same capture/correct/send interaction as
-- captures. Publish them so the other partner sees a correction arrive
-- without restarting the app. RLS still filters every subscriber.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'field_corrections'
  ) then
    alter publication supabase_realtime
      add table public.field_corrections;
  end if;
end;
$$;
