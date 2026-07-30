import Foundation

nonisolated struct TrustResponse: Equatable, Sendable {
    var status: ResponseStatus
    var choice: String?
    var note: String?

    static let none = TrustResponse(status: .none)
}

nonisolated struct TrustResolution: Equatable, Sendable {
    let type: ResolutionType
    let choice: String?
    let at: Int
}

nonisolated struct TrustState: Equatable, Sendable {
    var insightID: String
    var seedKey: String
    var visibility: ConsentVisibility
    var ownerID: String?
    var readiness: ConsentReadiness
    var initiatorID: String?
    var requestedAt: Int?
    var acceptedAt: Int?
    var responses: [String: TrustResponse]
    var sharedDirection: SharedDirection?
    var dismissedBy: Set<String>
    var declinedBy: Set<String>
    var resolution: TrustResolution?
}

nonisolated enum TrustPhase: Equatable, Sendable {
    case hidden
    case open
    case waiting
    case invited
    case declined
    case answering
    case held
    case shared
    /// Compatibility for visual mappings compiled against the former state.
    /// TrustCore never projects this phase.
    case revealed
    case resolved
}

nonisolated struct TrustProjection: Equatable, Sendable {
    let phase: TrustPhase
    let visibility: ConsentVisibility
    let initiatorID: String?
    let requestedAt: Int?
    let myResponse: TrustResponse
    let partnerResponse: TrustResponse?
    let matched: Bool?
    let sharedDirection: SharedDirection?
    let resolution: TrustResolution?
    let dismissed: Bool
}

nonisolated enum TrustTransitionError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            message
        }
    }
}

