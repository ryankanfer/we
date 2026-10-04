# Test baseline · October 2026

Recorded before the Today brief redesign, so that work is measured against a known
starting point rather than against "13 failures". Source: CI run
[37172198905](https://github.com/ryankanfer/we/actions/runs/37172198905) on
`165fd18` (PR 18), Xcode 26.3, iPhone 17 Pro, iOS 26.2.

The app builds. Ryan's local run reported 13 failures; CI shows 3 unit, 8 UI smoke and
6 database contract failures. The local count likely mixes unit and UI targets, so it
should be rechecked against this list rather than assumed to match.

## Unit tests: 3 of 709 fail, none caused by PR 18

| Test | What fails | Origin |
| --- | --- | --- |
| `FieldClassifierTests.theStretchIsSourcedOrOmitted` | Types "fast and furious" in lower case and expects Watchlist. The title rule now needs capitals ("Fast and Furious"), so it grows a Fast category. | `c25e597` (title capitalisation rule), before this branch. Fix the test input to title case. |
| `WECeremonyTests.theBeatsAreTheApprovedWords` | `yoursStaysYours.detail` reads "Anything you mark Only me stays with you until you share it with Dylan." The test still expects "Nothing you write reaches Dylan unless you send it." | `ef92538`. Copy changed, test did not. Decide which line is approved, then align. |
| `WEGateCopyTests.itIsSentenceCase` | `WEOnlyMeCopy.readyLabel = "READY TO SHARE"` is uppercase, which the gate copy rule forbids. | `5261057`. It is drawn through `FieldLabel`, which uppercases anyway, so store it as "Ready to share". |

## UI smoke: 8 of 10 fail on selectors the app no longer has

All in `FieldZoneUITests`. They predate PR 18.

1. `testZoneNavigationByLabelAndBySwipe` and `testSigningOutLeavesTheZones` wait for `field.nav.we`. The bar is Today · + · Life; there is no WE tab.
2. `testUsExplainsItselfBeforeItHoldsAnything`, `testUsHeldRevealsNoPartnerStatus`, `testUsProposalAndActiveJourneyStayFocused`, `testUsQuestionIsOnePrivateEvidenceBackedChoice` wait for `field.nav.us`. Us is no longer a zone; it lives in Life as Where we're headed.
3. `testCaptureProducesAReceipt` and `testForTodayPutsSomethingOnTheClearDay` wait for `field.capture.input` as a text view after tapping +. That identifier belongs to the retired inline capture field, not the + card.

These need rewriting against the current navigation, not patching; that is a separate change.

## Database contract: 6 of 28 fail in `field_solo_visibility.test.sql`

Tests 9, 11, 18, 21, 22 and 24, all about Only me visibility and the private to shared
crossing. PR 18 changes no SQL. These guard the privacy promise, so they are the most
important of the three groups to resolve, and they need someone with database access
to confirm whether the migrations or the test expectations moved.
