import Foundation

enum WEExternalSurface {
    static let appGroupIdentifier = "group.com.ryankanfer.WE.shared"
    static let snapshotKey = "external-surface.snapshot.v1"
    static let specificWordingOptInKey =
        "external-surface.specific-shared-wording.opt-in"
    static let todayURL = URL(string: "we://today")!
    static let maximumLifetime: TimeInterval = 8 * 60 * 60
}

enum ExternalSurfaceDisplayState: String, Codable, CaseIterable, Hashable {
    case quiet
    case roomAvailable
    case sharedRoomActive
    case resolved

    var genericWording: String {
        switch self {
        case .quiet:
            "Today is clear."
        case .roomAvailable:
            "Something opened for both of you."
        case .sharedRoomActive:
            "Shared room is active."
        case .resolved:
            "It is handled."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .quiet:
            "WE is quiet"
        case .roomAvailable:
            "Shared room available"
        case .sharedRoomActive:
            "Shared room active"
        case .resolved:
            "Shared moment resolved"
        }
    }
}

/// Wording may enter an external surface only from the already-sanitized
/// shared result type. There is deliberately no arbitrary-string initializer.
struct ExplicitlyPermittedSharedWording: Hashable, Sendable {
    let value: String

    init?(sharedDirection: SharedDirection) {
        guard let reviewed = ReviewedExternalDirection(
            rawValue: sharedDirection.key
        ) else {
            return nil
        }
        let sanitized = Self.sanitize(sharedDirection.title)
        guard sanitized == reviewed.canonicalTitle else { return nil }
        value = reviewed.canonicalTitle
    }

    private static func sanitize(_ value: String) -> String {
        let flattened = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(flattened.prefix(96))
    }
}

/// Closed copy set for surfaces visible outside the authenticated app.
/// A server payload with an unknown key or altered title falls back to generic
/// reassurance instead of making arbitrary text externally visible.
private enum ReviewedExternalDirection: String {
    case eveningRoom = "evening-room"
    case openWeekend = "open-weekend"
    case lighterWeek = "lighter-week"
    case protectedBeginning = "protected-beginning"
    case sharedRoom = "shared-room"

    var canonicalTitle: String {
        switch self {
        case .eveningRoom:
            "Begin with a little room"
        case .openWeekend:
            "Leave part of it open"
        case .lighterWeek:
            "Make one thing lighter"
        case .protectedBeginning:
            "Protect the simplest beginning"
        case .sharedRoom:
            "Start with a little room"
        }
    }
}

/// The complete, intentionally small boundary between WE and system surfaces.
///
/// This type contains no response, identity, invitation, receipt, or pending
/// fields. Widgets and Live Activities can therefore render only shared state
/// that has already crossed the in-app consent boundary.
struct ExternalSurfaceSnapshot: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let displayState: ExternalSurfaceDisplayState
    let expiresAt: Date
    private let permittedSharedWording: String?

    init(
        displayState: ExternalSurfaceDisplayState,
        expiresAt requestedExpiry: Date,
        permittedSharedWording: ExplicitlyPermittedSharedWording? = nil,
        now: Date = Date()
    ) {
        version = Self.schemaVersion
        self.displayState = displayState
        expiresAt = min(
            max(requestedExpiry, now),
            now.addingTimeInterval(WEExternalSurface.maximumLifetime)
        )
        self.permittedSharedWording = permittedSharedWording?.value
    }

    var containsSpecificWording: Bool {
        permittedSharedWording != nil
    }

    func wording(at date: Date = Date()) -> String {
        guard date < expiresAt else {
            return ExternalSurfaceDisplayState.quiet.genericWording
        }
        return permittedSharedWording ?? displayState.genericWording
    }

    func effectiveState(at date: Date = Date())
        -> ExternalSurfaceDisplayState {
        date < expiresAt ? displayState : .quiet
    }

    func withoutSpecificWording() -> ExternalSurfaceSnapshot {
        ExternalSurfaceSnapshot(
            displayState: displayState,
            expiresAt: expiresAt,
            now: expiresAt.addingTimeInterval(
                -WEExternalSurface.maximumLifetime
            )
        )
    }

    static func quiet(now: Date = Date()) -> ExternalSurfaceSnapshot {
        ExternalSurfaceSnapshot(
            displayState: .quiet,
            expiresAt: now.addingTimeInterval(60 * 60),
            now: now
        )
    }
}
