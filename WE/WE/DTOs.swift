import Foundation

nonisolated struct ProfileDTO: Decodable, Sendable {
    let id: String
    let name: String
}

nonisolated struct ProfileNameDTO: Decodable, Sendable {
    let name: String
}

nonisolated struct MembershipDTO: Decodable, Sendable {
    let coupleID: String
    let profileID: String
    let hue: String
    let hueChosenAt: String?

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case profileID = "profile_id"
        case hue
        case hueChosenAt = "hue_chosen_at"
    }
}

nonisolated struct PlanDTO: Decodable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let scheduledOn: String?
    let status: String
    let completedAt: String?
    let createdBy: String?
    let updatedBy: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, note, status
        case coupleID = "couple_id"
        case scheduledOn = "scheduled_on"
        case completedAt = "completed_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct ResponsibilityDTO: Decodable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let ownerID: String?
    let scheduledOn: String?
    let relatedPlanID: String?
    let suggestionProvenance: SuggestionProvenance?
    let status: String
    let completedAt: String?
    let createdBy: String?
    let updatedBy: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, note, status
        case coupleID = "couple_id"
        case ownerID = "owner_id"
        case scheduledOn = "scheduled_on"
        case relatedPlanID = "related_plan_id"
        case suggestionProvenance = "suggestion_provenance"
        case completedAt = "completed_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct PresenceDTO: Decodable, Sendable {
    let coupleID: String
    let mode: String
    let changedBy: String?
    let changedAt: String

    enum CodingKeys: String, CodingKey {
        case mode
        case coupleID = "couple_id"
        case changedBy = "changed_by"
        case changedAt = "changed_at"
    }
}

nonisolated struct SignalConsentDTO: Decodable, Sendable {
    let coupleID: String
    let profileID: String
    let signal: String
    let enabled: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case signal, enabled
        case coupleID = "couple_id"
        case profileID = "profile_id"
        case updatedAt = "updated_at"
    }
}

nonisolated struct AnchorDTO: Decodable, Sendable {
    let id: String
    let coupleID: String
    let title: String
    let note: String?
    let cadence: String
    let isActive: Bool
    let createdBy: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, note, cadence
        case coupleID = "couple_id"
        case isActive = "is_active"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct HandoffDTO: Decodable, Sendable {
    let id: String
    let responsibilityID: String
    let coupleID: String
    let fromProfileID: String
    let toProfileID: String
    let status: String
    let createdAt: String
    let respondedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case responsibilityID = "responsibility_id"
        case coupleID = "couple_id"
        case fromProfileID = "from_profile_id"
        case toProfileID = "to_profile_id"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

nonisolated struct ApproachDTO: Decodable, Sendable {
    let id: String
    let planID: String
    let profileID: String
    let approach: String
    let note: String?
    let revealedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, approach, note
        case planID = "plan_id"
        case profileID = "profile_id"
        case revealedAt = "revealed_at"
        case createdAt = "created_at"
    }
}

nonisolated struct RelationshipEventDTO: Decodable, Sendable {
    let id: String
    let coupleID: String
    let type: String
    let sourceID: String
    let title: String
    let occurredAt: String
    let provenance: [ProvenanceReference]

    enum CodingKeys: String, CodingKey {
        case id, title, provenance
        case coupleID = "couple_id"
        case type = "event_type"
        case sourceID = "source_id"
        case occurredAt = "occurred_at"
    }
}

nonisolated struct SeasonDTO: Decodable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id, sequence, title, summary, provenance
        case coupleID = "couple_id"
        case startsAt = "starts_at"
        case cutoffAt = "cutoff_at"
        case eventIDs = "event_ids"
        case createdAt = "created_at"
    }
}

nonisolated struct ContextualSuggestionDTO: Decodable, Sendable {
    let id: String
    let coupleID: String
    let kind: String
    let relatedPlanID: String
    let title: String
    let proposedResponsibilityTitle: String
    let proposedScheduledOn: String?
    let evidence: SuggestionEvidence
    let provenance: SuggestionProvenance
    let createdAt: String
    let isEligible: Bool
    let confirmedResponsibilityID: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, evidence, provenance
        case coupleID = "couple_id"
        case relatedPlanID = "related_plan_id"
        case proposedResponsibilityTitle =
            "proposed_responsibility_title"
        case proposedScheduledOn = "proposed_scheduled_on"
        case createdAt = "created_at"
        case isEligible = "is_eligible"
        case confirmedResponsibilityID = "confirmed_responsibility_id"
    }
}

nonisolated struct ContextualSuggestionDismissalDTO:
    Decodable,
    Sendable
{
    let suggestionID: String

    enum CodingKeys: String, CodingKey {
        case suggestionID = "suggestion_id"
    }
}

