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
        case completedAt = "completed_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
        snapshot = snapshotVersion == RelationshipArchiveSnapshot.currentVersion
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
    let kind: String
    let domain: String
    let present: Bool
    let title: String
    let body: String
    let evidence: String
    let source: String
    let options: [String]
    let sort: Int
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
