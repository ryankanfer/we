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

    init(repository: any Repository) {
        self.repository = repository
    }

    var insights: [Insight] {
        snapshot?.insights.map(\.insight) ?? []
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

    private func load(user: AuthenticatedUser) async throws {
        let loaded = try await repository.loadRelationship(for: user)
        self.user = user
        snapshot = loaded
        state = loaded.membership == nil ? .needsCouple : .ready
    }
}
