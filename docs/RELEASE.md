# The production release, prepared for Ryan to run

Project `tizunrayxyorzrvopnsw` (we-round1). Nothing in this file has been
executed. No production write has been made from this session.

## What was actually verified, and what was not

**Verified, from the remote database on 7 September 2026** via
`supabase migration list --linked` — which connects directly and needs no
Docker:

> The ledger stops at `20260820161957`. Twelve local migrations are unrecorded:
> `20260820210000`, `20260820230000`, `20260821120000`, `20260824120000`,
> `20260824130000`, `20260824140000`, `20260904120000`, `20260906120000`,
> and the four September ones below.

**Not verified: whether the first eight of those are already deployed.** The
ledger cannot tell "never applied" from "applied by hand in the dashboard",
and every route to reading the deployed schema from this machine was closed:
`supabase db dump` runs `pg_dump` inside a container and Docker is not
running, `psql` is not installed, and the Supabase connector was not
authorised.

So step 1 below is not a formality. **It is the gate**, and until it runs,
nothing here may be marked applied. A migration recorded as applied that was
never deployed is worse than one that is simply missing: the missing one still
shows up in `migration list`, and the mismarked one is invisible forever.

## Step 1 — Find out what is actually there

Open the SQL editor for `tizunrayxyorzrvopnsw` and run
`supabase/probes/which_migrations_are_applied.sql` in full. It writes nothing,
reads no relationship content, and returns one row per migration probing an
artifact only that migration creates.

Read every row. Two expectations, and a surprise in either direction stops the
release:

- The eight older ones may be `true` or `false`. Whichever they are, that is
  the answer step 2 uses.
- **The four September ones must all be `false`.** They are the release. A
  `true` there means one was applied by hand, and `db push` would then try to
  apply it a second time — go no further and say so.

