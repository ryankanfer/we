-- Backfill: solo-era rows that predate the visibility column.
--
-- WHAT IS WRONG TODAY
--
-- `20260803180000_field_solo_visibility.sql:113-118` adds the column as
--
--   add column if not exists visibility text not null default 'shared'
--
-- and adds no backfill. That default is argued for at lines 95-99 of that
-- file, and the argument is correct as far as it goes:
--
--   "a column default that silently hid rows from an existing couple would be
--    a data-loss bug wearing a privacy costume"
--
-- True — for a couple. It is exactly backwards for somebody who was still
-- alone when the migration ran. Every capture, life item, correction, standing
-- rule and held topic they wrote before 2026-08-03 is sitting at 'shared'
-- while its author has never been asked. Nobody can read it yet, because
-- nobody else is in the couple. But `field_share_solo_history()` is the door
-- that backlog is supposed to walk through, once, deliberately, having been
-- shown what will cross. These rows skip it: the moment a partner joins,
-- `my_couple_id()` returns the same id for them and the whole pre-migration
-- backlog is readable, with no event and nothing on screen to mark it.
--
-- That is the precise failure `20260803180000` was written to prevent. It
-- prevented it for every row written after it deployed and left the rows
-- written before.
--
-- WHY THIS IS SAFE IN THE DIRECTION IT MOVES
--
-- The hazard the 'shared' default guards against cannot occur here, because
-- this only touches rows whose couple has fewer than two members. A solo
-- couple has exactly one person in it, and that person is the author. Flipping
-- their own rows to 'private' hides nothing from anybody — there is nobody to
-- hide from. It restores their choice about the crossing rather than making it
-- for them.
--
-- Already-paired couples are untouched. The `< 2` predicate is evaluated per
-- row against live membership, so a couple that paired between 2026-08-03 and
-- this migration keeps everything it can currently see.
--
-- WHAT IT CANNOT REPAIR
--
-- If a partner has already joined, the crossing has already happened silently
-- and this will not claw it back. Un-sharing something a second person may
-- have read is not a privacy fix, it is a second silent visibility change
-- pointed the other way. Those couples keep what they have; the promise is
-- repaired for everyone still alone.
--
-- WHY A FUNCTION AND NOT A `do` BLOCK
--
-- So the test can run the real thing. A `do` block executes once at deploy
-- time and is then unreachable, which leaves a pgTAP test no choice but to
-- restate the same UPDATE and assert against its own copy — a test that
-- passes when the copy is right and the migration is wrong. This is also the
-- repair for the next migration that adds a visibility-bearing table: extend
-- the mapping below and call it again.

create or replace function private.field_backfill_solo_visibility()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer;
  v_total integer := 0;
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
    -- A row with no author cannot be private to anyone, so it is skipped
    -- rather than guessed at. The test asserts none exists.
    execute format(
      'update public.%I i
          set visibility = ''private''
        where i.visibility = ''shared''
          and i.%I is not null
          and (
            select count(*) from public.couple_members cm
            where cm.couple_id = i.couple_id
          ) < 2',
      r.tbl, r.actor
    );
    get diagnostics v_count = row_count;
    v_total := v_total + v_count;
  end loop;

  return v_total;
end;
$$;

-- Never a client's to call. `private.field_stamp_visibility` would freeze the
-- column for an `authenticated` request anyway, but the grant is the boundary
-- that says so rather than an implementation detail that happens to hold.
revoke all on function private.field_backfill_solo_visibility()
  from public, anon, authenticated;

do $$
declare
  v_total integer;
begin
  select private.field_backfill_solo_visibility() into v_total;
  raise notice 'solo backfill: % rows returned to private', v_total;
end;
$$;
