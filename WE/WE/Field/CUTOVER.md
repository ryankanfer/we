# Cutover

The zones are the app. `WEApp` hands the screen to `FieldRoot` the moment
`AppSession.State` is `.ready`; everything before that — sign in, verification,
password recovery, pairing — still runs through `ContentView`.

## What still runs the old way, and why

**Pairing and hue choice.** Onboarding 6f replaces both, but it is currently
only the colour picker. The three questions and the calendar connection are not
built. Until they are, `ContentView` handles pairing.

**Push notifications.** 6c is designed and its scheduler
(`FieldMomentScheduler`) is written and tested, but nothing registers for
notifications or schedules one. The lock screen in the gallery is a rendering
of what would be sent.

**Anchors, Threads, and Seasons** load empty from Supabase. They exist in the
domain and in `FieldThreadsView`, but the migration has no tables for them yet —
the old schema stores anchors and seasons in a different shape, and merging the
two is a decision, not a mapping.

## Files to delete once it builds green

Not deleted yet, deliberately: without a compiler here, removing a file that
something still references would leave the build broken with no way to fix it
until the next session. They are unreferenced now, so they cost nothing but
tidiness.

Verify with Xcode's *Find → Find in Workspace* that each has no remaining
callers, then delete:

```
WE/WE/AppShell.swift
WE/WE/ContentView.swift          # after moving SignInView routing out
WE/WE/WEView.swift
WE/WE/LifeView.swift
WE/WE/AheadView.swift
WE/WE/V2ExperienceViews.swift
WE/WE/ProfileView.swift
WE/WE/HueSelectionView.swift
WE/WE/WEConfluenceForm.swift
WE/WE/DesignSystem.swift
WE/WE/WEHue.swift
WE/WE/WEMark.swift
WE/WE/ProductComponents.swift
WE/WE/CinematicVisuals.swift
WE/WE/WEJourneyVisuals.swift
WE/WE/SoftStartView.swift
WE/WE/SoftStartCoordinator.swift
WE/WE/LivingConfluencePromise.swift
WE/WE/VisualEngineCoordinator.swift
WE/WETests/DesignTokenTests.swift
```

`WEHue` and `MemberHue` are the awkward pair. `MemberHue` is a database enum in
`couple_members.hue` and cannot be dropped without a migration; `WEHue` is its
view layer and can. `FieldSwatch` supersedes both, and `field_identity` is where
colour lives now — but the old column stays until something migrates it.

Keep everything else. `AppSession`, `SessionHost`, `Repository`,
`SupabaseRepository`, `TrustCore`, `SignInView`, `WEDeepLinkRouter`,
`ConnectivityMonitor`, `WEShared`, and `WEWidgets` are all still load-bearing.

## Before it will run against real data

```
supabase db push
```

Two migrations are pending: `20260729193000_private_answers_shared_directions`
(from the earlier session, and the cause of the "could not find the table"
error) and `20260730120000_field_zones` (the Field tables).

A brand-new couple will land on an entirely empty Us and Life. That is correct —
the app is supposed to earn its knowledge by observation — but it means the
first run shows "Nothing needs you here" against a blank horizon. Seed one
horizon and a handful of Life items to see it working, or run `WE_FIELD=seeded`
for the fictional couple.
