-- The column the whole journey surface reads, missing in production.
--
-- Signing in fails with `column field_journeys.subject_references does not
-- exist`. Confirmed on 7 September 2026 against `tizunrayxyorzrvopnsw`: every
-- other column the client selects from `field_journeys` resolves, and this one
-- alone returns 42703.
--
-- `20260808120000_shared_journeys_v1` is recorded as applied, and its
-- `create table public.field_journeys` names the column — but it is a
-- `create table if not exists`, so whichever earlier form of the table was
-- already there was left exactly as it stood. A column added inside a guarded
-- CREATE reaches a fresh database and no other. That is the same failure mode
-- the migration probe was written for: the ledger records a version number,
-- not which version of the file ran.
--
-- So this migration does not re-run that one. It states the column
-- unconditionally, on its own, in the one form that lands whether the table is
-- old or new.
--
-- The trigger writes from `20260819140000_journey_subject_accumulation` have
-- been failing on this too: `private.refresh_journey_subjects` updates this
-- column, and plpgsql bodies are not resolved until they run, so the function
-- was created cleanly and threw at every life item or evidence row attached to
-- a journey. Adding the column repairs the accumulation as well as the read.

begin;

alter table public.field_journeys
  add column if not exists subject_references jsonb not null
    default '[]'::jsonb;

comment on column public.field_journeys.subject_references is
  'What the journey was read from, accumulated over its life by '
  'private.refresh_journey_subjects. The room binds to the couple''s existing '
  'records through this rather than copying them.';

-- Rebuild provenance for every journey that has been running without it.
--
-- Not a cosmetic backfill: `SharedJourneyCapabilityPolicy` earns the criteria
-- surface at three references, and every journey here has been sitting at the
-- default of zero for as long as the column has been absent. The subjects are
-- not invented — `refresh_journey_subjects` reads them back from the insight,
-- the shared evidence and the shared Life the journey already gathered.
--
-- Guarded on the function existing so this migration also applies to a
-- database that has not reached 20260819140000 yet; there the default is
-- already the right answer and there is nothing to rebuild.
do $$
declare
  v_journey uuid;
begin
  if to_regprocedure('private.refresh_journey_subjects(uuid)') is null then
    return;
  end if;

  for v_journey in select id from public.field_journeys loop
    perform private.refresh_journey_subjects(v_journey);
  end loop;
end;
$$;

commit;
