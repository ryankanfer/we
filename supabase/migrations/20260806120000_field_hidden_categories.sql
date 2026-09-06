-- Putting a built-in LIFE group away.
--
-- Every other category in this app is derived. `FieldStore.lifeCategories`
-- reads them off the items that carry them and prepends the seven built-ins,
-- on the argument written into its doc comment: "a category is not a thing a
-- couple owns, it is the shape of what they have written down." A grown
-- category whose last item leaves stops existing, with nothing to clean up.
--
-- That is why deleting a *grown* group needs no table at all — moving its
-- items out is the deletion, and it is expressed as ordinary item upserts.
--
-- A built-in cannot work that way. `LifeCategory.builtIn` puts Care, Food,
-- Trips, Watchlist, Buys, Money, and Home on the screen whether or not
-- anything is in them, so emptying one leaves the word behind. A couple who
-- has never once used Watchlist has no way to stop looking at it. This table
-- is the one place a category becomes a stored entity, and it exists solely
-- so that absence can be recorded.
--
-- WHAT A ROW HERE MEANS, AND WHAT IT DOES NOT
--
-- It means: do not draw this word on LIFE. That is all. It is a display fact
-- and deliberately not a routing one. The classifier still sees every
-- category, Today still surfaces items out of a put-away group, search still
-- finds them, and the calendar still shows their dates. If a row here could
-- change where a new capture is filed, "put away" would quietly have become
-- "muted", and a vet appointment in a put-away Care would vanish. See
-- `FieldStore.visibleCategories`, which is a sibling to `lifeCategories` and
-- never a filter on it.
--
-- WHY IT IS COUPLE-SCOPED AND NOT PER PERSON
--
-- Because LIFE is one shared page. Two people looking at different sets of
-- headings for the same items is not a preference, it is two apps. So a hide
-- is a joint decision, both of them can make it, both of them can undo it,
-- and the copy on screen says so — "Hide Care from LIFE for both of you?"
--
-- `hidden_by` is recorded for the log and never rendered. The copy stays
-- partner-neutral in both directions ("Care is put away", never "you put Care
-- away") because the other person may be the one who did it, and telling
-- somebody they did something they did not is worse than saying nothing.
--
-- WHY THERE IS NO CHECK CONSTRAINT ON `category`
--
-- The obvious one restricts the value to the seven built-ins. That would copy
-- `LifeCategory.builtIn` into SQL, where it would drift the first time the
-- Swift list changes. The guard lives instead in `visibleCategories`, which
-- honours a row here only when the category is built-in — so a row for a
-- grown category, whether stale, hand-edited, or from a future bug, is inert
-- rather than able to hide a list that still has items in it. Same posture as
-- `LifeCategory.reserved`: make it impossible rather than merely unlikely.
--
-- Reconciliation-safe: every statement is idempotent.

begin;

-- MARK: The table -----------------------------------------------------------

create table if not exists public.field_hidden_categories (
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  -- The raw category value, matching `field_life_items.category` — lower
  -- case, one or two words. Stored as text rather than an enum for the same
  -- reason that column is: the set of categories is not knowable at compile
  -- time, and it stays readable in the table editor.
  category text not null,
  -- For the log, never for the screen. See above.
  hidden_by uuid references public.profiles(id) on delete set null,
  hidden_at timestamptz not null default now(),
  primary key (couple_id, category)
);

alter table public.field_hidden_categories enable row level security;

-- MARK: Access --------------------------------------------------------------
--
-- The plain couple-scoped shape from the generated policies in
-- `20260730120000_field_zones.sql`. There is no `visibility` column here, so
-- the three-way insert/update/delete split that
-- `20260803180000_field_solo_visibility.sql` had to impose on
-- `field_life_items` does not apply: there is no such thing as a hide one
-- partner can see and the other cannot, and a table where that were possible
-- would put the two of them on different pages.

drop policy if exists field_hidden_categories_select
  on public.field_hidden_categories;
create policy field_hidden_categories_select
  on public.field_hidden_categories
  for select using (couple_id = (select public.my_couple_id()));

drop policy if exists field_hidden_categories_write
  on public.field_hidden_categories;
create policy field_hidden_categories_write
  on public.field_hidden_categories
  for all
  using (couple_id = (select public.my_couple_id()))
  with check (couple_id = (select public.my_couple_id()));

-- MARK: Who did it ----------------------------------------------------------
--
-- Stamped by the database rather than trusted from the client, matching the
-- posture of `private.field_preserve_actor` in
-- `20260731230000_field_actor_integrity.sql`: a column recording who did
-- something is worth nothing if the doer supplies it.
--
-- Only on insert. Bringing a group back is a delete, and a hide that is
-- re-applied is a fresh row, so there is no update path that would need to
-- preserve an earlier author.

create or replace function private.field_stamp_hidden_by()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.hidden_by := (select auth.uid());
  return new;
end;
$$;

revoke all on function private.field_stamp_hidden_by() from public, anon, authenticated;

drop trigger if exists field_hidden_categories_stamp_actor
  on public.field_hidden_categories;
create trigger field_hidden_categories_stamp_actor
  before insert on public.field_hidden_categories
  for each row execute function private.field_stamp_hidden_by();

-- MARK: Realtime ------------------------------------------------------------
--
-- One partner puts Watchlist away; the other's LIFE has to stop drawing it
-- without a foreground. A table read by `load()` and missing from
-- `FieldSupabaseBackend.observedTables` reads to the person holding the phone
-- as the app being slow rather than as a subscription being wrong — see the
-- comment above that array.

do $$
declare
  v_table text;
begin
  foreach v_table in array array['field_hidden_categories']
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

commit;
