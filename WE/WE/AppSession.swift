import Combine
import Foundation

@MainActor
final class AppSession: ObservableObject {
    enum State: Equatable {
        case loading
        case unconfigured
        case signedOut
        case verificationPending(String)
        case resettingPassword
        case needsCouple
        case waitingForPartner
        case choosingHue
        case ready
        case failed(String)
    }

    enum ConnectionState: Equatable {
        case online
        case offline
        case reconnecting
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var connectionState: ConnectionState
    @Published private(set) var user: AuthenticatedUser?
    @Published private(set) var snapshot: RelationshipSnapshot?
    @Published private(set) var privateProposals: [SavedPrivateProposal] = []
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var cachedAt: Date?

    private let repository: any Repository
    private let cache: any RelationshipCache
    private let connectivity: ConnectivityMonitor
    private var didRestore = false
    private var authRoutingGeneration = 0
    private var changesTask: Task<Void, Never>?
    private var changesObservationID: UUID?
    private var connectivityCancellable: AnyCancellable?

    init(
        repository: any Repository,
        cache: (any RelationshipCache)? = nil,
        connectivity: ConnectivityMonitor? = nil
    ) {
        let resolvedConnectivity = connectivity ?? ConnectivityMonitor()
        self.repository = repository
        self.cache = cache ?? FileRelationshipCache()
        self.connectivity = resolvedConnectivity
        connectionState = resolvedConnectivity.isOnline ? .online : .offline

        connectivityCancellable = resolvedConnectivity.$isOnline
            .removeDuplicates()
            .sink { [weak self] isOnline in
                guard let self else { return }
                if isOnline {
                    connectionState = .reconnecting
                    Task { await self.refreshAfterReconnect() }
                } else {
                    connectionState = .offline
                }
            }
    }

    var insights: [Insight] {
        snapshot?.insights.map(\.insight) ?? []
    }

    var insightRecords: [InsightRecord] {
        snapshot?.insights ?? []
    }

    var plans: [PlanItem] { snapshot?.plans ?? [] }
    var responsibilities: [Responsibility] {
        snapshot?.responsibilities ?? []
    }
    var archives: [RelationshipArchive] { snapshot?.archives ?? [] }
    var v2State: V2RelationshipState { snapshot?.v2State ?? .empty }
    var presenceMode: PresenceMode {
        v2State.presence?.mode ?? .apart
    }
    var anchors: [Anchor] { v2State.anchors }
    var handoffs: [ResponsibilityHandoff] { v2State.handoffs }
    var relationshipEvents: [RelationshipEvent] { v2State.events }
    var seasons: [Season] { v2State.seasons }
    var hasUnlockedAhead: Bool { !plans.isEmpty }
    var hasUnlockedThread: Bool { !relationshipEvents.isEmpty }

    var contextualSuggestions: [ContextualSuggestion] {
        let persisted = v2State.suggestions.filter(\.isAvailable)
        if !v2State.suggestions.isEmpty { return persisted }
        return ContextualSuggestionEngine.partyGroceries(
            plans: plans,
            responsibilities: responsibilities
        )
    }

    var seasonReadiness: SeasonReadiness {
        let cutoff = seasons.last.flatMap {
            ISO8601DateFormatter.we.date(from: $0.cutoffAt)
        }
        return SeasonReadiness.evaluate(
            events: relationshipEvents,
            after: cutoff,
            now: Date()
        )
    }

    var isReady: Bool { state == .ready }
    var canMutate: Bool { connectionState == .online && !isWorking }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true

        guard repository.isConfigured else {
            state = .unconfigured
            return
        }

