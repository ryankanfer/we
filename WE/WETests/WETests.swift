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
    func happyPathCreatesOnlyASafeSharedDirection() throws {
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

        #expect(state.responses["ry"]?.status == .submitted)
        #expect(state.responses["dylan"]?.status == .submitted)
        let projection = try #require(
            TrustCore.project(state, for: "dylan")
        )
        let direction = try #require(projection.sharedDirection)
        #expect(projection.phase == .shared)
        #expect(projection.partnerResponse == nil)
        #expect(projection.matched == nil)
        #expect(!direction.title.contains("Keep it"))
        #expect(!direction.message.contains("time away"))
    }

    @Test
    func differentAnswersStillProduceOnlyAReversibleDirection() throws {
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

        #expect(state.sharedDirection?.key == "shared-room")
        #expect(state.resolution == nil)

        state = try TrustCore.resolve(
            state,
            type: .leftOpen,
            at: 2
        )
        #expect(state.resolution?.type == .leftOpen)
        #expect(state.resolution?.choice == nil)
    }

    @Test
    func sharedDirectionCannotRevealAnswerContentOrEquality() throws {
        let privateChoices = [
            "Quiet and close",
            "Out of the house",
            "Playful and spontaneous",
            "A choice containing UNIQUE_PRIVATE_MARKER",
        ]
        var visibleDirections = Set<SharedDirection>()

        for firstChoice in privateChoices {
            for secondChoice in privateChoices {
                var state = TrustCore.initialState(
                    seedKey: "tonight-non-interference"
                )
                state = try TrustCore.requestReveal(
                    state,
                    by: "ry",
                    at: 0
                )
                state = try TrustCore.acceptReveal(
                    state,
                    by: "dylan",
                    at: 1
                )
                state = try TrustCore.submitResponse(
                    state,
                    by: "ry",
                    choice: firstChoice,
                    note: "FIRST_PRIVATE_NOTE"
                )
                state = try TrustCore.submitResponse(
                    state,
                    by: "dylan",
                    choice: secondChoice,
                    note: "SECOND_PRIVATE_NOTE"
                )
                visibleDirections.insert(
                    try #require(state.sharedDirection)
                )
            }
        }

        #expect(visibleDirections.count == 1)
        let visibleCopy = visibleDirections
            .map { "\($0.title) \($0.message)" }
            .joined(separator: " ")
        #expect(!visibleCopy.contains("UNIQUE_PRIVATE_MARKER"))
        #expect(!visibleCopy.contains("PRIVATE_NOTE"))
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
            (.signedOut, .signedOut),
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
        async throws
    {
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
        #expect(state.resolution?.choice == state.sharedDirection?.title)
        #expect(state.resolution?.choice != "Keep it")

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
            choice: "Out of the house",
            note: nil
        )
        var snapshot = try await repository.loadRelationship(
            for: PreviewData.user
        )
        let shared = try #require(snapshot.insights.first)
        #expect(
            shared.responses.allSatisfy {
                $0.status == .submitted
            }
        )
        #expect(shared.sharedDirection != nil)

        try await repository.resolveInsight(
            insightID: insightID,
            type: .settled,
            choice: "Out of the house"
        )
        snapshot = try await repository.loadRelationship(
            for: PreviewData.user
        )
        #expect(
            snapshot.insights.first?.consent?.resolutionChoice
                == snapshot.insights.first?.sharedDirection?.title
        )
    }

    @Test
    func legacyRevealedRowsBecomeSubmittedWithoutProjectingRawData() throws {
        let insight = try #require(PreviewData.insights.first)
        let record = InsightRecord(
            insight: insight,
            consent: InsightConsent(
                insightID: insight.id,
                visibility: .mutual,
                ownerID: nil,
                readiness: .accepted,
                initiatorID: "ry",
                requestedAt: nil,
                acceptedAt: nil,
                resolutionType: nil,
                resolutionChoice: nil
            ),
            responses: [
                InsightResponse(
                    insightID: insight.id,
                    profileID: "ry",
                    status: .revealed,
                    choice: "Quiet and close",
                    note: "OWNER_SECRET"
                ),
                InsightResponse(
                    insightID: insight.id,
                    profileID: "dylan",
                    status: .revealed,
                    choice: "Quiet and close",
                    note: "PARTNER_SECRET"
                ),
            ],
            dismissedBy: [],
            declinedBy: []
        )

        let state = record.trustState(memberIDs: ["ry", "dylan"])
        let projection = try #require(
            TrustCore.project(state, for: "ry")
        )
        #expect(projection.phase == .shared)
        #expect(projection.myResponse.status == .submitted)
        #expect(projection.partnerResponse == nil)
        #expect(projection.matched == nil)
        #expect(projection.sharedDirection?.message.contains("SECRET") == false)
    }

    @Test
    func previewRepositoryClaimsThenOffersAPrivateProposal() async throws {
        let repository = PreviewRepository()
        let proposal = PrivateProposal(
            id: UUID(),
            sourceNote: "A private note",
            title: "Make a little room for this",
            offeredTopic: OfferedTopic(
                title: "A little more room",
                question: "What would feel useful right now?",
                options: ["More quiet", "A simple plan"]
            ),
            preparationMethod: .deterministicFallback,
            createdAt: Date()
        )

        let proposalID = try await repository.claimPrivateProposal(proposal)
        #expect(proposalID == proposal.id.uuidString.lowercased())
        let saved = try await repository.loadPrivateProposals(
            for: PreviewData.user
        )
        #expect(saved.count == 1)
        #expect(saved.first?.id == proposalID)
        #expect(saved.first?.title == proposal.title)
        #expect(saved.first?.offeredTopic == proposal.offeredTopic)
        try await repository.offerPrivateProposal(id: proposalID)
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

    @Test
    func partySuggestionIsDeterministicAuditableAndDateAware() throws {
        for term in ContextualSuggestionEngine.partyTerms {
            let plan = testPlan(
                id: "plan-\(term)",
                title: "Saturday \(term)",
                scheduledOn: "2026-08-09"
            )
            let suggestion = try #require(
                ContextualSuggestionEngine.partyGroceries(
                    plans: [plan],
                    responsibilities: [],
                    now: testDate("2026-07-27T12:00:00Z")
                ).first
            )

            #expect(suggestion.title == "Add a grocery run to the shared list?")
            #expect(suggestion.proposedResponsibilityTitle == "Grocery run")
            #expect(suggestion.proposedScheduledOn == "2026-08-08")
            #expect(suggestion.relatedPlanID == plan.id)
            #expect(suggestion.evidence.context == "For \(plan.title)")
            #expect(suggestion.evidence.sharedInputs == suggestion.provenance.references)
            #expect(
                suggestion.provenance.references.allSatisfy {
                    $0.shared
                }
            )
        }
    }

    @Test
    func partySuggestionRespectsDismissalAndRelatedCare() {
        let plan = testPlan(
            id: "party-plan",
            title: "A gathering at home",
            scheduledOn: "2026-08-09"
        )
        let existing = Responsibility(
            id: "care",
            coupleID: "preview-couple",
            title: "Pick up food",
            note: nil,
            ownerID: nil,
            owner: .together,
            relatedPlanID: plan.id,
            status: .active,
            completedAt: nil,
            createdBy: "ryan",
            updatedBy: "ryan",
            createdAt: "2026-07-27T12:00:00Z",
            updatedAt: "2026-07-27T12:00:00Z"
        )

        #expect(
            ContextualSuggestionEngine.partyGroceries(
                plans: [plan],
                responsibilities: [existing]
            ).isEmpty
        )
        #expect(
            ContextualSuggestionEngine.partyGroceries(
                plans: [plan],
                responsibilities: [],
                dismissedPlanIDs: [plan.id]
            ).isEmpty
        )
    }

    @Test
    func questionActionsReflectBothAnswerOrders() async throws {
        let session = AppSession(
            repository: PreviewRepository(),
            cache: InMemoryRelationshipCache(),
            connectivity: ConnectivityMonitor(startImmediately: false)
        )
        await session.restoreIfNeeded()
        let answered = try #require(
            session.insightRecords.first {
                $0.id == "saturday-plan"
            }
        )
        let unanswered = InsightRecord(
            insight: answered.insight,
            consent: answered.consent,
            responses: [],
            dismissedBy: [],
            declinedBy: []
        )

        #expect(
            session.questionAction(for: unanswered)
                == .hold(partnerName: "Dylan")
        )
        #expect(
            session.questionAction(for: unanswered).title
                == "Hold my answer"
        )
        #expect(
            session.questionAction(for: unanswered).explanation
                == "Your answer is never shown to Dylan. If they answer too, WE opens a separate shared direction."
        )
        #expect(
            session.questionAction(for: answered)
                == .openTogether(partnerName: "Dylan")
        )
        #expect(
            session.questionAction(for: answered).explanation
                == "Dylan has answered. Continuing opens a separate shared direction on both sides."
        )
    }

    @Test
    func seasonReadinessEnforcesEveryBoundary() throws {
        let sixEvents = [
            testEvent(1, at: "2026-02-06T12:00:00Z", type: .planCompleted),
            testEvent(2, at: "2026-02-10T12:00:00Z", type: .planCompleted),
            testEvent(3, at: "2026-02-15T12:00:00Z", type: .planCompleted),
            testEvent(
                4,
                at: "2026-03-01T12:00:00Z",
                type: .responsibilityCompleted
            ),
            testEvent(
                5,
                at: "2026-03-05T12:00:00Z",
                type: .responsibilityCompleted
            ),
            testEvent(
                6,
                at: "2026-03-10T12:00:00Z",
                type: .responsibilityCompleted
            ),
        ]

        #expect(
            SeasonReadiness.evaluate(
                events: sixEvents,
                after: nil,
                now: testDate("2026-03-19T12:00:00Z")
            ) == .needsTime(weeksRemaining: 1)
        )
        #expect(
            SeasonReadiness.evaluate(
                events: Array(sixEvents.prefix(5)),
                after: nil,
                now: testDate("2026-04-01T12:00:00Z")
            ) == .needsEntries(countRemaining: 1)
        )

        let oneType = sixEvents.map {
            testEvent(
                Int($0.id.dropFirst()) ?? 0,
                at: $0.occurredAt,
                type: .planCompleted
            )
        }
        #expect(
            SeasonReadiness.evaluate(
                events: oneType,
                after: nil,
                now: testDate("2026-04-01T12:00:00Z")
            ) == .needsEventVariety(typesRemaining: 1)
        )

        let oneMonth = (1 ... 6).map {
            testEvent(
                $0,
                at: "2026-02-\(String(format: "%02d", $0 + 1))T12:00:00Z",
                type: $0.isMultiple(of: 2)
                    ? .planCompleted
                    : .responsibilityCompleted
            )
        }
        #expect(
            SeasonReadiness.evaluate(
                events: oneMonth,
                after: nil,
                now: testDate("2026-04-01T12:00:00Z")
            ) == .needsCalendarBreadth(monthsRemaining: 1)
        )

        guard case .ready(let eventIDs, _) = SeasonReadiness.evaluate(
            events: sixEvents,
            after: nil,
            now: testDate("2026-03-20T12:00:00Z")
        ) else {
            Issue.record("Six weeks, entries, types, and months should be ready")
            return
        }
        #expect(eventIDs == sixEvents.map(\.id))
    }

    @Test
    func laterSeasonUsesOnlyEventsAfterPreviousCutoff() {
        let older = (1 ... 6).map {
            testEvent(
                $0,
                at: "2026-02-\(String(format: "%02d", $0 + 1))T12:00:00Z",
                type: $0.isMultiple(of: 2)
                    ? .planCompleted
                    : .responsibilityCompleted
            )
        }
        let newerDates = [
            "2026-04-01T12:00:00Z",
            "2026-04-08T12:00:00Z",
            "2026-04-15T12:00:00Z",
            "2026-05-01T12:00:00Z",
            "2026-05-08T12:00:00Z",
            "2026-05-12T12:00:00Z",
        ]
        let newer = newerDates.enumerated().map {
            testEvent(
                $0.offset + 10,
                at: $0.element,
                type: $0.offset.isMultiple(of: 2)
                    ? .planCompleted
                    : .mutualResolution
            )
        }

        guard case .ready(let eventIDs, _) = SeasonReadiness.evaluate(
            events: older + newer,
            after: testDate("2026-03-01T12:00:00Z"),
            now: testDate("2026-05-13T12:00:00Z")
        ) else {
            Issue.record("Post-cutoff events independently satisfy a season")
            return
        }
        #expect(eventIDs == newer.map(\.id))
    }

    @Test
    func simulationSharesStateButKeepsDismissalsAndApproachesPrivate()
        async throws {
        let store = SimulationStore()
        let initial = await store.load(viewer: .ryan)
        let suggestion = try #require(initial.v2State.suggestions.first)
        let heldPartnerAnswer = try #require(
            initial.insights.first {
                $0.id == "saturday-plan"
            }?.responses.first {
                $0.profileID == "dylan"
            }
        )
        #expect(heldPartnerAnswer.status == .submitted)
        #expect(heldPartnerAnswer.choice == nil)
        #expect(heldPartnerAnswer.note == nil)

        await store.dismissSuggestion(id: suggestion.id, viewer: .ryan)
        let ryan = await store.load(viewer: .ryan)
        let dylan = await store.load(viewer: .dylan)
        #expect(
            ryan.v2State.suggestions.first?.dismissedForViewer == true
        )
        #expect(
            dylan.v2State.suggestions.first?.dismissedForViewer == false
        )

        await store.createPlan(
            PlanInput(
                title: "A day at the lake",
                note: nil,
                scheduledOn: nil
            ),
            viewer: .dylan
        )
        let seenByRyan = await store.load(viewer: .ryan)
        #expect(
            seenByRyan.plans.contains {
                $0.title == "A day at the lake"
            }
        )

        let planID = try #require(initial.plans.first?.id)
        await store.setApproach(
            planID: planID,
            approach: .gently,
            note: "Start softly",
            viewer: .ryan
        )
        let privateForDylan = await store.load(viewer: .dylan)
        #expect(
            privateForDylan.v2State.approaches.allSatisfy {
                $0.profileID != "ryan"
            }
        )
        await store.setApproach(
            planID: planID,
            approach: .directly,
            note: nil,
            viewer: .dylan
        )
        let stillPrivateForRyan = await store.load(viewer: .ryan)
        #expect(
            stillPrivateForRyan.v2State.approaches.count == 1
        )
        #expect(
            stillPrivateForRyan.v2State.approaches.first?.profileID == "ryan"
        )
        #expect(
            stillPrivateForRyan.v2State.approaches.first?.approach == .gently
        )
        #expect(
            stillPrivateForRyan.v2State.approaches.first?.note
                == "Start softly"
        )
        let stillPrivateForDylan = await store.load(viewer: .dylan)
        #expect(
            stillPrivateForDylan.v2State.approaches.count == 1
        )
        #expect(
            stillPrivateForDylan.v2State.approaches.first?.profileID == "dylan"
        )
    }

    @Test
    func dismissedSimulationSuggestionDoesNotReappearFromFallback()
        async throws
    {
        let store = SimulationStore()
        let session = AppSession(
            repository: SimulationRepository(
                store: store,
                viewer: .ryan
            ),
            cache: InMemoryRelationshipCache(),
            connectivity: ConnectivityMonitor(startImmediately: false)
        )
        await session.restoreIfNeeded()
        let suggestion = try #require(session.contextualSuggestions.first)

        await session.dismissContextualSuggestion(id: suggestion.id)

        #expect(session.contextualSuggestions.isEmpty)
        #expect(session.v2State.suggestions.first?.dismissedForViewer == true)
    }

    @Test
    func allTenHueControlsKeepWhiteTextAtAAContrast() {
        #expect(WEHue.allCases.count == 10)
        for hue in WEHue.allCases {
            #expect(
                whiteContrastRatio(on: hue.controlComponents) >= 4.5,
                Comment(
                    rawValue:
                        "\(hue.name) must remain contrast-safe for controls"
                )
            )
        }
    }

    @Test
    func protectedCacheRoundTripsV2RelationshipState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileRelationshipCache(directory: directory)
        let snapshot = await SimulationStore().load(viewer: .ryan)

        try await cache.save(snapshot, userID: "simulation-cache")
        let restored = try #require(
            try await cache.load(userID: "simulation-cache")
        )

        #expect(restored.version == CachedRelationship.currentVersion)
        #expect(restored.snapshot.v2State == snapshot.v2State)
        #expect(restored.snapshot.responsibilities == snapshot.responsibilities)
    }

    private func testPlan(
        id: String,
        title: String,
        scheduledOn: String?
    ) -> PlanItem {
        PlanItem(
            id: id,
            coupleID: "preview-couple",
            title: title,
            note: nil,
            scheduledOn: scheduledOn,
            status: .active,
            completedAt: nil,
            createdBy: "ryan",
            updatedBy: "ryan",
            createdAt: "2026-07-27T12:00:00Z",
            updatedAt: "2026-07-27T12:00:00Z"
        )
    }

    private func testEvent(
        _ number: Int,
        at occurredAt: String,
        type: RelationshipEventType
    ) -> RelationshipEvent {
        RelationshipEvent(
            id: "e\(number)",
            coupleID: "preview-couple",
            type: type,
            sourceID: "source-\(number)",
            title: "Shared event \(number)",
            occurredAt: occurredAt,
            provenance: [
                ProvenanceReference(
                    kind: type == .responsibilityCompleted
                        ? .responsibility
                        : .plan,
                    id: "source-\(number)",
                    label: "Shared event \(number)",
                    shared: true
                ),
            ]
        )
    }

    private func testDate(_ value: String) -> Date {
        ISO8601DateFormatter.we.date(from: value)!
    }

    private func whiteContrastRatio(
        on rgb: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let luminance = 0.2126 * linearized(rgb.red)
            + 0.7152 * linearized(rgb.green)
            + 0.0722 * linearized(rgb.blue)
        return 1.05 / (luminance + 0.05)
    }

    private func linearized(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}
