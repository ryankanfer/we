# WE private beta: reconciliation and release record

Current scope: Ryan has deferred new-relationship/archive implementation. Focus on everyday pages, interaction, saving, privacy and useful interpretation. Do not run departure/replacement tests or change their behavior in this pass.

Status: implementation checkpoint, NOT a release candidate. No production changes, upload, or distributed-build verification performed.

September 7 review correction: production approval comes AFTER outstanding privacy/durability fixes, direct negative authorization/concurrency checks, and review of the exact committed revision. New-relationship/archive implementation is deferred at Ryan’s request; do not make it the next implementation task. The exported local archive proves compilation/signing only and must not be distributed as the beta. Timestamp-based Yours lifecycle authorization is invalid (PostgreSQL Query messages share statement_timestamp); replace it with explicitly scoped authorization and test zero-row/exception paths. Other open issues include attribution-only update authorization, any remaining asynchronous mutation paths, and unreadable-outbox recovery. Transport retry exhaustion and Waiting outcome semantics were corrected in the everyday-page pass below.

Deferred product direction: Ryan selected read-only retention of previously shared material with new relationships starting empty, then explicitly deferred that work. Preserve the decision for later; no departure/replacement testing or implementation in this pass.

Baseline: beta/p0-p1-execution, a158e2b, PR #14 open. GitHub checked September 7, 2026.

| Original deliverable | Current evidence | Remaining gate |
| --- | --- | --- |
| Schema/privacy, unit/build, critical smoke, private-to-shared | All four GitHub checks pass on a158e2b | Rerun after this implementation |
| Production ledger and newer migrations | Supabase connector verified tizunrayxyorzrvopnsw (we-round1); ledger stops at 20260820161957. Normalized deployed function bodies match all eight older migrations; columns, palette constraints, policies and arrival trigger checked | Repair history and deploy four newer migrations only after release approval |
| Save/recover/retrieve/correct | Existing outbox, recovery and item correction; synchronous durable capture staging added in this change | Disk-failure, restart and retry tests; actual beta device checks |
| Waiting, expired dates, Us prominence, capture phrases | Implemented on baseline, covered by existing unit suites | Recheck tests and beta behavior |
| Navigation/themes/readability | Updated in this change | Simulator and real-device inspection |
| New walkthrough and guided save | Implemented locally; walkthrough retrieval and skip/relaunch tests pass | Distributed first launch, invitation preservation, account-scoped real save |
| Native accessibility, interruption, keyboard | Existing support retained | Updated smoke/accessibility and device matrix |
| Distribution | Local signed archive/export exists, predating current fixes; nothing uploaded | Regenerate from final source, production approval and physical-device verification |
| Two-account automated suites | Explicitly deferred | Manual private beta, never report skipped as passed |

Vercel's September 7 build log confirms the frozen Next.js project compiles, then fails type checking `supabase/functions/announce-arrival/index.ts`: Next cannot resolve the Deno `jsr:@supabase/supabase-js@2` import. This is a web build configuration issue, separate from the native archive (which successfully signs and builds). Inspect any web URLs used by the release before distribution; this check does not verify production notification delivery.

## Release gates

Confirm the production project and eight older deployed migration versions from actual schema, not this note. Never mark newer migrations applied without deployment. No database mutation until Ryan approves the concrete release and recovery approach.

Capture release version/build, source commit plus any uncommitted changes, database project, migration list, and capability settings here before distribution. Shared Journeys is enabled in committed Release settings; Share Inbox is disabled. Push is excluded until APNs capability/worker delivery is proven. Widget inclusion requires signed build and stale/sign-out/privacy checks. Do not promise excluded features.

Read-only deployed verification succeeded through the Supabase connector despite the local CLI lacking authentication. No customer content was needed. The new departure helper is absent in production, so the deletion fix is not deployed.

## Everyday-page continuation

Local checkpoint `c100b6e` preserves the interface, walkthrough and durable-capture work; it is not pushed or release-ready. The subsequent everyday-page continuation is recorded with its own local checkpoint after the focused checks below.

- Yours keeps the draft visible after failed saving, prevents concurrent submissions, and reuses the same identity when retrying an uncertain response. A partial keep-indefinitely failure does not claim that retention succeeded. Closing an unsaved draft requires an explicit discard choice.
- Completing, removing, confirming outreach and reclaiming an item stage their changes on disk before the screen acknowledges them.
- Repeated transport failures remain eligible for automatic retry. Server/validation failures retain the separate attention state.
- The follow-up question distinguishes done, confirmed outreach awaiting a reply, and still on me. Cancelling outreach does not manufacture a Waiting item.
- Yours no longer promises unverified irreversible deletion within a fixed duration; it describes removal from the private space.
- Us labels the initial submission “Save my private answer”; changing that answer clears the processing-consent selection. Proposed and agreed directions have explicit text labels, so their state does not depend on colour or interpreting the available button.

