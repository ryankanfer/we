# WE — remaining work

Branch `design/handoff-visual-directions`, on top of `3bc6dca`. Working tree
clean. The plan this follows is
`~/.claude/plans/take-a-look-at-hashed-tarjan.md`.

## Landed

| Commit | What |
| --- | --- |
| `c0bfb61` | Two canvases, one ink ramp |
| `6c4a105` | Presence channel + acknowledgement persistence (3a, 3b, 3j) |
| `9375a31` | The stillness (3e), warm ink black |
| `5ad7a87` | Pigment palette + picker rewrite (phase 0, 2 palette, 3g, 3k) |
| `3bc6dca` | The Promise, performed rather than read (3d, partial) |

Phase 1 (Us surface, nav) landed earlier in the branch.

---

## Blockers — status

### 1. UI test baseline — established 2026-08-21

Run through the existing lane runner rather than hand-rolled `-only-testing:`
(`scripts/qa/run-xcode-tests.sh <lane> <destination> <result> <derived-data>`),
which is what avoids the result-bundle save failures on long runs.

Simulator `7CB80F68-12A9-4D4B-807D-E3EE1D36ACF3` (iPhone 17 Pro Max). No
`FBSOpenApplicationServiceErrorDomain` in any run below, so all of it is
trustworthy.

| Lane | Before | After the fix in §2 |
| --- | --- | --- |
| `unit` | 518 tests, 69 suites, green | green |
| `accessibility` | 1 of 2 failed | **green** |
| `smoke` | 2 of 7 failed | **green** |
| `full-ui` | not previously completed | 11 of 52 failing, all accounted for |

Expected skips, not passes and not failures: `FieldSupabaseLiveContractTests`
and `FieldTwoSimulatorContractTests` both live in `WETests`, so the `unit` lane
collects them and they `XCTSkip` without `WE_QA_*`. Those credentials are
GitHub Actions secrets driven by `qa-nightly.yml`; a green local run means
skipped.

**The pre-existing failure set is far larger than one test.** The handoff
recorded a single known failure because a full `full-ui` run had never
completed. It has now. Of the 13:

- **2** are the stale Promise tests in §3, which assert deleted copy.
- **1** is the calendar test in §4, which asserts an identifier that has never
  existed.
- **9** are pre-existing and unrelated to any of this work, **verified by
  stashing every source change and re-running them on `3bc6dca`**, where they
  fail identically: `testACategoryOpensItsRoomAndCloses`,
  `testAnItemCanBeMovedAndRemoved`, `testAnItemOutreachOwnsOffersNoLookupBlock`,
  `testReachingOutStopsForAConfirmationAndNeverGuesses`,
  `testSomethingBuyableOffersOneNamedDestination`,
  `testTappingACategoryDoesNotOpenSearch`,
  `testTheCircleMarkIsALabelledButtonAndTeachesOnce`,
  `testTheEscapeOnAStatementActuallyDefersIt`,
  `testUsProposalAndActiveJourneyStayFocused`.
- **1**, `testMovingEverythingOutOfAGroupEmptiesIt`, is **flaky rather than
  failing**: it failed once inside the full run and passes on repeated runs in
  isolation. Suspect cross-test state leakage in the seeded fixture.

Most of the nine are Life-zone room and item interactions, which suggests one
underlying cause rather than nine. That is worth a single investigation before
Phase 4 touches Life, and is **not** a licence to treat a red suite as normal:
this list is the baseline, and anything not on it is a new regression.

**That investigation has now been done, and the "one cause" guess was wrong.**
All nine reproduce on the V2 tree (2026-08-25). They are at least three
distinct causes, and only one of them was a product defect:

