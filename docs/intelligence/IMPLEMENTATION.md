# WE native intelligence — implementation and release record

This implementation keeps originals account-owned and makes a reviewed publication a separate, couple-readable representation. Today, Life, and Calendar use canonical objects and accepted timing. Yours remains a separate reflection experience with its existing storage and lifecycle; its writing and Us answers never enter these search indexes.

## Interactive prototype

Open `WE/WE/Intelligence/IntelligencePrototype.swift` in Xcode and run either preview. The largest-text preview uses accessibility5. The prototype uses the production SwiftUI screens and encrypted fictional captures, with synchronization disabled and an in-memory publication backend. Its fixtures include an unresolved reservation, an unfetched event link, and an interrupted plan.

For the existing seeded simulator scheme, set:

```
WE_FIELD=seeded
WE_REPOSITORY=preview
WE_INTELLIGENCE_PREVIEW=1
WE_SKIP_PROMISE=1
WE_SKIP_WALKTHROUGH=1
```

The prototype is compiled only in Debug. Its dedicated account namespace is `intelligence-interactive-preview`. Never enable preview environment variables on a real-account acceptance run.

## Annotated flow

| Step | Interface and action | Preservation / permission boundary | Failure and accessibility behavior |
| --- | --- | --- | --- |
| Bring it in | Share Sheet or common capture; text, HTTPS link, up to five images | Commit the supplied representation to encrypted storage before acknowledging saving. No website request. | Unsupported or oversized representations produce explicit omissions. Failed commit never claims saved. Inputs and save controls have accessibility identifiers. |
| Saved in Life | Rows say Only Me, Saved on this phone / Synced privately, and accepted timing | A synchronization receipt requires verified originals plus committed metadata. | Persistent issues lead to Needs attention. Labels use text as well as symbols; rows wrap. |
| Review understanding | Edit title, details, category, place, and timing; accept or dismiss suggestions; inspect Why this | Local consent is independent of fetch consent. OCR operates on a bounded thumbnail; originals remain unchanged. Foundation Models is optional and has no cloud fallback. | Manual completion works without intelligence. Stale jobs cannot replace corrections. Text and image evidence remain owner-only. |
| Understand this link | Explicit public-website disclosure and confirmation | No cookies, browser session, script execution, subresources, or redirect following. DNS results are checked and the TLS connection is pinned to the validated address. | Saved URL survives refusal or failure. Ambiguous, query-bearing, and opaque links never use automatic rules. |
| Progressive trust | After three distinct successful grants in a confirmed category, offer a deliberate rule choice | Restaurants, events, and real estate only. Rules never enable sharing. | Rules remain editable in Account / Needs attention; revocation cancels associated work. |
| Connect | Choose an existing shared plan, a private plan, a new private plan, or leave unattached | Private relationships do not change shared counts or adaptation. | Suggestions show actual keyword or embedding ranking reasons. Dated attachments offer a separate reviewed parent-timing update. |
| Review sharing | Show released text, category, place, timing, recipient, destination, URLs, and image previews | Images and URLs start excluded. Frozen payload, audience, destination, private version, published revision, and attachment hashes bind approval. | Changes invalidate review. Failed publication remains in Needs attention; private originals remain available. |
| Published | Both partners read one canonical Life item; the owner retains the original | Corrections update the same shared identity using expected versions. Private notes, original IDs, and evidence stay out of the shared item. | Concurrent changes preserve both versions for an explicit comparison. |
| Find and act | Keyword-first search, separate ephemeral private/shared embedding indexes, Today/Calendar, Maps, system Calendar editor | Eligibility is filtered before indexing and ranking. External-app opening never completes an item. No external calendar ingestion or background writes. | Unsupported embedding languages fall back to keywords. Unresolved timing must be corrected before Calendar. |
| Needs attention | Account and a quiet Life entry; open, retry, manually edit, or compare versions | Dismissing an error does not discard pending work. | Persistent processing, synchronization, publication, conflict, and deletion status; standard SwiftUI navigation and controls support VoiceOver and Dynamic Type. |
| Delete Everywhere | Consequence preview names originals, synced copies, processing/search data, relationships, shared representation, and attachments | Durable tombstone first. Hide locally; server cleanup retries. Containing plans and independently authored children survive. | Pending cleanup stays visible. Disconnected devices purge on reconciliation; exports and retained infrastructure backups are not claimed erased immediately. |

## Storage and execution

