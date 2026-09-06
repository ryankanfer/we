-- Held topics: give the row the app's own identity.
--
-- `field_held_topics` had no insert path at all. `FieldSupabaseBackend.setHeld`
-- was an UPDATE guarded by `UUID(uuidString: topic.id)`, and the ids the app
-- holds things under are routes, not uuids — `promote:japan`,
-- `occasion:<cluster>:<item>`. Every one of those failed the guard and was
-- dropped in silence. The ids that *were* uuids updated zero rows, because no
-- row had ever been inserted.
--
-- The read path had the mirror of the same bug: `HeldTopicRow.id` is the
-- database uuid, so even a hold that somehow existed came back identified by
-- something `FieldIntelligence` never matches against — it compares against the
-- route id. A held topic could not survive a round trip in either direction.
--
-- What this cost the product: "Not this year" and "Not related" were forgotten
-- on relaunch and the app asked again. It is the one promise the app makes in
-- its own voice — "the app does not ask twice" — and it was the promise least
-- able to keep itself.
--
-- `client_id` carries the route id. `id` stays the uuid primary key so existing
-- rows, foreign keys, and the realtime publication are untouched.
--
-- Additive and safe against an older client: the only writer of this table in
-- any shipped build is an UPDATE that names `id`, and nothing has ever
-- inserted, so a backfilled NOT NULL column cannot break a build already in
-- somebody's hands.

alter table public.field_held_topics
  add column if not exists client_id text;

update public.field_held_topics
set client_id = id::text
where client_id is null;

alter table public.field_held_topics
  alter column client_id set not null;

-- The upsert target. Scoped to the couple, because two couples holding
-- `promote:japan` are two unrelated decisions.
create unique index if not exists field_held_topics_client_idx
  on public.field_held_topics(couple_id, client_id);

-- MARK: Immutability --------------------------------------------------------
--
-- `client_id` is the identity the app matches on. A row whose client_id moves
-- is a decision reattached to a different question, which is exactly the class
-- of thing the actor-integrity trigger exists to prevent elsewhere. This table
-- carries no actor columns, so it gets its own guard rather than joining
-- `private.field_preserve_actor()`.

create or replace function private.field_held_topic_freeze_client_id()
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

revoke all on function private.field_held_topic_freeze_client_id()
  from public, anon, authenticated;

drop trigger if exists field_held_topic_client_id_integrity
  on public.field_held_topics;

create trigger field_held_topic_client_id_integrity
  before update on public.field_held_topics
  for each row execute function private.field_held_topic_freeze_client_id();
