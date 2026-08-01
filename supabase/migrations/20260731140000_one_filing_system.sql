-- One filing system: Ours becomes Life.
--
-- The app used to have three destinations — Life, Ours, and Us · Horizons —
-- where Ours was a drawer inside Us that filed under its own name. Two names
-- for one place is one name too many, and it confused the person who designed
-- it. So Ours is gone as a concept, and Us can no longer be filed to at all:
-- it is what Life becomes when somebody answers a question about it.
--
-- What made an Ours item different was never its table. It was that it had no
-- date. That survives intact — an undated Life item cannot reach the surfacing
-- threshold, so a film sits in Watchlist for a year without once asking
-- anything of anybody.

-- The four lists become four categories. Eating merges into Food, because a
-- craving and a dated food task are the same subject at different urgencies,
-- and Places becomes Trips, which is the word people actually use.
insert into public.field_life_items (
  id, couple_id, title, category, owner, due_on, closes_at,
  cluster_id, source, detail, is_time_critical, is_done, created_by, created_at
)
select
  o.id,
  o.couple_id,
  o.title,
  case o.list
    when 'watchlist' then 'watchlist'
    when 'eating'    then 'food'
    when 'places'    then 'trips'
    else                  'notes'
  end,
  -- `both_added` is the highest-value inference the app makes, and shared
  -- ownership is how the rest of the app already renders it.
  case when o.both_added then 'shared' else 'a' end,
  null, null, null,
  'captured',
  o.coincidence_note,
  false,
  false,
  o.added_by,
  o.added_at
from public.field_ours_items o
where not exists (
  select 1 from public.field_life_items l where l.id = o.id
);

-- `field_ours_items` is deliberately left in place, unread. The rows are a
-- couple's own history, and a migration that can lose them in exchange for a
-- tidier schema is not a trade worth making. Drop it in a later migration,
-- once the copy above has been verified against real data.
comment on table public.field_ours_items is
  'Deprecated. Copied into field_life_items by 20260731140000. Not read by the app.';

-- Corrections round-trip through a destination label, and a couple's log
-- predates this change. The app parses the old `OURS · EATING` form on read
-- (see LifeCategory.init(legacyLabel:)), so nothing here needs rewriting —
-- but new rows are written as bare category names.
comment on column public.field_corrections.original_destination is
  'A Life category name. Rows written before 20260731140000 hold a legacy label such as OURS · EATING.';

-- A horizon now records which Life items it was built from, because that is
-- the only way one is ever created: the app asked whether a thing said twice
-- was real, and somebody said yes. The items stay where they are — this is a
-- pointer, not a move — so a plain array of ids is the whole relationship.
alter table public.field_horizons
  add column if not exists linked_life_item_ids text[] not null default '{}';
