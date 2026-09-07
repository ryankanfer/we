# WE private beta: reconciliation and release record

Status: implementation checkpoint, NOT a release candidate. No production changes, upload, or distributed-build verification performed.

September 7 review correction: production approval comes AFTER departure/retention scope, durability fixes, direct negative authorization/concurrency checks, and review of the exact committed revision. The exported local archive proves compilation/signing only and must not be distributed as the beta. Timestamp-based Yours lifecycle authorization is invalid (PostgreSQL Query messages share statement_timestamp); replace it with explicitly scoped authorization and test zero-row/exception paths. Other open issues include attribution-only update authorization, remaining asynchronous mutations, transient network retry exhaustion, unreadable-outbox recovery, and Waiting outcome semantics.

Ryan selected read-only retention of previously shared material with new relationships starting empty. This does not freeze the survivor's entire product. Scope separate writable use and archive retrieval before changing departure behavior; the existing slot-reuse model must not expose old history to a new partner.

Baseline: beta/p0-p1-execution, a158e2b, PR #14 open. GitHub checked September 7, 2026.

| Original deliverable | Current evidence | Remaining gate |
| --- | --- | --- |
| Schema/privacy, unit/build, critical smoke, private-to-shared | All four GitHub checks pass on a158e2b | Rerun after this implementation |
| Production ledger and newer migrations | Supabase connector verified tizunrayxyorzrvopnsw (we-round1); ledger stops at 20260820161957. Normalized deployed function bodies match all eight older migrations; columns, palette constraints, policies and arrival trigger checked | Repair history and deploy four newer migrations only after release approval |
| Save/recover/retrieve/correct | Existing outbox, recovery and item correction; synchronous durable capture staging added in this change | Disk-failure, restart and retry tests; actual beta device checks |
| Waiting, expired dates, Us prominence, capture phrases | Implemented on baseline, covered by existing unit suites | Recheck tests and beta behavior |
| Navigation/themes/readability | Updated in this change | Simulator and real-device inspection |
| New walkthrough and guided save | In progress | First launch, skip/replay, isolated example, account-scoped real save |
| Native accessibility, interruption, keyboard | Existing support retained | Updated smoke/accessibility and device matrix |
| Distribution | Not yet built or uploaded | Signed archive, capabilities, production approval and device verification |
| Two-account automated suites | Explicitly deferred | Manual private beta, never report skipped as passed |

Vercel's September 7 build log confirms the frozen Next.js project compiles, then fails type checking `supabase/functions/announce-arrival/index.ts`: Next cannot resolve the Deno `jsr:@supabase/supabase-js@2` import. This is a web build configuration issue, separate from the native archive (which successfully signs and builds). Inspect any web URLs used by the release before distribution; this check does not verify production notification delivery.

## Release gates

Confirm the production project and eight older deployed migration versions from actual schema, not this note. Never mark newer migrations applied without deployment. No database mutation until Ryan approves the concrete release and recovery approach.

Capture release version/build, source commit plus any uncommitted changes, database project, migration list, and capability settings here before distribution. Shared Journeys is enabled in committed Release settings; Share Inbox is disabled. Push is excluded until APNs capability/worker delivery is proven. Widget inclusion requires signed build and stale/sign-out/privacy checks. Do not promise excluded features.

Read-only deployed verification succeeded through the Supabase connector despite the local CLI lacking authentication. No customer content was needed. The new departure helper is absent in production, so the deletion fix is not deployed.

## Current local verification

September 7: `/tmp/we-beta-unit-6.xcresult` passed 611 Swift Testing tests plus 8 XCTest tests. Three XCTest tests skipped (live backend and two-simulator contracts); these are not passes. New checks cover synchronous durable capture and corrections before background work, disk failure retaining the receipt/original item, partitioned draft recovery, fictional walkthrough isolation/correction, and account-scoped first-save progress. `/tmp/we-beta-smoke-3.xcresult` passed all nine core-flow tests, including full walkthrough retrieval and skip/relaunch. `/tmp/we-beta-accessibility-2.xcresult` passed all four accessibility tests, including the new walkthrough's larger-text screens. This is not a manual VoiceOver session or physical-device sign-off.

Local Release archive `/tmp/WE-PrivateBeta.xcarchive` built and signed successfully. Its bundle confirms version 1.0 (1), minimum iOS 26.2, production URL `https://tizunrayxyorzrvopnsw.supabase.co`, Shared Journeys YES, Share Inbox NO, and embedded widget/share extensions. This archive predates final feedback styling/control-touch-area fixes and must be regenerated before distribution. It has not been exported, uploaded, installed on a physical device, or tested as a distributed build. Push capability remains absent; the embedded share extension is not proof that Release importing is available.

## Proposed production release — approval still required