1. **A button inside a button — fixed.** `.accessibilityElement(children:
   .combine)` applied *after* `.buttonStyle` does not merge the Button into one
   element; it wraps the existing element in a second one. Four rows did this,
   all with the same `.buttonStyle(.plain)` → `.overlay { FieldRuleLine }` →
   `.combine` signature: `FieldCategoryRoom` (both bands),
   `FieldCalendarSurface`, and `FieldLifeSearch`. The accessibility tree showed
   the result plainly — `Button 'field.room.row'` containing a second unnamed
   `Button` with the same content. VoiceOver read every such row twice, and a
   query by label matched two elements. Removing the `.combine` line at those
   four sites fixes it; a Button already merges its label's children.
   `FieldLifeZone.categoryRow` shows the correct pattern — it combines the
   *content*, inside the label closure. This is the same family of mistake as
   §2's `.accessibilityHidden` bug: a modifier that promotes rather than
   annotates. **This cleared `testAnItemCanBeMovedAndRemoved`**, which was the
   "Multiple matching elements found" one.

2. **Rows compose title and reason into one label.** A room row now announces
   `"Dylan's birthday — Sunday. Lands Sunday."`, so `buttons["Dylan's birthday
   — Sunday"]` cannot match. This is the product behaving as designed and the
   tests asserting the pre-`combine` shape. Affects
   `testACategoryOpensItsRoomAndCloses` and
   `testTappingACategoryDoesNotOpenSearch`.

3. **Today's moment surface has drifted from its tests.** Every element of the
   moment carries the *same* identifier, `field.today.moment` — a collision in
   its own right — and the labels are sentence case. The tests look for
   `field.moment.postpone` with label `ASK ME AGAIN TONIGHT`; the tree has
   `field.today.moment` with label `Ask me again tonight`. `field.circle.mark`
   does not appear in the tree at all in the seeded state. Affects
   `testTheEscapeOnAStatementActuallyDefersIt` and
   `testTheCircleMarkIsALabelledButtonAndTeachesOnce`.

The remaining four (`testAnItemOutreachOwnsOffersNoLookupBlock`,
`testReachingOutStopsForAConfirmationAndNeverGuesses`,
`testSomethingBuyableOffersOneNamedDestination`,
`testUsProposalAndActiveJourneyStayFocused`) were not traced; they are item
detail, receipt and Us-journey surfaces, which the V2 re-cut rewrites anyway.

**Revised baseline: 8 pre-existing failures, not 9.** Causes 2 and 3 live
exactly where the V2 phases rewrite — Life becomes strata, Today becomes a read
— so they are deliberately left for those phases to resolve along with their
tests, rather than fixed twice.

`testTappingACategoryDoesNotOpenSearch` is timing-sensitive on top of being
broken — it took 281 seconds in one run and 15 in another. It depends on
`settleOnLife` (`FieldZoneUITests.swift:1294`), which uses a hard
`usleep(1_200_000)` for the paging transition.

**The simulator degrades over a long `full-ui` run.** After the fixes, that
lane reports 11 failures: the 8 pre-existing Life-zone ones, plus three
`WEUITests` cases that all pass on a freshly booted simulator and whose
durations in the long run are roughly double their isolated ones
(`testAAuthRecoveryPairingAndHueRoutes`,
`testAccountDeletionIsReachableBeforeAndDuringPairing`,
`testLivingConfluencePromiseSupportsReducedMotion`). Verified by re-running the
whole `WEUITests` class on an erased device, where only the first fails. Judge
`WEUITests` from the `smoke` lane or a short run, not from the tail of
`full-ui`.

**After `simctl erase`, the first UI run is a write-off.** The app asks for
notification permission on launch, and that system alert kills the audit with
`com.apple.accessibilityAudit Code=-902 "Invalid target app"`. It is not a
crash and not a regression — the second run is green, because the prompt has
been answered. Do not read the first post-erase run as a result.

`testAAuthRecoveryPairingAndHueRoutes` has its own flake, and it is worse than
recorded. It fails at `pairing.createInvitation` because the iOS password-save
sheet appears and the test's `Not Now` decline waits only two seconds; the tap
that follows computes a hit point of `{-1, -1}` while the system window is
still coming down. **It is not confined to a freshly erased simulator** — as of
2026-08-24 it fails on every run on this machine, in the `smoke` lane and in
isolation.

