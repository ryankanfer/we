-- Retire Yours as a destination. Keep what people wrote there.
--
-- WHY
--
-- The personal space was a room most people never found, and its lifecycle
-- (returns, renewals, held, let go) was a second product inside the first.
-- Privacy stays; it is now a property of any item ("Only me",
-- `20260923120000_private_by_choice.sql`).
--
-- WHAT HAPPENS TO THE WRITING
--
-- Moved, not destroyed. Every entry still in the space becomes a private
-- life item owned by its author, in the `notes` group:
--
--   title   the first line, shortened to 120 characters if it is longer
--   detail  everything after the first line — or the whole text, when the
--           first line had to be shortened, so nothing is lost
--
-- Each keeps its original id and creation time. Its lifecycle does not come
-- with it: renewals, returns and "held" are properties of the retired space,
-- and an ordinary item has none of them. Anything the owner had let go is
-- already gone (`private.yours_destroy`); nothing here resurrects it.
--
-- A prepared offer that was never sent becomes a private item the same way,
-- titled with its title and carrying its question as detail. One that was
-- sent already crossed, through the journey it opened, and needs nothing.
--
-- Rows stay private because they are written with `visibility = 'private'`
-- over a connection with no request claims, which both field triggers trust
-- (see `private.field_stamp_visibility` and `private.field_preserve_actor`).
--
-- WHY IT CAN REFUSE
--
-- Yours rows belong to a person; life items belong to a couple. An entry
-- whose author is in no couple has nowhere to go. That should be impossible —
-- the space was only reachable from inside the zones — but if it happens the
-- migration stops rather than dropping somebody's writing to make the numbers
-- work. Loud, so a person decides.
--
-- DELETION
--
-- Unaffected. `private.delete_my_account()` never named a yours table; it
-- relied on the profile cascade. The migrated rows are private field rows,
-- which it already deletes explicitly by author.

begin;

-- MARK: Nowhere to go --------------------------------------------------------

do $$
declare
  v_orphans integer;
begin
  select count(*) into v_orphans
  from (
    select owner_id from public.yours_entries
    union all
    select owner_id from public.yours_prepared_offers where sent_at is null
  ) rows
  where not exists (
    select 1 from public.couple_members cm where cm.profile_id = rows.owner_id
  );

  if v_orphans > 0 then
    raise exception
      'retire_yours: % row(s) belong to people in no couple; refusing to drop them',
      v_orphans;
  end if;
end;
$$;

-- MARK: Entries become private notes -----------------------------------------

with source as (
  select
    e.id,
    e.owner_id,
    e.created_at,
    btrim(e.body) as body,
    btrim(split_part(btrim(e.body), E'\n', 1)) as first_line
  from public.yours_entries e
)
insert into public.field_life_items (
  id, couple_id, title, category, owner, source, detail,
  created_by, created_at, visibility
)
select
  s.id,
  cm.couple_id,
  case
    when char_length(s.first_line) > 120 then left(s.first_line, 119) || '…'
    else s.first_line
  end,
  'notes',
  case cm.member_slot when 1 then 'a' when 2 then 'b' end,
  'captured',
  case
    when char_length(s.first_line) > 120 then s.body
    else nullif(btrim(substr(s.body, char_length(s.first_line) + 1)), '')
  end,
  s.owner_id,
  s.created_at,
  'private'
from source s
join public.couple_members cm on cm.profile_id = s.owner_id
on conflict (id) do nothing;

-- MARK: Unsent offers become private notes -----------------------------------

insert into public.field_life_items (
  id, couple_id, title, category, owner, source, detail,
  created_by, created_at, visibility
)
select
  o.id,
  cm.couple_id,
  o.title,
  'notes',
  case cm.member_slot when 1 then 'a' when 2 then 'b' end,
  'captured',
  o.question,
  o.owner_id,
  o.prepared_at,
  'private'
from public.yours_prepared_offers o
join public.couple_members cm on cm.profile_id = o.owner_id
where o.sent_at is null
on conflict (id) do nothing;

-- MARK: The sweep stops ------------------------------------------------------
--
-- Guarded exactly as the schedule was (`20260804092000_yours_sweep.sql`),
-- because `pg_cron` exists on the hosted platform and not in every stack
-- this file runs against.

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'yours-sweep') then
      perform cron.unschedule('yours-sweep');
    end if;
  end if;
end;
$$;

-- MARK: The space goes -------------------------------------------------------

do $$
declare
  r record;
begin
  for r in
    select n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname like 'yours\_%'
  loop
    execute format(
      'drop function if exists %I.%I(%s) cascade',
      r.nspname, r.proname, r.args
    );
  end loop;
end;
$$;

drop table if exists public.yours_releases cascade;
drop table if exists public.yours_prepared_offers cascade;
drop table if exists public.yours_owner_state cascade;
drop table if exists public.yours_entries cascade;

commit;
