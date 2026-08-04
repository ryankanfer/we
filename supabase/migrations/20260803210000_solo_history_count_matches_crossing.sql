-- The disclosure's number has to be the disclosure's promise.
--
-- WHAT IS WRONG TODAY
--
-- `20260803180000_field_solo_visibility.sql` shipped the pair that the
-- crossing screen is built on:
--
--   `field_solo_history_count()`  — counts life items, captures, standing rules
--   `field_share_solo_history()`  — moves  life items, captures, standing rules,
--                                          corrections, held topics
--
-- Three tables against five. Its own pgTAP file states the gap without
-- naming it: `field_solo_history_count() = 3` twelve lines above
-- `field_share_solo_history() = 5`, on the same five rows, written by the
-- same person.
--
-- That is a number on a consent screen that is smaller than what the button
-- under it does. `FieldCrossingView` reads the count into "You wrote N things
-- here on your own", and then lists, in full:
--
--   The things you filed, and what you typed to file them
--   Corrections you made to how I sort things
--   Rules you set, and what you asked me to hold back
--
-- Lines two and three name corrections and held topics. Neither was counted.
-- The screen's whole rule is that it names what will cross before anything
-- does, and it was naming two-fifths of it.
--
-- THE SECOND FAILURE, WHICH IS WORSE
--
-- `FieldStore.owesCrossingDecision` gates the screen on the count being above
-- zero — deliberately, so that somebody who paired on their first day is not
-- shown a dialog about an empty set. But a solo era that produced only
-- corrections and held topics counts zero. That person is never asked, and
-- because the RPC is the only door, their private rows have no way across.
-- Not a leak — the opposite — but "you can keep what you began here" quietly
-- becoming "you can never bring it" is still the app deciding something on
-- somebody's behalf and not saying so.
--
-- THE FIX
--
-- One `create or replace` over the counting function so it counts the five
-- tables the crossing moves, with the same per-table predicate the crossing
-- uses. Read-only, `stable`, no schema change, nothing to reverse but the
-- previous body.

begin;

create or replace function public.field_solo_history_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  -- Table for table, actor for actor, this is the WHERE clause of
  -- `field_share_solo_history()`. They are meant to be read side by side and
  -- to disagree loudly if either is edited alone.
  select coalesce(
    (select count(*) from public.field_life_items
      where couple_id = public.my_couple_id()
        and created_by = (select auth.uid()) and visibility = 'private')
    + (select count(*) from public.field_captures
        where couple_id = public.my_couple_id()
          and spoken_by = (select auth.uid()) and visibility = 'private')
    + (select count(*) from public.field_corrections
        where couple_id = public.my_couple_id()
          and corrected_by = (select auth.uid()) and visibility = 'private')
    + (select count(*) from public.field_standing_rules
        where couple_id = public.my_couple_id()
          and set_by = (select auth.uid()) and visibility = 'private')
    + (select count(*) from public.field_held_topics
        where couple_id = public.my_couple_id()
          and created_by = (select auth.uid()) and visibility = 'private'),
    0
  )::integer;
$$;

-- `create or replace` keeps the grants, but re-stating them costs nothing and
-- means this file can be read on its own.
revoke all on function public.field_solo_history_count() from public, anon;
grant execute on function public.field_solo_history_count() to authenticated;

commit;
