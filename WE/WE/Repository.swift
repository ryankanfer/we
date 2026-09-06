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

    /// Whether this repository keeps credentials somewhere that survives the
    /// app being deleted.
    ///
    /// True only for Supabase, which stores its session in the Keychain —
    /// and the Keychain outlives an uninstall, so a reinstall comes back
    /// signed in as whoever used the phone last. `AppSession` clears them on
    /// the first launch of a new install; the in-memory repositories have
    /// nothing to clear and must not be asked to.
    var persistsCredentialsAcrossInstalls: Bool { get }

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

    /// Issues a fresh invitation, revoking any live one in the same
    /// transaction. "I sent it to the wrong person" has to mean the old code
    /// stops working at the instant the new one starts.
    func createInvitation() async throws

    /// Withdraws the live invitation without waiting for it to expire.
    func revokeInvitation() async throws

    /// Who is waiting, for whoever holds this code.
    ///
    /// Answerable with no account and no session, because the person asking
    /// has neither yet. `nil` for anything that is not a live invitation, and
    /// `nil` says only that: a withdrawn code, an expired one, a spent one and
    /// a code that never existed are indistinguishable here on purpose. The
    /// four are told apart at redemption, where somebody has actually
    /// committed to spending one.
    func invitationGreeting(code: String) async throws -> InvitationGreeting?

    /// Closes an invitation from the invited person's side.
    ///
    /// The same revocation the inviter's own withdraw performs, authorised by
    /// holding the code rather than by a session, because the person declining
    /// has no account and must not need one in order to say no. Nothing
    /// records that a decline is what happened; see the migration.
    func declineInvitation(code: String) async throws

    /// Persists this device's push token against this person, and only this
    /// person. Owner only in both directions: a partner must never be able to
    /// read the other's devices.
    func registerDeviceToken(_ token: String) async throws

    /// Forgets every device this person has registered. A token left behind
    /// after a sign out is a phone that keeps being invited into somebody
    /// else's relationship.
    func forgetDeviceTokens() async throws

    /// Records that the survivor has been told their partner left, so the
    /// interface never raises it again.
    func acknowledgeDeparture() async throws
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
        note: String?,
        consentsToAIProcessing: Bool
    ) async throws
    func passJourneyQuestion(insightID: String) async throws
    func recordJourneyQuestionShown(insightID: String) async throws
    func confirmSharedDirection(
        insightID: String,
        decision: DirectionDecision
    ) async throws
    /// One person's half of ending a journey. The journey closes when both
    /// have called it; a single call is recorded and nothing else changes.
    func completeFieldJourney(journeyID: String) async throws
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
    func recordJourneyQuestionShown(insightID: String) async throws {}

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

extension Repository {
    /// Only a real backend has anything outliving the app bundle.
    var persistsCredentialsAcrossInstalls: Bool { false }
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
            // The shared client, never a new one — see
            // `SupabaseClientProvider`.
            SupabaseRepository(provider: .shared)
        }
    }
}
