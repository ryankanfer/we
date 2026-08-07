import Combine
import Foundation

@MainActor
final class SessionHost: ObservableObject {
    static let simulationEmail = "kanfer.ryan@gmail.com"

    @Published private(set) var session: AppSession {
        didSet { observeSession() }
    }
    @Published private(set) var mode: AppMode = .actual
    @Published private(set) var viewer: SimulationViewer = .ryan

    private let environment: AppEnvironment
    private let simulationStore: SimulationStore

    /// Forwards the session's own changes as changes to the host.
    ///
    /// `@Published var session` only fires when the *reference* is replaced,
    /// never when `session.state` changes inside it — so any view observing
    /// `SessionHost` and reading `session.state` would never re-render.
    /// `WEApp` is exactly that view, and the consequences were invisible
    /// rather than obviously broken: signing out left the zones on screen,
    /// and the Living Confluence Promise never appeared at all, because the
    /// switch that chooses between them was evaluated once and never again.
    private var sessionObserver: AnyCancellable?

    private func observeSession() {
        sessionObserver = session.objectWillChange.sink {
            [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    convenience init() {
        self.init(environment: .current)
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        let store = SimulationStore()
        simulationStore = store

        let startsInSimulation =
            ProcessInfo.processInfo.environment[
                "WE_START_SIMULATION"
            ] == "1"
        if startsInSimulation,
           environment.repositoryMode == .preview {
            mode = .simulation
            session = Self.makeSimulationSession(
                store: store,
                viewer: .ryan
            )
        } else {
            session = Self.makeActualSession(environment: environment)
        }

        // `didSet` does not fire for assignments made during init, so the
        // first session has to be subscribed to by hand.
        observeSession()
    }

    var canUseSimulation: Bool {
        if mode == .simulation {
            return true
        }
        return session.user?.email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == Self.simulationEmail
            || environment.repositoryMode == .preview
    }

    func restore() async {
        await session.restoreIfNeeded()
    }

    func setMode(_ newMode: AppMode) async {
        guard newMode != mode else { return }
        if newMode == .simulation, !canUseSimulation { return }

        session.suspend()
        mode = newMode
        session = if newMode == .actual {
            Self.makeActualSession(environment: environment)
        } else {
            Self.makeSimulationSession(
                store: simulationStore,
                viewer: viewer
            )
        }
        await session.restoreIfNeeded()
    }

    func setViewer(_ newViewer: SimulationViewer) async {
        guard mode == .simulation, newViewer != viewer else { return }
        session.suspend()
        viewer = newViewer
        session = Self.makeSimulationSession(
            store: simulationStore,
            viewer: newViewer
        )
        await session.restoreIfNeeded()
    }

    func resetSimulation() async {
        guard mode == .simulation else { return }
        await simulationStore.reset()
        session.suspend()
        session = Self.makeSimulationSession(
            store: simulationStore,
            viewer: viewer
        )
        await session.restoreIfNeeded()
    }

    private static func makeActualSession(
        environment: AppEnvironment
    ) -> AppSession {
        let isOfflinePreview = environment.repositoryMode == .preview
            && environment.previewScenario == .offline
        return AppSession(
            repository: RepositoryFactory.make(environment: environment),
            connectivity: ConnectivityMonitor(
                startImmediately: !isOfflinePreview,
                initiallyOnline: !isOfflinePreview
            )
        )
    }

    private static func makeSimulationSession(
        store: SimulationStore,
        viewer: SimulationViewer
    ) -> AppSession {
        AppSession(
            repository: SimulationRepository(
                store: store,
                viewer: viewer
            ),
            cache: InMemoryRelationshipCache(),
            connectivity: ConnectivityMonitor(
                startImmediately: false,
                initiallyOnline: true
            )
        )
    }
}

actor SimulationStore {
    private var snapshot = SimulationStore.seed()
    private var dismissedSuggestionIDs: [
        SimulationViewer: Set<String>
    ] = [:]

    func reset() {
        snapshot = Self.seed()
        dismissedSuggestionIDs = [:]
    }

    func load(viewer: SimulationViewer) -> RelationshipSnapshot {
        let profile = snapshot.members.first {
            $0.id == viewer.userID
        }.map {
            Profile(id: $0.id, name: $0.name)
        } ?? Profile(id: viewer.userID, name: viewer.title)

        let membership = Membership(
            coupleID: snapshot.couple?.id ?? "simulation-couple",
            profileID: viewer.userID,
            hue: snapshot.members.first {
                $0.id == viewer.userID
            }?.hue ?? .burgundy,
            hueChosenAt: "2026-01-01T00:00:00Z"
        )

        let responsibilities = snapshot.responsibilities.map { value in
            Responsibility(
                id: value.id,
                coupleID: value.coupleID,
                title: value.title,
                note: value.note,
                ownerID: value.ownerID,
                owner: value.ownerID == nil
                    ? .together
                    : value.ownerID == viewer.userID ? .me : .partner,
                scheduledOn: value.scheduledOn,
                relatedPlanID: value.relatedPlanID,
                suggestionProvenance: value.suggestionProvenance,
                status: value.status,
                completedAt: value.completedAt,
                createdBy: value.createdBy,
                updatedBy: value.updatedBy,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
        }
        let insights = snapshot.insights.map { record in
            InsightRecord(
                insight: record.insight,
                consent: record.consent,
                responses: record.responses.map { response in
                    if response.profileID == viewer.userID {
                        return InsightResponse(
                            insightID: response.insightID,
                            profileID: response.profileID,
                            status: response.status == .revealed
                                ? .submitted : response.status,
                            choice: response.choice,
                            note: response.note
                        )
                    }
                    return InsightResponse(
                        insightID: response.insightID,
                        profileID: response.profileID,
                        status: response.status == .revealed
                            ? .submitted : response.status,
                        choice: nil,
                        note: nil
                    )
                },
                sharedDirection: record.sharedDirection,
                dismissedBy: record.dismissedBy.intersection(
                    [viewer.userID]
                ),
                declinedBy: record.declinedBy.intersection(
                    [viewer.userID]
                )
            )
        }

        let viewerDismissals = dismissedSuggestionIDs[viewer, default: []]
        let v2 = snapshot.v2State
        let viewerV2 = V2RelationshipState(
            presence: v2.presence,
            signalConsents: v2.signalConsents.filter {
                $0.profileID == viewer.userID
            },
            anchors: v2.anchors,
            handoffs: v2.handoffs,
            approaches: v2.approaches.filter {
                $0.profileID == viewer.userID
            },
            events: v2.events,
            seasons: v2.seasons,
            suggestions: v2.suggestions.map { value in
                ContextualSuggestion(
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
                    dismissedForViewer:
                        viewerDismissals.contains(value.id)
                )
            },
            declineGrace: v2.declineGrace.filter {
                $0.profileID == viewer.userID
            }
        )

        return RelationshipSnapshot(
            profile: profile,
            membership: membership,
            couple: snapshot.couple,
            members: snapshot.members,
            insights: insights,
            reflections: snapshot.reflections.filter {
                $0.ownerID == viewer.userID
            },
            plans: snapshot.plans,
            responsibilities: responsibilities,
            archives: [],
            syncedAt: Date(),
            v2: viewerV2
        )
    }

    func updateProfile(viewer: SimulationViewer, name: String) {
        let members = snapshot.members.map {
            $0.id == viewer.userID
                ? Member(id: $0.id, name: name, hue: $0.hue)
                : $0
        }
        replace(members: members)
    }

    func updateHue(viewer: SimulationViewer, hue: MemberHue) {
        let members = snapshot.members.map {
            $0.id == viewer.userID
                ? Member(id: $0.id, name: $0.name, hue: hue)
                : $0
        }
        replace(members: members)
    }

    func createPlan(
        _ input: PlanInput,
        viewer: SimulationViewer
    ) {
        let now = Self.timestamp
        let value = PlanItem(
            id: UUID().uuidString,
            coupleID: "simulation-couple",
            title: input.title,
            note: input.note,
            scheduledOn: input.scheduledOn,
            status: .active,
            completedAt: nil,
            createdBy: viewer.userID,
            updatedBy: viewer.userID,
            createdAt: now,
            updatedAt: now
        )
        replace(plans: snapshot.plans + [value])
        refreshSuggestions(viewer: viewer)
    }

    func updatePlan(
        id: String,
        input: PlanInput,
        viewer: SimulationViewer
    ) {
        replace(plans: snapshot.plans.map { value in
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
                updatedBy: viewer.userID,
                createdAt: value.createdAt,
                updatedAt: Self.timestamp
            )
        })
        refreshSuggestions(viewer: viewer)
    }

    func setPlanStatus(
        id: String,
        status: SharedItemStatus,
        viewer: SimulationViewer
    ) {
        let now = Self.timestamp
        var eventToAdd: RelationshipEvent?
        let plans = snapshot.plans.map { value in
            guard value.id == id else { return value }
            if status == .completed, value.status != .completed {
                eventToAdd = RelationshipEvent(
                    id: "plan-completed-\(id)",
                    coupleID: value.coupleID,
                    type: .planCompleted,
                    sourceID: id,
                    title: value.title,
                    occurredAt: now,
                    provenance: [
                        ProvenanceReference(
                            kind: .plan,
                            id: id,
                            label: value.title,
                            shared: true
                        ),
                    ]
                )
            }
            return PlanItem(
                id: value.id,
                coupleID: value.coupleID,
                title: value.title,
                note: value.note,
                scheduledOn: value.scheduledOn,
                status: status,
                completedAt: status == .completed ? now : nil,
                createdBy: value.createdBy,
                updatedBy: viewer.userID,
                createdAt: value.createdAt,
                updatedAt: now
            )
        }
        replace(
            plans: plans,
            events: eventToAdd.map {
                snapshot.v2State.events + [$0]
            }
        )
    }

    func createResponsibility(
        _ input: ResponsibilityInput,
        ownerID: String?,
        viewer: SimulationViewer
    ) {
        let now = Self.timestamp
        let value = Responsibility(
            id: UUID().uuidString,
            coupleID: "simulation-couple",
            title: input.title,
            note: input.note,
            ownerID: ownerID,
            owner: input.owner,
            scheduledOn: input.scheduledOn,
            relatedPlanID: input.relatedPlanID,
            suggestionProvenance: input.suggestionProvenance,
            status: .active,
            completedAt: nil,
            createdBy: viewer.userID,
            updatedBy: viewer.userID,
            createdAt: now,
            updatedAt: now
        )
        replace(responsibilities: snapshot.responsibilities + [value])
    }

    func updateResponsibility(
        id: String,
        input: ResponsibilityInput,
        ownerID: String?,
        viewer: SimulationViewer
    ) {
        replace(responsibilities: snapshot.responsibilities.map { value in
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
                updatedBy: viewer.userID,
                createdAt: value.createdAt,
                updatedAt: Self.timestamp
            )
        })
    }

    func setResponsibilityStatus(
        id: String,
        status: SharedItemStatus,
        viewer: SimulationViewer
    ) {
        let now = Self.timestamp
        var eventToAdd: RelationshipEvent?
        let responsibilities = snapshot.responsibilities.map { value in
            guard value.id == id else { return value }
            if status == .completed, value.status != .completed {
                eventToAdd = RelationshipEvent(
                    id: "responsibility-completed-\(id)",
                    coupleID: value.coupleID,
                    type: .responsibilityCompleted,
                    sourceID: id,
                    title: value.title,
                    occurredAt: now,
                    provenance: [
                        ProvenanceReference(
                            kind: .responsibility,
                            id: id,
                            label: value.title,
                            shared: true
                        ),
                    ]
                )
            }
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
                completedAt: status == .completed ? now : nil,
                createdBy: value.createdBy,
                updatedBy: viewer.userID,
                createdAt: value.createdAt,
                updatedAt: now
            )
        }
        replace(
            responsibilities: responsibilities,
            events: eventToAdd.map {
                snapshot.v2State.events + [$0]
            }
        )
    }

    func saveReflection(
        text: String,
        viewer: SimulationViewer
    ) {
        let value = Reflection(
            id: UUID().uuidString,
            coupleID: "simulation-couple",
            ownerID: viewer.userID,
            domain: .us,
            kind: .reflection,
            text: text
        )
        replace(reflections: snapshot.reflections + [value])
    }

    func setPresence(_ mode: PresenceMode, viewer: SimulationViewer) {
        replace(
            presence: RelationshipPresence(
                coupleID: "simulation-couple",
                mode: mode,
                changedBy: viewer.userID,
                changedAt: Self.timestamp
            )
        )
    }

    func setSignal(
        _ signal: SignalKind,
        enabled: Bool,
        viewer: SimulationViewer
    ) {
        guard !signal.isPermanentlyDisabled else { return }
        var values = snapshot.v2State.signalConsents.filter {
            !($0.profileID == viewer.userID && $0.signal == signal)
        }
        values.append(
            SignalConsent(
                coupleID: "simulation-couple",
                profileID: viewer.userID,
                signal: signal,
                isEnabled: enabled,
                updatedAt: Self.timestamp
            )
        )
        replace(signalConsents: values)
    }

    func createAnchor(_ input: AnchorInput, viewer: SimulationViewer) {
        let now = Self.timestamp
        replace(
            anchors: snapshot.v2State.anchors + [
                Anchor(
                    id: UUID().uuidString,
                    coupleID: "simulation-couple",
                    title: input.title,
                    note: input.note,
                    cadence: input.cadence,
                    isActive: true,
                    createdBy: viewer.userID,
                    createdAt: now,
                    updatedAt: now
                ),
            ]
        )
    }

    func setAnchorActive(id: String, isActive: Bool) {
        replace(anchors: snapshot.v2State.anchors.map { value in
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
                updatedAt: Self.timestamp
            )
        })
    }

    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?,
        viewer: SimulationViewer
    ) {
        var values = snapshot.v2State.approaches.filter {
            !($0.planID == planID && $0.profileID == viewer.userID)
        }
        values.append(
            PlanApproach(
                id: "\(planID)-\(viewer.userID)",
                planID: planID,
                profileID: viewer.userID,
                approach: approach,
                note: note,
                createdAt: Self.timestamp
            )
        )
        replace(approaches: values)
    }

    func offerHandoff(
        responsibilityID: String,
        toProfileID: String,
        viewer: SimulationViewer
    ) {
        replace(
            handoffs: snapshot.v2State.handoffs + [
                ResponsibilityHandoff(
                    id: UUID().uuidString,
                    responsibilityID: responsibilityID,
                    coupleID: "simulation-couple",
                    fromProfileID: viewer.userID,
                    toProfileID: toProfileID,
                    status: .offered,
                    createdAt: Self.timestamp,
                    respondedAt: nil
                ),
            ]
        )
    }

    func respondToHandoff(
        id: String,
        accept: Bool,
        viewer: SimulationViewer
    ) {
        let now = Self.timestamp
        var acceptedResponsibilityID: String?
        let handoffs = snapshot.v2State.handoffs.map { value in
            guard value.id == id, value.toProfileID == viewer.userID else {
                return value
            }
            if accept { acceptedResponsibilityID = value.responsibilityID }
            return ResponsibilityHandoff(
                id: value.id,
                responsibilityID: value.responsibilityID,
                coupleID: value.coupleID,
                fromProfileID: value.fromProfileID,
                toProfileID: value.toProfileID,
                status: accept ? .accepted : .declined,
                createdAt: value.createdAt,
                respondedAt: now
            )
        }
        let responsibilities = snapshot.responsibilities.map { value in
            guard value.id == acceptedResponsibilityID else { return value }
            return Responsibility(
                id: value.id,
                coupleID: value.coupleID,
                title: value.title,
                note: value.note,
                ownerID: viewer.userID,
                owner: .me,
                scheduledOn: value.scheduledOn,
                relatedPlanID: value.relatedPlanID,
                suggestionProvenance: value.suggestionProvenance,
                status: value.status,
                completedAt: value.completedAt,
                createdBy: value.createdBy,
                updatedBy: viewer.userID,
                createdAt: value.createdAt,
                updatedAt: now
            )
        }
        replace(
            responsibilities: responsibilities,
            handoffs: handoffs
        )
    }

    func withdrawHandoff(id: String, viewer: SimulationViewer) {
        replace(handoffs: snapshot.v2State.handoffs.map { value in
            guard value.id == id,
                  value.fromProfileID == viewer.userID,
                  value.status == .offered else { return value }
            return ResponsibilityHandoff(
                id: value.id,
                responsibilityID: value.responsibilityID,
                coupleID: value.coupleID,
                fromProfileID: value.fromProfileID,
                toProfileID: value.toProfileID,
                status: .withdrawn,
                createdAt: value.createdAt,
                respondedAt: Self.timestamp
            )
        })
    }

    func refreshSuggestions(viewer: SimulationViewer) {
        let generated = ContextualSuggestionEngine.partyGroceries(
            plans: snapshot.plans,
            responsibilities: snapshot.responsibilities
        )
        replace(suggestions: generated)
    }

    func dismissSuggestion(id: String, viewer: SimulationViewer) {
        dismissedSuggestionIDs[viewer, default: []].insert(id)
    }

    func confirmSuggestion(
        _ confirmation: SuggestionConfirmation,
        viewer: SimulationViewer
    ) throws {
        let all = snapshot.v2State.suggestions.isEmpty
            ? ContextualSuggestionEngine.partyGroceries(
                plans: snapshot.plans,
                responsibilities: snapshot.responsibilities
            )
            : snapshot.v2State.suggestions
        guard let suggestion = all.first(
            where: { $0.id == confirmation.suggestionID }
        ) else {
            throw RepositoryError.invalidData("suggestion is no longer available")
        }
        if snapshot.responsibilities.contains(
            where: { $0.relatedPlanID == suggestion.relatedPlanID }
        ) {
            throw RepositoryError.invalidData("related care already exists")
        }
        let ownerID: String? = switch confirmation.owner {
        case .me: viewer.userID
        case .partner: viewer.partner.userID
        case .together: nil
        }
        createResponsibility(
            ResponsibilityInput(
                title: confirmation.title,
                note: confirmation.note,
                owner: confirmation.owner,
                scheduledOn: confirmation.scheduledOn,
                relatedPlanID: suggestion.relatedPlanID,
                suggestionProvenance: suggestion.provenance
            ),
            ownerID: ownerID,
            viewer: viewer
        )
        replace(suggestions: [])
        for simulationViewer in SimulationViewer.allCases {
            dismissedSuggestionIDs[simulationViewer]?.remove(
                confirmation.suggestionID
            )
        }
    }

    func mutateInsight(
        _ insightID: String,
        viewer: SimulationViewer,
        action: SimulationInsightAction
    ) throws {
        guard let index = snapshot.insights.firstIndex(
            where: { $0.id == insightID }
        ) else {
            throw RepositoryError.invalidData("simulation insight is missing")
        }
        let record = snapshot.insights[index]
        var state = record.trustState(
            memberIDs: snapshot.members.map(\.id)
        )
        switch action {
        case .request:
            state = try TrustCore.requestReveal(
                state,
                by: viewer.userID,
                at: Int(Date().timeIntervalSince1970)
            )
        case .accept:
            state = try TrustCore.acceptReveal(
                state,
                by: viewer.userID,
                at: Int(Date().timeIntervalSince1970)
            )
        case .decline:
            state = try TrustCore.declineReveal(state, by: viewer.userID)
        case .withdraw:
            state = try TrustCore.withdrawReveal(state, by: viewer.userID)
        case .submit(let choice, let note):
            state = try TrustCore.submitResponse(
                state,
                by: viewer.userID,
                choice: choice,
                note: note
            )
        case .resolve(let type, let choice):
            state = try TrustCore.resolve(
                state,
                type: type,
                at: Int(Date().timeIntervalSince1970),
                choice: choice
            )
        case .dismiss:
            state = try TrustCore.dismissSuggestion(
                state,
                by: viewer.userID
            )
        }
        let now = Self.timestamp
        var records = snapshot.insights
        records[index] = InsightRecord(
            insight: record.insight,
            consent: InsightConsent(
                insightID: insightID,
                visibility: state.visibility,
                ownerID: state.ownerID,
                readiness: state.readiness,
                initiatorID: state.initiatorID,
                requestedAt: state.requestedAt == nil ? nil : now,
                acceptedAt: state.acceptedAt == nil ? nil : now,
                resolutionType: state.resolution?.type,
                resolutionChoice: state.resolution?.choice
            ),
            responses: state.responses.map {
                InsightResponse(
                    insightID: insightID,
                    profileID: $0.key,
                    status: $0.value.status,
                    choice: $0.value.choice,
                    note: $0.value.note
                )
            },
            sharedDirection: state.sharedDirection,
            dismissedBy: state.dismissedBy,
            declinedBy: state.declinedBy
        )
        replace(insights: records)
    }

    func createReadySeason() throws {
        let current = snapshot.v2State
        let previousCutoff = current.seasons.last.flatMap {
            ISO8601DateFormatter.we.date(from: $0.cutoffAt)
        }
        guard case .ready(let eventIDs, let cutoff) =
            SeasonReadiness.evaluate(
                events: current.events,
                after: previousCutoff,
                now: Date()
            )
        else {
            throw RepositoryError.invalidData("a season is not ready")
        }
        let eligible = current.events.filter { eventIDs.contains($0.id) }
        let references = eligible.flatMap(\.provenance)
        let first = eligible.map(\.occurredAt).min() ?? cutoff
        replace(
            seasons: current.seasons + [
                Season(
                    id: UUID().uuidString,
                    coupleID: "simulation-couple",
                    sequence: current.seasons.count + 1,
                    startsAt: first,
                    cutoffAt: cutoff,
                    title: "A season of showing up",
                    summary:
                        "\(eligible.count) shared moments formed this season.",
                    eventIDs: eventIDs,
                    provenance: references,
                    createdAt: Self.timestamp
                ),
            ]
        )
    }

    private func replace(
        profile: Profile? = nil,
        membership: Membership? = nil,
        couple: Couple? = nil,
        members: [Member]? = nil,
        insights: [InsightRecord]? = nil,
        reflections: [Reflection]? = nil,
        plans: [PlanItem]? = nil,
        responsibilities: [Responsibility]? = nil,
        presence: RelationshipPresence? = nil,
        signalConsents: [SignalConsent]? = nil,
        anchors: [Anchor]? = nil,
        handoffs: [ResponsibilityHandoff]? = nil,
        approaches: [PlanApproach]? = nil,
        events: [RelationshipEvent]? = nil,
        seasons: [Season]? = nil,
        suggestions: [ContextualSuggestion]? = nil
    ) {
        let current = snapshot.v2State
        snapshot = RelationshipSnapshot(
            profile: profile ?? snapshot.profile,
            membership: membership ?? snapshot.membership,
            couple: couple ?? snapshot.couple,
            members: members ?? snapshot.members,
            insights: insights ?? snapshot.insights,
            reflections: reflections ?? snapshot.reflections,
            plans: plans ?? snapshot.plans,
            responsibilities: responsibilities ?? snapshot.responsibilities,
            archives: snapshot.archives,
            syncedAt: Date(),
            v2: V2RelationshipState(
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
        )
    }

    private static var timestamp: String {
        ISO8601DateFormatter.we.string(from: Date())
    }

    private static func seed() -> RelationshipSnapshot {
        let party = PlanItem(
            id: "plan-party",
            coupleID: "preview-couple",
            title: "Saturday’s party",
            note: "A few friends for dinner.",
            scheduledOn: "2026-08-01",
            status: .active,
            completedAt: nil,
            createdBy: "dylan",
            updatedBy: "dylan",
            createdAt: "2026-07-24T16:00:00Z",
            updatedAt: "2026-07-24T16:00:00Z"
        )
        let threadSeeds: [
            (String, String, RelationshipEventType)
        ] = [
            (
                "2026-05-02T18:00:00Z",
                "Morning coffee by the river",
                .sharedMomentOpened
            ),
            (
                "2026-05-16T18:00:00Z",
                "Make the guest room feel welcoming",
                .responsibilityCompleted
            ),
            (
                "2026-05-30T18:00:00Z",
                "Carry the Tuesday pickup for a while",
                .handoffAccepted
            ),
            (
                "2026-06-08T18:00:00Z",
                "Wait until spring",
                .planCompleted
            ),
            (
                "2026-06-22T18:00:00Z",
                "Clear one thing, protect the rest",
                .mutualResolution
            ),
            (
                "2026-07-12T18:00:00Z",
                "Out of the house",
                .mutualResolution
            ),
        ]
        let events = threadSeeds.enumerated().map { index, seed in
            RelationshipEvent(
                id: "simulation-event-\(index)",
                coupleID: "preview-couple",
                type: seed.2,
                sourceID: "simulation-source-\(index)",
                title: seed.1,
                occurredAt: seed.0,
                provenance: [
                    ProvenanceReference(
                        kind: seed.2 == .responsibilityCompleted
                            || seed.2 == .handoffAccepted
                            ? .responsibility
                            : .relationshipEvent,
                        id: "simulation-source-\(index)",
                        label: "Shared event \(index + 1)",
                        shared: true
                    ),
                ]
            )
        }
        var value = PreviewData.snapshot
        let baseV2 = V2RelationshipState(
            presence: RelationshipPresence(
                coupleID: "preview-couple",
                mode: .apart,
                changedBy: "ryan",
                changedAt: "2026-07-27T12:00:00Z"
            ),
            signalConsents: SignalKind.allCases.flatMap { signal in
                ["ryan", "dylan"].map {
                    SignalConsent(
                        coupleID: "preview-couple",
                        profileID: $0,
                        signal: signal,
                        isEnabled: !signal.isPermanentlyDisabled,
                        updatedAt: "2026-07-27T12:00:00Z"
                    )
                }
            },
            anchors: [
                Anchor(
                    id: "anchor-sunday",
                    coupleID: "preview-couple",
                    title: "Sunday reset",
                    note: "Ten quiet minutes to look at the week.",
                    cadence: .weekly,
                    isActive: true,
                    createdBy: "ryan",
                    createdAt: "2026-06-01T12:00:00Z",
                    updatedAt: "2026-06-01T12:00:00Z"
                ),
            ],
            handoffs: [],
            approaches: [],
            events: events,
            seasons: [
                Season(
                    id: "simulation-season-one",
                    coupleID: "preview-couple",
                    sequence: 1,
                    startsAt: threadSeeds[0].0,
                    cutoffAt: "2026-07-27T12:00:00Z",
                    title: "You got quieter, and it worked.",
                    summary: "Three months, six things closed together, and fewer repeated conversations. WE asked less as it learned more.",
                    eventIDs: events.map(\.id),
                    provenance: events.flatMap(\.provenance),
                    createdAt: "2026-07-27T12:00:00Z"
                ),
            ],
            suggestions: [],
            declineGrace: []
        )
        value = RelationshipSnapshot(
            profile: value.profile,
            membership: value.membership,
            couple: value.couple,
            members: value.members,
            insights: value.insights,
            reflections: value.reflections,
            plans: value.plans + [party],
            responsibilities: value.responsibilities,
            archives: [],
            syncedAt: Date(),
            v2: baseV2
        )
        let suggestions = ContextualSuggestionEngine.partyGroceries(
            plans: value.plans,
            responsibilities: value.responsibilities
        )
        return RelationshipSnapshot(
            profile: value.profile,
            membership: value.membership,
            couple: value.couple,
            members: value.members,
            insights: value.insights,
            reflections: value.reflections,
            plans: value.plans,
            responsibilities: value.responsibilities,
            archives: [],
            syncedAt: Date(),
            v2: V2RelationshipState(
                presence: baseV2.presence,
                signalConsents: baseV2.signalConsents,
                anchors: baseV2.anchors,
                handoffs: [],
                approaches: [],
                events: events,
                seasons: baseV2.seasons,
                suggestions: suggestions,
                declineGrace: []
            )
        )
    }
}

