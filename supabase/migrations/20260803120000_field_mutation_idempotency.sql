-- Make every Field write survive being sent twice.
--
-- The outbox (Phase 1b) exists because a write that fails offline must be
-- retried later. That guarantee is only worth having if a retry is safe, and
-- the dangerous case is not the one that failed — it is the one that
-- *succeeded* and then timed out on the way back. The client cannot tell those
-- apart. It has to be able to send again and have the second send do nothing.
--
-- Most Field writes already are safe, by accident of already being upserts on
-- a client-generated id: life items, horizons, clusters, held topics, identity,
-- and the daily moment all name their own key. Deletes are naturally
-- idempotent, and answering a question is an UPDATE. Captures carry the
-- receipt's UUID, which is the same identity the materialised Life item takes,
-- so they become an upsert on `id` in the client with no schema change at all.
--
-- That leaves exactly two tables that are plain INSERTs with no client key:
--
--   field_corrections   — the training signal the classifier learns from
--   field_standing_rules — a rule somebody set, once
--
-- Sent twice, each of those becomes two rows. Two corrections double the
-- weight of one opinion about what a word means. Two standing rules are the
-- same sentence printed twice on the surface that is meant to say what the
-- couple has decided. Both are quiet, and neither is recoverable by looking
-- at the data afterwards, because a genuine duplicate and an accidental one
-- are the same row.
--
-- The shape is the one 20260802120000 established for held topics: a
-- `client_id` carrying the app's own identity for the row, unique within the
-- couple, with `id` left alone as the uuid primary key so existing rows,
-- foreign keys, and the realtime publication are untouched.
--
-- Additive, per the plan's migration discipline (1f). The column is nullable
-- for exactly as long as it takes to backfill, and the *current* shipped
-- client — which sends neither column — keeps inserting successfully
-- throughout, because a null client_id conflicts with nothing.

-- MARK: Corrections ---------------------------------------------------------

alter table public.field_corrections
  add column if not exists client_id text;

update public.field_corrections
set client_id = id::text
where client_id is null;

alter table public.field_corrections
  alter column client_id set not null;

create unique index if not exists field_corrections_client_idx
  on public.field_corrections(couple_id, client_id);

-- MARK: Standing rules ------------------------------------------------------

alter table public.field_standing_rules
  add column if not exists client_id text;

update public.field_standing_rules
set client_id = id::text
where client_id is null;

alter table public.field_standing_rules
  alter column client_id set not null;

create unique index if not exists field_standing_rules_client_idx
  on public.field_standing_rules(couple_id, client_id);

-- MARK: Immutability --------------------------------------------------------
--
-- `client_id` is what makes a retry a no-op. A row whose client_id can move is
-- a row that can be made to collide with — or escape — a different mutation,
-- which turns the idempotency guarantee above into a way to overwrite somebody
-- else's correction. It is frozen after insert for the same reason the actor
-- columns are.
--
-- A separate guard rather than another branch inside
-- `private.field_preserve_actor()`: that function is a single 200-line
-- `create or replace` covering ten tables, and re-declaring the whole of it to
-- add two lines is how a migration silently reverts whatever changed in it
-- since. This is the pattern 20260802120000 chose for the same reason, written
-- once here so both tables share it.

create or replace function private.field_freeze_client_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.client_id is distinct from old.client_id then
    new.client_id := old.client_id;
  end if;
  return new;
end;
$$;

revoke all on function private.field_freeze_client_id()
  from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'field_corrections',
    'field_standing_rules'
  ]
  loop
    execute format(
      'drop trigger if exists field_client_id_integrity on public.%I',
      v_table
    );
    -- After field_actor_integrity, which sorts earlier: the actor is settled
    -- first, then the identity that decides whether this is a new row at all.
    execute format(
      'create trigger field_client_id_integrity
         before update on public.%I
         for each row execute function private.field_freeze_client_id()',
      v_table
    );
  end loop;
end;
$$;
