# Dual-sided lifecycle run

Two authenticated sessions driven through the whole relationship lifecycle
against a throwaway PostgreSQL cluster. It exists to answer one question before
release: does the trust model hold when two real people use it, not just when
one does.

```bash
./supabase/probes/dual-sided/run_dual_sided.sh
```

The script creates a fresh cluster, applies `supabase_shim.sql` (the small part
of the Supabase platform the migrations depend on: the `auth` schema,
`auth.uid()`, the three API roles, the realtime publication), applies every file
in `supabase/migrations` in order, then runs `dual_sided_lifecycle.sql` and
prints a pass/fail line per assertion. It exits non-zero on any failure and
never touches a hosted project.

Requires a PostgreSQL 16 binary set (`initdb`, `pg_ctl`, `psql`); override the
location with `PGBIN`.

## What it covers

| Phase | Both sides |
| --- | --- |
| 01 sign-up | profiles created from auth metadata |
| 02 pairing | join code, distinct hues, seeded shared field, bad code refused |
| 03 private reflection | unreadable by the partner, unforgeable in their name |
| 04 reveal request | topic and sender visible, answer not; acceptance opens it |
| 05 private answers | neither answer readable until both are in, then both at once |
| 06 resolution | a mutual item settles and cannot be reopened |
| 07 decline | owner-only; the initiator keeps seeing quiet waiting |
| 08 withdrawal | returns to rest, and grace outlives the invitation |
| 09 Life | shared responsibility, handoff offered and accepted |
| 10 Ahead | plan visible to both, approaches reveal together |
| 11 presence and consent | presence shared, signal consent private |
| 12 outsider | reads nothing, writes nothing, cannot touch consent |
| 13 relationship end | sanitized archive for the survivor, nothing for the leaver |

This complements the pgTAP suites in `supabase/tests`, which assert schema and
policy shape. This one asserts lived behavior across two sessions.

These files live under `supabase/probes/`, not `supabase/tests/`, because
`supabase test db` runs pg_prove over everything in the tests directory. A
helper that is not a pgTAP test fails the whole schema lane when it lands
there — which is exactly what it did.