1. Export the existing schema/function definitions and migration ledger to a protected local release folder; confirm project id again.
2. Record these eight versions as applied, without executing their already-present changes: `20260820210000`, `20260820230000`, `20260821120000`, `20260824120000`, `20260824130000`, `20260824140000`, `20260904120000`, `20260906120000`.
3. Apply the committed migrations `20260907000000` (explicit read-only grants), `20260907010000` (account-departure attribution cascades), `20260907020000` (Yours lifecycle guard scope), and `20260907030000` (unused local cleanup), normally and in order. An earlier manually applied grant change is idempotent; it still needs normal migration accounting.
4. Read back definitions, grants and ledger. Do not perform destructive account tests until the product decisions below are confirmed.

Expected account/data effects: no account recreation, bulk deletion or content rewrite. The release tightens direct-write permissions, allows existing departure cleanup to complete, and narrows lifecycle updates to their intended statement. History repair changes only migration records. It does not deploy features.

Recovery: keep the app release on hold if a migration or verification fails. Transactional migrations roll back their own failed changes; the grant-only migration can safely be rerun. Use a reviewed corrective migration from the exported pre-release definitions for an unexpected regression. Do not automatically restore older privacy guards or undo a completed account deletion. Read-only exports of affected function definitions, grants, invitation constraint and ledger are in protected `/tmp/we-beta-pre-release-functions.json` and `/tmp/we-beta-pre-release-ledger-grants.json` (no customer content). These are schema recovery references, not a customer-data backup. Database backup/PITR availability still needs confirmation before final approval.

## Manual initial checklist

Use the identified distributed build on both phones. Record each result separately.

- First launch: skip or finish the fictional story; no examples appear in the real account.
- Create/sign in, invite/join, and finish arrival without coaching.
- Find Yours, Account, Search and Calendar.
- Capture a real thought, identify visibility, inspect its date, save, retrieve and correct it.
- Disconnect, save, close/reopen and reconnect. Confirm eventual sync and no duplicates.
- Complete a shared action. Check changed proposals require renewed approval; withdrawal remains withdrawn.
- Interrupt forms, change accounts, use large text, VoiceOver and Reduce Motion. Check keyboard and final buttons.

## Destructive tests: separate disposable accounts

Do not delete either everyday account. Before tests, Ryan must confirm survivor retention, departed-account access removal, replacement-partner visibility and the fate of relationship archives. The existing model retains the shared field and vacates a membership slot; do not silently redesign it.

## Everyday beta: roughly two weeks

Use real thoughts and plans. Note confusion, incorrect interpretation, pressure, avoidable interruptions and helpful moments. Ask each partner separately: What did WE take off your mind? What needed correction? Could you retrieve it? Did you know what was private? Did a shared prompt feel like pressure?

Feedback: build version; what I tried; expected behavior; actual behavior; whether blocked. Screenshots and private detail are optional. Do not collect relationship text in diagnostics.

Immediately prioritize disclosure, data loss, account access and broken core flows. Group smaller visual/usability fixes into focused updates.

## Expansion

No wider cohort until both partners can save, retrieve, correct and complete a shared action without coaching and no critical privacy/saving/pairing/deletion defects remain. Revisit five couples for two weeks and isolated automated QA then. Earned restraint, expanded history, mutual stillness and Make room remain deferred.

## Remaining work, in delivery order

1. Final signed archive/export and source identification. Confirm both testers' phones meet iOS 26.2 and are eligible for the chosen distribution path; current development profile lists two devices, but this does not identify them as the testers' phones.
2. Confirm recovery availability in the Supabase dashboard (browser currently signed out), then request Ryan's approval for the exact production release above. No repair or migration has been run in production.
3. Resolve departure/archive/replacement-partner behavior and reconcile the in-app/online privacy policy with the chosen, verified behavior. The existing policy refers to a read-only archive, while the Field model preserves shared records and vacates a slot; this is an unresolved product/release gap, not a new behavior selected here.
4. Verify the Release build on two physical phones: real auth, invitations, consent revisions, private/shared boundaries, offline retries, partial failures, expired sessions and account switching. Capture/correction persistence has new deterministic coverage; remaining mutation paths and cross-account server enforcement still require the existing/manual contracts. No live two-account coverage was executed.
5. Complete visual review of populated Us consent/proposal states, Yours retention controls, keyboard behavior and small/large devices, then regenerate approved references. Current manual visual inspection covered Today and Life on iPhone 17 Pro; automated accessibility checks do not substitute for this remaining review.
6. Verify widget privacy/staleness/sign-out on the distributed build before calling widgets included. Shared Journeys is configured on but still needs its complete release-backend path verified. Share importing and push are excluded; local notification denial must still be checked. Finish TestFlight setup/upload with the agreed release and start the manual checklists.

Fine tuning that can wait for beta feedback: decorative transitions, extra empty-state polish, and small spacing refinements beyond readability/reachability. Deferring those helps evaluate daily usefulness first; it does not defer consent clarity or blocked controls.
