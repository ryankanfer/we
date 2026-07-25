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