nonisolated struct DeclineGraceDTO: Decodable, Sendable {
    let insightID: String
    let profileID: String
    let declineCount: Int
    let suppressUntil: String?

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case profileID = "profile_id"
        case declineCount = "decline_count"
        case suppressUntil = "suppress_until"
    }
}

nonisolated struct PartnerAnswerStatusDTO: Decodable, Sendable {
    let insightID: String
    let profileID: String
    let hasAnswered: Bool

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case profileID = "profile_id"
        case hasAnswered = "has_answered"
    }
}

nonisolated struct RelationshipArchiveDTO: Decodable, Sendable {
    let id: String
    let ownerID: String
    let endedAt: String
    let snapshotVersion: Int
    let snapshot: RelationshipArchiveSnapshot?

    enum CodingKeys: String, CodingKey {
        case id, snapshot
        case ownerID = "owner_id"
        case endedAt = "ended_at"
        case snapshotVersion = "snapshot_version"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        ownerID = try values.decode(String.self, forKey: .ownerID)
        endedAt = try values.decode(String.self, forKey: .endedAt)
        snapshotVersion = try values.decode(Int.self, forKey: .snapshotVersion)
        snapshot = (1...RelationshipArchiveSnapshot.currentVersion)
            .contains(snapshotVersion)
            ? try values.decode(
                RelationshipArchiveSnapshot.self,
                forKey: .snapshot
            )
            : nil
    }
}

nonisolated struct ProfileUpdatePayload: Encodable, Sendable {
    let name: String
}

nonisolated struct HueUpdatePayload: Encodable, Sendable {
    let hue: String
    let hueChosenAt: String

    enum CodingKeys: String, CodingKey {
        case hue
        case hueChosenAt = "hue_chosen_at"
    }
}

nonisolated struct SharedItemStatusPayload: Encodable, Sendable {
    let status: String
}

nonisolated struct PlanWritePayload: Encodable, Sendable {
    let coupleID: String?
    let title: String
    let note: String?
    let scheduledOn: String?

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case title, note
        case scheduledOn = "scheduled_on"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(coupleID, forKey: .coupleID)
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        try container.encode(scheduledOn, forKey: .scheduledOn)
    }
}

nonisolated struct ResponsibilityWritePayload: Encodable, Sendable {
    let coupleID: String?
    let title: String
    let note: String?
    let ownerID: String?

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case title, note
        case ownerID = "owner_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(coupleID, forKey: .coupleID)
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        try container.encode(ownerID, forKey: .ownerID)
    }
}

nonisolated struct ReflectionInsertPayload: Encodable, Sendable {
    let coupleID: String
    let ownerID: String
    let domain: String
    let kind: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case ownerID = "owner_id"
        case domain, kind, text
    }
}

nonisolated struct CoupleDTO: Decodable, Sendable {
    let id: String
    let joinCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case joinCode = "join_code"
    }
}

nonisolated struct MemberDTO: Decodable, Sendable {
    let profileID: String
    let hue: String
    let profiles: ProfileNameDTO?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case hue
        case profiles
    }
}

nonisolated struct InsightDTO: Decodable, Sendable {
    let id: String
    let seedKey: String
    let kind: String
    let domain: String
    let present: Bool
    let title: String
    let body: String
    let evidence: String
    let source: String
    let options: [String]
    let sort: Int

    enum CodingKeys: String, CodingKey {
        case id
        case seedKey = "seed_key"
        case kind
        case domain
        case present
        case title
        case body
        case evidence
        case source
        case options
        case sort
    }
}

nonisolated struct ConsentDTO: Decodable, Sendable {
    let insightID: String
    let visibility: String
    let ownerID: String?
    let readiness: String
    let initiatorID: String?
    let requestedAt: String?
    let acceptedAt: String?
    let resolutionType: String?
    let resolutionChoice: String?

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case visibility
        case ownerID = "owner_id"
        case readiness
        case initiatorID = "initiator_id"
        case requestedAt = "requested_at"
        case acceptedAt = "accepted_at"
        case resolutionType = "resolution_type"
        case resolutionChoice = "resolution_choice"
    }
}

nonisolated struct ResponseDTO: Decodable, Sendable {
    let insightID: String
    let profileID: String
    let status: String
    let choice: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case profileID = "profile_id"
        case status
        case choice
        case note
    }
}

nonisolated struct ReflectionDTO: Decodable, Sendable {
    let id: String
    let coupleID: String
    let ownerID: String
    let domain: String
    let kind: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case id
        case coupleID = "couple_id"
        case ownerID = "owner_id"
        case domain
        case kind
        case text
    }
}

