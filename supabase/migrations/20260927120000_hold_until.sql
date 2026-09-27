-- Hold until: Only me, framed as time rather than a wall.
--
-- WHY
--
-- `20260923120000_private_by_choice.sql` made any capture "Only me". Private
-- is meant to mean *not ready yet*: a gift idea, a surprise, something still
-- being worked out. This gives that "yet" a day. The author can pick one, and
-- on it WE asks the author, and only the author, whether it is time to share.
-- Nothing is ever shared automatically; the crossing is still the author's
-- own `private -> shared` write, exactly as before.
--
-- WHAT CHANGES
--
--   1. `field_life_items.hold_until`, a nullable date.
--   2. A BEFORE trigger that clears it whenever the row is shared. Once a
--      partner can read the row, when it was meant to arrive is nobody's
--      business, and it has no further job to do. Named with a `zz_` prefix
--      so it fires after `field_visibility_integrity` (`field_stamp_visibility`) has settled what the row's
--      visibility actually is (BEFORE triggers fire in name order).
--
-- No new policy is needed. A private row is already readable and writable by
-- its author alone (`20260803180000_field_solo_visibility.sql`), so the date
-- on it is too.

begin;

alter table public.field_life_items
  add column if not exists hold_until date;

comment on column public.field_life_items.hold_until is
  'Only me items: the day WE offers the author the chance to share. Cleared on share.';

create or replace function private.field_clear_hold_on_share()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.visibility is distinct from 'private' then
    new.hold_until := null;
  end if;
  return new;
end;
$$;

revoke all on function private.field_clear_hold_on_share()
  from public, anon, authenticated;

drop trigger if exists zz_field_life_items_clear_hold on public.field_life_items;

create trigger zz_field_life_items_clear_hold
  before insert or update on public.field_life_items
  for each row
  execute function private.field_clear_hold_on_share();

commit;
