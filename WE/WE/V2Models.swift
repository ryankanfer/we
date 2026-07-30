import Foundation

nonisolated enum AppMode: String, CaseIterable, Codable, Sendable {
    case actual
    case simulation

    var title: String {
        switch self {
        case .actual: "Actual"
        case .simulation: "Simulation"
        }
    }
}

nonisolated enum SimulationViewer: String, CaseIterable, Codable, Sendable {
    case ryan
    case dylan

    var title: String { rawValue.capitalized }
    var userID: String { rawValue }

    var partner: SimulationViewer {
        self == .ryan ? .dylan : .ryan
    }
}

nonisolated enum PresenceMode: String, CaseIterable, Codable, Sendable {
    case apart
    case together
    case away

    var title: String {
        switch self {
        case .apart: "Apart"
        case .together: "Together"
        case .away: "Away"
        }
    }

    var detail: String {
        switch self {
        case .apart:
            "WE can surface a shared moment."
        case .together:
            "WE goes quiet and holds everything for later."
        case .away:
            "Timing widens while one of you is away."
        }
    }
}

nonisolated struct RelationshipPresence: Codable, Hashable, Sendable {
    let coupleID: String
    let mode: PresenceMode
    let changedBy: String?
    let changedAt: String
}

nonisolated enum SignalKind: String, CaseIterable, Codable, Sendable {
    case sharedPlans = "shared_plans"
    case weeklyRhythm = "weekly_rhythm"
    case unfinishedThreads = "unfinished_threads"
    case privateReflections = "private_reflections"

    var title: String {
        switch self {
        case .sharedPlans: "Shared plans and care"
        case .weeklyRhythm: "The rhythm of your weeks"
        case .unfinishedThreads: "Set-asides and unfinished threads"
        case .privateReflections: "Private reflections"
        }
    }

    var detail: String {
        switch self {
        case .sharedPlans:
            "Plans and shared responsibilities that both of you can see."
        case .weeklyRhythm:
            "Shared timing patterns, never a score of either person."
        case .unfinishedThreads:
            "Mutual moments that were intentionally left open."
        case .privateReflections:
            "Never used for intelligence and permanently off."
        }
    }

    var isPermanentlyDisabled: Bool { self == .privateReflections }
}

nonisolated struct SignalConsent: Identifiable, Codable, Hashable, Sendable {
    let coupleID: String
    let profileID: String
    let signal: SignalKind
    let isEnabled: Bool
    let updatedAt: String

    var id: String { "\(profileID)-\(signal.rawValue)" }
}

nonisolated enum ProvenanceSourceKind: String, Codable, Sendable {
    case plan
    case responsibility
    case relationshipEvent = "relationship_event"
    case consentedSignal = "consented_signal"
}

nonisolated struct ProvenanceReference: Identifiable, Codable, Hashable, Sendable {
    let kind: ProvenanceSourceKind
    let id: String
    let label: String
    let shared: Bool

    var identifier: String { "\(kind.rawValue)-\(id)" }
    var idValue: String { id }
    var stableID: String { identifier }
}

extension ProvenanceReference {
    var identity: String { stableID }
}

nonisolated struct SuggestionProvenance: Codable, Hashable, Sendable {
    let templateVersion: Int
    let rule: String
    let generatedAt: String
    let references: [ProvenanceReference]
}

nonisolated enum SuggestionKind: String, Codable, Sendable {
    case partyGroceries = "party_groceries"
}

nonisolated struct SuggestionEvidence: Codable, Hashable, Sendable {
    let context: String
    let reason: String
    let sharedInputs: [ProvenanceReference]
}

nonisolated struct ContextualSuggestion: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let kind: SuggestionKind
    let relatedPlanID: String
    let title: String
    let proposedResponsibilityTitle: String
    let proposedScheduledOn: String?
    let evidence: SuggestionEvidence
    let provenance: SuggestionProvenance
    let createdAt: String
    let confirmedResponsibilityID: String?
    let dismissedForViewer: Bool

    var isAvailable: Bool {
        confirmedResponsibilityID == nil && !dismissedForViewer
    }
}