        state = .loading
        let generation = authRoutingGeneration
        do {
            guard let restoredUser = try await repository.restoreSession() else {
                guard generation == authRoutingGeneration else { return }
                state = .signedOut
                return
            }
            try await load(
                user: restoredUser,
                allowsCache: true,
                authRoutingGeneration: generation
            )
        } catch {
            guard generation == authRoutingGeneration else { return }
            if case RepositoryError.invalidSession(let storedUser) = error {
                await handleInvalidSession(for: storedUser)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func signUp(name: String, email: String, password: String) async {
        await working {
            let result = try await self.repository.signUp(
                name: name,
                email: email,
                password: password
            )
            switch result {
            case .signedIn(let signedInUser):
                try await self.load(user: signedInUser, allowsCache: false)
            case .verificationPending(let email):
                self.user = nil
                self.snapshot = nil
                self.privateProposals = []
                self.state = .verificationPending(email)
            }
        }
    }

    func returnToSignIn(message: String? = nil) {
        noticeMessage = message
        errorMessage = nil
        state = .signedOut
    }

    func signIn(email: String, password: String) async {
        await working {
            let signedInUser = try await self.repository.signIn(
                email: email,
                password: password
            )
            try await self.load(user: signedInUser, allowsCache: true)
        }
    }

    func sendPasswordReset(email: String) async {
        await working {
            try await self.repository.sendPasswordReset(email: email)
            self.noticeMessage = "Check your email for a secure reset link."
        }
    }

    func handleAuthCallback(_ url: URL) async {
        authRoutingGeneration += 1
        let generation = authRoutingGeneration
        await working {
            switch try await self.repository.handleAuthCallback(url) {
            case .emailConfirmed(let confirmedUser):
                try await self.load(
                    user: confirmedUser,
                    allowsCache: false,
                    authRoutingGeneration: generation
                )
                self.noticeMessage = "Your email is verified."
            case .passwordRecovery(let recoveringUser):
                self.stopObservingRelationship()
                self.user = recoveringUser
                self.snapshot = nil
                self.privateProposals = []
                self.state = .resettingPassword
            }
        }
    }

    func completePasswordRecovery(_ password: String) async {
        guard let user else { return }
        await working {
            try await self.repository.updatePassword(password)
            try await self.load(user: user, allowsCache: false)
            self.noticeMessage = "Your password has been updated."
        }
    }

    func signOut() async {
        let signingOutUser = user
        isWorking = true
        errorMessage = nil
        noticeMessage = nil
        defer { isWorking = false }
        stopObservingRelationship()

        do {
            if let signingOutUser {
                try await cache.remove(userID: signingOutUser.id)
            }
        } catch {
            errorMessage = "WE could not remove protected offline data: \(error.localizedDescription)"
            return
        }

        do {
            try await repository.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        user = nil
        snapshot = nil
        privateProposals = []
        cachedAt = nil
        state = .signedOut
    }

    func deleteAccount(password: String) async {
        guard let user else { return }
        let deletingUser = user
        await working {
            self.stopObservingRelationship()
            try await self.cache.remove(userID: deletingUser.id)
            try await self.repository.deleteAccount(
                email: deletingUser.email,
                password: password
            )
            self.user = nil
            self.snapshot = nil
            self.privateProposals = []
            self.cachedAt = nil
            self.noticeMessage = "Your account and live WE space were deleted."
            self.state = .signedOut
        }
    }

    func retry() async {
        errorMessage = nil
        if let user {
            do {
                try await load(user: user, allowsCache: true)
            } catch {
                state = .failed(error.localizedDescription)
            }
        } else {
            didRestore = false
            await restoreIfNeeded()
        }
    }

    func createCouple() async {
        await perform { try await self.repository.createCouple() }
    }

    func joinCouple(code: String) async {
        await perform { try await self.repository.joinCouple(code: code) }
    }

    func updateProfile(name: String) async {
        guard let user else { return }
        await perform {
            try await self.repository.updateProfile(name: name, userID: user.id)
        }
    }

    func updateHue(_ hue: MemberHue) async {
        guard let membership = snapshot?.membership else { return }
        await perform {
            try await self.repository.updateHue(hue, membership: membership)
        }
    }

    /// Moves a pre-account proposal into owner-only storage. This deliberately
    /// does not reload the shared relationship snapshot because the claimed
    /// source remains outside couple membership.
    func claimPrivateProposal(_ proposal: PrivateProposal) async -> String? {
        guard user != nil else { return nil }
        guard connectionState == .online else {
            errorMessage = RepositoryError.offline.localizedDescription
            return nil
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let proposalID = try await repository.claimPrivateProposal(
                proposal
            )
            privateProposals.removeAll { $0.id == proposalID }
            privateProposals.insert(
                SavedPrivateProposal(
                    serverID: proposalID,
                    proposal: proposal
                ),
                at: 0
            )
            noticeMessage = "Your proposal is protected on your side."
            return proposalID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Publishes only the frozen safe preview created during the claim. The
    /// repository cannot derive an offer from the source note at this step.
    func offerPrivateProposal(id: String) async -> Bool {
        guard user != nil else { return false }
        guard connectionState == .online else {
            errorMessage = RepositoryError.offline.localizedDescription
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await repository.offerPrivateProposal(id: id)
            noticeMessage = "Only the approved topic was offered."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createPlan(_ input: PlanInput) async {
        guard let coupleID = snapshot?.membership?.coupleID else { return }
        await perform {
            try await self.repository.createPlan(input, coupleID: coupleID)
        }
    }

    func updatePlan(id: String, input: PlanInput) async {
        await perform { try await self.repository.updatePlan(id: id, input: input) }
    }

    func setPlanStatus(id: String, status: SharedItemStatus) async {
        await perform {
            try await self.repository.setPlanStatus(id: id, status: status)
        }
    }

    func createResponsibility(_ input: ResponsibilityInput) async {
        guard let coupleID = snapshot?.membership?.coupleID else { return }
        await perform {
            try await self.repository.createResponsibility(
                input,
                coupleID: coupleID,
                ownerID: self.ownerID(for: input.owner)
            )
        }
    }

    func updateResponsibility(
        id: String,
        input: ResponsibilityInput
    ) async {
        await perform {
            try await self.repository.updateResponsibility(
                id: id,
                input: input,
                ownerID: self.ownerID(for: input.owner)
            )
        }
    }

    func setResponsibilityStatus(
        id: String,
        status: SharedItemStatus
    ) async {
        await perform {
            try await self.repository.setResponsibilityStatus(
                id: id,
                status: status
            )
        }
    }

    func setPresence(_ mode: PresenceMode) async {
        await perform { try await self.repository.setPresence(mode) }
    }

    func setSignalConsent(
        _ signal: SignalKind,
        enabled: Bool
    ) async {
        await perform {
            try await self.repository.setSignalConsent(
                signal,
                enabled: enabled
            )
        }
    }

    func createAnchor(_ input: AnchorInput) async {
        guard let coupleID = snapshot?.membership?.coupleID else { return }
        await perform {
            try await self.repository.createAnchor(input, coupleID: coupleID)
        }
    }

    func setAnchorActive(id: String, isActive: Bool) async {
        await perform {
            try await self.repository.setAnchorActive(
                id: id,
                isActive: isActive
            )
        }
    }

    func offerHandoff(
        responsibilityID: String,
        toProfileID: String
    ) async {
        await perform {
            try await self.repository.offerHandoff(
                responsibilityID: responsibilityID,
                toProfileID: toProfileID
            )
        }
    }

    func respondToHandoff(id: String, accept: Bool) async {
        await perform {
            try await self.repository.respondToHandoff(
                id: id,
                accept: accept
            )
        }
    }

    func withdrawHandoff(id: String) async {
        await perform {
            try await self.repository.withdrawHandoff(id: id)
        }
    }

    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?
    ) async {
        await perform {
            try await self.repository.setApproach(
                planID: planID,
                approach: approach,
                note: note
            )
        }
    }

    func dismissContextualSuggestion(id: String) async {
        await perform {
            try await self.repository.dismissContextualSuggestion(id: id)
        }
        if errorMessage == nil {
            noticeMessage = "“Not useful” stays private."
        }
    }

    func confirmContextualSuggestion(
        _ confirmation: SuggestionConfirmation
    ) async {
        await perform {
            try await self.repository.confirmContextualSuggestion(
                SuggestionConfirmation(
                    suggestionID: confirmation.suggestionID,
                    title: confirmation.title,
                    note: confirmation.note,
                    owner: confirmation.owner,
                    scheduledOn: confirmation.scheduledOn,
                    ownerID: self.ownerID(for: confirmation.owner)
                )
            )
        }
    }

    func createReadySeason() async {
        await perform { try await self.repository.createReadySeason() }
    }

    func saveReflection(text: String) async {
        guard let user,
              let coupleID = snapshot?.membership?.coupleID else { return }
        await perform {
            try await self.repository.saveReflection(
                text: text,
                domain: .us,
                coupleID: coupleID,
                ownerID: user.id
            )
        }
    }

    func requestReveal(insightID: String) async {
        await perform { try await self.repository.requestReveal(insightID: insightID) }
    }

    func acceptReveal(insightID: String) async {
        await perform { try await self.repository.acceptReveal(insightID: insightID) }
    }

    func declineReveal(insightID: String) async {
        await perform { try await self.repository.declineReveal(insightID: insightID) }
        if errorMessage == nil {
            noticeMessage = "Your “not now” stays private."
        }
    }

    func withdrawReveal(insightID: String) async {
        await perform { try await self.repository.withdrawReveal(insightID: insightID) }
    }

    func submitResponse(
        insightID: String,
        choice: String,
        note: String? = nil
    ) async {
        await perform {
            try await self.repository.submitResponse(
                insightID: insightID,
                choice: choice,
                note: note
            )
        }
    }

    func resolveInsight(
        insightID: String,
        type: ResolutionType,
        choice: String? = nil
    ) async {
        await perform {
            try await self.repository.resolveInsight(
                insightID: insightID,
                type: type,
                choice: choice
            )
        }
    }

    func dismissSuggestion(insightID: String) async {
        await perform {
            try await self.repository.dismissSuggestion(insightID: insightID)
        }
    }

    func projection(for record: InsightRecord) -> TrustProjection? {
        guard let user else { return nil }
        let memberIDs = snapshot?.members.map(\.id) ?? [user.id]
        return TrustCore.project(
            record.trustState(memberIDs: memberIDs),
            for: user.id
        )
    }

    func questionAction(for record: InsightRecord) -> QuestionPrimaryAction {
        guard let user else {
            return .hold(partnerName: "your partner")
        }
        let partnerHasAnswered = record.responses.contains {
            $0.profileID != user.id
                && ($0.status == .submitted || $0.status == .revealed)
        }
        return partnerHasAnswered
            ? .openTogether(partnerName: partnerName)
            : .hold(partnerName: partnerName)
    }

    func clearMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    func suspend() {
        stopObservingRelationship()
    }

    private func working(
        _ operation: () async throws -> Void
    ) async {
        isWorking = true
        errorMessage = nil
        noticeMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(
        _ operation: () async throws -> Void
    ) async {
        guard let user else { return }
        guard connectionState == .online else {
            errorMessage = RepositoryError.offline.localizedDescription
            return
        }
        await working {
            try await operation()
            try await self.load(user: user, allowsCache: false)
        }
    }

    private func load(
        user: AuthenticatedUser,
        allowsCache: Bool,
        authRoutingGeneration expectedGeneration: Int? = nil
    ) async throws {
        do {
            async let relationshipRequest =
                repository.loadRelationship(for: user)
            async let proposalsRequest =
                repository.loadPrivateProposals(for: user)
            let (loaded, loadedPrivateProposals) = try await (
                relationshipRequest,
                proposalsRequest
            )
            if let expectedGeneration,
               expectedGeneration != authRoutingGeneration {
                return
            }
            self.user = user
            snapshot = loaded
            privateProposals = loadedPrivateProposals
            cachedAt = nil
            connectionState = connectivity.isOnline ? .online : .offline
            try? await cache.save(loaded, userID: user.id)
            route(loaded)
            observeRelationshipIfNeeded()
        } catch {
            if let expectedGeneration,
               expectedGeneration != authRoutingGeneration {
                return
            }
            if allowsCache,
               !connectivity.isOnline,
               let cached = try? await cache.load(userID: user.id) {
                self.user = user
                snapshot = cached.snapshot
                privateProposals = []
                cachedAt = cached.savedAt
                connectionState = .offline
                route(cached.snapshot)
                return
            }
            throw error
        }
    }

    private func route(_ snapshot: RelationshipSnapshot) {
        guard let membership = snapshot.membership else {
            state = .needsCouple
            stopObservingRelationship()
            return
        }
        if snapshot.members.count < 2 {
            state = .waitingForPartner
        } else if !membership.hasChosenHue {
            state = .choosingHue
        } else {
            state = .ready
        }
    }

    private func handleInvalidSession(
        for storedUser: AuthenticatedUser
    ) async {
        if !connectivity.isOnline,
           let cached = try? await cache.load(userID: storedUser.id) {
            user = storedUser
            snapshot = cached.snapshot
            privateProposals = []
            cachedAt = cached.savedAt
            connectionState = .offline
            route(cached.snapshot)
            return
        }

        stopObservingRelationship()
        do {
            try await cache.remove(userID: storedUser.id)
        } catch {
            errorMessage =
                "WE could not remove protected offline data: "
                + error.localizedDescription
        }
        try? await repository.signOut()
        user = nil
        snapshot = nil
        privateProposals = []
        cachedAt = nil
        noticeMessage = "Your session expired. Sign in again."
        state = .signedOut
    }

    private func ownerID(for owner: ResponsibilityOwner) -> String? {
        switch owner {
        case .me:
            user?.id
        case .partner:
            snapshot?.members.first { $0.id != user?.id }?.id
        case .together:
            nil
        }
    }

    var partnerName: String {
        guard let user else { return "Your partner" }
        return snapshot?.members.first { $0.id != user.id }?.name
            ?? "Your partner"
    }

    private func observeRelationshipIfNeeded() {
        guard snapshot?.membership != nil, changesTask == nil else { return }
        let observationID = UUID()
        changesObservationID = observationID
        changesTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if changesObservationID == observationID {
                    changesObservationID = nil
                    changesTask = nil
                }
            }
            while !Task.isCancelled {
                do {
                    let changes = try await repository.relationshipChanges()
                    for try await _ in changes {
                        guard !Task.isCancelled,
                              let user = self.user else {
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { break }
                        do {
                            try await self.load(
                                user: user,
                                allowsCache: true
                            )
                        } catch {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                    if !Task.isCancelled {
                        connectionState = .reconnecting
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    connectionState = connectivity.isOnline
                        ? .reconnecting
                        : .offline
                    errorMessage = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopObservingRelationship() {
        changesObservationID = nil
        changesTask?.cancel()
        changesTask = nil
    }

    private func refreshAfterReconnect() async {
        guard let user else {
            connectionState = connectivity.isOnline ? .online : .offline
            return
        }
        do {
            try await load(user: user, allowsCache: true)
            errorMessage = nil
        } catch {
            connectionState = connectivity.isOnline
                ? .reconnecting
                : .offline
            errorMessage = error.localizedDescription
        }
    }
}
