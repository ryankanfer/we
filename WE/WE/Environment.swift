import Foundation

struct SupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String
}

enum RepositoryMode: String, Sendable {
    case live
    case preview
}

struct AppEnvironment: Sendable {
    let repositoryMode: RepositoryMode
    let supabase: SupabaseConfiguration?

    static var current: AppEnvironment {
        let values = ProcessInfo.processInfo.environment
        let mode = RepositoryMode(
            rawValue: values["WE_REPOSITORY"]?.lowercased() ?? ""
        ) ?? .live

        let urlString = firstValue(
            in: values,
            keys: ["SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL"]
        ) ?? Bundle.main.object(
            forInfoDictionaryKey: "SUPABASE_URL"
        ) as? String

        let key = firstValue(
            in: values,
            keys: [
                "SUPABASE_PUBLISHABLE_KEY",
                "SUPABASE_ANON_KEY",
                "NEXT_PUBLIC_SUPABASE_ANON_KEY"
            ]
        ) ?? Bundle.main.object(
            forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"
        ) as? String

        let configuration: SupabaseConfiguration?
        if let urlString,
           let url = URL(string: urlString),
           let key,
           !key.isEmpty {
            configuration = SupabaseConfiguration(
                url: url,
                publishableKey: key
            )
        } else {
            configuration = nil
        }

        return AppEnvironment(
            repositoryMode: mode,
            supabase: configuration
        )
    }

    private static func firstValue(
        in values: [String: String],
        keys: [String]
    ) -> String? {
        keys.lazy
            .compactMap { values[$0] }
            .first { !$0.isEmpty }
    }
}