**Verified as pre-existing** by running the same test from a worktree at
`3bc6dca` with its own derived data, where it fails at the same button in the
same way, *and* goes on to fail a second time at `field.onboarding.finish`.
This branch fails once where the base fails twice, so nothing here caused it
and something here improved it.

The fix, when somebody takes it: the two second decline is the bug. Wait for
the app to be hittable rather than for a fixed interval.

### 1b. The ink ramp now floors at WCAG AA — and the old gate never saw V2

`DesignTokenTests` measured `canvas = #17140F` and `ink = #F4EFE5`. Neither is
V2's palette. The near-black re-value therefore landed with **no contrast gate
over it at all**, and the suite stayed green while the shipping ground was
never measured.

Measured properly, `#F0EBDD` on `#0A0A09`:

| role | old alpha | contrast | verdict |
| --- | --- | --- | --- |
| `metadataProse` | 0.50 | 4.65:1 | AA |
| `deemphasisedItem` | 0.45 | 3.96:1 | large text only |
| `label` | 0.40 | 3.35:1 | large text only |
| `dateCount` | 0.35 | 2.82:1 | fails both |
| `headerMeta` | 0.32 | 2.53:1 | fails both |
| `recessive` | 0.30 | 2.36:1 | fails both |

The bottom three failed outright, and they are what the 9pt tracked DM Sans
labels use — the smallest text in the app, where WCAG's large-text allowance
(18pt / 24px) does not apply. §3's own strata ink (100 / 72 / 40 / 24) puts two
of Life's four bands below AA by design; the 24% band scores 1.91:1.

**Decision (Ryan, 2026-08-25): raise the floor to AA.** The AA threshold on the
lightest ground is 0.491 alpha, so the ramp now bottoms at 0.50 — worst step
4.63:1. The nine roles below `reasoning` were re-valued; the six that were
under the floor are now within thousandths of each other and **read as one
weight**. That is the accepted cost, and it is why Life's bands separate by
structure and rule weight instead. Swift forbids duplicate raw values in a
`Double`-backed enum, so they stay distinct and ordered rather than collapsed.

`everyInkStepClearsAAOnEveryV2Ground` is the gate. It reads the shipping tokens
through `WECanvas.alpha(for:)` rather than a copy of their hex values, covers
every `FieldInk` step against all three canvases plus the shared elevated
sheet, and was verified to fail — lower `recessive` back to 0.30 and it reports
2.36:1 by name. **Do not lower the floor to make something pass.**

### 2. Accessibility audit regression — fixed

**The recorded diagnosis was wrong in two ways, and both mattered.**

First, the failure was not in an audit at all. It was
`FieldZoneUITests.swift:1091`, `capture.waitForExistence` — `field.capture.input`
never appeared, so the audit never ran. Cause: `c0bfb61` chained
`.accessibilityHidden(true)` onto the *outer* stack of `FieldCaptureField`
rather than onto the border shape its comment describes, hiding the entire
capture surface, editor included, from assistive technology.

Second, and the reason six individual reverts each failed to fix it: **the
cause was the hiding, not any of the things being hidden.**
`.accessibilityHidden(true)` on a view that is not otherwise an accessibility
element *promotes it into one* in order to carry the flag, leaving a node with
nothing but the flag on it — which is precisely what
`.sufficientElementDescription` reports as "missing useful accessibility
information". Reverting the colour field, the zone identifier, the Dynamic Type
conversion, the canvas environment, the ambient wrapper or the capture field
never helped, because every one of those left the `accessibilityHidden` in
place.

Isolated by running the audit with an issue handler that printed each issue's
element frame, then bisecting: with the decoration present the audit reported
one node at `(0, 788, 440, 168)`; removing the decoration entirely gave zero
issues; reducing it to a bare `Color.clear` still gave one issue **until
`.accessibilityHidden(true)` came off**, at which point it gave zero.

Fixed in four places, all the same shape:

- `FieldCaptureField.swift` — the hiding moved inside `.overlay { }` onto the
  border shape it was written for
- `FieldZoneShell.swift` — the nav decoration is no longer marked hidden
- `WEColourField.swift` — the field no longer marks itself hidden
- `WEStillness.swift` — the same, for consistency

