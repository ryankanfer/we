import Foundation

struct TrustResponse: Equatable, Sendable {
    var status: ResponseStatus
    var choice: String?
    var note: String?

    static let none = TrustResponse(status: .none)
}

struct TrustResolution: Equatable, Sendable {
    let type: ResolutionType
    let choice: String?
    let at: Int
}

struct TrustState: Equatable, Sendable {
    var visibility: ConsentVisibility
    var ownerID: String?
    var readiness: ConsentReadiness
    var initiatorID: String?
    var requestedAt: Int?
    var acceptedAt: Int?
    var responses: [String: TrustResponse]
    var dismissedBy: Set<String>
    var resolution: TrustResolution?
}

enum TrustPhase: Equatable, Sendable {
    case hidden
    case open
    case waiting
    case invited
    case answering
    case held
    case revealed
    case resolved
}

struct TrustProjection: Equatable, Sendable {
    let phase: TrustPhase
    let visibility: ConsentVisibility
    let initiatorID: String?
    let requestedAt: Int?
    let myResponse: TrustResponse
    let partnerResponse: TrustResponse?
    let matched: Bool?
    let resolution: TrustResolution?
    let dismissed: Bool
}

enum TrustTransitionError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            message
        }
    }
}

enum TrustCore {
    static func initialState(
        visibility: ConsentVisibility = .shared,
        ownerID: String? = nil,
        memberIDs: [String] = ["ry", "dylan"]
    ) -> TrustState {
        TrustState(
            visibility: visibility,
            ownerID: visibility == .private ? ownerID : nil,
            readiness: .idle,
            responses: Dictionary(
                uniqueKeysWithValues: memberIDs.map { ($0, .none) }
            ),
            dismissedBy: []
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
        next.readiness = .declined
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
        next.readiness = .withdrawn
        next.initiatorID = nil
        next.requestedAt = nil
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
           next.responses[otherID]?.status == .submitted {
            next.responses[memberID]?.status = .revealed
            next.responses[otherID]?.status = .revealed
        }
        return next
    }

    static func answersMatch(_ state: TrustState) -> Bool? {
        let responses = Array(state.responses.values)
        guard responses.count >= 2,
              responses.allSatisfy({ $0.status == .revealed }) else {
            return nil
        }
        return responses[0].choice == responses[1].choice
    }

    static func resolve(
        _ state: TrustState,
        type: ResolutionType,
        at: Int,
        choice: String? = nil
    ) throws -> TrustState {
        let responses = Array(state.responses.values)
        guard responses.count >= 2,
              responses.allSatisfy({ $0.status == .revealed }) else {
            throw TrustTransitionError.invalid(
                "cannot resolve before both answers are revealed"
            )
        }

        var next = state
        next.resolution = TrustResolution(
            type: type,
            choice: choice,
            at: at
        )
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

        let otherID = otherMemberID(in: state, viewer: viewerID)
        let mine = state.responses[viewerID] ?? .none
        let theirs = otherID.flatMap { state.responses[$0] } ?? .none

        let phase: TrustPhase
        if state.resolution != nil {
            phase = .resolved
        } else if state.readiness == .requested
                    || state.readiness == .declined {
            phase = viewerID == state.initiatorID ? .waiting : .invited
        } else if state.visibility == .mutual {
            if mine.status == .revealed && theirs.status == .revealed {
                phase = .revealed
            } else if mine.status == .submitted {
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
            myResponse: mine,
            partnerResponse: theirs.status == .revealed ? theirs : nil,
            matched: answersMatch(state),
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
}

extension InsightRecord {
    func trustState(memberIDs: [String]) -> TrustState {
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

        return TrustState(
            visibility: consent?.visibility ?? .shared,
            ownerID: consent?.ownerID,
            readiness: consent?.readiness ?? .idle,
            initiatorID: consent?.initiatorID,
            requestedAt: consent?.requestedAt == nil ? nil : 0,
            acceptedAt: consent?.acceptedAt == nil ? nil : 0,
            responses: mappedResponses,
            dismissedBy: dismissedBy,
            resolution: resolution
        )
    }
}
