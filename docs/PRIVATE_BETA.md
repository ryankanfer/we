# WE private beta: readiness record

**Status: ready to upload — not verified for everyday use.**

Those are two different things and this file never merges them. The first is
reachable from a desk. The second is only reachable after both phones have the
build, and nothing here claims it.

Scope: everyday pages, interaction, saving, privacy and useful interpretation.
New-relationship/archive work stays deferred at Ryan's request — do not
implement it and do not run departure/replacement tests in this pass. The
decision it is waiting on (read-only retention of previously shared material,
new relationships starting empty) is preserved for later.

---

## The build

| | |
| --- | --- |
| Version / build | **1.0 (2)** |
| Source commit | `bc8cd5e` on `beta/p0-p1-execution` (PR #14) |
| Backend | production `tizunrayxyorzrvopnsw` (we-round1) |
| Minimum iOS | 26.2 |
| Archive | `~/Library/Developer/Xcode/Archives/2026-09-07/WE 1.0 (2).xcarchive` |

Verified by reading the archive's own bundle, not the build settings: version
1.0, build 2, minimum iOS 26.2, `https://tizunrayxyorzrvopnsw.supabase.co`,
Shared Journeys `YES`, Share Inbox `NO`, widget and share extensions embedded,
no `aps-environment`.

The build number is 2 because three earlier local archives are all 1.0 (1) and
an upload has to be distinguishable from them.

### What is in it

- Everyday capture, retrieval, correction
- Yours, including the lifecycle and the sanctioned way out of held
- Shared questions, consent, proposal and approval
- Offline save and recovery
- Widgets — **built and embedded, not yet verified on a distributed build**
- Shared Journeys — **enabled, and its production path is not yet verified**

### What is not in it, and must not be promised

- **Share Sheet importing.** `WEShareInboxEnabled` is `NO` in Release, so
  `WEFeatureFlags.shareInboxEnabled` is false and the entry point in
  `FieldLifeZone` is absent. The embedded `WEShareExtension.appex` is not
  evidence to the contrary.
- **Push notifications.** Not a decision — a fact, and here is the evidence:
  the provisioning profile for `com.ryankanfer.WE` carries no
  `aps-environment`, so the App ID does not have the capability. Restoring the
  entitlement before Ryan enables it would break signing on every device build.
  The arrival notification is built and tested (`supabase/functions/
  announce-arrival`) and its absence is a designed-for path, so no copy
  promises it and none had to be removed. B's arrival reaches A on next open.
- **Live Activity push updates.** No push token, so no remote updates.
- **New relationships and archive.** Deferred.

---

## Uploading it

Export needs an Apple ID signed into Xcode, and this session had none —
`exportArchive` failed with `No Accounts` and could not create a distribution
profile. So the last step is Ryan's:

1. Xcode → Settings → Accounts → sign in, if not already.
2. Window → Organizer → Archives → **WE 1.0 (2)**, dated 7 September 2026.
3. **Distribute App** → **TestFlight & App Store** → **Distribute**. Let Xcode
   manage signing; it creates the distribution profile that the development
   ones on this machine are not.
4. Wait for App Store Connect to finish processing, add the tester, send the
   invitation.

Both phones must end up on **1.0 (2)**. A mismatch invalidates the checklist.

---

## Before it is a release: the database

`docs/RELEASE.md` is the runbook. **It has not been executed** and no
production write has been made from this session.

Read directly from the remote on 7 September 2026 via `supabase migration list
--linked`: the ledger stops at `20260820161957`, with twelve local migrations
unrecorded.

**Not verified:** whether the eight older unrecorded migrations are actually
deployed. Every route was closed from this machine — `supabase db dump` runs
`pg_dump` in a container and Docker is not running, `psql` is not installed,
and the Supabase connector was not authorised. That is why step 1 of the
runbook is a gate and not a formality, and why nothing may be marked applied
before it runs.

The app runs correctly against the current production schema — the release
only removes direct-write permissions the app never uses. What is missing
until it lands is the guarantees, not the function. Do not claim them before
then.

---

## What was fixed in this pass

**The Yours lifecycle door** (`20260907020000`, rewritten). The previous
version scoped the door with `statement_timestamp()` and was wrong about its
own mechanism: that value is set once per client Query message, not per
statement, so

```sql
select public.yours_hold('...'); update public.yours_entries
  set state = 'held', ready_at = now() + interval '10 years';
```

sent as one body walked straight through. It is also exactly why the design
appeared to work — the statements inside an RPC body share a timestamp for the
same reason. Replaced with two layers: `authenticated` now holds
`insert (client_id, body)` and `update (body)` on `yours_entries` and nothing
else, so naming a lifecycle column is a privilege error with no ambient state
involved; and the announcement is closed by the RPCs that open it, on every
path, rather than cleverly scoped. Three RPCs that never wrote a lifecycle
column stop opening it at all.

**Forged departures** (`20260907010000`, tightened). `is_departure_attribution`
recognised the deletion cascade by its shape, and a partner could type that
shape: the Field tables are directly client-writable with
`couple_id = my_couple_id()` as the whole predicate, so
`update public.field_life_items set created_by = null where id = <theirs>`
returned from the guard before a single check. Either partner could strip
authorship from anything in their own space. Every column that goes to NULL
must now have named a profile that no longer exists — which account deletion
arranges and a client cannot.

**Silently lost unsent writing** (`FieldOutbox`). An undecodable queue was
moved aside and an empty array returned, with no path to any view. The app
carried on working perfectly and the item was simply not there next time, with
no reason given — the one case where somebody genuinely lost something was the
one case that said nothing. The fact now reaches `FieldStore` and the zone
shell says it once, with a single button: there is nothing to retry, because a
queue that could not be decoded cannot be sent, and offering an action would be
a second untruth. It does not claim recovery and cannot name what was lost.
The feedback report gains a count of such files — never a name or a byte.
`FieldStateCache` is left silent on purpose; it is re-derivable from the server.

**Retries cannot lose or duplicate.** Audited and now asserted rather than
commented: `stage()` reaches disk before the interface acknowledges; `flush()`
stops at the first failure and keeps order; queued writes to the same subject
compact to the newest; every backend write upserts on a client-generated id. A
new test covers the seam `remove(_:)` sits on — a send that lands and a
queue-shrink that does not — and proves the relaunch resends once and writes
once. If any mutation case ever stopped upserting, that test fails; nothing
else would have noticed.

---

## Test results

Distinguished by where they ran, because that is the only thing that makes
them worth anything.

### On the real CI, against the exact code

Run `34136805479` on the database commit: **all four checks green.**

- Schema + privacy contract — `supabase test db` from a from-scratch database
  plus `db lint --fail-on warning`. This is what proves the rewritten migration
  applies, that a client `update … set state='held'` is now refused with
  `42501` rather than silently neutralised, that the multi-statement bypass
  above fails, that the door is shut after an RPC returns *and* after one whose
  write matched no rows, and that A cannot take B's name off B's work while B
  is still here.
- Private-to-shared contract — Deno edge-function tests.
- iOS build + unit.
- Critical UI smoke.

### Locally, on a simulator

- Unit: **627 passed, 3 skipped, 0 failed** (`/tmp/we-beta-unit-7.xcresult`).
  The three skips are the live-backend and two-simulator contracts. **They are
  skips, not passes.**
- Smoke: **12 of 12 passed** (`/tmp/we-beta-smoke-4.xcresult`).
- Accessibility at `accessibility5`: **4 of 4 passed**
  (`/tmp/we-beta-a11y-3.xcresult`).
- Release archive built and signed; bundle contents verified as above.

### Not executed

- Any production database verification or change.
- Shared Journeys against the production AI path.
- APNs delivery.
- Widgets on a distributed build.
- Anything at all on a physical phone.

---

## The testing gap, stated plainly

Deferring the separate QA Supabase project and the four `WE_QA_*` secrets means
the nightly `live-couple-contract` job never runs — neither
`run-live-repository-contract.sh` (three disposable users) nor
`run-two-simulator-contract.sh` (Partner A and B on separate simulators, paired
through the public RPCs).

**What that leaves unchecked:** RLS behaviour between two genuinely
authenticated accounts, realtime delivery from one partner to the other, and
pairing against a live Postgres. pgTAP proves the policies against a local
database with forged JWT claims. It does not prove PostgREST applies them to a
real session.

That gap is covered by section 2 of `docs/FIRST_INSTALL.md` — two phones, two
real accounts, invented content — and by nothing else. It will be reported as
manually verified or not at all, never as a passed suite.

---

## Remaining blockers, in order

1. **Ryan runs `docs/RELEASE.md`.** Step 1 first; nothing marked applied
   without it. Confirm the backup/PITR window before starting.
2. **Ryan uploads the archive** and invites the tester.
3. **Shared Journeys against production.** Consent required and version-
   stamped; changing an answer clears it; a synthesis job exists only for a
   consented response; the `pg_cron` schedule from `20260820161957` is live;
   one journey completes end to end. **If any leg fails, set
   `WE_SHARED_JOURNEYS_ENABLED = NO` and ship without it** — a dead AI path
   with real content in it is worse than an absent feature.
4. **Push, if wanted.** Ryan enables Push Notifications on App ID
   `com.ryankanfer.WE`; then `WE/Config/WE.entitlements` is restored exactly as
   its own comment describes, and delivery is proven on a physical phone before
   push is called included.
5. **Widgets on the distributed build** before calling them included — stale
   content, sign-out, and what they show on a locked screen.
6. **`docs/FIRST_INSTALL.md` on both phones.**

Only after 6 does "verified for everyday use" mean anything.

## Expansion

No wider cohort until both of you can save, find, correct and complete a
shared action without help, and no critical privacy, saving, pairing or
deletion defect remains. Revisit five couples for two weeks, and isolated
automated QA, then. Earned restraint, expanded history, mutual stillness and
Make room remain deferred.

## Fine tuning that can wait for feedback

Decorative transitions, extra empty-state polish, and small spacing
refinements beyond readability and reachability. Deferring those is what makes
it possible to find out whether the thing is useful daily. It does not defer
consent clarity or a blocked control.
