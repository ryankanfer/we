import Foundation

enum RepositoryError: LocalizedError {
    case missingConfiguration
    case invalidData(String)
    case invalidSession(AuthenticatedUser)
    case offline

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Supabase is not configured for this run."
        case .invalidData(let description):
            "The backend returned data WE could not read: \(description)"
        case .invalidSession:
            "Your saved session is no longer valid."
        case .offline:
            "WE is offline. Your last shared state is still here, but changes need a connection."
        }
    }
}

protocol Repository {
    var isConfigured: Bool { get }

    func restoreSession() async throws -> AuthenticatedUser?
    func signUp(name: String, email: String, password: String) async throws
        -> SignUpResult
    func signIn(email: String, password: String) async throws
        -> AuthenticatedUser
    func sendPasswordReset(email: String) async throws
    func handleAuthCallback(_ url: URL) async throws -> AuthCallbackResult
    func updatePassword(_ password: String) async throws
    func signOut() async throws
    func deleteAccount(email: String, password: String) async throws

    func loadRelationship(for user: AuthenticatedUser) async throws
        -> RelationshipSnapshot
    func relationshipChanges() async throws
        -> AsyncThrowingStream<Void, Error>

    func createCouple() async throws
    func joinCouple(code: String) async throws
    func updateProfile(name: String, userID: String) async throws
    func updateHue(_ hue: MemberHue, membership: Membership) async throws
    func loadPrivateProposals(
        for user: AuthenticatedUser
    ) async throws -> [SavedPrivateProposal]
    func claimPrivateProposal(_ proposal: PrivateProposal) async throws
        -> String
    func offerPrivateProposal(id: String) async throws

    func createPlan(_ input: PlanInput, coupleID: String) async throws
    func updatePlan(id: String, input: PlanInput) async throws
    func setPlanStatus(id: String, status: SharedItemStatus) async throws

    func createResponsibility(
        _ input: ResponsibilityInput,
        coupleID: String,
        ownerID: String?
    ) async throws
    func updateResponsibility(
        id: String,
        input: ResponsibilityInput,
        ownerID: String?
    ) async throws
    func setResponsibilityStatus(
        id: String,
        status: SharedItemStatus
    ) async throws

    func saveReflection(
        text: String,
        domain: InsightDomain,
        coupleID: String,
        ownerID: String
    ) async throws

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

    func setPresence(_ mode: PresenceMode) async throws
    func setSignalConsent(_ signal: SignalKind, enabled: Bool) async throws
    func createAnchor(_ input: AnchorInput, coupleID: String) async throws
    func setAnchorActive(id: String, isActive: Bool) async throws
    func offerHandoff(
        responsibilityID: String,
        toProfileID: String
    ) async throws
    func respondToHandoff(id: String, accept: Bool) async throws
    func withdrawHandoff(id: String) async throws
    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?
    ) async throws
    func refreshContextualSuggestions(localDate: String) async throws
    func dismissContextualSuggestion(id: String) async throws
    func confirmContextualSuggestion(
        _ confirmation: SuggestionConfirmation
    ) async throws
    func createReadySeason() async throws
}

extension Repository {
    func loadPrivateProposals(
        for user: AuthenticatedUser
    ) async throws -> [SavedPrivateProposal] {
        []
    }

    func claimPrivateProposal(_ proposal: PrivateProposal) async throws
        -> String
    {
        throw RepositoryError.invalidData(
            "private proposals are unavailable"
        )
    }

    func offerPrivateProposal(id: String) async throws {
        throw RepositoryError.invalidData(
            "offering a private proposal is unavailable"
        )
    }

    func setPresence(_ mode: PresenceMode) async throws {
        throw RepositoryError.invalidData("presence is unavailable")
    }

    func setSignalConsent(
        _ signal: SignalKind,
        enabled: Bool
    ) async throws {
        throw RepositoryError.invalidData("signal consent is unavailable")
    }

    func createAnchor(
        _ input: AnchorInput,
        coupleID: String
    ) async throws {
        throw RepositoryError.invalidData("anchors are unavailable")
    }

    func setAnchorActive(id: String, isActive: Bool) async throws {
        throw RepositoryError.invalidData("anchors are unavailable")
    }

    func offerHandoff(
        responsibilityID: String,
        toProfileID: String
    ) async throws {
        throw RepositoryError.invalidData("handoffs are unavailable")
    }

    func respondToHandoff(id: String, accept: Bool) async throws {
        throw RepositoryError.invalidData("handoffs are unavailable")
    }

    func withdrawHandoff(id: String) async throws {
        throw RepositoryError.invalidData("handoffs are unavailable")
    }

    func setApproach(
        planID: String,
        approach: ApproachKind,
        note: String?
    ) async throws {
        throw RepositoryError.invalidData("approach is unavailable")
    }

    func refreshContextualSuggestions(localDate: String) async throws {
        throw RepositoryError.invalidData("suggestions are unavailable")
    }

    func dismissContextualSuggestion(id: String) async throws {
        throw RepositoryError.invalidData("suggestions are unavailable")
    }

    func confirmContextualSuggestion(
        _ confirmation: SuggestionConfirmation
    ) async throws {
        throw RepositoryError.invalidData("suggestions are unavailable")
    }

    func createReadySeason() async throws {
        throw RepositoryError.invalidData("a season is not ready")
    }
}

enum AuthCallbackResult: Equatable, Sendable {
    case emailConfirmed(AuthenticatedUser)
    case passwordRecovery(AuthenticatedUser)
}

enum RepositoryFactory {
    static func make(
        environment: AppEnvironment = .current
    ) -> any Repository {
        switch environment.repositoryMode {
        case .preview:
            PreviewRepository(
                scenario: environment.previewScenario,
                acceptedDeletionPassword:
                    environment.previewDeletionPassword
            )
        case .live:
            SupabaseRepository(
                provider: SupabaseClientProvider(
                    configuration: environment.supabase
                )
            )
        }
    }
}
