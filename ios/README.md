# WE — iOS (SwiftUI)

A native SwiftUI front end on the same Supabase backend as the web app. Same tables, same
row-level security, same consent RPCs — the DB and the privacy model are shared, not reimplemented.

## Run it (on a Mac with Xcode 15+)

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonik/XcodeGen):

```bash
brew install xcodegen         # once
cd ios
xcodegen                      # writes WE.xcodeproj
open WE.xcodeproj
```

Then in Xcode: select a simulator (or your iPhone) and press ⌘R. The Supabase Swift package
resolves automatically on first build.

**Prefer not to use XcodeGen?** Create a new iOS App in Xcode (SwiftUI, name `WE`), delete its
starter files, drag the contents of `ios/WE/` into the project, and add the Swift package
`https://github.com/supabase/supabase-swift` (product **Supabase**) under Package Dependencies.

## Backend

`Config.swift` points at the `we-round1` Supabase project with the publishable key (safe to ship;
RLS protects the data). For sign-up to work instantly, turn **off** "Confirm email" in
Supabase → Authentication → Providers → Email. Two test accounts already exist:
`ry@we.test` / `dylan@we.test`, password `wetest1234`.

## What's here

- `Config.swift`, `Theme.swift`, `Components.swift` — backend config, design tokens, the interlock mark + shared UI.
- `Models.swift` — the consent domain model and `Consent.project(...)`, a faithful port of the web `lib/consent.ts` (private answers and reflections never surface to the partner until revealed).
- `Session.swift` — auth, pairing, data loading, and the consent RPCs.
- `Views/` — Splash, Onboarding, Auth, Pairing, Today (with the reveal flow in `InsightDetailView`), Plan, Home, Profile.

The consent loop (Today → open a card → bring it to us → reveal) is real and talks to the live
backend. Plan / Home content is seeded, matching the web dashboard.

## Status

First scaffold — authored without a local Xcode toolchain, so expect a compile pass to shake out
small fixes. Realtime sync is not wired yet (the app reloads after each action); pull-to-refresh
and realtime are the natural next additions.
