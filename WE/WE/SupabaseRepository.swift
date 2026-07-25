import Foundation
import Supabase

struct SupabaseRepository: Repository {
    private let client: SupabaseClient?

    var isConfigured: Bool { client != nil }

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        let client = try configuredClient()
        guard client.auth.currentSession != nil else {
            return nil
        }

        let session = try await client.auth.session
        return AuthenticatedUser(
            id: session.user.id.uuidString,
            email: session.user.email ?? ""
        )
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        let session = try await configuredClient().auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )

        return AuthenticatedUser(
            id: session.user.id.uuidString,
            email: session.user.email ?? email
        )
    }

    func signOut() async throws {
        try await configuredClient().auth.signOut()
    }

    func loadRelationship(
        for user: AuthenticatedUser
    ) async throws -> RelationshipSnapshot {
        let client = try configuredClient()

        let profiles: [ProfileDTO] = try await client
            .from("profiles")
            .select("id,name")
            .eq("id", value: user.id)
            .limit(1)
            .execute()
            .value

        let profile = profiles.first.map {
            Profile(id: $0.id, name: $0.name)
        } ?? Profile(id: user.id, name: "You")

        let memberships: [MembershipDTO] = try await client
            .from("couple_members")
            .select("couple_id,profile_id,hue")
            .eq("profile_id", value: user.id)
            .limit(1)
            .execute()
            .value

        guard let membershipDTO = memberships.first else {
            return RelationshipSnapshot(
                profile: profile,
                membership: nil,
                couple: nil,
                members: [],
                insights: [],
                reflections: []
            )
        }

        let membership = Membership(
            coupleID: membershipDTO.coupleID,
            profileID: membershipDTO.profileID,
            hue: try memberHue(membershipDTO.hue)
        )

        let couples: [CoupleDTO] = try await client
            .from("couples")
            .select("id,join_code")
            .eq("id", value: membership.coupleID)
            .limit(1)
            .execute()
            .value

        let memberDTOs: [MemberDTO] = try await client
            .from("couple_members")
            .select("profile_id,hue,profiles(name)")
            .eq("couple_id", value: membership.coupleID)
            .execute()
            .value

        let insightDTOs: [InsightDTO] = try await client
            .from("insights")
            .select(
                "id,kind,domain,present,title,body,evidence,source,options,sort"
            )
            .eq("couple_id", value: membership.coupleID)
            .order("sort", ascending: true)
            .execute()
            .value

        let consentDTOs: [ConsentDTO] = try await client
            .from("insight_consent")
            .select(
                """
                insight_id,visibility,owner_id,readiness,initiator_id,\
                requested_at,accepted_at,resolution_type,resolution_choice
                """
            )
            .execute()
            .value

        let responseDTOs: [ResponseDTO] = try await client
            .from("responses")
            .select("insight_id,profile_id,status,choice,note")
            .execute()
            .value

        let reflectionDTOs: [ReflectionDTO] = try await client
            .from("reflections")
            .select("id,couple_id,owner_id,domain,kind,text")
            .eq("owner_id", value: user.id)
            .execute()
            .value

        let members = try memberDTOs.map {
            Member(
                id: $0.profileID,
                name: $0.profiles?.name ?? "Partner",
                hue: try memberHue($0.hue)
            )
        }

        let consentByInsight = Dictionary(
            uniqueKeysWithValues: try consentDTOs.map {
                ($0.insightID, try consent($0))
            }
        )

        let responsesByInsight = Dictionary(
            grouping: try responseDTOs.map(response),
            by: \.insightID
        )

        let insights = try insightDTOs.map { dto in
            let insight = try insight(dto)
            return InsightRecord(
                insight: insight,
                consent: consentByInsight[insight.id],
                responses: responsesByInsight[insight.id] ?? []
            )
        }

        let reflections = try reflectionDTOs.map(reflection)
        let couple = couples.first.map {
            Couple(id: $0.id, joinCode: $0.joinCode)
        }

        return RelationshipSnapshot(
            profile: profile,
            membership: membership,
            couple: couple,
            members: members,
            insights: insights,
            reflections: reflections
        )
    }

    private func configuredClient() throws -> SupabaseClient {
        guard let client else {
            throw RepositoryError.missingConfiguration
        }
        return client
    }

    private func memberHue(_ rawValue: String) throws -> MemberHue {
        guard let value = MemberHue(rawValue: rawValue) else {
            throw RepositoryError.invalidData("unknown member hue")
        }
        return value
    }

    private func insight(_ dto: InsightDTO) throws -> Insight {
        guard let kind = InsightKind(rawValue: dto.kind),
              let domain = InsightDomain(rawValue: dto.domain) else {
            throw RepositoryError.invalidData("unknown insight kind or domain")
        }

        return Insight(
            id: dto.id,
            kind: kind,
            domain: domain,
            present: dto.present,
            title: dto.title,
            body: dto.body,
            evidence: dto.evidence,
            source: dto.source,
            actionTitle: kind == .logistical
                ? "Shape a plan"
                : "Open together",
            options: dto.options
        )
    }

    private func consent(_ dto: ConsentDTO) throws -> InsightConsent {
        guard let visibility = ConsentVisibility(
            rawValue: dto.visibility
        ),
        let readiness = ConsentReadiness(rawValue: dto.readiness) else {
            throw RepositoryError.invalidData("unknown consent state")
        }

        let resolutionType = try dto.resolutionType.map {
            guard let value = ResolutionType(rawValue: $0) else {
                throw RepositoryError.invalidData("unknown resolution type")
            }
            return value
        }

        return InsightConsent(
            insightID: dto.insightID,
            visibility: visibility,
            ownerID: dto.ownerID,
            readiness: readiness,
            initiatorID: dto.initiatorID,
            requestedAt: dto.requestedAt,
            acceptedAt: dto.acceptedAt,
            resolutionType: resolutionType,
            resolutionChoice: dto.resolutionChoice
        )
    }

    private func response(_ dto: ResponseDTO) throws -> InsightResponse {
        guard let status = ResponseStatus(rawValue: dto.status) else {
            throw RepositoryError.invalidData("unknown response status")
        }

        return InsightResponse(
            insightID: dto.insightID,
            profileID: dto.profileID,
            status: status,
            choice: dto.choice,
            note: dto.note
        )
    }

    private func reflection(_ dto: ReflectionDTO) throws -> Reflection {
        guard let domain = InsightDomain(rawValue: dto.domain),
              let kind = ReflectionKind(rawValue: dto.kind) else {
            throw RepositoryError.invalidData(
                "unknown reflection kind or domain"
            )
        }

        return Reflection(
            id: dto.id,
            coupleID: dto.coupleID,
            ownerID: dto.ownerID,
            domain: domain,
            kind: kind,
            text: dto.text
        )
    }
}
