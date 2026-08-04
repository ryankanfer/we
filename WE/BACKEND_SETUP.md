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

The committed `WE.xctestplan` is the source of truth for native tests. Pull requests publish
three stable checks that should be required by the default branch ruleset:

- `Schema + privacy contract`
- `iOS build + unit`
- `Critical UI smoke`

The database check rebuilds an isolated local Supabase stack from all migrations, runs every
pgTAP contract, and fails on schema-lint warnings. In addition to the existing native-product
tests, `field_couple_contract.test.sql` exercises the production pairing RPCs as Partner A,
Partner B, and an outsider. It proves server-owned actor attribution, RLS isolation, private
answers, safe mutual reveal, and realtime publication.

The Swift unit lane includes a transport-backed adapter contract that executes every live Field
query and decodes the real PostgREST row shapes. The nightly live contract uses three isolated
authenticated clients against a disposable QA Supabase project and covers pairing, onboarding,
Partner B capture/correct/send, realtime arrival, restart, sign-out/sign-in, private answers,
mutual reveal, account deletion, and the survivor archive. A second paired cohort then runs in
two distinct simulator-hosted app processes: Partner A establishes a Realtime subscription,
Partner B writes from the other simulator, and A must observe the capture as B. The service role
never enters either app process; host coordinators use it only for exact user/couple setup and
cleanup.

The serial UI lane freezes the clock and animations. Nightly runs small and large iPhones plus a
maximum-Dynamic-Type/Reduce-Motion/Reduce-Transparency profile, performs XCTest accessibility
audits, compares named screenshots with committed references, and uploads the `.xcresult`,
screenshots, diagnostics, and visual diffs even on failure. The app and WidgetKit extension are
built together. A shared renderer also produces small/medium widget-content goldens; the
SpringBoard/Lock Screen chrome and tinted host transformations remain outside public automation.

Run the same database gate locally with Docker Desktop running:

```bash
bash scripts/qa/run-supabase-contract.sh artifacts/supabase
```

Run a native lane against a prepared simulator with:

```bash
bash scripts/qa/run-xcode-tests.sh unit \
  "platform=iOS Simulator,id=<UDID>" \
  artifacts/xcresults/unit.xcresult \
  artifacts/DerivedData/unit
```

The remaining hands-on gates are genuinely human or operational:

1. Use VoiceOver end to end and judge whether the language, order, and custom actions make sense,
   not only whether the accessibility API reports no audit issue.
2. Inspect the supported WidgetKit families in their real SpringBoard/Lock Screen hosts; the
   automated goldens cover WE-owned content, not system-owned chrome.
3. Review Supabase security advisors and confirm production callback URLs.
4. Validate Private / Shared / Mutual, navigation, and emotional clarity with five target
   couples.

Do not mark the milestone release-ready until the required checks and nightly contract pass,
these human gates are complete, and local scheme credentials remain uncommitted. Tests are never
retried automatically; any temporary quarantine needs a named owner, linked defect, and expiry.
