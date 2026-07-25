struct PreviewRepository: Repository {
    let isConfigured = true

    func restoreSession() async throws -> AuthenticatedUser? {
        PreviewData.user
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        PreviewData.user
    }

    func signOut() async throws {}

    func loadRelationship(
        for user: AuthenticatedUser
    ) async throws -> RelationshipSnapshot {
        PreviewData.snapshot
    }
}