nonisolated struct DismissalDTO: Decodable, Sendable {
    let insightID: String
    let profileID: String

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case profileID = "profile_id"
    }
}

nonisolated struct InsightDeclineDTO: Decodable, Sendable {
    let insightID: String
    let profileID: String

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case profileID = "profile_id"
    }
}

nonisolated struct JoinCoupleParameters: Encodable, Sendable {
    let code: String

    enum CodingKeys: String, CodingKey {
        case code = "p_code"
    }
}

nonisolated struct InsightParameters: Encodable, Sendable {
    let insightID: String

    enum CodingKeys: String, CodingKey {
        case insightID = "p_insight"
    }
}

nonisolated struct SubmitResponseParameters: Encodable, Sendable {
    let insightID: String
    let choice: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case insightID = "p_insight"
        case choice = "p_choice"
        case note = "p_note"
    }
}

nonisolated struct ResolveInsightParameters: Encodable, Sendable {
    let insightID: String
    let type: String
    let choice: String?

    enum CodingKeys: String, CodingKey {
        case insightID = "p_insight"
        case type = "p_type"
        case choice = "p_choice"
    }
}

nonisolated struct RefreshSharedMomentsParameters: Encodable, Sendable {
    let localDate: String

    enum CodingKeys: String, CodingKey {
        case localDate = "p_local_date"
    }
}

nonisolated struct CreatePlanParameters: Encodable, Sendable {
    let coupleID: String
    let title: String
    let note: String?
    let scheduledOn: String?

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple"
        case title = "p_title"
        case note = "p_note"
        case scheduledOn = "p_scheduled_on"
    }
}

nonisolated struct UpdatePlanParameters: Encodable, Sendable {
    let id: String
    let title: String
    let note: String?
    let scheduledOn: String?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case title = "p_title"
        case note = "p_note"
        case scheduledOn = "p_scheduled_on"
    }
}

nonisolated struct SharedItemStatusParameters: Encodable, Sendable {
    let id: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case status = "p_status"
    }
}

nonisolated struct CreateResponsibilityParameters: Encodable, Sendable {
    let coupleID: String
    let title: String
    let note: String?
    let ownerID: String?

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple"
        case title = "p_title"
        case note = "p_note"
        case ownerID = "p_owner"
    }
}

nonisolated struct PresenceParameters: Encodable, Sendable {
    let mode: String

    enum CodingKeys: String, CodingKey {
        case mode = "p_mode"
    }
}

nonisolated struct SignalConsentParameters: Encodable, Sendable {
    let signal: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case signal = "p_signal"
        case enabled = "p_enabled"
    }
}

nonisolated struct CreateAnchorParameters: Encodable, Sendable {
    let coupleID: String
    let title: String
    let note: String?
    let cadence: String

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple"
        case title = "p_title"
        case note = "p_note"
        case cadence = "p_cadence"
    }
}

nonisolated struct AnchorStatusParameters: Encodable, Sendable {
    let anchorID: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case anchorID = "p_anchor"
        case isActive = "p_active"
    }
}

nonisolated struct ApproachParameters: Encodable, Sendable {
    let planID: String
    let approach: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case planID = "p_plan"
        case approach = "p_approach"
        case note = "p_note"
    }
}

nonisolated struct OfferHandoffParameters: Encodable, Sendable {
    let responsibilityID: String
    let toProfileID: String

    enum CodingKeys: String, CodingKey {
        case responsibilityID = "p_responsibility"
        case toProfileID = "p_to_profile"
    }
}

nonisolated struct RespondHandoffParameters: Encodable, Sendable {
    let handoffID: String
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case handoffID = "p_handoff"
        case accept = "p_accept"
    }
}

nonisolated struct HandoffParameters: Encodable, Sendable {
    let handoffID: String

    enum CodingKeys: String, CodingKey {
        case handoffID = "p_handoff"
    }
}

nonisolated struct ContextualSuggestionParameters: Encodable, Sendable {
    let suggestionID: String

    enum CodingKeys: String, CodingKey {
        case suggestionID = "p_suggestion"
    }
}

nonisolated struct ConfirmContextualSuggestionParameters:
    Encodable,
    Sendable
{
    let suggestionID: String
    let title: String
    let note: String?
    let ownerID: String?
    let scheduledOn: String?

    enum CodingKeys: String, CodingKey {
        case suggestionID = "p_suggestion"
        case title = "p_title"
        case note = "p_note"
        case ownerID = "p_owner"
        case scheduledOn = "p_scheduled_on"
    }
}

nonisolated struct UpdateResponsibilityParameters: Encodable, Sendable {
    let id: String
    let title: String
    let note: String?
    let ownerID: String?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case title = "p_title"
        case note = "p_note"
        case ownerID = "p_owner"
    }
}
