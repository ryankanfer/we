import Supabase

struct SupabaseClientProvider: Sendable {
    let client: SupabaseClient?

    init(configuration: SupabaseConfiguration?) {
        client = configuration.map {
            SupabaseClient(
                supabaseURL: $0.url,
                supabaseKey: $0.publishableKey
            )
        }
    }
}