nonisolated enum SimulationInsightAction: Sendable {
    case request
    case accept
    case decline
    case withdraw
    case submit(choice: String, note: String?)
    case resolve(type: ResolutionType, choice: String?)
    case dismiss
}

actor SimulationRepository: Repository {
    nonisolated let isConfigured = true

    private let store: SimulationStore
    private let viewer: SimulationViewer
    private var signedIn = true

    init(store: SimulationStore, viewer: SimulationViewer) {
        self.store = store
        self.viewer = viewer
    }

    private var user: AuthenticatedUser {
        AuthenticatedUser(
            id: viewer.userID,
            email: "\(viewer.rawValue)@simulation.we"
        )
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        signedIn ? user : nil
    }

    func signUp(
        name: String,
        email: String,
        password: String
    ) async throws -> SignUpResult {
        signedIn = true
        return .signedIn(user)
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        signedIn = true
        return user
    }

    func sendPasswordReset(email: String) async throws {}
    func handleAuthCallback(_ url: URL) async throws -> AuthCallbackResult {
        .emailConfirmed(user)
    }
    func updatePassword(_ password: String) async throws {}
    func signOut() async throws { signedIn = false }
    func deleteAccount(email: String, password: String) async throws {
        signedIn = false
    }

    func loadRelationship(
        for user: AuthenticatedUser
    ) async throws -> RelationshipSnapshot {
        await store.load(viewer: viewer)
    }

    func relationshipChanges() async throws
        -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { _ in }
    }

    func createCouple() async throws {}
    func joinCouple(code: String) async throws {}
    func createInvitation() async throws {}
    func revokeInvitation() async throws {}
    func acknowledgeDeparture() async throws {}

    func updateProfile(name: String, userID: String) async throws {
        await store.updateProfile(viewer: viewer, name: name)
    }

    func updateHue(
        _ hue: MemberHue,
        membership: Membership
    ) async throws {
        await store.updateHue(viewer: viewer, hue: hue)
    }

    func createPlan(_ input: PlanInput, coupleID: String) async throws {
        await store.createPlan(input, viewer: viewer)
    }

    func updatePlan(id: String, input: PlanInput) async throws {
        await store.updatePlan(id: id, input: input, viewer: viewer)
    }

    func setPlanStatus(
        id: String,
        status: SharedItemStatus
    ) async throws {
        await store.setPlanStatus(id: id, status: status, viewer: viewer)
    }

    func createResponsibility(
        _ input: ResponsibilityInput,
        coupleID: String,
        ownerID: String?
    ) async throws {
        await store.createResponsibility(
            input,
            ownerID: ownerID,
            viewer: viewer
        )
    }

    func updateResponsibility(
        id: String,
        input: ResponsibilityInput,
        ownerID: String?
    ) async throws {
        await store.updateResponsibility(
            id: id,
            input: input,
            ownerID: ownerID,
            viewer: viewer
        )
    }

    func setResponsibilityStatus(
        id: String,
        status: SharedItemStatus
    ) async throws {
        await store.setResponsibilityStatus(
            id: id,
            status: status,
            viewer: viewer
        )
    }

    func saveReflection(
        text: String,
        domain: InsightDomain,
        coupleID: String,
        ownerID: String
    ) async throws {
        await store.saveReflection(text: text, viewer: viewer)
    }

    func requestReveal(insightID: String) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .request
        )
    }

    func acceptReveal(insightID: String) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .accept
        )
    }

    func declineReveal(insightID: String) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .decline
        )
    }

    func withdrawReveal(insightID: String) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .withdraw
        )
    }

    func submitResponse(
        insightID: String,
        choice: String,
        note: String?
    ) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .submit(choice: choice, note: note)
        )
    }

    func resolveInsight(
        insightID: String,
        type: ResolutionType,
        choice: String?
    ) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .resolve(type: type, choice: choice)
        )
    }

    func dismissSuggestion(insightID: String) async throws {
        try await store.mutateInsight(
            insightID,
            viewer: viewer,
            action: .dismiss
        )
    }

    func setPresence(_ mode: PresenceMode) async throws {
        await store.setPresence(mode, viewer: viewer)
    }

    func setSignalConsent(
        _ signal: SignalKind,
        enabled: Bool
    ) async throws {
        await store.setSignal(signal, enabled: enabled, viewer: viewer)
    }

    func createAnchor(
        _ input: AnchorInput,
        coupleID: String
    ) async throws {
        await store.createAnchor(input, viewer: viewer)
    }

    func setAnchorActive(id: String, isActive: Bool) async throws {
        await store.setAnchorActive(id: id, isActive: isActive)
    }

    func offerHandoff(
        responsibilityID: String,
        toProfileID: String
    ) async throws {
        await store.offerHandoff(
            responsibilityID: responsibilityID,
            toProfileID: toProfileID,
            viewer: viewer
        )
    }

    func respondToHandoff(id: String, accept: Bool) async throws {
        await store.respondToHandoff(
            id: id,
            accept: accept,
            viewer: viewer
        )
    }

    func withdrawHandoff(id: String) async throws {
        await store.withdrawHandoff(id: id, viewer: viewer)
    }

    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?
    ) async throws {
        await store.setApproach(
            planID: planID,
            approach: approach,
            note: note,
            viewer: viewer
        )
    }

    func refreshContextualSuggestions(localDate: String) async throws {
        await store.refreshSuggestions(viewer: viewer)
    }

    func dismissContextualSuggestion(id: String) async throws {
        await store.dismissSuggestion(id: id, viewer: viewer)
    }

    func confirmContextualSuggestion(
        _ confirmation: SuggestionConfirmation
    ) async throws {
        try await store.confirmSuggestion(confirmation, viewer: viewer)
    }

    func createReadySeason() async throws {
        try await store.createReadySeason()
    }
}
