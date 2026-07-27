import Foundation
import Supabase

final class SupabaseRepository: Repository {
    private let client: SupabaseClient?

    var isConfigured: Bool { client != nil }

    init(provider: SupabaseClientProvider) {
        client = provider.client
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        let client = try configuredClient()
        guard let storedSession = client.auth.currentSession else {
            return nil
        }
        do {
            let validatedSession = try await client.auth.session
            return authenticatedUser(validatedSession.user)
        } catch {
            throw RepositoryError.invalidSession(
                authenticatedUser(storedSession.user)
            )
        }
    }

    func signUp(
        name: String,
        email: String,
        password: String
    ) async throws -> SignUpResult {
        let normalizedEmail = normalized(email)
        let response = try await configuredClient().auth.signUp(
            email: normalizedEmail,
            password: password,
            data: ["name": .string(normalized(name))],
            redirectTo: Self.emailConfirmationURL
        )
        let user = authenticatedUser(response.user)
        return response.session == nil
            ? .verificationPending(email: normalizedEmail)
            : .signedIn(user)
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        let session = try await configuredClient().auth.signIn(
            email: normalized(email),
            password: password
        )
        return authenticatedUser(session.user)
    }

    func sendPasswordReset(email: String) async throws {
        try await configuredClient().auth.resetPasswordForEmail(
            normalized(email),
            redirectTo: Self.passwordRecoveryURL
        )
    }

    func handleAuthCallback(_ url: URL) async throws
        -> AuthCallbackResult
    {
        guard url.scheme?.lowercased() == "we",
              let host = url.host?.lowercased(),
              ["email-confirmed", "password-recovery"].contains(host)
        else {
            throw RepositoryError.invalidData("unrecognized sign-in link")
        }
        let session = try await configuredClient().auth.session(from: url)
        let user = authenticatedUser(session.user)
        return host == "password-recovery"
            ? .passwordRecovery(user)
            : .emailConfirmed(user)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await configuredClient().auth.update(
            user: UserAttributes(password: password)
        )
    }

    func signOut() async throws {
        try await configuredClient().auth.signOut()
    }

    func deleteAccount(email: String, password: String) async throws {
        let client = try configuredClient()
        _ = try await client.auth.signIn(
            email: normalized(email),
            password: password
        )
        _ = try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut(scope: .local)
    }

    func createCouple() async throws {
        _ = try await configuredClient().rpc("create_couple").execute()
    }

    func joinCouple(code: String) async throws {
        _ = try await configuredClient()
            .rpc(
                "join_couple",
                params: JoinCoupleParameters(code: normalized(code))
            )
            .execute()
    }

    func updateProfile(name: String, userID: String) async throws {
        _ = try await configuredClient()
            .from("profiles")
            .update(ProfileUpdatePayload(name: normalized(name)))
            .eq("id", value: userID)
            .execute()
    }

    func updateHue(
        _ hue: MemberHue,
        membership: Membership
    ) async throws {
        _ = try await configuredClient()
            .from("couple_members")
            .update(
                HueUpdatePayload(
                    hue: hue.rawValue,
                    hueChosenAt: Self.timestamp(Date())
                )
            )
            .eq("couple_id", value: membership.coupleID)
            .eq("profile_id", value: membership.profileID)
            .execute()
    }

    func createPlan(_ input: PlanInput, coupleID: String) async throws {
        _ = try await configuredClient()
            .rpc(
                "create_plan",
                params: CreatePlanParameters(
                    coupleID: coupleID,
                    title: normalized(input.title),
                    note: normalizedOptional(input.note),
                    scheduledOn: input.scheduledOn
                )
            )
            .execute()
    }

    func updatePlan(id: String, input: PlanInput) async throws {
        _ = try await configuredClient()
            .rpc(
                "update_plan",
                params: UpdatePlanParameters(
                    id: id,
                    title: normalized(input.title),
                    note: normalizedOptional(input.note),
                    scheduledOn: input.scheduledOn
                )
            )
            .execute()
    }

