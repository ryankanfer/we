import Foundation

enum RepositoryError: LocalizedError {
    case missingConfiguration
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Supabase is not configured for this run."
        case .invalidData(let description):
            "The backend returned data WE could not read: \(description)"
        }
    }
}

protocol Repository {
    var isConfigured: Bool { get }

    func restoreSession() async throws -> AuthenticatedUser?
    func signIn(email: String, password: String) async throws
        -> AuthenticatedUser
    func signOut() async throws
    func loadRelationship(for user: AuthenticatedUser) async throws
        -> RelationshipSnapshot
    func relationshipChanges() async throws -> AsyncStream<Void>

    func createCouple() async throws
    func joinCouple(code: String) async throws
    func requestReveal(insightID: String) async throws
    func acceptReveal(insightID: String) async throws
    func declineReveal(insightID: String) async throws
    func withdrawReveal(insightID: String) async throws
    func submitResponse(
        insightID: String,
        choice: String,
        note: String?
    ) async throws
    func resolveInsight(
        insightID: String,
        type: ResolutionType,
        choice: String?
    ) async throws
    func dismissSuggestion(insightID: String) async throws
}

enum RepositoryFactory {
    static func make(
        environment: AppEnvironment = .current
    ) -> any Repository {
        switch environment.repositoryMode {
        case .preview:
            PreviewRepository()
        case .live:
            SupabaseRepository(
                provider: SupabaseClientProvider(
                    configuration: environment.supabase
                )
            )
        }
    }
}