The `20260907020000` probe is deliberately narrow: it looks for
`private.yours_open_lifecycle`. An earlier, withdrawn version of that
migration scoped the door with `statement_timestamp()` and was wrong about its
own mechanism (see the file's header). If production somehow has *that*
version, the probe reads `false` and the push replaces it, which is correct.

## Step 2 — Record the ones that are genuinely already there

For each of the eight older migrations the probe reported **`true`**, and only
those:

```bash
supabase migration repair --status applied 20260820210000
supabase migration repair --status applied 20260820230000
supabase migration repair --status applied 20260821120000
supabase migration repair --status applied 20260824120000
supabase migration repair --status applied 20260824130000
supabase migration repair --status applied 20260824140000
supabase migration repair --status applied 20260904120000
supabase migration repair --status applied 20260906120000
```

**Delete the line for any migration the probe reported `false`.** Leave it
unrepaired and step 3 will apply it normally, in version order, alongside the
rest. That is the whole branch: repair what is there, push what is not.

This step changes migration records only. It deploys nothing and touches no
account or content.

## Step 3 — Apply the release

```bash
supabase db push
```

With step 2 done, this applies exactly the migrations that are not yet
deployed, oldest first:

| Migration | What it does |
| --- | --- |
| `20260907000000_v2_write_grants` | Revokes `insert, update, delete` on `relationship_events`, `seasons` and `contextual_suggestions` from `anon` and `authenticated`. Supabase's bootstrap grant had left these writable; only a select-only RLS policy stood between a client and a fabricated Season. Every real write comes from a `security definer` RPC and is unaffected. |
| `20260907010000_deletion_attribution_cascade` | Lets account deletion finish. Three guards were rejecting the `on delete set null` cascade as though it were a client write, and two of them wrote the departing person's id back over the null. Also narrows what counts as a departure: every attribution column that goes to NULL must have named a profile that no longer exists, so a partner cannot forge the shape and strip authorship from the other's work. |
| `20260907020000_yours_lifecycle_scope` | Closes the Yours lifecycle door. `authenticated` loses the privilege to name a lifecycle column on `yours_entries` — it keeps `insert (client_id, body)` and `update (body)` — and the nine RPCs that write one now open and close the announcement on every path. Three that never wrote one stop opening it. |
| `20260907030000_lint_dead_locals` | Removes two unread locals so `db lint --fail-on warning` passes. Changes no behaviour. |

If a migration fails, **stop**. It is transactional and rolls back its own
changes; the database is where it was before that file started. Do not push
again until the failure is understood.

## Step 4 — Read it back

Run the probe from step 1 again. All twelve rows must now read `true`. Then:

```bash
supabase migration list --linked
```

Every local version must have a remote counterpart.

## Account and data effects

No account is recreated. Nothing is bulk-deleted. No content is rewritten.
No column holding anything either of you wrote is touched.

What changes is permissions and function bodies:

- Three V2 tables and `public.yours_entries` stop accepting direct client
  writes they should never have accepted. **The app does not use those
  writes** — `YoursSupabaseBackend` inserts `client_id, body` and updates
  `body`, which is exactly what stays granted — so nothing in the build breaks.
- Existing account-deletion cleanup can complete instead of failing partway.
- One constraint on `public.invitations` is relaxed from "a consumed
  invitation must name its consumer" to "consumption must record its time",
  because a consumed invitation whose consumer has left is a complete record
  about someone who is no longer here, not half a record.
- History repair changes only rows in `supabase_migrations.schema_migrations`.

This release deploys no feature.

## Recovery

- **Before you start, confirm the project's backup or PITR window in the
  dashboard.** A schema export is not a data backup and must not be treated as
  one.
- A failed migration rolls itself back — every file here is wrapped in
  `begin`/`commit`.
- `20260907000000` is grants only and is safe to run again.
- For an unexpected regression after a successful push, write a reviewed
  corrective migration. Do not hand-edit production, do not restore an older
  privacy guard reflexively, and do not attempt to undo a completed account
  deletion.
- Hold the TestFlight build if any step fails. The app is fine on the current
  production schema; it is the new privacy guarantees that would be missing,
  and shipping while claiming them is the thing to avoid.

## Addendum, 7 September: what the probe actually said

Three of the four September migrations came back `true`, which step 1 said
must not happen and which means they were applied by hand rather than by
`db push`. Only `20260907030000_lint_dead_locals` is outstanding. Two things
follow.

**First, the ledger records none of the twelve.** Applying SQL in the
dashboard does not write `supabase_migrations.schema_migrations`, which is the
whole reason that probe exists. So once `20260907030000` is in, all twelve
need recording — see the repair block below.

**Second, and this is the one that matters: the probe for `20260907010000`
cannot tell which version is deployed.** It looks for
`private.is_departure_attribution`, and *both* versions of that migration
create it — the original, which recognised the deletion cascade by its shape
alone, and the tightened one, which also requires the person each nulled
column named to be gone. If the original is what is in production, either
partner can still run

```sql
update public.field_life_items set created_by = null where id = <theirs>
```

and take the other's name off their own work. Run
`supabase/probes/verify_september_release.sql`, which reads bodies and
privileges instead of existence. Every row must read `ok = true`. If the
attribution row is `false`, re-apply `20260907010000` from this checkout.

That file also checks the half of `20260907020000` that actually does the
work — the column privileges on `yours_entries` — and confirms the withdrawn
`statement_timestamp` version is not what landed.

## Finishing it

1. Apply `supabase/migrations/20260907030000_lint_dead_locals.sql`.
2. Run `supabase/probes/verify_september_release.sql`. All rows `true`.
3. Run `supabase/probes/which_migrations_are_applied.sql`. All rows `true`.
4. Record all twelve, which deploys nothing:

```bash
supabase migration repair --status applied \
  20260820210000 20260820230000 20260821120000 20260824120000 \
  20260824130000 20260824140000 20260904120000 20260906120000 \
  20260907000000 20260907010000 20260907020000 20260907030000
```

5. `supabase migration list --linked` — every local version has a remote
   counterpart, and `db push` has nothing left to do.

Tell me the output of steps 2 and 3 and I will record the deployed migration
list in `docs/PRIVATE_BETA.md` against the exact build.