Colour and shapes are not accessibility elements to begin with, so nothing here
reaches VoiceOver either way; the audit now passes on both Today and Us.

**This also explains the two smoke failures**, which the handoff never recorded:
`testForTodayPutsSomethingOnTheClearDay` and
`testAAuthRecoveryPairingAndHueRoutes` (the latter as `field.onboarding.finish`
"not hittable"). The phantom node spanned the full width of the bottom of the
screen and intercepted hit testing. Both pass now without being touched.

### 3. Stale Promise tests — rewritten

`WEUITests.testLivingConfluencePromiseSupportsReducedMotion` (`:114`) and
`testTrustPromiseAndInvitationRemainReachableAtAccessibilityTextSize` (`:145`)
assert the pre-`3bc6dca` Promise: "You see what crosses.", "Shared is a new
space.", and buttons "Continue" / "Enter WE". All four exist only in those two
test files. The current beats are "Yours stays yours." / "Nothing moves without
you." / "What opens, opens together.", and the replay button is "Next".
`WEPromiseViewTests` additionally forbids a `"Continue"` literal in the Promise
source, so one test taps a button another test forbids existing.

Both rewritten against the three real beats, walking a single shared
`beatTitles` list so they cannot drift apart again, and driving the affordance
by `we.promise.give` rather than by its wording.

**That identifier did not work, and fixing it was an app change.**
`LivingConfluencePromise` carried `.accessibilityIdentifier("we.promise")` on
its root. An identifier on a container is inherited by every descendant, so the
give affordance and the held line were both reporting as `we.promise` and
`we.promise.give` / `we.promise.held` matched nothing at all. The root now uses
`.accessibilityElement(children: .contain)` instead, and the child identifiers
resolve — which the ceremony work needs directly, since C1 and C3 have to tap
give and assert held.

### 4. Navigation — settled

`LIFE · WE · US` stays fixed at the bottom, uppercase. The reference images put
it at the top in sentence case; that direction is declined. It remains the
single deliberate uppercase exception in the product. The former "Open design
question" section is removed rather than left to be reopened.

### 5. `testOnboardingOffersTheCalendarWithoutRequiringIt` — deleted

Confirmed: `field.onboarding.calendar.connect` exists nowhere, there is no
`EKEventStore` and no calendar-connect machinery, and `README.md:108` lists
external calendar accounts among the product's deliberate exclusions.

---

## Phase 3 — the ceremony

### 3d — present the Promise at arrival — done, needs live verification

Eligibility and the presentation point both landed. The pieces:

- `supabase/migrations/20260821120000_ceremony_eligibility.sql` —
  `couples.ceremony_required` plus `ceremony_is_required()`. **The column is
  added as `false` and only then defaults to `true`**, so adding it *is* the
  backfill for every couple that predates the ceremony, and a replay cannot
  un-require it for a new one. No acknowledgement row is ever forged: doing so
  would make the aggregate report a promise nobody made.
- `WECeremonySession.swift` — `WECeremonyPhase` with four cases
  (`loading`, `notRequired`, `required`, `complete`) and the reads behind them.
  `loading` exists because a default `WECeremonyState` has an empty `kept`, so
  "no answer yet" and "on beat one" are otherwise the same value — which is
  exactly how the Promise ends up flashing over the zones on a cold launch. A
  failed read holds the phase rather than falling back.
- `WECeremonyHost.swift` — presents `LivingConfluencePromise` above
  `FieldRoot`, gated on the phase, and joins the presence channel to re-read
  **the aggregate only** on each occupancy change.
- `FieldEntry.swift` — `FieldDurableBackend` now keeps `remote` alongside
  `outbox`. It previously discarded it, and `WECeremonyBackend` conformance is
  on the raw backend. Acknowledgements deliberately do not go through the
  outbox: one queued in a phone's outbox would let that phone believe a beat
  was given while the other cannot see it.

**Not driven by a state transition, deliberately.** The existing
`.waitingForPartner -> .ready` hook in `ContentView` reaches only the inviter
who is on screen at that instant, never the joiner, never the `.choosingHue`
route, and cannot survive a relaunch.

