-- Which migrations are actually applied?
--
-- Read-only. Answers the question `supabase migration list` cannot, because
-- that reads `supabase_migrations.schema_migrations` — a ledger written only by
-- `db push` / `migration up`. SQL run by hand in the dashboard editor applies
-- the schema and records nothing, so an empty Remote column means "not pushed",
-- never "not applied".
--
-- Each row checks an artifact the migration is the only thing that creates.

select '20260727190000_we_v2_native' as migration,
       to_regclass('public.signal_consents') is not null as applied
union all
select '20260729193000_private_answers_shared_directions',
       to_regclass('public.shared_directions') is not null
union all
select '20260730120000_field_zones',
       to_regclass('public.field_life_items') is not null
union all
select '20260730210000_field_onboarding_answers',
       exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'field_identity'
           and column_name = 'lives_together'
       )
union all
select '20260731090000_open_life_categories',
       exists (
         select 1 from pg_indexes
         where schemaname = 'public'
           and indexname = 'field_life_items_category_idx'
       )
union all
-- Vacuously true if `field_ours_items` is empty — this one is a data
-- migration, so it has no schema artifact to point at.
select '20260731140000_one_filing_system',
       not exists (
         select 1 from public.field_ours_items o
         where not exists (
           select 1 from public.field_life_items l where l.id = o.id
         )
       )
union all
select '20260731230000_field_actor_integrity',
       to_regprocedure('private.field_preserve_actor()') is not null
union all
select '20260802120000_field_held_topic_client_id',
       exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'field_held_topics'
           and column_name = 'client_id'
       )
union all
-- The one that matters most right now: the client already writes `client_id`
-- and upserts on (couple_id, client_id) for corrections and standing rules.
-- False here means those two writes fail against this database today.
select '20260803120000_field_mutation_idempotency',
       exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'field_corrections'
           and column_name = 'client_id'
       )
union all
select '20260808120000_shared_journeys_v1',
       to_regclass('public.field_journeys') is not null
union all
-- Everything below is what `supabase migration list --linked` reports as
-- unpushed as of 2026-09-06. The ledger cannot tell "never applied" from
-- "applied by hand in the dashboard", which is the whole reason this file
-- exists, so each row probes an artifact only that migration creates.
select '20260820210000_ceremony_acknowledgements',
       to_regclass('public.ceremony_acknowledgements') is not null
union all
-- The eight pigment families. The check constraint is the artifact: the
-- column predates this migration, the constraint naming these values does not.
select '20260820230000_pigment_palette',
       exists (
         select 1 from pg_constraint
         where conname = 'field_identity_swatch_a_check'
           and pg_get_constraintdef(oid) like '%burgundy%'
       )
union all
select '20260821120000_ceremony_eligibility',
       exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'couples'
           and column_name = 'ceremony_required'
       )
union all
select '20260824120000_invitation_greeting',
       to_regprocedure('public.invitation_greeting(text)') is not null
union all
select '20260824130000_invitation_decline',
       to_regprocedure('public.decline_invitation(text)') is not null
union all
-- Push. False here means arrival announcement has no table to write to,
-- independent of whether APNs is configured.
select '20260824140000_arrival_notification',
       to_regclass('public.device_tokens') is not null
union all
-- Replaces functions rather than creating objects, so the probe reads a
-- body. `FOR KEY SHARE` in `prepare_shared_item` arrives only here: the
-- 20260725062000 version of the same function has no row lock at all.
-- False here means the space guards described in that migration's header
-- (a NULL comparison falling through for a caller in no space) are still open.
select '20260904120000_shared_item_and_space_guards',
       exists (
         select 1
         from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'private'
           and p.proname = 'prepare_shared_item'
           and pg_get_functiondef(p.oid) ilike '%for key share%'
       )
order by 1;
