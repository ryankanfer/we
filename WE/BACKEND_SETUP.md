# WE native backend setup

The SwiftUI app uses Supabase for authentication, pairing, shared data, consent, realtime
updates, account deletion, and sanitized relationship archives.

## 1. Resolve the Swift package

Open `WE/WE.xcodeproj`. Xcode should resolve the `Supabase` product from:

`https://github.com/supabase/supabase-swift.git`

If needed, choose **File → Packages → Resolve Package Versions**.

## 2. Add local credentials

The project does not commit its Supabase publishable key.

1. In Xcode choose **Product → Scheme → Edit Scheme…**
2. Select **Run → Arguments**.
3. Add checked environment variables:
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
4. Copy their values from the repository-root `.env.local`:
   - `NEXT_PUBLIC_SUPABASE_URL` → `SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` → `SUPABASE_PUBLISHABLE_KEY`

The shared local scheme and Supabase temporary directory are ignored by Git. Before every
commit, confirm no URL, publishable key, service-role key, password, or session token is staged.

## 3. Configure authentication callbacks

Add both native URLs to the Supabase Authentication redirect allowlist:

```text
we://email-confirmed
we://password-recovery
```

The app registers the `we` URL scheme in `Config/WE-Info.plist`. Email verification and
password-recovery links return through these routes.

Native authentication supports:

- account creation with name and email verification,
- verification-pending routing,
- email/password sign-in and session restoration,
- password-reset email and in-app password update,
- sign-out with protected-cache removal,
- password-confirmed in-app account deletion.

## 4. Apply the database migrations

The native product is defined by the timestamped migrations in `supabase/migrations`, including:

- base profiles, couples, memberships, insights, consent, responses, and reflections,
- plans, responsibilities, archives, account deletion, and realtime publication,
- archive sanitization and trust/privacy hardening,
- owner-only private declines and advisory-locked plan/responsibility write functions.

Using a Supabase CLI linked to the intended project:

```bash
supabase migration list --linked
supabase db push --linked
supabase db lint --linked
```

Review the target project and migration list before pushing. Never use a service-role key in the
app.

## 5. Data and privacy behavior

`plans` and `responsibilities` are shared only with members of an active couple. Either partner
may edit, complete, or archive an item. Creator and last-editor attribution are set on the
server, and shared writes run through database functions guarded by relationship advisory locks.

When an account is deleted, one locked database operation:

1. verifies the requester,
2. creates a versioned owner-only archive for the surviving partner,
3. includes plans, responsibilities, and completed mutual-reveal resolutions,
4. excludes all private or unrevealed material,
5. removes the live couple and requester data, and
6. returns the survivor to Pairing with read-only archive access.

## 6. Run live or preview data

For the live repository, omit `WE_REPOSITORY` or set it to:

```text
WE_REPOSITORY=live
```

For backend-free UI work:

```text
WE_REPOSITORY=preview
```

Preview scenarios are selected with `WE_PREVIEW_SCENARIO`:

```text
ready
empty
offline
error
waiting
archived
signedout
choosinghue
```

The preview repository implements authentication, pairing, trust transitions, plans,
responsibilities, archives, profile/hue changes, and account deletion without network access.

### Paired test account

Select the shared **WE Test Account** scheme in Xcode and run it on a simulator or device.
The app opens directly into a complete paired relationship for Ryan and Dylan, so no invitation
or second session is required. This scheme:

- uses only `PreviewRepository` data,
- never reads or writes the live Supabase project,
- supports local plan, responsibility, profile, and trust-flow testing, and
- resets to the paired preview fixture whenever the app is relaunched.

Switch back to the **WE** scheme for live authentication, pairing, realtime, and backend tests.

## 7. Offline cache

WE stores one versioned relationship snapshot per signed-in profile with iOS file protection.
Cached mode is read-only, shows the last synchronization time, and disables mutations until the
connection returns. The cache is purged on sign-out and account deletion. An invalid online
Supabase session is not allowed to reopen cached relationship data.

## 8. Verification

Automated Swift tests cover auth routing, preview variants, trust transformations, archive
decoding, cache fallback, connection transitions, and shared-item behavior. UI tests cover the
Promise, auth/recovery/pairing/hue routes, native tabs, contextual creation, Profile, account
deletion, resilience states, Insight Detail, and a core accessibility audit.

Database tests live in `supabase/tests/native_product.test.sql` and cover partner/outsider
access, archived access, pairing concurrency, shared CRUD, realtime publication, account
deletion, archive sanitization, and private/unrevealed leakage.

Run before release:

```bash
supabase test db
supabase db lint --linked
xcodebuild -project WE/WE.xcodeproj -scheme WE build
```

Also complete these hands-on gates:

1. Pair two authenticated simulator/device sessions.
2. Exercise shared CRUD and the full request → accept → both submit → mutual-reveal loop.
3. Restart both sessions and verify restoration.
4. Disconnect, verify protected read-only cache behavior, reconnect, and verify refresh.
5. Delete one account and inspect the survivor’s sanitized archive.
6. Test small and large iPhones, largest Dynamic Type, VoiceOver, and Reduce Motion.
7. Review Supabase security advisors and confirm callback URLs.
8. Validate Private / Shared / Mutual and navigation with five target couples.

Do not mark the milestone release-ready until all gates pass and local scheme credentials remain
uncommitted.
