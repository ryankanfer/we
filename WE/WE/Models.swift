import Foundation

nonisolated struct AuthenticatedUser: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let email: String
}

nonisolated enum SignUpResult: Equatable, Sendable {
    case signedIn(AuthenticatedUser)
    case verificationPending(email: String)
}

nonisolated struct Profile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

nonisolated struct Couple: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let joinCode: String

    /// When the current invitation stops working, or nil when there is no
    /// live invitation to send.
    ///
    /// `joinCode` is never nil — the column behind it is `not null` — so the
    /// code alone cannot tell you whether there is anything to share. This is
    /// the field that can: nil means withdrawn, spent, or never issued, and
    /// the code sitting beside it would be refused.
    var invitationExpiresAt: Date?

    /// When a partner deleted their account, or nil if nobody ever has.
    ///
    /// This is what distinguishes the two shapes of a one-member couple:
    /// somebody who has never paired, and somebody whose partner left. They
    /// are the same member count and completely different situations.
    var departedAt: Date?

    /// When the survivor was told. Set once, by `acknowledgeDeparture`.
    var departureSeenAt: Date?

    init(
        id: String,
        joinCode: String,
        invitationExpiresAt: Date? = nil,
        departedAt: Date? = nil,
        departureSeenAt: Date? = nil
    ) {
        self.id = id
        self.joinCode = joinCode
        self.invitationExpiresAt = invitationExpiresAt
        self.departedAt = departedAt
        self.departureSeenAt = departureSeenAt
    }

    /// The one quiet moment: somebody left and this person has not been told.
    ///
    /// Both halves are required. `departedAt` alone would raise it again on
    /// every launch for the rest of the account's life, which is the opposite
    /// of the rule in CIRCLE.md:52 — a thing is told once, and then the
    /// interface is silent about it.
    var owesDepartureNotice: Bool {
        departedAt != nil && departureSeenAt == nil
    }

    /// Whether the code is worth putting on screen. Evaluated against the
    /// clock at the moment it is asked, because a screen left open across the
    /// boundary should stop offering a code that no longer works.
    func hasLiveInvitation(asOf now: Date = Date()) -> Bool {
        guard let invitationExpiresAt else { return false }
        return invitationExpiresAt > now
    }
}

nonisolated enum MemberHue: String, CaseIterable, Codable, Sendable {
    case burgundy
    case sage
    case ember
    case tide
    case plum
    case clay
    case pearl
    case mist
    case blush
    case celadon
}

nonisolated struct Membership: Codable, Hashable, Sendable {
    let coupleID: String
    let profileID: String
    let hue: MemberHue
    let hueChosenAt: String?

    var hasChosenHue: Bool { hueChosenAt != nil }
}

nonisolated struct Member: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let hue: MemberHue
}

nonisolated enum InsightKind: String, Codable, Sendable {
    case logistical
    case relational
    case unresolved
}

nonisolated enum InsightDomain: String, Codable, Sendable {
    case life
    case us
}

nonisolated struct Insight: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let seedKey: String
    let kind: InsightKind
    let domain: InsightDomain
    let present: Bool
    let title: String
    let body: String
    let evidence: String
    let source: String
    let actionTitle: String
    let options: [String]
}

nonisolated enum ConsentVisibility: String, Codable, Sendable {
    case `private`
    case shared
    case mutual
}

nonisolated enum ConsentReadiness: String, Codable, Sendable {
    case idle
    case requested
    case accepted
    case declined
    case withdrawn
}

nonisolated enum ResolutionType: String, Codable, Sendable {
    case settled
    case released
    case leftOpen
}

nonisolated struct InsightConsent: Codable, Hashable, Sendable {
    let insightID: String
    let visibility: ConsentVisibility
    let ownerID: String?
    let readiness: ConsentReadiness
    let initiatorID: String?
    let requestedAt: String?
    let acceptedAt: String?
    let resolutionType: ResolutionType?
    let resolutionChoice: String?
}

nonisolated enum ResponseStatus: String, Codable, Sendable {
    case none
    case draft
    case submitted
    /// Read-only compatibility for snapshots created before answers became
    /// permanently owner-only. New writes never create this state.
    case revealed
}

nonisolated struct InsightResponse: Codable, Hashable, Sendable {
    let insightID: String
    let profileID: String
    let status: ResponseStatus
    let choice: String?
    let note: String?
}

nonisolated enum ReflectionKind: String, Codable, Sendable {
    case reflection
    case suggestion
}

nonisolated struct Reflection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let ownerID: String
    let domain: InsightDomain
    let kind: ReflectionKind
    let text: String
}

nonisolated struct InsightRecord: Identifiable, Codable, Hashable, Sendable {
    let insight: Insight
    let consent: InsightConsent?
    let responses: [InsightResponse]
    var sharedDirection: SharedDirection? = nil
    let dismissedBy: Set<String>
    let declinedBy: Set<String>

    var id: String { insight.id }
}

