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

    func loadPrivateProposals(
        for user: AuthenticatedUser
    ) async throws -> [SavedPrivateProposal] {
        let values: [PrivateProposalDTO] = try await configuredClient()
            .from("private_proposals")
            .select(
                "id,owner_id,proposal_title,offered_title,offered_question,offered_options,preparation_method,prepared_at"
            )
            .eq("owner_id", value: user.id)
            .order("prepared_at", ascending: false)
            .execute()
            .value

        return try values.map { value in
            guard value.ownerID == user.id else {
                throw RepositoryError.invalidData(
                    "private proposal ownership did not match"
                )
            }
            guard let method = ProposalPreparationMethod(
                rawValue: value.preparationMethod
            ) else {
                throw RepositoryError.invalidData(
                    "unknown proposal preparation method"
                )
            }
            return SavedPrivateProposal(
                id: value.id,
                title: value.title,
                offeredTopic: OfferedTopic(
                    title: value.offeredTitle,
                    question: value.offeredQuestion,
                    options: value.offeredOptions
                ),
                preparationMethod: method,
                preparedAt: value.preparedAt
            )
        }
    }

    func claimPrivateProposal(_ proposal: PrivateProposal) async throws
        -> String
    {
        let proposalID: String = try await configuredClient()
            .rpc(
                "claim_private_proposal",
                params: ClaimPrivateProposalParameters(
                    localID: proposal.id,
                    sourceNote: proposal.sourceNote,
                    title: proposal.title,
                    offeredTitle: proposal.offeredTopic.title,
                    offeredQuestion: proposal.offeredTopic.question,
                    offeredOptions: proposal.offeredTopic.options,
                    preparationMethod: proposal.preparationMethod.rawValue,
                    createdAt: Self.timestamp(proposal.createdAt)
                )
            )
            .execute()
            .value
        return proposalID
    }

    func offerPrivateProposal(id: String) async throws {
        _ = try await configuredClient()
            .rpc(
                "offer_private_proposal",
                params: OfferPrivateProposalParameters(proposalID: id)
            )
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

    func setPresence(_ mode: PresenceMode) async throws {
        _ = try await configuredClient()
            .rpc(
                "set_relationship_presence",
                params: PresenceParameters(mode: mode.rawValue)
            )
            .execute()
    }

    func setSignalConsent(
        _ signal: SignalKind,
        enabled: Bool
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "set_signal_consent",
                params: SignalConsentParameters(
                    signal: signal.rawValue,
                    enabled: enabled
                )
            )
            .execute()
    }

    func createAnchor(
        _ input: AnchorInput,
        coupleID: String
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "create_anchor",
                params: CreateAnchorParameters(
                    coupleID: coupleID,
                    title: normalized(input.title),
                    note: normalizedOptional(input.note),
                    cadence: input.cadence.rawValue
                )
            )
            .execute()
    }

    func setAnchorActive(id: String, isActive: Bool) async throws {
        _ = try await configuredClient()
            .rpc(
                "set_anchor_active",
                params: AnchorStatusParameters(
                    anchorID: id,
                    isActive: isActive
                )
            )
            .execute()
    }

    func offerHandoff(
        responsibilityID: String,
        toProfileID: String
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "offer_responsibility_handoff",
                params: OfferHandoffParameters(
                    responsibilityID: responsibilityID,
                    toProfileID: toProfileID
                )
            )
            .execute()
    }

    func respondToHandoff(id: String, accept: Bool) async throws {
        _ = try await configuredClient()
            .rpc(
                "respond_responsibility_handoff",
                params: RespondHandoffParameters(
                    handoffID: id,
                    accept: accept
                )
            )
            .execute()
    }

    func withdrawHandoff(id: String) async throws {
        _ = try await configuredClient()
            .rpc(
                "withdraw_responsibility_handoff",
                params: HandoffParameters(handoffID: id)
            )
            .execute()
    }

    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "set_plan_approach",
                params: ApproachParameters(
                    planID: planID,
                    approach: approach.rawValue,
                    note: normalizedOptional(note)
                )
            )
            .execute()
    }

    func refreshContextualSuggestions(localDate: String) async throws {
        _ = try await configuredClient()
            .rpc(
                "refresh_contextual_suggestions",
                params: RefreshSharedMomentsParameters(
                    localDate: localDate
                )
            )
            .execute()
    }

    func dismissContextualSuggestion(id: String) async throws {
        _ = try await configuredClient()
            .rpc(
                "dismiss_contextual_suggestion",
                params: ContextualSuggestionParameters(
                    suggestionID: id
                )
            )
            .execute()
    }

    func confirmContextualSuggestion(
        _ confirmation: SuggestionConfirmation
    ) async throws {
        _ = try await configuredClient()
            .rpc(
                "confirm_contextual_suggestion",
                params: ConfirmContextualSuggestionParameters(
                    suggestionID: confirmation.suggestionID,
                    title: normalized(confirmation.title),
                    note: normalizedOptional(confirmation.note),
                    ownerID: confirmation.ownerID,
                    scheduledOn: confirmation.scheduledOn
                )
            )
            .execute()
    }

    func createReadySeason() async throws {
        _ = try await configuredClient()
            .rpc("create_ready_season")
            .execute()
    }

    func relationshipChanges() async throws
        -> AsyncThrowingStream<Void, Error>
    {
        let client = try configuredClient()
        let channel = client.channel("we-couple")
        let tables = [
            "insight_consent",
            "shared_directions",
            "offered_topics",
            "couple_members",
            "dismissals",
            "insight_declines",
            "reflections",
            "plans",
            "responsibilities",
            "relationship_archives",
            "relationship_presence",
            "signal_consents",
            "anchors",
            "responsibility_handoffs",
            "relationship_events",
            "seasons",
            "contextual_suggestions",
            "contextual_suggestion_dismissals",
            "insight_grace",
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
        _ = try? await client
            .rpc(
                "refresh_contextual_suggestions",
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
            // `member_slot` is the database's stable A/B contract. Postgres
            // row order is otherwise undefined, so leaving this implicit can
            // swap sides between launches and persist the viewer's work under
            // their partner.
            .order("member_slot", ascending: true)
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
            .eq("profile_id", value: user.id)
            .execute()
            .value
        async let sharedDirectionsRequest: [SharedDirectionDTO] = client
            .from("shared_directions")
            .select(
                "insight_id,couple_id,direction_key,eyebrow,title,message,symbol,created_at"
            )
            .eq("couple_id", value: membership.coupleID)
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
        async let graceRequest: [DeclineGraceDTO] = client
            .from("insight_grace")
            .select(
                "insight_id,profile_id,decline_count,suppress_until"
            )
            .eq("profile_id", value: user.id)
            .execute()
            .value
        async let partnerAnswerStatusesRequest:
            [PartnerAnswerStatusDTO] = client
            .rpc("partner_answer_statuses")
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
            .select(
                "id,couple_id,title,note,owner_id,scheduled_on,related_plan_id,suggestion_provenance,status,completed_at,created_by,updated_by,created_at,updated_at"
            )
            .eq("couple_id", value: membership.coupleID)
            .order("created_at", ascending: true)
            .execute()
            .value
        async let presenceRequest: [PresenceDTO] = client
            .from("relationship_presence")
            .select("couple_id,mode,changed_by,changed_at")
            .eq("couple_id", value: membership.coupleID)
            .limit(1)
            .execute()
            .value
        async let signalConsentsRequest: [SignalConsentDTO] = client
            .from("signal_consents")
            .select("couple_id,profile_id,signal,enabled,updated_at")
            .eq("profile_id", value: user.id)
            .execute()
            .value
        async let anchorsRequest: [AnchorDTO] = client
            .from("anchors")
            .select(
                "id,couple_id,title,note,cadence,is_active,created_by,created_at,updated_at"
            )
            .eq("couple_id", value: membership.coupleID)
            .order("created_at", ascending: true)
            .execute()
            .value
        async let handoffsRequest: [HandoffDTO] = client
            .from("responsibility_handoffs")
            .select(
                "id,responsibility_id,couple_id,from_profile_id,to_profile_id,status,created_at,responded_at"
            )
            .eq("couple_id", value: membership.coupleID)
            .order("created_at", ascending: false)
            .execute()
            .value
        async let approachesRequest: [ApproachDTO] = client
            .from("plan_approaches")
            .select(
                "id,plan_id,profile_id,approach,note,created_at"
            )
            .eq("couple_id", value: membership.coupleID)
            .eq("profile_id", value: user.id)
            .execute()
            .value
        async let eventsRequest: [RelationshipEventDTO] = client
            .from("relationship_events")
            .select(
                "id,couple_id,event_type,source_id,title,occurred_at,provenance"
            )
            .eq("couple_id", value: membership.coupleID)
            .order("occurred_at", ascending: true)
            .execute()
            .value
        async let seasonsRequest: [SeasonDTO] = client
            .from("seasons")
            .select(
                "id,couple_id,sequence,starts_at,cutoff_at,title,summary,event_ids,provenance,created_at"
            )
            .eq("couple_id", value: membership.coupleID)
            .order("sequence", ascending: true)
            .execute()
            .value
        async let suggestionsRequest: [ContextualSuggestionDTO] = client
            .from("contextual_suggestions")
            .select(
                "id,couple_id,kind,related_plan_id,title,proposed_responsibility_title,proposed_scheduled_on,evidence,provenance,created_at,is_eligible,confirmed_responsibility_id"
            )
            .eq("couple_id", value: membership.coupleID)
            .eq("is_eligible", value: true)
            .is("confirmed_responsibility_id", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
        async let suggestionDismissalsRequest:
            [ContextualSuggestionDismissalDTO] = client
            .from("contextual_suggestion_dismissals")
            .select("suggestion_id")
            .eq("profile_id", value: user.id)
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

        let (
            presenceDTOs,
            signalConsentDTOs,
            anchorDTOs,
            handoffDTOs,
            approachDTOs,
            eventDTOs,
            seasonDTOs,
            suggestionDTOs,
            suggestionDismissalDTOs
        ) = try await (
            presenceRequest,
            signalConsentsRequest,
            anchorsRequest,
            handoffsRequest,
            approachesRequest,
            eventsRequest,
            seasonsRequest,
            suggestionsRequest,
            suggestionDismissalsRequest
        )
        let graceDTOs = try await graceRequest
        let partnerAnswerStatusDTOs =
            try await partnerAnswerStatusesRequest
        let sharedDirectionDTOs = try await sharedDirectionsRequest

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
        var responsesByInsight = try Dictionary(
            grouping: responseDTOs.map(response),
            by: \.insightID
        )
        let sharedDirectionsByInsight = Dictionary(
            uniqueKeysWithValues: sharedDirectionDTOs.map {
                ($0.insightID, sharedDirection($0))
            }
        )
        for status in partnerAnswerStatusDTOs where status.hasAnswered {
            guard !responsesByInsight[
                status.insightID,
                default: []
            ].contains(where: { $0.profileID == status.profileID })
            else { continue }
            responsesByInsight[status.insightID, default: []].append(
                InsightResponse(
                    insightID: status.insightID,
                    profileID: status.profileID,
                    status: .submitted,
                    choice: nil,
                    note: nil
                )
            )
        }
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
                sharedDirection: sharedDirectionsByInsight[value.id],
                dismissedBy: Set(
                    dismissalsByInsight[value.id, default: []].map(\.profileID)
                ),
                declinedBy: Set(
                    declinesByInsight[value.id, default: []].map(\.profileID)
                )
            )
        }
        let dismissedSuggestionIDs = Set(
            suggestionDismissalDTOs.map(\.suggestionID)
        )

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
            syncedAt: Date(),
            v2: V2RelationshipState(
                presence: try presenceDTOs.first.map(presence),
                signalConsents: try signalConsentDTOs.map(signalConsent),
                anchors: try anchorDTOs.map(anchor),
                handoffs: try handoffDTOs.map(handoff),
                approaches: try approachDTOs.map(approach),
                events: try eventDTOs.map(relationshipEvent),
                seasons: seasonDTOs.map(season),
                suggestions: try suggestionDTOs.map {
                    try contextualSuggestion(
                        $0,
                        dismissed: dismissedSuggestionIDs.contains($0.id)
                    )
                },
                declineGrace: graceDTOs.map(declineGrace)
            )
        )
    }

    /// The session lives in the Keychain, which the system does not remove
    /// when the app is deleted.
    var persistsCredentialsAcrossInstalls: Bool { true }

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
            // Postgres renders UUIDs lowercase; Swift's uuidString is
            // uppercase. Match Postgres so ID comparisons hold.
            id: user.id.uuidString.lowercased(),
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
            status: status == .revealed ? .submitted : status,
            choice: dto.choice,
            note: dto.note
        )
    }

    private func sharedDirection(
        _ dto: SharedDirectionDTO
    ) -> SharedDirection {
        SharedDirection(
            insightID: dto.insightID,
            key: dto.key,
            eyebrow: dto.eyebrow,
            title: dto.title,
            message: dto.message,
            symbol: dto.symbol,
            createdAt: dto.createdAt
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
            scheduledOn: dto.scheduledOn,
            relatedPlanID: dto.relatedPlanID,
            suggestionProvenance: dto.suggestionProvenance,
            status: sharedStatus(dto.status),
            completedAt: dto.completedAt,
            createdBy: dto.createdBy,
            updatedBy: dto.updatedBy,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    private func presence(
        _ dto: PresenceDTO
    ) throws -> RelationshipPresence {
        guard let mode = PresenceMode(rawValue: dto.mode) else {
            throw RepositoryError.invalidData("unknown presence mode")
        }
        return RelationshipPresence(
            coupleID: dto.coupleID,
            mode: mode,
            changedBy: dto.changedBy,
            changedAt: dto.changedAt
        )
    }

    private func signalConsent(
        _ dto: SignalConsentDTO
    ) throws -> SignalConsent {
        guard let signal = SignalKind(rawValue: dto.signal) else {
            throw RepositoryError.invalidData("unknown intelligence signal")
        }
        return SignalConsent(
            coupleID: dto.coupleID,
            profileID: dto.profileID,
            signal: signal,
            isEnabled: dto.enabled,
            updatedAt: dto.updatedAt
        )
    }

    private func anchor(_ dto: AnchorDTO) throws -> Anchor {
        guard let cadence = AnchorCadence(rawValue: dto.cadence) else {
            throw RepositoryError.invalidData("unknown anchor cadence")
        }
        return Anchor(
            id: dto.id,
            coupleID: dto.coupleID,
            title: dto.title,
            note: dto.note,
            cadence: cadence,
            isActive: dto.isActive,
            createdBy: dto.createdBy,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    private func handoff(
        _ dto: HandoffDTO
    ) throws -> ResponsibilityHandoff {
        guard let status = HandoffStatus(rawValue: dto.status) else {
            throw RepositoryError.invalidData("unknown handoff status")
        }
        return ResponsibilityHandoff(
            id: dto.id,
            responsibilityID: dto.responsibilityID,
            coupleID: dto.coupleID,
            fromProfileID: dto.fromProfileID,
            toProfileID: dto.toProfileID,
            status: status,
            createdAt: dto.createdAt,
            respondedAt: dto.respondedAt
        )
    }

    private func approach(_ dto: ApproachDTO) throws -> PlanApproach {
        guard let value = ApproachKind(rawValue: dto.approach) else {
            throw RepositoryError.invalidData("unknown plan approach")
        }
        return PlanApproach(
            id: dto.id,
            planID: dto.planID,
            profileID: dto.profileID,
            approach: value,
            note: dto.note,
            createdAt: dto.createdAt
        )
    }

    private func relationshipEvent(
        _ dto: RelationshipEventDTO
    ) throws -> RelationshipEvent {
        guard let type = RelationshipEventType(rawValue: dto.type) else {
            throw RepositoryError.invalidData("unknown relationship event")
        }
        return RelationshipEvent(
            id: dto.id,
            coupleID: dto.coupleID,
            type: type,
            sourceID: dto.sourceID,
            title: dto.title,
            occurredAt: dto.occurredAt,
            provenance: dto.provenance
        )
    }

    private func season(_ dto: SeasonDTO) -> Season {
        Season(
            id: dto.id,
            coupleID: dto.coupleID,
            sequence: dto.sequence,
            startsAt: dto.startsAt,
            cutoffAt: dto.cutoffAt,
            title: dto.title,
            summary: dto.summary,
            eventIDs: dto.eventIDs,
            provenance: dto.provenance,
            createdAt: dto.createdAt
        )
    }

    private func contextualSuggestion(
        _ dto: ContextualSuggestionDTO,
        dismissed: Bool
    ) throws -> ContextualSuggestion {
        guard let kind = SuggestionKind(rawValue: dto.kind) else {
            throw RepositoryError.invalidData("unknown suggestion kind")
        }
        return ContextualSuggestion(
            id: dto.id,
            coupleID: dto.coupleID,
            kind: kind,
            relatedPlanID: dto.relatedPlanID,
            title: dto.title,
            proposedResponsibilityTitle:
                dto.proposedResponsibilityTitle,
            proposedScheduledOn: dto.proposedScheduledOn,
            evidence: dto.evidence,
            provenance: dto.provenance,
            createdAt: dto.createdAt,
            confirmedResponsibilityID: dto.confirmedResponsibilityID,
            dismissedForViewer: dismissed
        )
    }

    private func declineGrace(_ dto: DeclineGraceDTO) -> DeclineGrace {
        DeclineGrace(
            insightID: dto.insightID,
            profileID: dto.profileID,
            declineCount: dto.declineCount,
            suppressUntil: dto.suppressUntil
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
