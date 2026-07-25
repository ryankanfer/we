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

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case profileID = "profile_id"
        case hue
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