nonisolated enum TrustCore {
    static func initialState(
        insightID: String = "local-insight",
        seedKey: String = "local",
        visibility: ConsentVisibility = .shared,
        ownerID: String? = nil,
        memberIDs: [String] = ["ry", "dylan"]
    ) -> TrustState {
        TrustState(
            insightID: insightID,
            seedKey: seedKey,
            visibility: visibility,
            ownerID: visibility == .private ? ownerID : nil,
            readiness: .idle,
            responses: Dictionary(
                uniqueKeysWithValues: memberIDs.map { ($0, .none) }
            ),
            sharedDirection: nil,
            dismissedBy: [],
            declinedBy: []
        )
    }

    static func requestReveal(
        _ state: TrustState,
        by memberID: String,
        at: Int
    ) throws -> TrustState {
        guard state.resolution == nil else {
            throw TrustTransitionError.invalid("already resolved")
        }
        guard state.readiness == .idle || state.readiness == .withdrawn
        else {
            throw TrustTransitionError.invalid("reveal already in motion")
        }
        guard state.visibility != .private || state.ownerID == memberID
        else {
            throw TrustTransitionError.invalid(
                "cannot request someone else's private item"
            )
        }

        var next = state
        next.visibility = state.visibility == .mutual ? .mutual : .shared
        next.ownerID = nil
        next.readiness = .requested
        next.initiatorID = memberID
        next.requestedAt = at
        next.declinedBy.removeAll()
        return next
    }

    static func acceptReveal(
        _ state: TrustState,
        by memberID: String,
        at: Int
    ) throws -> TrustState {
        guard state.readiness == .requested || state.readiness == .declined
        else {
            throw TrustTransitionError.invalid("nothing to accept")
        }
        guard state.initiatorID != memberID else {
            throw TrustTransitionError.invalid(
                "initiator cannot accept their own request"
            )
        }

        var next = state
        next.readiness = .accepted
        next.visibility = .mutual
        next.acceptedAt = at
        next.declinedBy.remove(memberID)
        return next
    }

    static func declineReveal(
        _ state: TrustState,
        by memberID: String
    ) throws -> TrustState {
        guard state.readiness == .requested else {
            throw TrustTransitionError.invalid("nothing to decline")
        }
        guard state.initiatorID != memberID else {
            throw TrustTransitionError.invalid(
                "initiator cannot decline their own request"
            )
        }

        var next = state
        next.declinedBy.insert(memberID)
        return next
    }

    static func withdrawReveal(
        _ state: TrustState,
        by memberID: String
    ) throws -> TrustState {
        guard state.readiness == .requested || state.readiness == .declined
        else {
            throw TrustTransitionError.invalid("nothing to withdraw")
        }
        guard state.initiatorID == memberID else {
            throw TrustTransitionError.invalid(
                "only the initiator can withdraw"
            )
        }

        var next = state
        next.readiness = .idle
        next.initiatorID = nil
        next.requestedAt = nil
        next.acceptedAt = nil
        next.declinedBy.removeAll()
        return next
    }

    static func saveDraft(
        _ state: TrustState,
        by memberID: String,
        choice: String,
        note: String? = nil
    ) throws -> TrustState {
        guard state.visibility == .mutual else {
            throw TrustTransitionError.invalid(
                "answers happen only in Between Us"
            )
        }
        let status = state.responses[memberID]?.status ?? .none
        guard status != .submitted && status != .revealed else {
            throw TrustTransitionError.invalid("already submitted")
        }

        var next = state
        next.responses[memberID] = TrustResponse(
            status: .draft,
            choice: choice,
            note: note
        )
        return next
    }

    static func submitResponse(
        _ state: TrustState,
        by memberID: String,
        choice: String,
        note: String? = nil
    ) throws -> TrustState {
        guard state.visibility == .mutual else {
            throw TrustTransitionError.invalid(
                "answers happen only in Between Us"
            )
        }
        let status = state.responses[memberID]?.status ?? .none
        guard status != .submitted && status != .revealed else {
            throw TrustTransitionError.invalid("already submitted")
        }

        var next = state
        next.responses[memberID] = TrustResponse(
            status: .submitted,
            choice: choice,
            note: note
        )

        if let otherID = otherMemberID(in: state, viewer: memberID),
           hasSubmitted(next.responses[otherID]) {
            if next.responses[otherID]?.status == .revealed {
                next.responses[otherID]?.status = .submitted
            }
            next.sharedDirection = safeDirection(for: next)
        }
        return next
    }

    static func resolve(
        _ state: TrustState,
        type: ResolutionType,
        at: Int,
        choice: String? = nil
    ) throws -> TrustState {
        guard state.resolution == nil else {
            throw TrustTransitionError.invalid("already resolved")
        }
        guard let sharedDirection = state.sharedDirection else {
            throw TrustTransitionError.invalid(
                "cannot resolve before a shared direction exists"
            )
        }

        var next = state
        next.resolution = TrustResolution(
            type: type,
            choice: type == .settled ? sharedDirection.title : nil,
            at: at
        )
        _ = choice
        return next
    }

    static func dismissSuggestion(
        _ state: TrustState,
        by memberID: String
    ) throws -> TrustState {
        guard state.readiness == .idle || state.readiness == .withdrawn
        else {
            throw TrustTransitionError.invalid(
                "cannot dismiss once it is between you"
            )
        }

        var next = state
        next.dismissedBy.insert(memberID)
        return next
    }

    static func project(
        _ state: TrustState,
        for viewerID: String
    ) -> TrustProjection? {
        guard state.visibility != .private || state.ownerID == viewerID else {
            return nil
        }

        let mine = state.responses[viewerID] ?? .none

        let phase: TrustPhase
        if state.resolution != nil {
            phase = .resolved
        } else if state.readiness == .requested
                    || state.readiness == .declined {
            if viewerID == state.initiatorID {
                phase = .waiting
            } else if state.declinedBy.contains(viewerID) {
                phase = .declined
            } else {
                phase = .invited
            }
        } else if state.visibility == .mutual {
            if state.sharedDirection != nil {
                phase = .shared
            } else if hasSubmitted(mine) {
                phase = .held
            } else {
                phase = .answering
            }
        } else {
            phase = .open
        }

        return TrustProjection(
            phase: phase,
            visibility: state.visibility,
            initiatorID: state.initiatorID,
            requestedAt: state.requestedAt,
            myResponse: normalizedOwnerResponse(mine),
            partnerResponse: nil,
            matched: nil,
            sharedDirection: state.sharedDirection,
            resolution: state.resolution,
            dismissed: state.dismissedBy.contains(viewerID)
        )
    }

    private static func otherMemberID(
        in state: TrustState,
        viewer: String
    ) -> String? {
        state.responses.keys.first { $0 != viewer }
    }

    private static func hasSubmitted(_ response: TrustResponse?) -> Bool {
        response?.status == .submitted || response?.status == .revealed
    }

    private static func normalizedOwnerResponse(
        _ response: TrustResponse
    ) -> TrustResponse {
        guard response.status == .revealed else { return response }
        return TrustResponse(
            status: .submitted,
            choice: response.choice,
            note: response.note
        )
    }

    private static func safeDirection(
        for state: TrustState
    ) -> SharedDirection {
        let content: (
            key: String,
            title: String,
            message: String,
            symbol: String
        )
        // A shared direction may vary only with public insight context. If it
        // varied with choice content or equality, a person could infer their
        // partner's answer by comparing the result with their own.
        if state.seedKey.hasPrefix("tonight-") {
            content = (
                "evening-room",
                "Begin with a little room",
                "Keep the first part unhurried, with room to change course.",
                "sun.horizon"
            )
        } else if state.seedKey.hasPrefix("weekend-") {
            content = (
                "open-weekend",
                "Leave part of it open",
                "Choose one easy beginning without deciding the whole weekend.",
                "water.waves"
            )
        } else if state.seedKey.hasPrefix("load-") {
            content = (
                "lighter-week",
                "Make one thing lighter",
                "Choose the smallest shared adjustment and let the rest wait.",
                "line.horizontal.3.decrease"
            )
        } else if state.seedKey.hasPrefix("plan-") {
            content = (
                "protected-beginning",
                "Protect the simplest beginning",
                "Name one quality to carry into the plan without deciding every detail.",
                "sparkle"
            )
        } else {
            content = (
                "shared-room",
                "Start with a little room",
                "Choose one easy beginning without deciding the whole shape.",
                "line.horizontal.3.decrease"
            )
        }

        return SharedDirection(
            insightID: state.insightID,
            key: content.key,
            eyebrow: eyebrow(for: state.seedKey),
            title: content.title,
            message: content.message,
            symbol: content.symbol,
            createdAt: nil
        )
    }

    private static func eyebrow(for seedKey: String) -> String {
        if seedKey.hasPrefix("tonight-") { return "FOR TONIGHT" }
        if seedKey.hasPrefix("weekend-") { return "FOR THE WEEKEND" }
        if seedKey.hasPrefix("load-") { return "FOR THIS WEEK" }
        if seedKey.hasPrefix("plan-") { return "FOR THE PLAN" }
        return "BETWEEN YOU"
    }

    static func normalizingLegacyState(
        _ state: TrustState
    ) -> TrustState {
        var next = state
        for memberID in next.responses.keys
        where next.responses[memberID]?.status == .revealed {
            next.responses[memberID]?.status = .submitted
        }
        if next.sharedDirection == nil,
           next.responses.values.filter(hasSubmitted).count >= 2 {
            next.sharedDirection = safeDirection(for: next)
        }
        return next
    }
}

extension InsightRecord {
    nonisolated func trustState(memberIDs: [String]) -> TrustState {
        let consent = consent
        var mappedResponses = Dictionary(
            uniqueKeysWithValues: memberIDs.map { ($0, TrustResponse.none) }
        )

        for response in responses {
            mappedResponses[response.profileID] = TrustResponse(
                status: response.status,
                choice: response.choice,
                note: response.note
            )
        }

        let resolution = consent?.resolutionType.map {
            TrustResolution(
                type: $0,
                choice: consent?.resolutionChoice,
                at: 0
            )
        }

        return TrustCore.normalizingLegacyState(TrustState(
            insightID: insight.id,
            seedKey: insight.seedKey,
            visibility: consent?.visibility ?? .shared,
            ownerID: consent?.ownerID,
            readiness: consent?.readiness ?? .idle,
            initiatorID: consent?.initiatorID,
            requestedAt: consent?.requestedAt == nil ? nil : 0,
            acceptedAt: consent?.acceptedAt == nil ? nil : 0,
            responses: mappedResponses,
            sharedDirection: sharedDirection,
            dismissedBy: dismissedBy,
            declinedBy: declinedBy,
            resolution: resolution
        ))
    }
}
