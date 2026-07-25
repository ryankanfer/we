import Combine
import Foundation

@MainActor
final class AppSession: ObservableObject {
    enum State: Equatable {
        case loading
        case unconfigured
        case signedOut
        case needsCouple
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var user: AuthenticatedUser?
    @Published private(set) var snapshot: RelationshipSnapshot?
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let repository: any Repository
    private var didRestore = false
    private var changesTask: Task<Void, Never>?

    init(repository: any Repository) {
        self.repository = repository
    }

    var insights: [Insight] {
        snapshot?.insights.map(\.insight) ?? []
    }

    var insightRecords: [InsightRecord] {
        snapshot?.insights ?? []
    }

    var isReady: Bool {
        state == .ready
    }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true

        guard repository.isConfigured else {
            state = .unconfigured
            return
        }

        state = .loading
        do {
            guard let restoredUser = try await repository.restoreSession()
            else {
                state = .signedOut
                return
            }
            try await load(user: restoredUser)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signIn(email: String, password: String) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let signedInUser = try await repository.signIn(
                email: email,
                password: password
            )
            try await load(user: signedInUser)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }

        do {
            changesTask?.cancel()
            changesTask = nil
            try await repository.signOut()
            user = nil
            snapshot = nil
            errorMessage = nil
            state = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry() async {
        didRestore = false
        await restoreIfNeeded()
    }

    func createCouple() async {
        await perform {
            try await self.repository.createCouple()
        }
    }

    func joinCouple(code: String) async {
        await perform {
            try await self.repository.joinCouple(code: code)
        }
    }

    func requestReveal(insightID: String) async {
        await perform {
            try await self.repository.requestReveal(insightID: insightID)
        }
    }

    func acceptReveal(insightID: String) async {
        await perform {
            try await self.repository.acceptReveal(insightID: insightID)
        }
    }

    func declineReveal(insightID: String) async {
        await perform {
            try await self.repository.declineReveal(insightID: insightID)
        }
    }

    func withdrawReveal(insightID: String) async {
        await perform {
            try await self.repository.withdrawReveal(insightID: insightID)
        }
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

    private func load(user: AuthenticatedUser) async throws {
        let loaded = try await repository.loadRelationship(for: user)
        self.user = user
        snapshot = loaded
        state = loaded.membership == nil ? .needsCouple : .ready
        if loaded.membership == nil {
            changesTask?.cancel()
            changesTask = nil
        } else {
            observeRelationship()
        }
    }

    private func perform(
        _ operation: () async throws -> Void
    ) async {
        guard let user else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await operation()
            try await load(user: user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeRelationship() {
        guard changesTask == nil else { return }

        changesTask = Task { [weak self] in
            guard let self else { return }

            do {
                let changes = try await repository.relationshipChanges()
                for await _ in changes {
                    guard !Task.isCancelled, let user = self.user else {
                        break
                    }
                    do {
                        let loaded = try await repository.loadRelationship(
                            for: user
                        )
                        snapshot = loaded
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
