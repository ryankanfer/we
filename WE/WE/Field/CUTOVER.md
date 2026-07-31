# Cutover

The zones are the app. `WEApp` hands the screen to `FieldRoot` the moment
`AppSession.State` is `.ready`; everything before that — sign in, verification,
password recovery, pairing — still runs through `ContentView`.

## The account surface

The zones carry no chrome, so the WE mark carries the account: tap returns to
Today, **long-press opens `FieldAccountView`** — colours, signal consent, sign
out, and deletion.

It is not a nicety. Deleting the tab bar took `ProfileView` with it, and with
it the only route to `AppSession.deleteAccount` — which App Store guideline
5.1.1(v) requires to be reachable in-app. Between the cutover and this, the
app could not have been submitted.

A long press does not exist for VoiceOver, so the mark also carries an
`.accessibilityAction(named: "Account")`. **That action is the entire
VoiceOver route to deletion.** XCUITest cannot enumerate custom actions, so
nothing guards it automatically — check it in the Accessibility Inspector
before shipping.

## The bug that hid behind two others

`SessionHost` exposes `@Published private(set) var session: AppSession`, which
fires only when the *reference* is replaced — never when something inside the
session changes. `WEApp` reads `host.session.state` to decide between the zones
and `ContentView`, so that decision was made once at launch and never revisited.

Two symptoms, which looked unrelated:

- **Signing out did nothing.** The session went to `.signedOut`; the zones
  stayed on screen.
- **The Living Confluence Promise never appeared**, in any state.

`SessionHost` now forwards the session's `objectWillChange`, and both work.
`.ready` is still listed in `showsPromise` and is still dead — `FieldRoot`
takes the screen first — so the Promise now runs for the pre-couple states
only. Whether it should also greet someone who arrives already paired is a
product call, not a bug.

Worth remembering when reading anything else here: a nested `ObservableObject`
publishes nothing to its parent's observers.

## Sample data, and where it is allowed

The fictional couple used to reach real screens. `FieldStore`'s defaults are
`FieldState.seed` and `FieldSampleData.today`, and the live roots took them —
so a real couple saw Ryan and Dylan's groceries, and every date calculation ran
against 13 August 2025.

`FieldState.empty(nameA:nameB:now:)` is the live default now, carrying the
couple's own names from the session, and both roots pass `Date()` explicitly.

**Where sample data is still correct:**

- `WE_FIELD=gallery` and `WE_FIELD=seeded`, which exist to show the design.
- Five screens reachable *only* from the gallery — `FieldPresenceView`,
  `FieldDailyMomentView`, `FieldCorrectionReceiptView`, `FieldDeferralView`,
  `FieldSeasonClosedView`. Nothing routes to them from a zone, so their
  narrative is a rendering of the handoff, not something a user is told.
- Copy quoted from the spec: the onboarding questions, the closing line, and
  the four canonical capture phrases, which the handoff specifies as a
  demonstration of classification.

**What now derives from real state:** Life's category counts, ordering, and
summaries; Ours' totals and filter counts.

**What was removed rather than faked.** "The shape of this week" and the Ours
payoff card are the app speaking in its own voice, and nothing generates
either. Printing the handoff's prose told a real couple their week was
front-loaded and that they had committed $540. `FieldWeekSynthesis` and
`FieldOursPayoff` now exist as types; `FieldStore.weekSynthesis` and
`.oursPayoff` return nil, and the blocks do not render. Restore them with a
generator reading `store.state` — not by putting the strings back. Silence is
the app's own rule: it "stays quiet rather than manufacturing a reason to
speak."

## What still runs the old way, and why

**Sign in, verification, password recovery, and pairing** still run through
`ContentView`. They work and they are not zones; restyling them is cosmetic.
This is what keeps the files in the table below alive.

**Hue choice is now 6f.** `ContentView`'s `.choosingHue` renders
`FieldOnboardingRoot` — colour, three questions, and a calendar. Finishing
writes the swatch through `FieldStore` *and* the nearest `MemberHue` through
`session.updateHue`, because `couple_members.hue` is still a column. The
mapping lives in `FieldSwatch.memberHue`.

**Anchors, Threads, and Seasons** load empty from Supabase. They exist in the
domain and in `FieldThreadsView`, but the migration has no tables for them yet —
the old schema stores anchors and seasons in a different shape, and merging the
two is a decision, not a mapping.

## One moment a day (6c)

Delivered locally, not by a server. `FieldMomentScheduler.decide` still answers
"would I speak now" for the in-app surface; `FieldMomentDelivery` answers "when,
and with what" and hands it to `UNUserNotificationCenter`.

