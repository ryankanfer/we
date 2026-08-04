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
order by 1;
