# Connect the living backend

The native app now uses the same Supabase schema as the web prototype.

## 1. Resolve the Swift package

Open `WE/WE.xcodeproj`. Xcode should resolve the `Supabase` product from:

`https://github.com/supabase/supabase-swift.git`

If it does not, choose **File → Packages → Resolve Package Versions**.

## 2. Add the local environment values

The project deliberately does not commit the Supabase publishable key.

1. In Xcode, choose **Product → Scheme → Edit Scheme…**
2. Select **Run → Arguments**.
3. Under **Environment Variables**, add:
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
4. Copy their values from the repository root `.env.local`:
   - `NEXT_PUBLIC_SUPABASE_URL` → `SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` → `SUPABASE_PUBLISHABLE_KEY`
5. Keep both variables checked.

These are launch-time values for the local Xcode scheme. They are not added to
source control.

## 3. Run the live repository

Do not set `WE_REPOSITORY`, or set it to `live`.

Run WE and sign in with an existing email/password account. The app:

1. persists the Supabase session,
2. restores it at the next launch,
3. reads the profile and membership,
4. reads the couple and both members,
5. reads insights, consent rows, response rows, and private reflections,
6. shows live profile/partner names and live insight content.

Sign out from the bottom of the WE space.

## 4. Select preview data

For design work without the backend, add this checked Run environment variable:

`WE_REPOSITORY` = `preview`

Remove it or change it to `live` to return to Supabase.

## 5. Verify session restoration

1. Run the app and sign in.
2. Stop it from Xcode.
3. Run it again.
4. Confirm it opens the same shared relationship without showing sign-in.
5. Open the WE space, sign out, and confirm the sign-in screen returns.