    func setPlanStatus(
        id: String,
        status: SharedItemStatus
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "set_plan_status",
                params: SharedItemStatusParameters(
                    id: id,
                    status: status.rawValue
                )
            )
            .execute()
    }

    func createResponsibility(
        _ input: ResponsibilityInput,
        coupleID: String,
        ownerID: String?
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "create_responsibility",
                params: CreateResponsibilityParameters(
                    coupleID: coupleID,
                    title: normalized(input.title),
                    note: normalizedOptional(input.note),
                    ownerID: ownerID
                )
            )
            .execute()
    }

    func updateResponsibility(
        id: String,
        input: ResponsibilityInput,
        ownerID: String?
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "update_responsibility",
                params: UpdateResponsibilityParameters(
                    id: id,
                    title: normalized(input.title),
                    note: normalizedOptional(input.note),
                    ownerID: ownerID
                )
            )
            .execute()
    }

    func setResponsibilityStatus(
        id: String,
        status: SharedItemStatus
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "set_responsibility_status",
                params: SharedItemStatusParameters(
                    id: id,
                    status: status.rawValue
                )
            )
            .execute()
    }

    func saveReflection(
        text: String,
        domain: InsightDomain,
        coupleID: String,
        ownerID: String
    ) async throws {
        _ = try await configuredClient()
            .from("reflections")
            .insert(
                ReflectionInsertPayload(
                    coupleID: coupleID,
                    ownerID: ownerID,
                    domain: domain.rawValue,
                    kind: ReflectionKind.reflection.rawValue,
                    text: normalized(text)
                )
            )
            .execute()
    }

    func requestReveal(insightID: String) async throws {
        try await runInsightRPC("request_reveal", insightID: insightID)
    }

    func acceptReveal(insightID: String) async throws {
        try await runInsightRPC("accept_reveal", insightID: insightID)
    }

    func declineReveal(insightID: String) async throws {
        try await runInsightRPC("decline_reveal", insightID: insightID)
    }

    func withdrawReveal(insightID: String) async throws {
        try await runInsightRPC("withdraw_reveal", insightID: insightID)
    }

    func submitResponse(
        insightID: String,
        choice: String,
        note: String?
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "submit_response",
                params: SubmitResponseParameters(
                    insightID: insightID,
                    choice: choice,
                    note: note
                )
            )
            .execute()
    }

    func resolveInsight(
        insightID: String,
        type: ResolutionType,
        choice: String?
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "resolve_insight",
                params: ResolveInsightParameters(
                    insightID: insightID,
                    type: type.rawValue,
                    choice: choice
                )
            )
            .execute()
    }

    func dismissSuggestion(insightID: String) async throws {
        try await runInsightRPC("dismiss_suggestion", insightID: insightID)
    }

    func relationshipChanges() async throws
        -> AsyncThrowingStream<Void, Error>
    {
        let client = try configuredClient()
        let channel = client.channel("we-couple")
        let tables = [
            "insight_consent",
            "responses",
            "couple_members",
            "dismissals",
            "insight_declines",
            "reflections",
            "plans",
            "responsibilities",
            "relationship_archives",
        ]
        let sourceStreams = tables.map {
            channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: $0
            )
        }

        try await channel.subscribeWithError()

        let (stream, continuation) = AsyncThrowingStream<
            Void,
            Error
        >.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let completion = RealtimeSourceCompletion(
            remaining: sourceStreams.count
        )
        let tasks = sourceStreams.map { source in
            Task {
                for await _ in source {
                    guard !Task.isCancelled else { break }
                    continuation.yield(())
                }
                if await completion.didFinishLastSource() {
                    continuation.finish()
                }
            }
        }

        continuation.onTermination = { _ in
            tasks.forEach { $0.cancel() }
            Task { await client.removeChannel(channel) }
        }
        return stream
    }

    func loadRelationship(
        for user: AuthenticatedUser
    ) async throws -> RelationshipSnapshot {
        let client = try configuredClient()

        async let profilesRequest: [ProfileDTO] = client
            .from("profiles")
            .select("id,name")
            .eq("id", value: user.id)
            .limit(1)
            .execute()
            .value

        async let archivesRequest: [RelationshipArchiveDTO] = client
            .from("relationship_archives")
            .select("id,owner_id,ended_at,snapshot_version,snapshot")
            .eq("owner_id", value: user.id)
            .order("ended_at", ascending: false)
            .execute()
            .value

        async let membershipsRequest: [MembershipDTO] = client
            .from("couple_members")
            .select("couple_id,profile_id,hue,hue_chosen_at")
            .eq("profile_id", value: user.id)
            .limit(1)
            .execute()
            .value
        let (profiles, archiveDTOs, memberships) = try await (
            profilesRequest,
            archivesRequest,
            membershipsRequest
        )
        let profile = profiles.first.map {
            Profile(id: $0.id, name: $0.name)
        } ?? Profile(id: user.id, name: "You")
        let archives = archiveDTOs.compactMap(archive)

        guard let membershipDTO = memberships.first else {
            return RelationshipSnapshot(
                profile: profile,
                membership: nil,
                couple: nil,
                members: [],
                insights: [],
                reflections: [],
                plans: [],
                responsibilities: [],
                archives: archives,
                syncedAt: Date()
            )
        }

        let membership = try Membership(
            coupleID: membershipDTO.coupleID,
            profileID: membershipDTO.profileID,
            hue: memberHue(membershipDTO.hue),
            hueChosenAt: membershipDTO.hueChosenAt
        )

        let localDate = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: Date()
        )
        let localDateValue = String(
            format: "%04d-%02d-%02d",
            localDate.year ?? 1970,
            localDate.month ?? 1,
            localDate.day ?? 1
        )
        _ = try? await client
            .rpc(
                "refresh_shared_moments",
                params: RefreshSharedMomentsParameters(
                    localDate: localDateValue
                )
            )
            .execute()

        async let couplesRequest: [CoupleDTO] = client
            .from("couples")
            .select("id,join_code")
            .eq("id", value: membership.coupleID)
            .limit(1)
            .execute()
            .value
        async let membersRequest: [MemberDTO] = client
            .from("couple_members")
            .select("profile_id,hue,profiles(name)")
            .eq("couple_id", value: membership.coupleID)
            .execute()
            .value
        async let insightsRequest: [InsightDTO] = client
            .from("insights")
            .select("id,seed_key,kind,domain,present,title,body,evidence,source,options,sort")
            .eq("couple_id", value: membership.coupleID)
            .order("sort", ascending: true)
            .execute()
            .value
        async let consentRequest: [ConsentDTO] = client
            .from("insight_consent")
            .select(
                "insight_id,visibility,owner_id,readiness,initiator_id,requested_at,accepted_at,resolution_type,resolution_choice"
            )
            .execute()
            .value
        async let responsesRequest: [ResponseDTO] = client
            .from("responses")
            .select("insight_id,profile_id,status,choice,note")
            .execute()
            .value
        async let reflectionsRequest: [ReflectionDTO] = client
            .from("reflections")
            .select("id,couple_id,owner_id,domain,kind,text")
            .eq("owner_id", value: user.id)
            .execute()
            .value
        async let dismissalsRequest: [DismissalDTO] = client
            .from("dismissals")
            .select("insight_id,profile_id")
            .execute()
            .value
        async let declinesRequest: [InsightDeclineDTO] = client
            .from("insight_declines")
            .select("insight_id,profile_id")
            .execute()
            .value
        async let plansRequest: [PlanDTO] = client
            .from("plans")
            .select("id,couple_id,title,note,scheduled_on,status,completed_at,created_by,updated_by,created_at,updated_at")
            .eq("couple_id", value: membership.coupleID)
            .order("scheduled_on", ascending: true, nullsFirst: false)
            .execute()
            .value
        async let responsibilitiesRequest: [ResponsibilityDTO] = client
            .from("responsibilities")
            .select("id,couple_id,title,note,owner_id,status,completed_at,created_by,updated_by,created_at,updated_at")
            .eq("couple_id", value: membership.coupleID)
            .order("created_at", ascending: true)
            .execute()
            .value

        let (
            coupleDTOs,
            memberDTOs,
            insightDTOs,
            consentDTOs,
            responseDTOs,
            reflectionDTOs,
            dismissalDTOs,
            declineDTOs,
            planDTOs,
            responsibilityDTOs
        ) = try await (
            couplesRequest,
            membersRequest,
            insightsRequest,
            consentRequest,
            responsesRequest,
            reflectionsRequest,
            dismissalsRequest,
            declinesRequest,
            plansRequest,
            responsibilitiesRequest
        )

        let members = try memberDTOs.map {
            try Member(
                id: $0.profileID,
                name: $0.profiles?.name ?? "Partner",
                hue: memberHue($0.hue)
            )
        }
        let consentByInsight = try Dictionary(
            uniqueKeysWithValues: consentDTOs.map {
                try ($0.insightID, consent($0))
            }
        )
        let responsesByInsight = try Dictionary(
            grouping: responseDTOs.map(response),
            by: \.insightID
        )
        let dismissalsByInsight = Dictionary(
            grouping: dismissalDTOs,
            by: \.insightID
        )
        let declinesByInsight = Dictionary(
            grouping: declineDTOs,
            by: \.insightID
        )
        let insights = try insightDTOs.map { dto in
            let value = try insight(dto)
            return InsightRecord(
                insight: value,
                consent: consentByInsight[value.id],
                responses: responsesByInsight[value.id] ?? [],
                dismissedBy: Set(
                    dismissalsByInsight[value.id, default: []].map(\.profileID)
                ),
                declinedBy: Set(
                    declinesByInsight[value.id, default: []].map(\.profileID)
                )
            )
        }

        return try RelationshipSnapshot(
            profile: profile,
            membership: membership,
            couple: coupleDTOs.first.map {
                Couple(id: $0.id, joinCode: $0.joinCode)
            },
            members: members,
            insights: insights,
            reflections: reflectionDTOs.map(reflection),
            plans: planDTOs.map(plan),
            responsibilities: responsibilityDTOs.map {
                try responsibility($0, userID: user.id)
            },
            archives: archives,
            syncedAt: Date()
        )
    }

    private func configuredClient() throws -> SupabaseClient {
        guard let client else { throw RepositoryError.missingConfiguration }
        return client
    }

    private func runInsightRPC(
        _ function: String,
        insightID: String
    ) async throws {
        _ = try await configuredClient()
            .rpc(function, params: InsightParameters(insightID: insightID))
            .execute()
    }

    private func authenticatedUser(_ user: User) -> AuthenticatedUser {
        AuthenticatedUser(
            id: user.id.uuidString,
            email: user.email ?? ""
        )
    }

    private func planPayload(
        _ input: PlanInput,
        coupleID: String?
    ) -> PlanWritePayload {
        PlanWritePayload(
            coupleID: coupleID,
            title: normalized(input.title),
            note: normalizedOptional(input.note),
            scheduledOn: input.scheduledOn
        )
    }

    private func responsibilityPayload(
        _ input: ResponsibilityInput,
        coupleID: String?,
        ownerID: String?
    ) -> ResponsibilityWritePayload {
        ResponsibilityWritePayload(
            coupleID: coupleID,
            title: normalized(input.title),
            note: normalizedOptional(input.note),
            ownerID: ownerID
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = normalized(value)
        return result.isEmpty ? nil : result
    }

    private func memberHue(_ rawValue: String) throws -> MemberHue {
        guard let value = MemberHue(rawValue: rawValue) else {
            throw RepositoryError.invalidData("unknown member hue")
        }
        return value
    }

    private func sharedStatus(_ rawValue: String) throws -> SharedItemStatus {
        guard let value = SharedItemStatus(rawValue: rawValue) else {
            throw RepositoryError.invalidData("unknown shared item status")
        }
        return value
    }

    private func insight(_ dto: InsightDTO) throws -> Insight {
        guard let kind = InsightKind(rawValue: dto.kind),
              let domain = InsightDomain(rawValue: dto.domain)
        else {
            throw RepositoryError.invalidData("unknown insight kind or domain")
        }
        return Insight(
            id: dto.id,
            seedKey: dto.seedKey,
            kind: kind,
            domain: domain,
            present: dto.present,
            title: dto.title,
            body: dto.body,
            evidence: dto.evidence,
            source: dto.source,
            actionTitle: kind == .logistical ? "Shape a plan" : "Open together",
            options: dto.options
        )
    }

    private func consent(_ dto: ConsentDTO) throws -> InsightConsent {
        guard let visibility = ConsentVisibility(rawValue: dto.visibility),
              let readiness = ConsentReadiness(rawValue: dto.readiness)
        else {
            throw RepositoryError.invalidData("unknown consent state")
        }
        let resolution: ResolutionType?
        if let raw = dto.resolutionType {
            guard let value = ResolutionType(rawValue: raw) else {
                throw RepositoryError.invalidData("unknown resolution")
            }
            resolution = value
        } else {
            resolution = nil
        }
        return InsightConsent(
            insightID: dto.insightID,
            visibility: visibility,
            ownerID: dto.ownerID,
            readiness: readiness,
            initiatorID: dto.initiatorID,
            requestedAt: dto.requestedAt,
            acceptedAt: dto.acceptedAt,
            resolutionType: resolution,
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
              let kind = ReflectionKind(rawValue: dto.kind)
        else {
            throw RepositoryError.invalidData("unknown reflection")
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

    private func plan(_ dto: PlanDTO) throws -> PlanItem {
        try PlanItem(
            id: dto.id,
            coupleID: dto.coupleID,
            title: dto.title,
            note: dto.note,
            scheduledOn: dto.scheduledOn,
            status: sharedStatus(dto.status),
            completedAt: dto.completedAt,
            createdBy: dto.createdBy,
            updatedBy: dto.updatedBy,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    private func responsibility(
        _ dto: ResponsibilityDTO,
        userID: String
    ) throws -> Responsibility {
        let owner: ResponsibilityOwner = if dto.ownerID == nil {
            .together
        } else if dto.ownerID == userID {
            .me
        } else {
            .partner
        }
        return try Responsibility(
            id: dto.id,
            coupleID: dto.coupleID,
            title: dto.title,
            note: dto.note,
            ownerID: dto.ownerID,
            owner: owner,
            status: sharedStatus(dto.status),
            completedAt: dto.completedAt,
            createdBy: dto.createdBy,
            updatedBy: dto.updatedBy,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    private func archive(
        _ dto: RelationshipArchiveDTO
    ) -> RelationshipArchive? {
        guard let snapshot = dto.snapshot else { return nil }
        return RelationshipArchive(
            id: dto.id,
            ownerID: dto.ownerID,
            endedAt: dto.endedAt,
            snapshotVersion: dto.snapshotVersion,
            snapshot: snapshot
        )
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static let emailConfirmationURL = URL(
        string: "we://email-confirmed"
    )!
    private static let passwordRecoveryURL = URL(
        string: "we://password-recovery"
    )!
}

private actor RealtimeSourceCompletion {
    private var remaining: Int

    init(remaining: Int) {
        self.remaining = remaining
    }

    func didFinishLastSource() -> Bool {
        remaining -= 1
        return remaining == 0
    }
}
