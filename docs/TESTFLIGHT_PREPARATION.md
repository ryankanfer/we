# TestFlight preparation — 9 September 2026

Version 1.0, build 4 for WE and both embedded extensions. iPhone only, portrait.
The ordinary WE Run scheme now uses live mode. Archive uses Release.

Public client configuration lives in `WE/Config/Client.xcconfig`, attached to
both WE build configurations. Source Info.plist uses build-setting substitutions.
The URL and publishable key remain recoverable from the built app, as expected
for Supabase public client configuration. Never place a service-role key here.

The encryption declaration is NO. The inspected uses are Apple URLSession TLS
and Apple CryptoKit AES-GCM; swift-crypto reexports CryptoKit on Apple platforms.

## App Store Connect values

- Privacy Policy URL: https://we-privacy-policy.kanfery.chatgpt.site
- Support URL: https://we-privacy-policy.kanfery.chatgpt.site
- Contact email: kanfer.ryan@gmail.com

The policy site is publicly readable and its Contact section provides email
support. Both URL fields were saved and verified in App Store Connect on 9 September.
The created listing is WE by Ryan Kanfer, Apple ID 6810233376, SKU WE-iOS,
bundle ID com.ryankanfer.WE. TestFlight shows no uploaded builds, so build 4
is not in use there. The on-device app name remains WE.

## Accepted surfaces

Account → How WE responds contains Presence, One moment a day, What I'm
watching, What I've changed, and Past seasons. The routes inherit the live
FieldStore. Corrections also appear in the current Us goals surface when
there are derived changes.

Presence renders actual shared away windows. No away window does not claim
that the person is available. Daily moment is a preview, not proof that the
OS delivered a notification. Deferrals and corrections have honest empty states.
Past seasons lists only closed records; the current backend returns no season
records, so this beta shows an explicit empty state. A season lifecycle or
archive feature has not been implemented by this preparation work.

The route UI test uses the live root and an empty preview repository; it does
not use the gallery/seed modes or a production account. Device/backend behavior
still requires a signed-in smoke test.

## Validation

- Final unsigned iPhone Release build: BUILD SUCCEEDED.
- Built WE.app: version 1.0, build 4, UIDeviceFamily [1], portrait only,
  ITSAppUsesNonExemptEncryption false. Both embedded extensions: build 4.
- Supabase public URL/key substitutions resolved in the built app.
- Focused simulator run: TEST SUCCEEDED, all four selected tests passed.
  - FieldBackendConformanceTests.testTheStubServesALoadAndRecordsAWrite
  - FieldBackendConformanceTests.testTheSupabaseBackendHonoursTheSameContract
  - FieldSupabaseAdapterContractTests.testEveryLiveFieldRowDecodesWithPartnerBOwnership
  - BetaSurfaceRoutingUITests.testAcceptedSurfacesOpenFromLiveRootWithoutGalleryOrSeed

No archive, upload, App Review submission, production account mutation, or
backend migration was performed. Full App Store listing and data-collection
questionnaire are not completed by these URL updates.
