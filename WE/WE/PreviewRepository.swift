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

    func relationshipChanges() async throws -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func createCouple() async throws {}
    func joinCouple(code: String) async throws {}
    func requestReveal(insightID: String) async throws {}
    func acceptReveal(insightID: String) async throws {}
    func declineReveal(insightID: String) async throws {}
    func withdrawReveal(insightID: String) async throws {}

    func submitResponse(
        insightID: String,
        choice: String,
        note: String?
    ) async throws {}

    func resolveInsight(
        insightID: String,
        type: ResolutionType,
        choice: String?
    ) async throws {}

    func dismissSuggestion(insightID: String) async throws {}
}