Proven hermetically in `WETests/WECeremonySessionTests.swift` (11 tests, green):
one phone cannot advance a beat alone, a relaunch resumes on the held beat,
a phone cannot read the other's acknowledgements, eligibility is not inferred
from row absence, and a failed read never presents the Promise on a guess.

See "Still outstanding on the ceremony" below: the migrations have not been
applied to a live project, so nothing has exercised the real Realtime seam or
the real RPC.

### 3f — Dylan's path, and arrival — done, needs live verification

**`WEInvitationArrival` replaces `JoinWithCodeView`.** The screen that stood
here opened with "Enter the code." over a form. The sentence now comes first
and the code field sits under it, in both directions:

- a `we://join/CODE` link resolves the name before the screen settles, so
  there is no field at all — one line, and a way on;
- a typed code buys the name *before* it buys an account, so the practical
  step still arrives after the sentence.

**The name needs a read that runs without a session**, which nothing in the app
had: every existing path is scoped by `my_couple_id()`, and the person reading
this line is not a member of anything.
`20260824120000_invitation_greeting.sql` adds `invitation_greeting(code)`,
granted to `anon`, returning **a first name and a hue and nothing else** for a
live invitation and null for everything else. A withdrawn, spent, expired or
invented code are indistinguishable there on purpose; `join_couple` still tells
its four refusals apart for somebody who has committed to spending one.

That disclosure is not a new one. The invitation screen already promises it in
as many words: "They'll see your name and nothing else." This is the first code
path that makes the promise true before redemption rather than after it. The
code is the credential, and `gen_join_code()` is sixteen hex characters from
`gen_random_bytes(8)`.

**Arrival.** `PartnerArrivalCeremony` was a paragraph explaining the moment to
somebody looking straight at it. It is now three words on the dark canvas with
both hues under them, and it is always about the *other* person, so neither
phone announces its owner to its owner. It also fires for the joiner now:
`.waitingForPartner -> .ready` only ever reached the inviter, and the person who
redeemed the code walked into a colour picker without the app acknowledging
that they had arrived anywhere.

**No haptic on arrival**, deliberately, against the original note. WE has
exactly one and it fires when a ceremony beat lands on both phones. Spending
the only piece of physical vocabulary the product has on the smaller of two
moments is a poor trade.

### 3h — Dylan declines — done, needs live verification

`20260824130000_invitation_decline.sql` adds `decline_invitation(code)`,
granted to `anon` for the same reason: requiring an account in order to say no
is the worst possible reading of what an invitation is. It revokes, by the same
route the inviter's own withdraw takes, and it is deliberately narrower than
the greeting that accompanies it — live invitations only, so a spent code
cannot be revoked by whoever still has a copy of it.

**Nothing records that a decline is what happened.** No table, no column, no
timestamp. A stored decline is a fact about somebody who deliberately did not
join, held in a space they never entered, and the only thing anybody could ever
do with it is show it to the person who was turned down.

The affordance sits under `Begin`, in the same typeface at the same size. A
decline drawn three shades quieter is the same funnel being coy about it.

Ryan meets `WEGateCopy.invitationClosedTitle` on a natural return, which names
nobody. His own withdrawal keeps the sentence that says he withdrew it — the
two are told apart by `invitationSent`, which only his own withdraw clears.

### 3i — gate copy and its governance — done

`WEGateCopy.swift` exists and holds every gate string. `WEGateCopyTests` was
applying its rules to a **hand copied array of literals kept beside it**, so a
view could be reworded into a violation and every rule would keep passing. Both
the views and the rules now read the same source.

Replaced: the welcome headline and its subtitle (one question, no eyebrow, no
restatement), "Start a WE space" to "Begin", the invitation label and its
button collapsed into "Someone invited me", "SIGN IN" to "Sign in", "Enter the
code." to the arrival sentence, the arrival paragraph to three words, "Replay
the Living Confluence Promise" to "See the beginning again", "How WE notices"
to "When WE interrupts you". The privacy line is cut; the Promise carries it.

