-- Life's categories are open.
--
-- Five are given — care, calendar, food, money, home — and the classifier
-- starts a new one when a capture fits none of them. A CHECK against those
-- five would reject exactly the rows that behaviour exists to produce: the
-- item would file locally, the upsert would fail silently, and it would
-- vanish on the next load. That is the bug this migration prevents.
--
-- The shape is still constrained, because a category is a heading and not a
-- paragraph: lowercase letters and single spaces, at most two words, 3–18
-- characters. The app normalises to the same rule in `LifeCategory`.

alter table public.field_life_items
  drop constraint if exists field_life_items_category_check;

alter table public.field_life_items
  add constraint field_life_items_category_check
  check (
    category ~ '^[a-z]+( [a-z]+)?$'
    and char_length(category) between 3 and 18
  );

-- Categories are derived from the items that carry them, so this index is
-- what makes "which categories exist" cheap on read.
create index if not exists field_life_items_category_idx
  on public.field_life_items(couple_id, category)
  where is_done = false;