- `WEShareCore`: bounded preservation, immutable manifests, account vault keys, authenticated chunk encryption for original resources. Existing optimized captures remain marked as optimized. Existing draft and review identities are retained. Lost/deleted originals cannot be reconstructed.
- `IntelligencePersistence`: encrypted atomic ledger containing accepted edits, authorization, jobs, conflicts, stable pending writes, and content-free deletion state.
- `IntelligenceStore`: containing-app processing and synchronization; immutable pending write snapshots; account checks before and after suspension; revision checks before accepting results.
- `IntelligenceBackend`: owner-bound transport tokens, paginated reconciliation, immutable private-original upload and actual-byte receipts.
- `IntelligenceUnderstanding`: Vision OCR with image bounds and text ranges; validated exact-substring model suggestions; keyword-first retrieval with permission-filtered ephemeral vector indexes. Indexes are rebuilt from eligible saved objects and cleared on session/account invalidation.
- `ShareInbox`: frozen exact-revision publication; containing-app normalized image derivatives; no deletion on publication or automatic original expiry.
- `IntelligenceModels` and `WETimeProvider`: canonical references, visibility, timing, provenance, and a boundary for future time providers. Existing date-only values keep date precision.
- `20260913010000_native_intelligence.sql`: owner-only records/storage, versioned writes, canonical shared publication, tombstones, verification receipts, cleanup queues, and account-deletion cleanup.
- `intake-resources`: authenticated byte verification and owner deletion. The existing scheduled `cleanup-life-resources` worker also drains durable intake cleanup.

Cloud privacy follows Supabase authorization. This is not an end-to-end encryption claim. Category rules are device-local; item-specific grants and processing history belong to private artifact content. Synchronization runs in the containing app on entry, reconnect, foreground, and explicit retry; the extension never enriches or synchronizes.

## Release and rollback

Release still has `WE_SHARE_INBOX_ENABLED = NO`. This change has not been deployed. Apply the migration and deploy both edge functions together before enabling intake. Preserve existing production data and reconcile remote migration history first.

Enrichment and automatic website work have separate optional Info.plist Boolean switches: `WEEnrichmentEnabled` and `WEAutomaticLinksEnabled` (both default true). Set either false for a capability rollback; leave preservation, editing, search, recovery, and deletion available. The initial intake gate is a release gate, not the operational rollback switch.

The link reader currently accepts public HTTPS over IPv4, UTF-8 HTML/plain text, at most 1 MiB, and rejects redirects. The transport has a 20-second timeout; system DNS resolution remains dependent on the operating system resolver. A failed fetch always leaves manual editing available.

## Verification record — 2026-09-13

Executed:

- Signed iOS Simulator build, iOS 26.3 / iPhone 17 Pro.
- Full Swift Testing suite: 674 tests passed. XCTest: 8 passed, 3 skipped. Both UI tests passed again in `/tmp/we-intelligence-verified.xcresult`. Final deletion-cache/outbox regressions: 42 tests passed in `/tmp/we-intelligence-cleanup.xcresult`, including removal of deleted-item queued edits while independent edits survive.
- Final legacy-review migration and intake regression run: 22 tests passed in `/tmp/we-intelligence-migration.xcresult`.
- Two interactive UI checks passed: capture → terminate → relaunch → private search; persistent recovery → detail at largest Dynamic Type with Reduce Motion.
- Screenshots exported and visually inspected: explicit privacy/status labels, wrapped content, and actionable recovery controls.
- All repository migrations applied in isolated PGlite with Supabase platform shims; 23 assertions passed covering owner filtering, lost acknowledgment, conflicts, canonical publication, immutable revision guards, deletion, late uploads, and late verification.
- Deno type checks for both affected edge functions.

An earlier parallel simulator run crashed in an existing XCTest process. The serial full run passed; the crash is retained in `/tmp/we-intelligence-unit-4.xcresult`, not silently counted as a pass. PGlite checks are isolated SQL verification, not a deployed Supabase or Storage service test.

Skipped / blocked until the release environment is available:

- Three repository integration checks requiring their dedicated simulator/live configuration.
- Remote migration reconciliation, real Storage byte-upload verification, cleanup cron execution, and multi-device authorization/concurrency tests against the target Supabase environment.
- Actual signed distribution archive inspection and entitlements verification.
- Two physical phones, including one without Apple Intelligence; Share Sheet kill points, memory pressure, locked-device behavior, VoiceOver traversal, offline departure/revocation, and external Calendar editor confirmation.
- Full paraphrase/language quality and calendar timezone/DST acceptance matrix on devices.

These are release gates. Simulator and isolated database passes do not satisfy them.

## Reproducing local checks

The XCTest and Swift Testing suites are in `WE/WETests`; the interaction checks are `WE/WEUITests/IntelligenceUITests.swift`. Use the existing WE Test Account scheme, signed simulator tests, and `-parallel-testing-enabled NO`.

For isolated SQL checks without Docker:

```sh
npm install --prefix /tmp/we-sql-check @electric-sql/pglite
NODE_PATH=/tmp/we-sql-check/node_modules node scripts/intelligence/check-sql.mjs
```

The script runs the committed SQL tests with a minimal assertion adapter. Run the actual pgTAP tests under the Supabase stack before release.