Both live violations are fixed: `WEJourneyVisuals` no longer says "consent
threshold" to VoiceOver, and the em dash left with `JoinWithCodeView`.

**The tracked uppercase eyebrows are gone from the gate flow.** Every
`FieldGateScaffold(label:)` call site drops its label, along with "Saved on your
side" and "When you are ready" in `PairingView`. The deletion alone changes the
temperature more than any rewrite; "Past relationships" survives, because it
names a list that is otherwise ambiguous.

**A held code presents the invited person's screen by itself, once per launch.**
Somebody who tapped an invitation should not have to pick a door to be told who
sent it. Once, and not on every appearance, so dismissing it in order to sign in
does not put them straight back.

`WelcomeView` keeps its three doors. The cold open in the plan — one line, one
name field, no buttons row — would delete the join and sign in doors, and that
is a structural decision rather than a copy one. **Not done, and deliberately
left open.**

### 3c — push ("Dylan is here") — written, never exercised

All of it is new: `aps-environment` in `WE.entitlements`, `remote-notification`
in `WE-Info.plist`, a delegate whose only job is receiving a token,
`device_tokens` with owner only RLS in both directions, and
`supabase/functions/announce-arrival`.

- **A client cannot make the other phone speak.** The only writer of
  `arrival_notifications` is a trigger on `couple_members`, which is to say a
  successful redemption. No RPC, no grant, no writable path.
- **Idempotent by the primary key.** `couple_id` is it, so a couple has at most
  one arrival for as long as the couple exists. A replayed trigger or a retried
  worker cannot produce a second.
- **The payload is one fixed sentence** and has no room in it: no name, no
  couple, no badge, no sound, no custom keys. `WEArrivalNotificationTests`
  asserts the worker's string is the app's string, so the duplication across
  the language boundary cannot drift.
- **Marked delivered before it is sent, and never retried.** A worker that
  sends first announces twice the moment it is interrupted, and a push that
  arrives a day late is news about yesterday.
- **Permission denial changes nothing.** Nothing asks a second time, and
  `registerIfPermitted` has no way to ask at all — the one ask is still
  `FieldMomentDelivery.requestAuthorization`, after onboarding.

The migration schedules the worker the way the synthesis worker is scheduled,
with one difference: missing Vault secrets raise a **notice** rather than an
exception. The synthesis worker raises because a deployment that cannot
synthesise leaves every answer held forever while reporting success. This one
cannot leave anything held.

**`aps-environment` is deliberately not in the entitlements**, and the reason is
written where it was. Declaring it while the App ID lacks the Push
Notifications capability fails **every device build** at signing — "Provisioning
profile doesn't include the aps-environment entitlement" — while every
simulator lane stays green, because the simulator never signs. It was added,
it broke device builds, and it came back out.

To turn push on: target WE, Signing & Capabilities, add Push Notifications,
then restore the two lines from the comment in `WE/Config/WE.entitlements`.

**Outstanding, and it is all of the proof:** that capability, an APNs key, and
`arrival_worker_key` / `arrival_worker_url` in Vault. There is also no release
override for `aps-environment` once it is restored. Nothing has ever been sent.

---

## Phase 2 — done

`WEColourField`'s two states are implemented and are moments rather than
conditions: each plays once and settles back into the shared field, so a beat
held for an hour looks like a beat held for a second and the third beat is lit
like the first.

- **`.oneActed`** strengthens that person's hue by drawing a second copy of
  their own field over it, rather than by dimming the other. Dimming would be a
  statement about the partner, and there is nothing to state. The owner is
  always the viewer, and `LivingConfluencePromise` can only construct it from
  `held`, which is by definition this device having acted.
- **`.bothLanded`** draws the two fields toward one another over eight hundred
  milliseconds and deepens the shared atmosphere, then lets go. Under Reduce
  Motion both moments are carried by light alone, with no travel.

No haptic was added. The single shared one already fires correctly.

