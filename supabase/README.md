# WE database

The trust model is enforced here, not only in Swift. A reveal exposes a topic
and a sender but never an answer; each person answers privately and answers
appear only once both have submitted; a decline is owner-only; a withdrawal
leaves no partner-side trace. Every one of those is a database rule, and the
pgTAP suites are the proof.

## Running the suites

CI runs them on every change under `supabase/` (`.github/workflows/database.yml`).
To run them locally against a scratch Postgres with pgTAP installed:

```bash
createdb we_test
psql -d we_test -f supabase/tests/harness/00_supabase_shim.sql
for f in supabase/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -q -d we_test -f "$f"; done
for s in supabase/tests/*.test.sql; do psql -q -At -d we_test -f "$s"; done
```

`supabase test db` against a local Supabase stack works too and is more
faithful. The harness exists so CI does not need Docker: it creates the objects
the platform normally provides (the `anon`/`authenticated`/`service_role` roles,
`auth.users`, `auth.uid()`, the realtime publication, and Supabase's default
grants on `public`). Point it at a scratch database only.

A suite that reports zero assertions is a **failure**, not a pass. Both suites
previously aborted on their first assertion and reported nothing for months;
the CI job now treats an empty result as a failure for that reason.

## Migrations

Migrations are append-only. Never edit one that has been applied anywhere — CI
fails a pull request that modifies an existing file. Fix forward with a new
timestamped migration instead.

## Drift

**The live project is ahead of this repository.** As of this writing the project
`we-round1` had applied 35 migrations; this repository contains 9. The 27
missing ones were applied outside the repository, and the project's
`schema_migrations` rows recorded no SQL for them — so their text cannot be
recovered from the database. They exist only wherever they were authored.

What that means concretely:

- This repository cannot rebuild the live project.
- The live schema has roughly 38 tables this repository has never seen
  (`field_*`, `yours_*`, `journey_*`, `share_*`, `invitations`, `device_tokens`),
  plus cron jobs, a storage bucket, and an external synthesis worker.
- Some live RPC signatures no longer match what the Swift app in this
  repository sends. `submit_response` now takes a required
  `p_ai_processing_consent` argument that the app does not pass, so the call
  does not resolve. `join_couple` now redeems a row in `invitations`.

Check the current state at any time:

```bash
supabase/scripts/check-drift.sh
```

### Recovering

Pick one, deliberately:

1. **Recover the SQL.** Find the branch or machine where those 27 migrations
   were written and commit them. This is the only option that preserves
   history. Try this first.
2. **Baseline from the project.** If the SQL is genuinely gone, take a
   schema-only dump and commit it as one squashed baseline, then repair the
   migration history so the project and repository agree:

   ```bash
   supabase db dump --linked -f supabase/migrations/<timestamp>_baseline.sql
   supabase migration repair --linked --status applied <timestamp>
   ```

   History before the baseline is lost, but the repository becomes able to
   rebuild the schema again.

Until one of those happens, treat the live project as the source of truth and
do not run `supabase db push` from this repository expecting it to reproduce
production.

New migrations added here are still safe to push: they are timestamped after
everything the project has applied and only touch objects that exist in both.
