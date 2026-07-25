//
//  WETests.swift
//  WETests
//
//  Created by Ryan Kanfer on 7/24/26.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct WETests {
    @Test
    func happyPathRevealsBothAnswersTogether() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 1)

        #expect(state.readiness == .requested)
        #expect(TrustCore.project(state, for: "ry")?.phase == .waiting)
        #expect(TrustCore.project(state, for: "dylan")?.phase == .invited)

        state = try TrustCore.acceptReveal(state, by: "dylan", at: 2)
        #expect(state.visibility == .mutual)

        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Keep it",
            note: "I want the time away with you."
        )

        let dylanView = TrustCore.project(state, for: "dylan")
        #expect(dylanView?.partnerResponse == nil)
        #expect(dylanView?.phase == .answering)
        #expect(TrustCore.project(state, for: "ry")?.phase == .held)

        state = try TrustCore.submitResponse(
            state,
            by: "dylan",
            choice: "Keep it"
        )

        #expect(state.responses["ry"]?.status == .revealed)
        #expect(state.responses["dylan"]?.status == .revealed)
        #expect(TrustCore.answersMatch(state) == true)
        #expect(
            TrustCore.project(state, for: "dylan")?.partnerResponse?.note
                == "I want the time away with you."
        )
    }

    @Test
    func mismatchDoesNotDecideAnything() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        state = try TrustCore.acceptReveal(state, by: "dylan", at: 1)
        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Keep it"
        )
        state = try TrustCore.submitResponse(
            state,
            by: "dylan",
            choice: "Change it"
        )

        #expect(TrustCore.answersMatch(state) == false)
        #expect(state.resolution == nil)

        state = try TrustCore.resolve(
            state,
            type: .leftOpen,
            at: 2
        )
        #expect(state.resolution?.type == .leftOpen)
    }

    @Test
    func oneAnswerIsNeverProjectedBeforeBothSubmit() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "dylan", at: 0)
        state = try TrustCore.acceptReveal(state, by: "ry", at: 1)
        state = try TrustCore.saveDraft(
            state,
            by: "ry",
            choice: "Change it",
            note: "a private draft"
        )
        #expect(
            TrustCore.project(state, for: "dylan")?.partnerResponse == nil
        )

        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Change it",
            note: "a private note"
        )
        #expect(
            TrustCore.project(state, for: "dylan")?.partnerResponse == nil
        )
    }

    @Test
    func declineStaysPrivate() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        let before = TrustCore.project(state, for: "ry")

        state = try TrustCore.declineReveal(state, by: "dylan")
        let after = TrustCore.project(state, for: "ry")
        let invitee = TrustCore.project(state, for: "dylan")

        #expect(after?.phase == before?.phase)
        #expect(after?.phase == .waiting)
        #expect(invitee?.phase == .declined)
        #expect(state.declinedBy == ["dylan"])

        state = try TrustCore.acceptReveal(state, by: "dylan", at: 5)
        #expect(state.visibility == .mutual)
        #expect(state.declinedBy.isEmpty)
    }

    @Test
    func withdrawalLeavesNoPartnerTrace() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        state = try TrustCore.withdrawReveal(state, by: "ry")

        let dylanView = TrustCore.project(state, for: "dylan")
        #expect(dylanView?.phase == .open)
        #expect(dylanView?.initiatorID == nil)
        #expect(dylanView?.requestedAt == nil)
    }

    @Test
    func privateItemsStayHiddenFromNonOwner() {
        let state = TrustCore.initialState(
            visibility: .private,
            ownerID: "ry"
        )
        #expect(TrustCore.project(state, for: "dylan") == nil)
        #expect(TrustCore.project(state, for: "ry") != nil)
    }

    @Test
    func invalidTransitionsThrow() throws {
        var state = TrustCore.initialState()

        #expect(throws: TrustTransitionError.self) {
            try TrustCore.acceptReveal(state, by: "dylan", at: 0)
        }
        #expect(throws: TrustTransitionError.self) {
            try TrustCore.submitResponse(
                state,
                by: "ry",
                choice: "Keep it"
            )
        }

        state = try TrustCore.requestReveal(state, by: "ry", at: 0)

        #expect(throws: TrustTransitionError.self) {
            try TrustCore.acceptReveal(state, by: "ry", at: 1)
        }
        #expect(throws: TrustTransitionError.self) {
            try TrustCore.withdrawReveal(state, by: "dylan")
        }
        #expect(throws: TrustTransitionError.self) {
            try TrustCore.dismissSuggestion(state, by: "dylan")
        }
    }

    @Test
    func dismissalIsIndividual() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.dismissSuggestion(state, by: "ry")

        #expect(TrustCore.project(state, for: "ry")?.dismissed == true)
        #expect(TrustCore.project(state, for: "dylan")?.dismissed == false)
    }

    @Test
    func sessionRoutesEveryPreviewRelationshipState() async {
        let cases: [(PreviewScenario, AppSession.State)] = [
            (.ready, .ready),
            (.empty, .ready),
            (.waiting, .waitingForPartner),
            (.archived, .needsCouple),
            (.choosingHue, .choosingHue),
            (.signedOut, .signedOut)
        ]

        for (scenario, expected) in cases {
            let session = AppSession(
                repository: PreviewRepository(scenario: scenario),
                cache: InMemoryRelationshipCache(),
                connectivity: ConnectivityMonitor(startImmediately: false)
            )
            await session.restoreIfNeeded()
            #expect(session.state == expected)
        }
    }

    @Test
    func cachedSnapshotKeepsWEReadableWhenLoadingFails() async throws {
        let cache = InMemoryRelationshipCache()
        try await cache.save(
            PreviewData.snapshot,
            userID: PreviewData.user.id
        )
        let session = AppSession(
            repository: PreviewRepository(
                scenario: .error,
                user: PreviewData.user
            ),
            cache: cache,
            connectivity: ConnectivityMonitor(
                startImmediately: false,
                initiallyOnline: false
            )
        )

        await session.restoreIfNeeded()

        #expect(session.state == .ready)
        #expect(session.connectionState == .offline)
        #expect(session.snapshot == PreviewData.snapshot)
        #expect(session.cachedAt != nil)
        #expect(session.canMutate == false)
    }

    @Test
    func onlineLoadFailureNeverFallsBackToCachedRelationshipData()
        async throws {
        let cache = InMemoryRelationshipCache()
        try await cache.save(
            PreviewData.snapshot,
            userID: PreviewData.errorUser.id
        )
        let session = AppSession(
            repository: PreviewRepository(
                scenario: .error,
                user: PreviewData.errorUser
            ),
            cache: cache,
            connectivity: ConnectivityMonitor(
                startImmediately: false,
                initiallyOnline: true
            )
        )

        await session.restoreIfNeeded()

        guard case .failed = session.state else {
            Issue.record("An online data failure must be shown as a failure")
            return
        }
        #expect(session.snapshot == nil)
        #expect(session.cachedAt == nil)
    }

    @Test
    func connectionTransitionsFromOfflineBackToOnline() async throws {
        let connectivity = ConnectivityMonitor(
            startImmediately: false,
            initiallyOnline: false
        )
        let session = AppSession(
            repository: PreviewRepository(),
            cache: InMemoryRelationshipCache(),
            connectivity: connectivity
        )

        await session.restoreIfNeeded()
        #expect(session.connectionState == .offline)

        connectivity.setOnlineForTesting(true)
        try await Task.sleep(for: .milliseconds(100))

        #expect(session.connectionState == .online)
        #expect(session.state == .ready)
    }

    @Test
    func previewRepositorySupportsSharedItemLifecycle() async throws {
        let repository = PreviewRepository(scenario: .empty)

        try await repository.createPlan(
            PlanInput(
                title: "Meet at the museum",
                note: "After lunch",
                scheduledOn: "2026-08-09"
            ),
            coupleID: "preview-couple"
        )
        var snapshot = try await repository.loadRelationship(
            for: PreviewData.user
        )
        let plan = try #require(snapshot.plans.first)
        #expect(plan.title == "Meet at the museum")

        try await repository.updatePlan(
            id: plan.id,
            input: PlanInput(
                title: "Meet by the museum",
                note: nil,
                scheduledOn: nil
            )
        )
        try await repository.setPlanStatus(id: plan.id, status: .completed)

        try await repository.createResponsibility(
            ResponsibilityInput(
                title: "Call the landlord",
                note: nil,
                owner: .me
            ),
            coupleID: "preview-couple",
            ownerID: PreviewData.user.id
        )
        snapshot = try await repository.loadRelationship(for: PreviewData.user)
        let responsibility = try #require(snapshot.responsibilities.first)
        try await repository.updateResponsibility(
            id: responsibility.id,
            input: ResponsibilityInput(
                title: "Email the landlord",
                note: "About the window",
                owner: .together
            ),
            ownerID: nil
        )
        try await repository.setResponsibilityStatus(
            id: responsibility.id,
            status: .archived
        )

        snapshot = try await repository.loadRelationship(for: PreviewData.user)
        #expect(snapshot.plans.first?.title == "Meet by the museum")
        #expect(snapshot.plans.first?.status == .completed)
        #expect(snapshot.responsibilities.first?.title == "Email the landlord")
        #expect(snapshot.responsibilities.first?.owner == .together)
        #expect(snapshot.responsibilities.first?.status == .archived)
    }

    @Test
    func relationshipArchiveRoundTripsWithItsVersion() throws {
        let data = try JSONEncoder().encode(PreviewData.archive)
        let decoded = try JSONDecoder().decode(
            RelationshipArchive.self,
            from: data
        )

        #expect(decoded == PreviewData.archive)
        #expect(decoded.snapshotVersion == 1)
        #expect(decoded.snapshot.resolutions.count == 1)
    }

    @Test
    func signUpRoutesToVerificationPending() async {
        let pendingEmail = "held@example.com"
        let session = AppSession(
            repository: PreviewRepository(
                scenario: .signedOut,
                signUpResult: .verificationPending(email: pendingEmail)
            ),
            cache: InMemoryRelationshipCache(),
            connectivity: ConnectivityMonitor(startImmediately: false)
        )

        await session.signUp(
            name: "Held",
            email: pendingEmail,
            password: "a-secure-password"
        )

        #expect(session.state == .verificationPending(pendingEmail))
        #expect(session.user == nil)
        #expect(session.snapshot == nil)
    }

    @Test
    func recoveryCallbackRequiresANewPasswordBeforeLoadingWE() async throws {
        let session = AppSession(
            repository: PreviewRepository(),
            cache: InMemoryRelationshipCache(),
            connectivity: ConnectivityMonitor(startImmediately: false)
        )
        let url = try #require(
            URL(string: "we://password-recovery?code=preview")
        )

        await session.handleAuthCallback(url)
        #expect(session.state == .resettingPassword)
        #expect(session.user == PreviewData.user)
        #expect(session.snapshot == nil)

        await session.completePasswordRecovery("a-new-password")
        #expect(session.state == .ready)
        #expect(session.snapshot != nil)
        #expect(session.noticeMessage == "Your password has been updated.")
    }

    @Test
    func completedResolutionCannotBeOverwritten() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        state = try TrustCore.acceptReveal(state, by: "dylan", at: 1)
        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Keep it"
        )
        state = try TrustCore.submitResponse(
            state,
            by: "dylan",
            choice: "Keep it"
        )
        state = try TrustCore.resolve(
            state,
            type: .settled,
            at: 2,
            choice: "Keep it"
        )

        #expect(throws: TrustTransitionError.self) {
            try TrustCore.resolve(
                state,
                type: .released,
                at: 3
            )
        }
    }

    @Test
    func previewRepositorySupportsPrivateMatchTransition() async throws {
        let repository = PreviewRepository()
        let insightID = try #require(PreviewData.insights.first?.id)

        try await repository.submitResponse(
            insightID: insightID,
            choice: "The little Thai place",
            note: nil
        )
        var snapshot = try await repository.loadRelationship(
            for: PreviewData.user
        )
        let revealed = try #require(snapshot.insights.first)
        #expect(
            revealed.responses.allSatisfy {
                $0.status == .revealed
            }
        )

        try await repository.resolveInsight(
            insightID: insightID,
            type: .settled,
            choice: "The little Thai place"
        )
        snapshot = try await repository.loadRelationship(
            for: PreviewData.user
        )
        #expect(
            snapshot.insights.first?.consent?.resolutionChoice
                == "The little Thai place"
        )
    }

    @Test
    func fileCacheRoundTripsPurgesAndRejectsUnknownVersions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileRelationshipCache(directory: directory)
        let userID = "cache-user"

        try await cache.save(PreviewData.snapshot, userID: userID)
        let loaded = try await cache.load(userID: userID)
        #expect(loaded?.version == CachedRelationship.currentVersion)
        #expect(loaded?.snapshot.profile == PreviewData.snapshot.profile)
        #expect(loaded?.snapshot.members == PreviewData.snapshot.members)
        #expect(loaded?.snapshot.insights == PreviewData.snapshot.insights)
        #expect(loaded?.snapshot.plans == PreviewData.snapshot.plans)
        #expect(
            loaded?.snapshot.responsibilities
                == PreviewData.snapshot.responsibilities
        )

        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory
                .appendingPathComponent("\(userID).json")
                .path
        )
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }

        try await cache.remove(userID: userID)
        #expect(try await cache.load(userID: userID) == nil)

        try await cache.save(PreviewData.snapshot, userID: userID)
        let invalid = CachedRelationship(
            version: CachedRelationship.currentVersion + 1,
            snapshot: PreviewData.snapshot,
            savedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(invalid).write(
            to: directory.appendingPathComponent("\(userID).json"),
            options: .atomic
        )

        #expect(try await cache.load(userID: userID) == nil)
    }

    @Test
    func wrongDeletionPasswordKeepsTheSignedInSession() async throws {
        let cache = InMemoryRelationshipCache()
        let session = AppSession(
            repository: PreviewRepository(
                acceptedDeletionPassword: "correct-password"
            ),
            cache: cache,
            connectivity: ConnectivityMonitor(startImmediately: false)
        )

        await session.restoreIfNeeded()
        await session.deleteAccount(password: "wrong-password")

        #expect(session.state == .ready)
        #expect(session.user == PreviewData.user)
        #expect(session.snapshot == PreviewData.snapshot)
        #expect(session.errorMessage != nil)
        #expect(try await cache.load(userID: PreviewData.user.id) == nil)
    }

    @Test
    func signOutPurgesTheProtectedRelationshipCache() async throws {
        let cache = InMemoryRelationshipCache()
        let session = AppSession(
            repository: PreviewRepository(),
            cache: cache,
            connectivity: ConnectivityMonitor(startImmediately: false)
        )

        await session.restoreIfNeeded()
        #expect(try await cache.load(userID: PreviewData.user.id) != nil)

        await session.signOut()

        #expect(session.state == .signedOut)
        #expect(try await cache.load(userID: PreviewData.user.id) == nil)
    }
}
