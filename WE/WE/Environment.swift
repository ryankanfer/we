import Foundation

struct SupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String
}

enum RepositoryMode: String, Sendable {
    case live
    case preview
}

enum PreviewScenario: String, Sendable {
    case ready
    case empty
    case offline
    case error
    case waiting
    case archived
    case signedOut = "signedout"
    case choosingHue = "choosinghue"

    init(environmentValue: String?) {
        let value = environmentValue?.lowercased() ?? ""
        if value == "failure" {
            self = .error
        } else {
            self = PreviewScenario(rawValue: value) ?? .ready
        }
    }
}

struct AppEnvironment: Sendable {
    let repositoryMode: RepositoryMode
    let supabase: SupabaseConfiguration?
    let previewScenario: PreviewScenario
    let previewDeletionPassword: String?

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
            supabase: configuration,
            previewScenario: PreviewScenario(
                environmentValue: values["WE_PREVIEW_SCENARIO"]
            ),
            previewDeletionPassword: values[
                "WE_PREVIEW_DELETION_PASSWORD"
            ]
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
