import Foundation

actor PreviewRepository: Repository {
    nonisolated let isConfigured = true

    private var currentUser: AuthenticatedUser?
    private var snapshot: RelationshipSnapshot
    private let scenario: PreviewScenario
    private let waitingSnapshot: RelationshipSnapshot
    private let choosingHueSnapshot: RelationshipSnapshot
    private let configuredSignUpResult: SignUpResult?
    private let acceptedDeletionPassword: String?

    init(
        scenario: PreviewScenario = .ready,
        user: AuthenticatedUser? = nil,
        signUpResult: SignUpResult? = nil,
        acceptedDeletionPassword: String? = nil
    ) {
        self.scenario = scenario
        configuredSignUpResult = signUpResult
        self.acceptedDeletionPassword = acceptedDeletionPassword
        waitingSnapshot = PreviewData.waitingSnapshot
        choosingHueSnapshot = PreviewData.choosingHueSnapshot
        currentUser = if scenario == .signedOut {
            nil
        } else if let user {
            user
        } else if scenario == .error {
            PreviewData.errorUser
        } else {
            PreviewData.user
        }
        snapshot = switch scenario {
        case .ready, .offline, .error: PreviewData.snapshot
        case .empty: PreviewData.emptySnapshot
        case .waiting: PreviewData.waitingSnapshot
        case .archived, .signedOut: PreviewData.archivedSnapshot
        case .choosingHue: PreviewData.choosingHueSnapshot
        }
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        currentUser
    }

    func signUp(
        name: String,
        email: String,
        password: String
    ) async throws -> SignUpResult {
        if let configuredSignUpResult {
            if case .signedIn(let user) = configuredSignUpResult {
                currentUser = user
            }
            return configuredSignUpResult
        }
        let user = AuthenticatedUser(id: "preview-user", email: email)
        currentUser = user
        return .signedIn(user)
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        let user = AuthenticatedUser(id: "ryan", email: "ryan@example.com")
        currentUser = user
        return user
    }

    func sendPasswordReset(email: String) async throws {}
    func handleAuthCallback(_ url: URL) async throws -> AuthCallbackResult {
        let user = AuthenticatedUser(
            id: currentUser?.id ?? PreviewData.user.id,
            email: currentUser?.email ?? PreviewData.user.email
        )
        currentUser = user
        return url.host == "password-recovery"
            ? .passwordRecovery(user)
            : .emailConfirmed(user)
    }
    func updatePassword(_ password: String) async throws {}
    func signOut() async throws { currentUser = nil }
    func deleteAccount(email: String, password: String) async throws {
        if let acceptedDeletionPassword,
           password != acceptedDeletionPassword {
            throw RepositoryError.invalidData("invalid password")
        }
        currentUser = nil
    }

    func loadRelationship(
        for user: AuthenticatedUser
    ) async throws -> RelationshipSnapshot {
        if scenario == .error {
            throw RepositoryError.invalidData("preview failure")
        }
        return snapshot
    }

    func relationshipChanges() async throws
        -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { _ in }
    }

    func createCouple() async throws {
        snapshot = waitingSnapshot
    }

    func joinCouple(code: String) async throws {
        snapshot = choosingHueSnapshot
    }

    func updateProfile(name: String, userID: String) async throws {
        snapshot = replacing(profile: Profile(id: userID, name: name))
    }

    func updateHue(
        _ hue: MemberHue,
        membership: Membership
    ) async throws {
        let updated = Membership(
            coupleID: membership.coupleID,
            profileID: membership.profileID,
            hue: hue,
            hueChosenAt: ISO8601DateFormatter().string(from: Date())
        )
        snapshot = replacing(membership: updated)
    }

    func createPlan(_ input: PlanInput, coupleID: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let value = PlanItem(
            id: UUID().uuidString,
            coupleID: coupleID,
            title: input.title,
            note: input.note,
            scheduledOn: input.scheduledOn,
            status: .active,
            completedAt: nil,
            createdBy: currentUser?.id,
            updatedBy: currentUser?.id,
            createdAt: now,
            updatedAt: now
        )
        snapshot = replacing(plans: snapshot.plans + [value])
    }

    func updatePlan(id: String, input: PlanInput) async throws {
        snapshot = replacing(plans: snapshot.plans.map { value in
            guard value.id == id else { return value }
            return PlanItem(
                id: value.id,
                coupleID: value.coupleID,
                title: input.title,
                note: input.note,
                scheduledOn: input.scheduledOn,
                status: value.status,
                completedAt: value.completedAt,
                createdBy: value.createdBy,
                updatedBy: currentUser?.id,
                createdAt: value.createdAt,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
        })
    }

    func setPlanStatus(
        id: String,
        status: SharedItemStatus
    ) async throws {
        snapshot = replacing(plans: snapshot.plans.map { value in
            guard value.id == id else { return value }
            return PlanItem(
                id: value.id,
                coupleID: value.coupleID,
                title: value.title,
                note: value.note,
                scheduledOn: value.scheduledOn,
                status: status,
                completedAt: status == .completed
                    ? ISO8601DateFormatter().string(from: Date()) : nil,
                createdBy: value.createdBy,
                updatedBy: currentUser?.id,
                createdAt: value.createdAt,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
        })
    }

    func createResponsibility(
        _ input: ResponsibilityInput,
        coupleID: String,
        ownerID: String?
    ) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let value = Responsibility(
            id: UUID().uuidString,
            coupleID: coupleID,
            title: input.title,
            note: input.note,
            ownerID: ownerID,
            owner: input.owner,
            scheduledOn: input.scheduledOn,
            relatedPlanID: input.relatedPlanID,
            suggestionProvenance: input.suggestionProvenance,
            status: .active,
            completedAt: nil,
            createdBy: currentUser?.id,
            updatedBy: currentUser?.id,
            createdAt: now,
            updatedAt: now
        )
        snapshot = replacing(
            responsibilities: snapshot.responsibilities + [value]
        )
    }

    func updateResponsibility(
        id: String,
        input: ResponsibilityInput,
        ownerID: String?
    ) async throws {
        snapshot = replacing(
            responsibilities: snapshot.responsibilities.map { value in
                guard value.id == id else { return value }
                return Responsibility(
                    id: value.id,
                    coupleID: value.coupleID,
                    title: input.title,
                    note: input.note,
                    ownerID: ownerID,
                    owner: input.owner,
                    scheduledOn: input.scheduledOn,
                    relatedPlanID: input.relatedPlanID,
                    suggestionProvenance: input.suggestionProvenance,
                    status: value.status,
                    completedAt: value.completedAt,
                    createdBy: value.createdBy,
                    updatedBy: currentUser?.id,
                    createdAt: value.createdAt,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            }
        )
    }

    func setResponsibilityStatus(
        id: String,
        status: SharedItemStatus
    ) async throws {
        snapshot = replacing(
            responsibilities: snapshot.responsibilities.map { value in
                guard value.id == id else { return value }
                return Responsibility(
                    id: value.id,
                    coupleID: value.coupleID,
                    title: value.title,
                    note: value.note,
                    ownerID: value.ownerID,
                    owner: value.owner,
                    scheduledOn: value.scheduledOn,
                    relatedPlanID: value.relatedPlanID,
                    suggestionProvenance: value.suggestionProvenance,
                    status: status,
                    completedAt: status == .completed
                        ? ISO8601DateFormatter().string(from: Date()) : nil,
                    createdBy: value.createdBy,
                    updatedBy: currentUser?.id,
                    createdAt: value.createdAt,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            }
        )
    }

    func saveReflection(
        text: String,
        domain: InsightDomain,
        coupleID: String,
        ownerID: String
    ) async throws {
        let value = Reflection(
            id: UUID().uuidString,
            coupleID: coupleID,
            ownerID: ownerID,
            domain: domain,
            kind: .reflection,
            text: text
        )
        snapshot = replacing(reflections: snapshot.reflections + [value])
    }

    func requestReveal(insightID: String) async throws {
        try updateInsight(insightID) { state, userID in
            try TrustCore.requestReveal(
                state,
                by: userID,
                at: Self.now
            )
        }
    }

    func acceptReveal(insightID: String) async throws {
        try updateInsight(insightID) { state, userID in
            try TrustCore.acceptReveal(
                state,
                by: userID,
                at: Self.now
            )
        }
    }

    func declineReveal(insightID: String) async throws {
        try updateInsight(insightID) { state, userID in
            try TrustCore.declineReveal(state, by: userID)
        }
    }

    func withdrawReveal(insightID: String) async throws {
        try updateInsight(insightID) { state, userID in
            try TrustCore.withdrawReveal(state, by: userID)
        }
    }

    func submitResponse(
        insightID: String,
        choice: String,
        note: String?
    ) async throws {
        try updateInsight(insightID) { state, userID in
            try TrustCore.submitResponse(
                state,
                by: userID,
                choice: choice,
                note: note
            )
        }
    }

    func resolveInsight(
        insightID: String,
        type: ResolutionType,
        choice: String?
    ) async throws {
        try updateInsight(insightID) { state, _ in
            try TrustCore.resolve(
                state,
                type: type,
                at: Self.now,
                choice: choice
            )
        }
    }

    func dismissSuggestion(insightID: String) async throws {
        try updateInsight(insightID) { state, userID in
            try TrustCore.dismissSuggestion(state, by: userID)
        }
    }

    func setPresence(_ mode: PresenceMode) async throws {
        let current = snapshot.v2State
        snapshot = replacing(
            v2: replacingV2(
                current,
                presence: RelationshipPresence(
                    coupleID: snapshot.couple?.id ?? "preview-couple",
                    mode: mode,
                    changedBy: currentUser?.id,
                    changedAt: ISO8601DateFormatter.we.string(from: Date())
                )
            )
        )
    }

    func setSignalConsent(
        _ signal: SignalKind,
        enabled: Bool
    ) async throws {
        guard !signal.isPermanentlyDisabled,
              let userID = currentUser?.id else { return }
        let current = snapshot.v2State
        var values = current.signalConsents.filter {
            !($0.profileID == userID && $0.signal == signal)
        }
        values.append(
            SignalConsent(
                coupleID: snapshot.couple?.id ?? "preview-couple",
                profileID: userID,
                signal: signal,
                isEnabled: enabled,
                updatedAt: ISO8601DateFormatter.we.string(from: Date())
            )
        )
        snapshot = replacing(
            v2: replacingV2(current, signalConsents: values)
        )
    }

    func createAnchor(
        _ input: AnchorInput,
        coupleID: String
    ) async throws {
        let current = snapshot.v2State
        let now = ISO8601DateFormatter.we.string(from: Date())
        snapshot = replacing(
            v2: replacingV2(
                current,
                anchors: current.anchors + [
                    Anchor(
                        id: UUID().uuidString,
                        coupleID: coupleID,
                        title: input.title,
                        note: input.note,
                        cadence: input.cadence,
                        isActive: true,
                        createdBy: currentUser?.id,
                        createdAt: now,
                        updatedAt: now
                    ),
                ]
            )
        )
    }

    func setAnchorActive(id: String, isActive: Bool) async throws {
        let current = snapshot.v2State
        snapshot = replacing(
            v2: replacingV2(
                current,
                anchors: current.anchors.map { value in
                    guard value.id == id else { return value }
                    return Anchor(
                        id: value.id,
                        coupleID: value.coupleID,
                        title: value.title,
                        note: value.note,
                        cadence: value.cadence,
                        isActive: isActive,
                        createdBy: value.createdBy,
                        createdAt: value.createdAt,
                        updatedAt: ISO8601DateFormatter.we.string(
                            from: Date()
                        )
                    )
                }
            )
        )
    }

    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?
    ) async throws {
        guard let userID = currentUser?.id else { return }
        let current = snapshot.v2State
        var values = current.approaches.filter {
            !($0.planID == planID && $0.profileID == userID)
        }
        values.append(
            PlanApproach(
                id: "\(planID)-\(userID)",
                planID: planID,
                profileID: userID,
                approach: approach,
                note: note,
                revealedAt: nil,
                createdAt: ISO8601DateFormatter.we.string(from: Date())
            )
        )
        if values.filter({ $0.planID == planID }).count == 2 {
            let revealedAt = ISO8601DateFormatter.we.string(from: Date())
            values = values.map { value in
                guard value.planID == planID else { return value }
                return PlanApproach(
                    id: value.id,
                    planID: value.planID,
                    profileID: value.profileID,
                    approach: value.approach,
                    note: value.note,
                    revealedAt: value.revealedAt ?? revealedAt,
                    createdAt: value.createdAt
                )
            }
        }
        snapshot = replacing(v2: replacingV2(current, approaches: values))
    }

    func refreshContextualSuggestions(localDate: String) async throws {
        let current = snapshot.v2State
        snapshot = replacing(
            v2: replacingV2(
                current,
                suggestions: ContextualSuggestionEngine.partyGroceries(
                    plans: snapshot.plans,
                    responsibilities: snapshot.responsibilities
                )
            )
        )
    }

    func dismissContextualSuggestion(id: String) async throws {
        let current = snapshot.v2State
        let suggestions = availableSuggestions.map { value in
            guard value.id == id else { return value }
            return ContextualSuggestion(
                id: value.id,
                coupleID: value.coupleID,
                kind: value.kind,
                relatedPlanID: value.relatedPlanID,
                title: value.title,
                proposedResponsibilityTitle:
                    value.proposedResponsibilityTitle,
                proposedScheduledOn: value.proposedScheduledOn,
                evidence: value.evidence,
                provenance: value.provenance,
                createdAt: value.createdAt,
                confirmedResponsibilityID:
                    value.confirmedResponsibilityID,
                dismissedForViewer: true
            )
        }
        snapshot = replacing(
            v2: replacingV2(current, suggestions: suggestions)
        )
    }

    func confirmContextualSuggestion(
        _ confirmation: SuggestionConfirmation
    ) async throws {
        guard let suggestion = availableSuggestions.first(
            where: { $0.id == confirmation.suggestionID }
        ) else {
            throw RepositoryError.invalidData("suggestion is no longer available")
        }
        try await createResponsibility(
            ResponsibilityInput(
                title: confirmation.title,
                note: confirmation.note,
                owner: confirmation.owner,
                scheduledOn: confirmation.scheduledOn,
                relatedPlanID: suggestion.relatedPlanID,
                suggestionProvenance: suggestion.provenance
            ),
            coupleID: suggestion.coupleID,
            ownerID: confirmation.owner == .me ? currentUser?.id : nil
        )
        snapshot = replacing(
            v2: replacingV2(snapshot.v2State, suggestions: [])
        )
    }

    func offerHandoff(
        responsibilityID: String,
        toProfileID: String
    ) async throws {
        guard let userID = currentUser?.id else { return }
        let current = snapshot.v2State
        snapshot = replacing(
            v2: replacingV2(
                current,
                handoffs: current.handoffs + [
                    ResponsibilityHandoff(
                        id: UUID().uuidString,
                        responsibilityID: responsibilityID,
                        coupleID: snapshot.couple?.id ?? "preview-couple",
                        fromProfileID: userID,
                        toProfileID: toProfileID,
                        status: .offered,
                        createdAt: ISO8601DateFormatter.we.string(
                            from: Date()
                        ),
                        respondedAt: nil
                    ),
                ]
            )
        )
    }

    func respondToHandoff(id: String, accept: Bool) async throws {
        let current = snapshot.v2State
        snapshot = replacing(
            v2: replacingV2(
                current,
                handoffs: current.handoffs.map { value in
                    guard value.id == id else { return value }
                    return ResponsibilityHandoff(
                        id: value.id,
                        responsibilityID: value.responsibilityID,
                        coupleID: value.coupleID,
                        fromProfileID: value.fromProfileID,
                        toProfileID: value.toProfileID,
                        status: accept ? .accepted : .declined,
                        createdAt: value.createdAt,
                        respondedAt: ISO8601DateFormatter.we.string(
                            from: Date()
                        )
                    )
                }
            )
        )
    }

    func withdrawHandoff(id: String) async throws {
        let current = snapshot.v2State
        snapshot = replacing(
            v2: replacingV2(
                current,
                handoffs: current.handoffs.map { value in
                    guard value.id == id else { return value }
                    return ResponsibilityHandoff(
                        id: value.id,
                        responsibilityID: value.responsibilityID,
                        coupleID: value.coupleID,
                        fromProfileID: value.fromProfileID,
                        toProfileID: value.toProfileID,
                        status: .withdrawn,
                        createdAt: value.createdAt,
                        respondedAt: ISO8601DateFormatter.we.string(
                            from: Date()
                        )
                    )
                }
            )
        )
    }

    func createReadySeason() async throws {
        let current = snapshot.v2State
        let cutoff = current.seasons.last.flatMap {
            ISO8601DateFormatter.we.date(from: $0.cutoffAt)
        }
        guard case .ready(let eventIDs, let cutoffAt) =
            SeasonReadiness.evaluate(
                events: current.events,
                after: cutoff,
                now: Date()
            )
        else {
            throw RepositoryError.invalidData("a season is not ready")
        }
        let eligible = current.events.filter { eventIDs.contains($0.id) }
        let season = Season(
            id: UUID().uuidString,
            coupleID: snapshot.couple?.id ?? "preview-couple",
            sequence: current.seasons.count + 1,
            startsAt: eligible.map(\.occurredAt).min() ?? cutoffAt,
            cutoffAt: cutoffAt,
            title: "A season of showing up",
            summary: "\(eligible.count) shared moments formed this season.",
            eventIDs: eventIDs,
            provenance: eligible.flatMap(\.provenance),
            createdAt: ISO8601DateFormatter.we.string(from: Date())
        )
        snapshot = replacing(
            v2: replacingV2(
                current,
                seasons: current.seasons + [season]
            )
        )
    }

    private func updateInsight(
        _ insightID: String,
        transform: (TrustState, String) throws -> TrustState
    ) throws {
        guard let userID = currentUser?.id else {
            throw RepositoryError.invalidData("preview user is signed out")
        }
        guard let index = snapshot.insights.firstIndex(
            where: { $0.id == insightID }
        ) else {
            throw RepositoryError.invalidData("preview insight is missing")
        }

        let current = snapshot.insights[index]
        let memberIDs = snapshot.members.map(\.id)
        let next = try transform(
            current.trustState(memberIDs: memberIDs),
            userID
        )
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let consent = InsightConsent(
            insightID: insightID,
            visibility: next.visibility,
            ownerID: next.ownerID,
            readiness: next.readiness,
            initiatorID: next.initiatorID,
            requestedAt: next.requestedAt == nil ? nil : timestamp,
            acceptedAt: next.acceptedAt == nil ? nil : timestamp,
            resolutionType: next.resolution?.type,
            resolutionChoice: next.resolution?.choice
        )
        let responses = next.responses.map { profileID, response in
            InsightResponse(
                insightID: insightID,
                profileID: profileID,
                status: response.status,
                choice: response.choice,
                note: response.note
            )
        }
        var insights = snapshot.insights
        insights[index] = InsightRecord(
            insight: current.insight,
            consent: consent,
            responses: responses,
            dismissedBy: next.dismissedBy,
            declinedBy: next.declinedBy
        )
        snapshot = replacing(insights: insights)
    }

    nonisolated private static var now: Int {
        Int(Date().timeIntervalSince1970)
    }

    private func replacing(
        profile: Profile? = nil,
        membership: Membership? = nil,
        insights: [InsightRecord]? = nil,
        reflections: [Reflection]? = nil,
        plans: [PlanItem]? = nil,
        responsibilities: [Responsibility]? = nil,
        v2: V2RelationshipState? = nil
    ) -> RelationshipSnapshot {
        RelationshipSnapshot(
            profile: profile ?? snapshot.profile,
            membership: membership ?? snapshot.membership,
            couple: snapshot.couple,
            members: snapshot.members,
            insights: insights ?? snapshot.insights,
            reflections: reflections ?? snapshot.reflections,
            plans: plans ?? snapshot.plans,
            responsibilities: responsibilities ?? snapshot.responsibilities,
            archives: snapshot.archives,
            syncedAt: Date(),
            v2: v2 ?? snapshot.v2
        )
    }

    private var availableSuggestions: [ContextualSuggestion] {
        let persisted = snapshot.v2State.suggestions
        return persisted.isEmpty
            ? ContextualSuggestionEngine.partyGroceries(
                plans: snapshot.plans,
                responsibilities: snapshot.responsibilities
            )
            : persisted
    }

    private func replacingV2(
        _ current: V2RelationshipState,
        presence: RelationshipPresence? = nil,
        signalConsents: [SignalConsent]? = nil,
        anchors: [Anchor]? = nil,
        handoffs: [ResponsibilityHandoff]? = nil,
        approaches: [PlanApproach]? = nil,
        events: [RelationshipEvent]? = nil,
        seasons: [Season]? = nil,
        suggestions: [ContextualSuggestion]? = nil
    ) -> V2RelationshipState {
        V2RelationshipState(
            presence: presence ?? current.presence,
            signalConsents: signalConsents ?? current.signalConsents,
            anchors: anchors ?? current.anchors,
            handoffs: handoffs ?? current.handoffs,
            approaches: approaches ?? current.approaches,
            events: events ?? current.events,
            seasons: seasons ?? current.seasons,
            suggestions: suggestions ?? current.suggestions,
            declineGrace: current.declineGrace
        )
    }
}
