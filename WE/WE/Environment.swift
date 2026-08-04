import Foundation
import SwiftUI

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

/// Deterministic knobs used only by automated UI and screenshot contracts.
///
/// These are environment variables rather than persisted preferences so a
/// test process cannot leak its clock or accessibility settings into the next
/// launch. None of them is set by a shipping scheme.
struct AppTestConfiguration {
    let frozenNow: Date?
    let disablesAnimations: Bool
    let reduceMotion: Bool?
    let reduceTransparency: Bool?
    let dynamicTypeSize: DynamicTypeSize?

    static var current: AppTestConfiguration {
        let values = ProcessInfo.processInfo.environment
        return AppTestConfiguration(
            frozenNow: parseDate(
                values["WE_QA_FIXED_NOW"] ?? values["WE_TEST_NOW"]
            ),
            disablesAnimations: bool(
                values["WE_QA_DISABLE_ANIMATIONS"]
                    ?? values["WE_TEST_DISABLE_ANIMATIONS"]
            ) ?? false,
            reduceMotion: bool(values["WE_TEST_REDUCE_MOTION"]),
            reduceTransparency: bool(
                values["WE_TEST_REDUCE_TRANSPARENCY"]
            ),
            dynamicTypeSize: dynamicTypeSize(
                values["WE_QA_DYNAMIC_TYPE"]
                    ?? values["WE_TEST_DYNAMIC_TYPE"]
            )
        )
    }

    func now(fallback: @autoclosure () -> Date) -> Date {
        frozenNow ?? fallback()
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter.weFlexible.date(from: value)
            ?? ISO8601DateFormatter.we.date(from: value)
    }

    private static func bool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes": true
        case "0", "false", "no": false
        default: nil
        }
    }

    private static func dynamicTypeSize(_ value: String?) -> DynamicTypeSize? {
        switch value?.lowercased() {
        case "xsmall": .xSmall
        case "small": .small
        case "medium": .medium
        case "large": .large
        case "xlarge": .xLarge
        case "xxlarge": .xxLarge
        case "xxxlarge": .xxxLarge
        case "accessibility1": .accessibility1
        case "accessibility2": .accessibility2
        case "accessibility3": .accessibility3
        case "accessibility4": .accessibility4
        case "accessibility5": .accessibility5
        default: nil
        }
    }
}
