import Foundation

typealias PersonID = String

struct Member: Identifiable, Equatable {
    let id: PersonID
    let name: String
    let hue: Hue
}

enum InsightKind: String, Codable { case logistical, relational, unresolved }
enum Domain: String, Codable { case life, us }
enum Visibility: String, Codable { case privateOnly = "private", shared, mutual }
enum Readiness: String, Codable { case idle, requested, accepted, declined, withdrawn }
enum ResponseStatus: String, Codable { case none, draft, submitted, revealed }
enum ResolutionType: String, Codable { case settled, released, leftOpen }

/// Immutable content of a surfaced card.
struct Insight: Identifiable, Equatable {
    let id: String
    let kind: InsightKind
    let domain: Domain
    let present: Bool
    let title: String
    let body: String
    let evidence: String
    let source: String
    let options: [String]
}

struct PersonResponse: Equatable {
    var status: ResponseStatus = .none
    var choice: String?
    var note: String?
}

struct Resolution: Equatable {
    let type: ResolutionType
    let choice: String?
}

/// The consent state for one insight.
struct InsightState: Equatable {
    var visibility: Visibility = .shared
    var owner: PersonID?
    var readiness: Readiness = .idle
    var initiator: PersonID?
    var requestedAt: Date?
    var acceptedAt: Date?
    var responses: [PersonID: PersonResponse] = [:]
    var dismissedBy: [PersonID] = []
    var resolution: Resolution?
}

struct Record: Identifiable, Equatable {
    var insight: Insight
    var state: InsightState
    var id: String { insight.id }
}

struct Reflection: Identifiable, Equatable {
    let id: String
    let owner: PersonID
    let domain: Domain
    let kind: ReflectionKind
    let text: String
}

enum ReflectionKind: String, Codable { case reflection, suggestion }

// MARK: - Projection (what a viewer is permitted to see)

enum Phase { case open, waiting, invited, answering, held, revealed, resolved }

struct Projection {
    var phase: Phase = .open
    var visibility: Visibility
    var initiator: PersonID?
    var requestedAt: Date?
    var myResponse: PersonResponse
    var partnerResponse: (choice: String?, note: String?)?
    var matched: Bool?
    var resolution: Resolution?
    var dismissed: Bool
}

enum Consent {
    /// The other member's id, derived from the two response keys.
    static func other(_ state: InsightState, _ viewer: PersonID) -> PersonID? {
        state.responses.keys.first { $0 != viewer }
    }

    static func answersMatch(_ state: InsightState) -> Bool? {
        let keys = Array(state.responses.keys)
        guard keys.count >= 2 else { return nil }
        let a = state.responses[keys[0]]!, b = state.responses[keys[1]]!
        guard a.status == .revealed, b.status == .revealed else { return nil }
        return a.choice == b.choice
    }

    /// Returns nil when a private item does not belong to the viewer.
    static func project(_ state: InsightState, viewer: PersonID) -> Projection? {
        let otherID = other(state, viewer)

        if state.visibility == .privateOnly, state.owner != viewer { return nil }

        let mine = state.responses[viewer] ?? PersonResponse()
        let theirs = otherID.flatMap { state.responses[$0] } ?? PersonResponse()

        var base = Projection(
            phase: .open,
            visibility: state.visibility,
            initiator: state.initiator,
            requestedAt: state.requestedAt,
            myResponse: mine,
            partnerResponse: nil,
            matched: nil,
            resolution: nil,
            dismissed: state.dismissedBy.contains(viewer)
        )

        if let resolution = state.resolution {
            base.phase = .resolved
            base.resolution = resolution
            base.partnerResponse = revealedOnly(theirs)
            base.matched = answersMatch(state)
            return base
        }

        if state.readiness == .requested || state.readiness == .declined {
            // A decline is private: the initiator sees quiet waiting either way.
            base.phase = (viewer == state.initiator) ? .waiting : .invited
            return base
        }

        if state.visibility == .mutual {
            if mine.status == .revealed, theirs.status == .revealed {
                base.phase = .revealed
                base.partnerResponse = revealedOnly(theirs)
                base.matched = answersMatch(state)
            } else if mine.status == .submitted {
                base.phase = .held
            } else {
                base.phase = .answering
            }
            return base
        }

        return base // idle or withdrawn → ordinary open card
    }

    private static func revealedOnly(_ r: PersonResponse) -> (choice: String?, note: String?)? {
        guard r.status == .revealed else { return nil }
        return (r.choice, r.note)
    }
}