nonisolated struct SuggestionConfirmation: Equatable, Sendable {
    let suggestionID: String
    let title: String
    let note: String?
    let owner: ResponsibilityOwner
    let scheduledOn: String?
    var ownerID: String? = nil
}

nonisolated enum AnchorCadence: String, CaseIterable, Codable, Sendable {
    case weekly
    case monthly
    case seasonal
    case open
}

nonisolated struct AnchorInput: Equatable, Sendable {
    let title: String
    let note: String?
    let cadence: AnchorCadence
}

nonisolated struct Anchor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let cadence: AnchorCadence
    let isActive: Bool
    let createdBy: String?
    let createdAt: String
    let updatedAt: String
}

nonisolated enum HandoffStatus: String, Codable, Sendable {
    case offered
    case accepted
    case declined
    case withdrawn
}

nonisolated struct ResponsibilityHandoff: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let responsibilityID: String
    let coupleID: String
    let fromProfileID: String
    let toProfileID: String
    let status: HandoffStatus
    let createdAt: String
    let respondedAt: String?
}

nonisolated enum ApproachKind: String, CaseIterable, Codable, Sendable {
    case gently
    case directly
    case together

    var title: String {
        switch self {
        case .gently: "Gently"
        case .directly: "Directly"
        case .together: "Together"
        }
    }
}

nonisolated struct PlanApproach: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let planID: String
    let profileID: String
    let approach: ApproachKind
    let note: String?
    let createdAt: String
}

nonisolated enum RelationshipEventType: String, CaseIterable, Codable, Sendable {
    case planCompleted = "plan_completed"
    case responsibilityCompleted = "responsibility_completed"
    case mutualResolution = "mutual_resolution"
    case handoffAccepted = "handoff_accepted"
    case sharedMomentOpened = "shared_moment_opened"

    var title: String {
        switch self {
        case .planCompleted: "A plan became part of your story"
        case .responsibilityCompleted: "Shared care was completed"
        case .mutualResolution: "A shared question found a close"
        case .handoffAccepted: "Care changed hands"
        case .sharedMomentOpened: "A shared moment opened"
        }
    }
}

nonisolated struct RelationshipEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let type: RelationshipEventType
    let sourceID: String
    let title: String
    let occurredAt: String
    let provenance: [ProvenanceReference]
}

nonisolated struct DeclineGrace: Identifiable, Codable, Hashable, Sendable {
    let insightID: String
    let profileID: String
    let declineCount: Int
    let suppressUntil: String?

    var id: String { "\(insightID)-\(profileID)" }
}

nonisolated enum SeasonReadiness: Codable, Hashable, Sendable {
    case needsTime(weeksRemaining: Int)
    case needsEntries(countRemaining: Int)
    case needsEventVariety(typesRemaining: Int)
    case needsCalendarBreadth(monthsRemaining: Int)
    case ready(eligibleEventIDs: [String], cutoff: String)

    static func evaluate(
        events: [RelationshipEvent],
        after previousCutoff: Date?,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> SeasonReadiness {
        let eligible = events.compactMap { event -> (RelationshipEvent, Date)? in
            guard let date = ISO8601DateFormatter.we.date(
                from: event.occurredAt
            ) ?? ISO8601DateFormatter.weFlexible.date(
                from: event.occurredAt
            ) else { return nil }
            if let previousCutoff, date <= previousCutoff { return nil }
            return (event, date)
        }.sorted { $0.1 < $1.1 }

        guard let first = eligible.first?.1 else {
            return .needsTime(weeksRemaining: 6)
        }

        let sixWeeks = calendar.date(byAdding: .day, value: 42, to: first) ?? first
        if now < sixWeeks {
            let days = max(
                1,
                calendar.dateComponents([.day], from: now, to: sixWeeks).day ?? 1
            )
            return .needsTime(weeksRemaining: Int(ceil(Double(days) / 7)))
        }

        if eligible.count < 6 {
            return .needsEntries(countRemaining: 6 - eligible.count)
        }

        let types = Set(eligible.map(\.0.type))
        if types.count < 2 {
            return .needsEventVariety(typesRemaining: 2 - types.count)
        }

        let months = Set(eligible.map {
            calendar.dateComponents([.year, .month], from: $0.1)
        })
        if months.count < 2 {
            return .needsCalendarBreadth(monthsRemaining: 2 - months.count)
        }

        return .ready(
            eligibleEventIDs: eligible.map(\.0.id),
            cutoff: ISO8601DateFormatter.we.string(from: now)
        )
    }
}

nonisolated struct Season: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let sequence: Int
    let startsAt: String
    let cutoffAt: String
    let title: String
    let summary: String
    let eventIDs: [String]
    let provenance: [ProvenanceReference]
    let createdAt: String
}

