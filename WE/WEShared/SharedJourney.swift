import Foundation

/// How close the evidence is to requiring a shared choice.
nonisolated enum JourneyScope: String, CaseIterable, Codable, Sendable {
    case immediate
    case nearTerm
    case longTerm

    var priority: Int {
        switch self {
        case .immediate: 0
        case .nearTerm: 1
        case .longTerm: 2
        }
    }

    var lifetime: TimeInterval {
        switch self {
        case .immediate: 24 * 60 * 60
        case .nearTerm: 7 * 24 * 60 * 60
        case .longTerm: 30 * 24 * 60 * 60
        }
    }
}

nonisolated enum JourneyTriggerProvenance: String, Codable, Sendable {
    case repeatedAspiration
    case upcomingPlan
    case unresolvedChoice
    case slippingRhythm
    case meaningfulCluster
    case legacyHorizon
}

/// A pointer at a record the couple can already see. Every adaptive surface
/// binds to these rather than copying what it displays, so a derived view can
/// name its exact sources and nothing it shows outlives the thing it points at.
///
/// `kind` is a string rather than an enum because the set of referenceable
/// records grows with the product and old rows must still decode. Resolution is
/// the reader's job; an unresolvable reference is dropped, never rendered.
nonisolated struct FieldReference: Codable, Hashable, Sendable {
    let kind: String
    let id: String

    init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }
}

extension FieldReference {
    /// The kinds written today. Held as constants rather than an enum for the
    /// decoding reason above.
    enum Kind {
        static let lifeItem = "lifeItem"
        static let cluster = "cluster"
        static let horizon = "horizon"
        static let evidence = "evidence"

        // The trigger vocabulary, spelled exactly as
        // `refresh_shared_journey_question` writes it. These were previously
        // wrong or missing here — the server wrote `field_question` while this
        // declared `question`, and `rhythm` and `ours_item` had no constant at
        // all — so three of the five trigger kinds could never match. Because
        // an unrecognised kind is dropped without a trace, nothing surfaced.
        //
        // `FieldReferenceKindTests` pins these against the migration text.
        static let fieldQuestion = "field_question"
        static let rhythm = "rhythm"
        static let oursItem = "ours_item"

        /// Every kind any server path writes today.
        static let all: [String] = [
            lifeItem, cluster, horizon, evidence,
            fieldQuestion, rhythm, oursItem,
        ]
    }
}

/// The journey-side spelling. Journeys were the first caller; the type turned
/// out to be general, so the name moved and this stayed behind.
typealias JourneySubjectReference = FieldReference

/// The deliberately small shared context frozen when a question is created.
/// Private writing and full-account state never belong in this value.
nonisolated struct JourneyContextSnapshot: Codable, Hashable, Sendable {
    let evidence: [String]
    let frozenAt: String
}

nonisolated enum JourneyActionKind: String, Codable, Sendable {
    case lifeItem
}

nonisolated struct ProposedJourneyAction: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: JourneyActionKind
    let title: String
    let category: String
    let detail: String?
    let dueOn: String?
}

nonisolated enum SharedDirectionStatus: String, Codable, Sendable {
    case proposed
    case noSafeDirection = "no_safe_direction"
    case active
}

nonisolated enum DirectionDecision: String, Codable, Sendable {
    case choose
    case rest
}

/// RLS exposes only the current person's row. A partner's single decision is
/// intentionally not representable in the client snapshot.
nonisolated struct DirectionConfirmation: Codable, Hashable, Sendable {
    let insightID: String
    let profileID: String
    let decision: DirectionDecision
    let decidedAt: String
}

/// A private pass is owner-only and never changes a shared question row.
nonisolated struct JourneyPass: Codable, Hashable, Sendable {
    let insightID: String
    let profileID: String
    let passedAt: String
}

nonisolated enum SharedJourneyStatus: String, Codable, Sendable {
    case active
    case completed
}

/// A view a journey can grow, once the couple's own shared material supports
/// it.
///
/// A closed set of ordinary reviewed views, deliberately. Adaptivity here is
/// *which* of these is lit and *what* it is bound to — selection and binding,
/// never generation. A journey cannot invent a surface, and there is no
/// registry to extend at runtime: adding one is a Swift change that goes
/// through review like anything else.
///
/// The cases beyond `criteria` are declared before they are eligible so the
/// exhaustive switches that consume this enum name the whole road, and so
/// filling one in later is a compile error rather than a silent gap.
nonisolated enum JourneyCapability: String, Codable, Sendable, CaseIterable {
    /// What both people keep pointing at.
    case criteria
    case comparison
    case schedule
    case budgetBand
    case checklist
}

/// A capability that has earned its place, and the proof of why.
nonisolated struct JourneyCapabilityBinding: Identifiable, Hashable, Sendable {
    var id: JourneyCapability { capability }
    let capability: JourneyCapability
    /// The records this capability reads. It binds to them; it never holds a
    /// copy, so nothing it displays outlives the thing it points at.
    let provenance: FieldProvenance
}

nonisolated struct SharedJourney: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let insightID: String
    let directionID: String
    let scope: JourneyScope
    let title: String
    let summary: String
    let rationale: String
    let evidence: [String]
    let nextMove: String?
    let horizonID: String?
    var status: SharedJourneyStatus
    let activatedAt: String

    /// What the journey was read from, carried through activation.
    ///
    /// Defaulted and last so a journey decoded from a row written before the
    /// column existed still loads, and every existing construction site keeps
    /// compiling — the pattern `LifeItem.sourceURL` documents.
    var subjectReferences: [FieldReference] = []
}