- Authorisation is requested at the end of 6f and nowhere else, `.alert` and
  `.sound` only — **never `.badge`**, because the handoff forbids badge counts
  and the app should not hold the right to set one.
- One fixed request identifier, so rescheduling replaces rather than
  accumulates. That is what makes "no second attempt" true at the OS layer and
  not only in `decide`.
- Re-planned on every foreground *and* background: a local notification freezes
  its content when scheduled, so this is the only thing preventing a moment
  arriving about something already done.

The remaining limitation is inherent to local delivery — if the app is not
opened for days, the content stops being re-planned. Moving to APNs is the fix,
and it is a deliberate non-goal for now.

## Files deleted

Done, with a green build behind each group:

```
WE/WE/AppShell.swift
WE/WE/WEView.swift
WE/WE/LifeView.swift
WE/WE/AheadView.swift
WE/WE/V2ExperienceViews.swift
```

Three things had to be lifted out of them first, because the pre-couple flow
still needs them:

- `relationshipPartnerHue(_:)` — was in `WEView`, now in `WEHue.swift`.
  `ProductComponents` is the only caller left.
- `ResponsibilityOwner.title` — was an extension in `LifeView`, now on the enum
  itself in `Models.swift`. Profile's archive rows read it.
- `SignalConsentView` and `ModeSettingsView` — were the only live views left in
  `V2ExperienceViews`, now in `ProfileSettingsViews.swift`. Profile reaches
  both by `NavigationLink`.

`String.nilIfEmpty` went with `LifeView` and was not replaced; nothing used it.

## What the original list got wrong

The rest of the list cannot be deleted, and the reason is the same in every
case: `WEApp` still renders `ContentView` for every state before `.ready`, and
`ContentView` reaches all of it.

| File | Reached by |
| --- | --- |
| `ContentView.swift` | `WEApp`, for sign in / pairing / hue |
| `ProfileView.swift` | `ContentView`, as a sheet |
| `HueSelectionView.swift` | `ContentView` → `HueOnboardingView` |
| `WEConfluenceForm.swift` | `HueSelectionView` |
| `SoftStartView` / `SoftStartCoordinator` | `ContentView`, `WEApp` |
| `LivingConfluencePromise.swift` | `WEApp` |
| `VisualEngineCoordinator.swift` | `WEApp` |
| `DesignSystem.swift` | `.weSettle`, used throughout the above |
| `WEHue.swift`, `WEMark.swift` | `ContentView`, `SignInView` |
| `ProductComponents.swift` | `SignInView`, `ProfileView`, `SoftStartView` |
| `CinematicVisuals.swift`, `WEJourneyVisuals.swift` | `ProfileView` |
| `WETests/DesignTokenTests.swift` | covers `WEHue`, which stays |

All of it goes when 6f replaces pairing and hue choice with Field-native
screens. Not before — deleting `ContentView` today means the app has no way in.

`WEHue` and `MemberHue` are the awkward pair. `MemberHue` is a database enum in
`couple_members.hue` and cannot be dropped without a migration; `WEHue` is its
view layer and can. `FieldSwatch` supersedes both, and `field_identity` is where
colour lives now — but the old column stays until something migrates it.

Keep everything else. `AppSession`, `SessionHost`, `Repository`,
`SupabaseRepository`, `TrustCore`, `SignInView`, `WEDeepLinkRouter`,
`ConnectivityMonitor`, `WEShared`, and `WEWidgets` are all still load-bearing.

## WEUITests

All nine fail. They drive the deleted tab-bar shell — `LifeView`, the Ahead
tab, the old profile route — and were already failing before this pass, from
the moment `WEApp` started handing `.ready` to `FieldRoot`. They need to be
rewritten against the zones or deleted; they are not evidence of a regression.

## Before it will run against real data

```
supabase db push
```

`20260729193000_private_answers_shared_directions` and
`20260730120000_field_zones` are applied.
**`20260730210000_field_onboarding_answers` is not** — it adds
`lives_together`, `saving_for`, and `looks_after` to `field_identity` for 6f's
three questions. Until it is pushed, the answers are held in memory and the
`setIdentity` upsert fails against the live database.

A brand-new couple will land on an entirely empty Us and Life. That is correct —
the app is supposed to earn its knowledge by observation — but it means the
first run shows "Nothing needs you here" against a blank horizon. Seed one
horizon and a handful of Life items to see it working, or run `WE_FIELD=seeded`
for the fictional couple.