nonisolated enum SharedItemStatus: String, CaseIterable, Codable, Sendable {
    case active
    case completed
    case archived
}

nonisolated struct PlanInput: Equatable, Sendable {
    let title: String
    let note: String?
    let scheduledOn: String?
}

nonisolated struct PlanItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let scheduledOn: String?
    let status: SharedItemStatus
    let completedAt: String?
    let createdBy: String?
    let updatedBy: String?
    let createdAt: String
    let updatedAt: String
}

nonisolated enum ResponsibilityOwner: String, CaseIterable, Codable, Sendable {
    case me
    case partner
    case together

    /// Display name. Lived in `LifeView` until the zones replaced it; Profile
    /// is the caller that outlasted it.
    var title: String {
        switch self {
        case .me: "Me"
        case .partner: "Partner"
        case .together: "Together"
        }
    }
}

nonisolated struct ResponsibilityInput: Equatable, Sendable {
    let title: String
    let note: String?
    let owner: ResponsibilityOwner
    var scheduledOn: String? = nil
    var relatedPlanID: String? = nil
    var suggestionProvenance: SuggestionProvenance? = nil
}

nonisolated struct Responsibility: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let ownerID: String?
    let owner: ResponsibilityOwner
    var scheduledOn: String? = nil
    var relatedPlanID: String? = nil
    var suggestionProvenance: SuggestionProvenance? = nil
    let status: SharedItemStatus
    let completedAt: String?
    let createdBy: String?
    let updatedBy: String?
    let createdAt: String
    let updatedAt: String
}

nonisolated struct ArchivedPlan: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let note: String?
    let scheduledOn: String?
    let status: SharedItemStatus
    let completedAt: String?
    let updatedAt: String
}

nonisolated struct ArchivedResponsibility: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let note: String?
    let ownership: ResponsibilityOwner
    var scheduledOn: String? = nil
    var relatedPlanID: String? = nil
    var suggestionProvenance: SuggestionProvenance? = nil
    let status: SharedItemStatus
    let completedAt: String?
    let updatedAt: String
}

nonisolated struct ArchivedResolution: Identifiable, Codable, Hashable, Sendable {
    let insightID: String
    let title: String
    let resolutionType: ResolutionType
    let resolutionChoice: String?
    let resolvedAt: String

    var id: String { insightID }
}

nonisolated struct RelationshipArchiveSnapshot: Codable, Hashable, Sendable {
    static let currentVersion = 2

    let plans: [ArchivedPlan]
    let responsibilities: [ArchivedResponsibility]
    let resolutions: [ArchivedResolution]
    var anchors: [Anchor] = []
    var events: [RelationshipEvent] = []
    var seasons: [Season] = []
    var handoffs: [ResponsibilityHandoff] = []

    enum CodingKeys: String, CodingKey {
        case plans, responsibilities, resolutions, anchors, events, seasons
        case handoffs
    }

    init(
        plans: [ArchivedPlan],
        responsibilities: [ArchivedResponsibility],
        resolutions: [ArchivedResolution],
        anchors: [Anchor] = [],
        events: [RelationshipEvent] = [],
        seasons: [Season] = [],
        handoffs: [ResponsibilityHandoff] = []
    ) {
        self.plans = plans
        self.responsibilities = responsibilities
        self.resolutions = resolutions
        self.anchors = anchors
        self.events = events
        self.seasons = seasons
        self.handoffs = handoffs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        plans = try values.decodeIfPresent(
            [ArchivedPlan].self,
            forKey: .plans
        ) ?? []
        responsibilities = try values.decodeIfPresent(
            [ArchivedResponsibility].self,
            forKey: .responsibilities
        ) ?? []
        resolutions = try values.decodeIfPresent(
            [ArchivedResolution].self,
            forKey: .resolutions
        ) ?? []
        anchors = try values.decodeIfPresent(
            [Anchor].self,
            forKey: .anchors
        ) ?? []
        events = try values.decodeIfPresent(
            [RelationshipEvent].self,
            forKey: .events
        ) ?? []
        seasons = try values.decodeIfPresent(
            [Season].self,
            forKey: .seasons
        ) ?? []
        handoffs = try values.decodeIfPresent(
            [ResponsibilityHandoff].self,
            forKey: .handoffs
        ) ?? []
    }
}

nonisolated struct RelationshipArchive: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let ownerID: String
    let endedAt: String
    let snapshotVersion: Int
    let snapshot: RelationshipArchiveSnapshot
}

nonisolated struct RelationshipSnapshot: Codable, Hashable, Sendable {
    let profile: Profile
    let membership: Membership?
    let couple: Couple?
    let members: [Member]
    let insights: [InsightRecord]
    let reflections: [Reflection]
    let plans: [PlanItem]
    let responsibilities: [Responsibility]
    let archives: [RelationshipArchive]
    let syncedAt: Date
    var v2: V2RelationshipState? = nil

    var v2State: V2RelationshipState { v2 ?? .empty }
}
