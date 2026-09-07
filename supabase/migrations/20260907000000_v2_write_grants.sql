-- Three V2 tables were given `grant select` and nothing else, which read as
-- read-only. It was not: Supabase's bootstrap grants all privileges on new
-- public tables to `authenticated` by default, so INSERT survived on every
-- one of them. Nothing could actually be forged — RLS is enabled and each
-- table carries a select-only policy — but the only thing standing between a
-- client and a fabricated Season was that single policy. `public.plans`
-- already establishes the pattern
-- (20260725062000_private_declines_and_shared_item_rpcs.sql:379): revoke the
-- writes, and let the definer RPCs be the only way in.
--
-- Every write to these tables comes from a `security definer` function
-- (`refresh_contextual_suggestions`, `confirm_contextual_suggestion`,
-- `create_ready_season`), which runs as the owner and is unaffected.
--
-- Asserted by v2_native.test.sql:129-151 — three assertions that had never
-- executed, because the schema lane died at an earlier migration before
-- pgTAP ever ran.

revoke insert, update, delete on public.relationship_events
  from anon, authenticated;
revoke insert, update, delete on public.seasons
  from anon, authenticated;
revoke insert, update, delete on public.contextual_suggestions
  from anon, authenticated;