`LivingConfluencePromise` holds the landing on screen for a little over two
seconds, because the beat resolves and `currentBeat` advances in the same
instant. That is the one piece of ceremony timing not read from persisted
state, and it is safe to hold locally precisely because it says nothing: it is
triggered by the aggregate resolving, which both phones see at once.

---

## Still outstanding on the ceremony

**The migrations have not been applied to a live project.** Four now, not one:
ceremony eligibility, the invitation greeting, the decline, and the arrival
notification. Until they are, every screen above is proven in-process only.

**The two-simulator additions are written but have never run.** The three
assertions the hermetic suite can only make against a fake now live in
`FieldTwoSimulatorContractTests`, folded into the two existing role methods
rather than added as new ones, because the coordinator runs exactly one test
per role:

- A keeps a beat **before** the readiness barrier, so "the aggregate is still
  false" is a fact rather than a race, and asserts its own acknowledgement came
  back while the aggregate did not;
- B asserts the aggregate is false, keeps the same beat, and watches it flip;
- both select `profile_id` from `ceremony_acknowledgements` and assert every
  row that comes back is their own.

They skip without `WE_QA_*`, which are CI secrets. **A green local run means
skipped, not passed.**

## Phase 4 — Today, Life, retirement, receipts

Apply the system to Today (dark) then Life (cream). **Remove competing
interface elements before adjusting their appearance** — do not merely restyle
the existing density.

**Today.** One current decision or invitation dominates the page. Remove
section labels, counts, waiting summaries, repeated explanations, and the card
framing around the capture field. Add the persistent quiet capture line
immediately above the nav — "What is on your mind?" — expanding to a
full-screen composition surface on tap, with the colour field rising slightly
with the composition and settling after submission. **This does not exist
anywhere in the codebase yet.** `WE/Field/FieldCaptureField.swift` is the home.

**Life.** An editorial index rather than a database or task list. Whitespace
and typography instead of categories in containers.

Two defects already visible on the cream Life screen, deferred to this phase:

- the top-right controls (search / calendar) are near-invisible on cream
- content collides with the nav bar at the bottom

**Retirement as a real interface behaviour.** Nobody ships "gets quieter with
trust" as something you can see:

- the receipt explaining where a capture was filed stops explaining once
  corrections stop;
- labels that have been right many times remove themselves;
- a room that has proven itself loses its scaffolding;
- teaching text appears once, is learned, and does not return.

`FieldTeaching.swift` and `FieldAdaptation.swift` are the existing seams. When
WE changes its behaviour, show one quiet receipt — "Dinner ideas will go to
Food from now on." It appears once. Once the behaviour proves reliable the
receipt retires too.

**The learning principle.** As WE learns, the interface becomes more selective
rather than simply smaller. Repeated teaching, redundant explanations and
unnecessary interruptions compress over time, while orientation, confirmation,
privacy boundaries and access to reasoning remain stable.

A receipt may shorten, but WE always confirms that an input was safely
received. Reasoning may leave the primary surface but remains available through
"Why this?" When behaviour changes, confidence falls or the moment is higher
stakes, explanation returns.

The goal is earned restraint, not disappearance.

This is a correction rather than a restatement. "Learning removes interface"
read as licence to delete confirmation and reasoning along with the teaching
text, and those are the two things that must survive: a receipt that vanishes
entirely leaves somebody unsure whether their input landed, and reasoning that
becomes unreachable makes the app unaccountable exactly when it is least
predictable.

**The learning contract**, enforced by tests:

1. Private learning stays private. Ryan's private corrections cannot change
   what Dylan sees.
2. Shared adaptation requires shared evidence.
3. WE explains its own behaviour, never the relationship.
4. Learning makes the interface more selective, never absent. Teaching,
   repetition and interruption compress; orientation, confirmation, privacy
   boundaries and access to reasoning do not.
5. Explanation returns when behaviour changes, when confidence falls, or when
   the moment is higher stakes.
6. Everything learned can be corrected or reset.

**Deliverable: the same screen at week one and month nine, side by side**, as a
golden-image test rather than a mockup. This is the pairing in the user's
second reference image.

---

## Phase 5 — mutual stillness, utilities, cleanup

