import Supabase

/// The app's one Supabase client.
///
/// **There must only ever be one.** Every `SupabaseClient` runs its own auth
/// with its own in-memory session and its own refresh timer, but they all
/// share one Keychain. Three of them — the repository's, `FieldRoot`'s, and
/// `FieldOnboardingRoot`'s — meant signing out cleared the session on one
/// while the others carried on holding it, and a background refresh from
/// either of the survivors wrote a valid session straight back into the
/// Keychain. Sign out appeared to do nothing, and because the Keychain
/// outlives app deletion, a reinstall came back already signed in.
///
/// `shared` is a `static let`, so it is created once, lazily, and safely.
struct SupabaseClientProvider: Sendable {
    let client: SupabaseClient?

    /// Use this everywhere. Construct a provider directly only in tests, and
    /// only when a genuinely separate client is the point.
    static let shared = SupabaseClientProvider(
        configuration: AppEnvironment.current.supabase
    )

    init(configuration: SupabaseConfiguration?) {
        client = configuration.map {
            SupabaseClient(
                supabaseURL: $0.url,
                supabaseKey: $0.publishableKey
            )
        }
    }
}