nonisolated struct V2RelationshipState: Codable, Hashable, Sendable {
    let presence: RelationshipPresence?
    let signalConsents: [SignalConsent]
    let anchors: [Anchor]
    let handoffs: [ResponsibilityHandoff]
    let approaches: [PlanApproach]
    let events: [RelationshipEvent]
    let seasons: [Season]
    let suggestions: [ContextualSuggestion]
    let declineGrace: [DeclineGrace]

    static let empty = V2RelationshipState(
        presence: nil,
        signalConsents: [],
        anchors: [],
        handoffs: [],
        approaches: [],
        events: [],
        seasons: [],
        suggestions: [],
        declineGrace: []
    )
}

nonisolated enum QuestionPrimaryAction: Equatable, Sendable {
    case hold(partnerName: String)
    case openTogether(partnerName: String)

    var title: String {
        switch self {
        case .hold: "Hold my answer"
        case .openTogether: "Open together"
        }
    }

    var explanation: String {
        switch self {
        case .hold(let partnerName):
            "Your answer is never shown to \(partnerName). If they answer too, WE opens a separate shared direction."
        case .openTogether(let partnerName):
            "\(partnerName) has answered. Continuing opens a separate shared direction on both sides."
        }
    }
}

nonisolated enum ContextualSuggestionEngine {
    static let templateVersion = 1
    static let partyTerms = ["party", "gathering", "dinner", "guest", "hosting"]

    static func partyGroceries(
        plans: [PlanItem],
        responsibilities: [Responsibility],
        dismissedPlanIDs: Set<String> = [],
        now: Date = Date()
    ) -> [ContextualSuggestion] {
        plans.compactMap { plan in
            guard plan.status == .active,
                  !dismissedPlanIDs.contains(plan.id),
                  partyTerms.contains(where: {
                      "\(plan.title) \(plan.note ?? "")"
                          .localizedCaseInsensitiveContains($0)
                  }),
                  !responsibilities.contains(where: {
                      $0.status == .active
                          && $0.relatedPlanID == plan.id
                  })
            else { return nil }

            let reference = ProvenanceReference(
                kind: .plan,
                id: plan.id,
                label: plan.title,
                shared: true
            )
            let createdAt = ISO8601DateFormatter.we.string(from: now)
            return ContextualSuggestion(
                id: "party-groceries-\(plan.id)",
                coupleID: plan.coupleID,
                kind: .partyGroceries,
                relatedPlanID: plan.id,
                title: "Add a grocery run to the shared list?",
                proposedResponsibilityTitle: "Grocery run",
                proposedScheduledOn: inferredDate(before: plan.scheduledOn),
                evidence: SuggestionEvidence(
                    context: "For \(plan.title)",
                    reason: "The party is coming up, and groceries have not been named yet.",
                    sharedInputs: [reference]
                ),
                provenance: SuggestionProvenance(
                    templateVersion: templateVersion,
                    rule: "upcoming shared plan contains a hosting context and no related grocery care exists",
                    generatedAt: createdAt,
                    references: [reference]
                ),
                createdAt: createdAt,
                confirmedResponsibilityID: nil,
                dismissedForViewer: false
            )
        }
    }

    private static func inferredDate(before rawDate: String?) -> String? {
        guard let rawDate,
              let date = DateFormatter.weDay.date(from: rawDate),
              let dayBefore = Calendar.current.date(
                  byAdding: .day,
                  value: -1,
                  to: date
              )
        else { return nil }
        return DateFormatter.weDay.string(from: dayBefore)
    }
}

extension ISO8601DateFormatter {
    nonisolated static let we: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated static let weFlexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter
    }()
}

extension DateFormatter {
    nonisolated static let weDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