**Stillness, asked for by both.** One person presses, the other confirms, and
WE stills for both. Not muted, not snoozed. **Still.** Nothing surfaces,
nothing is held for later in a way you can feel accumulating, no badge on the
other side.

`WEStillness` already takes an `owner` parameter for exactly this — mutual
stillness is the same screen with a shared field. This is the third of the
user's reference images (ask → confirm → still).

**Build it as an asked-for gesture, never an inferred one.** Inferring
stillness from proximity needs a location signal, which is a privacy
concession this product should not make. The learning sits on top of the
gesture, so the mechanism is honest from day one and gets smarter without ever
getting closer.

**Utilities to cream.** `FieldAccountView`, `WEPrivacyPolicyView`, archives,
forms, offline states, errors — at conventional readable sizing, without
forcing every settings row into a dramatic composition.

**Walkthrough conversion.** Keep the journeys in
`WE/Walkthrough/WalkthroughJourney.swift` — they show the real rule and break
if it changes. Drop `progressIndex`, `nextTitle`, and `headerLabel`
("TODAY · HOME").

**Final sweep.** Remaining `FieldLabel` eyebrows, remaining `FieldCard` uses,
and any surviving legacy `DesignSystem.swift` / `WEHue.swift` /
`WEJourneyVisuals.swift` paths once nothing references them.

`FieldLabel` is now pinned to a ramp step rather than a fixed colour, so the
remaining ones are legible on both canvases while they wait to be deleted.

---

## Standing constraints — do not weaken

These are asserted by tests in several places. If a change requires relaxing
one, that is the thing to discuss, not to route around.

- **Never show one person the other's action before it lands.** `WEBeatState`
  has no case for "they acted and I have not" — from this device that is
  indistinguishable from nothing having happened, on purpose.
- **Nothing reports on the other person's timing, ever.** Three mechanisms
  keep this true and all three are load-bearing: owner-only RLS on select; the
  aggregate RPC returning a bare boolean per beat; and
  `ceremony_acknowledgements` being **deliberately absent from
  `FieldSupabaseBackend.observedTables`**, because a realtime row event
  carries its own arrival time. Asserted in `WECeremonyMigrationTests`.
- **Day thirty is day one.** Nothing time-varying may reach `WEStillness`.
  Asserted in `WEStillnessTests`.
- **Similar-pair resolution happens only after both commit**, offering nearby
  tonal variations to both at the same instant, revealing nothing about who
  chose what or when. The four muddy pairs are named in
  `FieldSwatch.blendIsMuddy` and asserted against the maths in both
  directions.
- **`FieldAccountView` deletion copy must not be strengthened** past
  `YoursCopy.deletionAssurance` ("Unrecoverable within 24 hours") until the
  key-service question closes.
- **WE never has an opinion about the relationship.** It may have opinions
  about its own behaviour and nothing else.
- **No decorative interface numerals** — steps, scores, counts, streaks,
  telemetry, "one of three". Meaningful user data (dates, prices, quantities,
  addresses, user-authored text) keeps localized numerals. Years are never
  spelled out as words.
- **Sentence case throughout.** The `LIFE · WE · US` navigation is the single
  deliberate uppercase exception.
- **No hyphens, en dashes, or em dashes in any copy.**
- **WE has no sound.** One shared haptic at the instant both acknowledgements
  land, and nothing else in onboarding. In particular not on arrival: that
  moment is three words and a field, and spending the product's only piece of
  physical vocabulary on it would leave the beats with nothing.
- **WE never sends a notification containing news, only ones inviting
  presence.** One fixed sentence, once per space, carrying no name, no count,
  no badge and no custom keys. Delivery failure and refused permission are the
  same product, and nothing ever reports that the other person was notified.
  Asserted in `WEArrivalNotificationTests`, across the language boundary.
- **The invited person is told, never asked, and never told off.** The screen
  that greets them cannot report on the state of an invitation somebody else
  made: a code that answers nothing is a quieter sentence, not an error.
- **Nothing records that a decline happened.** No table, no column, no
  timestamp, and no attribution in the copy the other person meets.
