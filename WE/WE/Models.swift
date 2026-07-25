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
}

nonisolated struct ResponsibilityInput: Equatable, Sendable {
    let title: String
    let note: String?
    let owner: ResponsibilityOwner
}

nonisolated struct Responsibility: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let ownerID: String?
    let owner: ResponsibilityOwner
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
    static let currentVersion = 1

    let plans: [ArchivedPlan]
    let responsibilities: [ArchivedResponsibility]
    let resolutions: [ArchivedResolution]
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
}