Current verification: `/tmp/we-pages-unit-5.xcresult` passed all 615 Swift Testing tests in 79 suites; Eight XCTest tests passed and three were skipped (not counted as passes). `/tmp/we-pages-edge/edge-function-tests.log` reports 17 local edge-function contract tests passed, zero failed. These do not verify deployed authorization or real AI responses. The expanded 12-test simulator smoke run (`/tmp/we-pages-smoke-1.xcresult`) passed 11 and failed one: an obsolete all-caps heading expectation in the active-journey test. The current screen displays the actual next action. The focused rerun (`/tmp/we-pages-focused-1.xcresult`) passed all three UI tests: Us proposal/agreed state, Yours close behavior, and saving with the keyboard open. Its copy suite initially failed one obsolete requirement to promise irrecoverability; after removing that incorrect requirement, all four copy tests passed in `/tmp/we-pages-copy-2.xcresult`. The two populated Us checks also passed in `/tmp/we-pages-visual-1.xcresult`; exported screenshots were visually reviewed for consent, proposal and agreed states. The final labelled-state check passed in `/tmp/we-pages-visual-2.xcresult`. Screenshots were inspected again after the labels were added. `/tmp/we-pages-evidence-1.xcresult` also passed: supporting shared evidence scrolls above navigation, opens, and displays the expected record. Local visual references are in `artifacts/private-beta-review/` (fictional data only, not approved distribution goldens). Yours’ keyboard-open screenshot confirms both save choices are above the keyboard. Previous accessibility results below predate this continuation.

## Previous local verification

September 7: `/tmp/we-beta-unit-6.xcresult` passed 611 Swift Testing tests plus 8 XCTest tests. Three XCTest tests skipped (live backend and two-simulator contracts); these are not passes. New checks cover synchronous durable capture and corrections before background work, disk failure retaining the receipt/original item, partitioned draft recovery, fictional walkthrough isolation/correction, and account-scoped first-save progress. `/tmp/we-beta-smoke-3.xcresult` passed all nine core-flow tests, including full walkthrough retrieval and skip/relaunch. `/tmp/we-beta-accessibility-2.xcresult` passed all four accessibility tests, including the new walkthrough's larger-text screens. This is not a manual VoiceOver session or physical-device sign-off.

Local Release archive `/tmp/WE-PrivateBeta.xcarchive` built and signed successfully. Its bundle confirms version 1.0 (1), minimum iOS 26.2, production URL `https://tizunrayxyorzrvopnsw.supabase.co`, Shared Journeys YES, Share Inbox NO, and embedded widget/share extensions. This archive predates final feedback styling/control-touch-area fixes and must be regenerated before distribution. A subsequent local archive `/tmp/WE-PrivateBeta-Final.xcarchive` and development export `/tmp/WE-PrivateBeta-Export/WE.ipa` succeeded, but both also predate the everyday-page continuation. Nothing has been uploaded, installed on a physical phone, or verified as a distributed build. Push capability remains absent; the embedded share extension is not proof that Release importing is available.

## Historical production proposal — blocked, not approved for execution

The sequence below is historical preparation, not an executable release. Migration `20260907020000` has a known authorization flaw and must be replaced and verified before any approval request. The eight older entries still need complete backfill, grant, and security verification; matching function bodies alone is insufficient. Reconcile departure-related migrations with the deferred scope.

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

Do not delete either everyday account. Departure/replacement tests are deferred. Before resuming them, document and verify the selected archive direction, departed-account access removal and replacement-partner visibility. The existing model retains the shared field and vacates a membership slot; do not silently redesign it.

## Everyday beta: roughly two weeks

Use real thoughts and plans. Note confusion, incorrect interpretation, pressure, avoidable interruptions and helpful moments. Ask each partner separately: What did WE take off your mind? What needed correction? Could you retrieve it? Did you know what was private? Did a shared prompt feel like pressure?

Feedback: build version; what I tried; expected behavior; actual behavior; whether blocked. Screenshots and private detail are optional. Do not collect relationship text in diagnostics.

Immediately prioritize disclosure, data loss, account access and broken core flows. Group smaller visual/usability fixes into focused updates.

## Expansion

No wider cohort until both partners can save, retrieve, correct and complete a shared action without coaching and no critical privacy/saving/pairing/deletion defects remain. Revisit five couples for two weeks and isolated automated QA then. Earned restraint, expanded history, mutual stillness and Make room remain deferred.

## Remaining work, in delivery order

1. Extend the completed iPhone 17 Pro populated Us/Yours review to small/large layouts, larger text, VoiceOver and remaining retention controls. Keep the archive redesign deferred.
2. Resolve remaining everyday privacy/reliability gaps: unreadable-outbox recovery, direct negative server authorization/concurrency checks, and the invalid lifecycle migration. Verify all older migration effects before history repair. No live two-account coverage has run.
3. Regenerate the signed archive/export from the final identified source. Confirm tester phone compatibility (iOS 26.2) and distribution eligibility. The existing development profile lists two devices but does not establish that they are the testers’ phones.
4. Confirm backup/recovery availability, prepare a corrected exact production release, and request Ryan’s approval. No repair or migration has run in production.
5. Verify the distributed build on both physical phones: auth, invitations, consent revisions, visibility, offline/partial failures, expired sessions, accessibility and account switching.
6. Verify widgets on the distributed build before calling them included. Shared Journeys needs its full release-backend path verified. Share importing and push are excluded. Complete the agreed distribution path and begin the manual checklists.

Fine tuning that can wait for beta feedback: decorative transitions, extra empty-state polish, and small spacing refinements beyond readability/reachability. Deferring those helps evaluate daily usefulness first; it does not defer consent clarity or blocked controls.
