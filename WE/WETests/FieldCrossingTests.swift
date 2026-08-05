//
//  FieldCrossingTests.swift
//  WETests
//
//  The client half of 2a. The database half is proved in pgTAP; this proves
//  the rules that decide whether anybody is ever asked, and that declining is
//  as durable as accepting.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct FieldCrossingTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Reports a solo backlog and records what was asked of it.
    private final class CrossingBackend: FieldBackend, @unchecked Sendable {
        struct Unreachable: Error {}

        let viewerOwner: FieldOwner = .a
        var count: Int
        /// When true, `shareSoloHistory` throws — the network was not there,
        /// or the RPC refused.
        var shareFails: Bool
        private(set) var shareCalls = 0

        init(count: Int, shareFails: Bool = false) {
            self.count = count
            self.shareFails = shareFails
        }

        func soloHistoryCount() async throws -> Int { count }

        func shareSoloHistory() async throws -> Int {
            shareCalls += 1
            if shareFails { throw Unreachable() }
            let moved = count
            count = 0
            return moved
        }

        func load() async throws -> FieldState {
            FieldState.empty(nameA: "Ryan", nameB: "Sam", now: now)
        }
        func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
        func append(_ capture: FieldCapture) async throws {}
        func record(_ correction: FieldCorrection) async throws {}
        func upsert(_ item: LifeItem) async throws {}
        func delete(itemID: String) async throws {}
        func upsert(_ horizon: FieldHorizon) async throws {}
        func upsert(_ evidence: FieldEvidence) async throws {}
        func upsert(_ cluster: FieldCluster) async throws {}
        func answer(question: String, choice: String) async throws {}
        func setHeld(_ topic: FieldHeldTopic) async throws {}
        func setStandingRule(_ rule: FieldStandingRule) async throws {}
        func setIdentity(_ identity: FieldIdentity) async throws {}
        func setDailyMoment(_ moment: FieldDailyMoment) async throws {}
    }

    private func decision(
        user: String = "user-1",
        couple: String = "couple-1"
    ) -> (FieldCrossingDecision, UserDefaults) {
        let suite = "FieldCrossingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            FieldCrossingDecision(
                userID: user, coupleID: couple, defaults: defaults
            ),
            defaults
        )
    }

    private func makeStore(backend: FieldBackend) -> FieldStore {
        FieldStore(
            state: FieldState.empty(nameA: "Ryan", nameB: "Sam", now: Self.now),
            now: Self.now,
            backend: backend
        )
    }

    // MARK: Whether anybody is asked at all

    @Test
    func aSoloBacklogIsWorthAsking() async {
        let (decision, _) = decision()
        let store = makeStore(backend: CrossingBackend(count: 12))

        await store.considerCrossing(decision: decision)

        #expect(store.soloHistoryCount == 12)
        #expect(store.owesCrossingDecision)
    }

    /// Somebody who paired on their first day has no solo history, and asking
    /// them what to do with nothing is a dialog about an empty set.
    @Test
    func nothingWrittenAloneMeansNoQuestion() async {
        let (decision, _) = decision()
        let store = makeStore(backend: CrossingBackend(count: 0))

        await store.considerCrossing(decision: decision)

        #expect(!store.owesCrossingDecision)
    }

    /// The whole point of recording a refusal: "keep it to myself" must not
    /// quietly mean "ask me again tomorrow".
    @Test
    func decliningIsRememberedAcrossLaunches() async {
        let (decision, defaults) = decision()
        let first = makeStore(backend: CrossingBackend(count: 5))

        await first.considerCrossing(decision: decision)
        #expect(first.owesCrossingDecision)

        first.keepSoloHistoryPrivate(decision: decision)
        #expect(!first.owesCrossingDecision)

        // A new process, the same device, the same still-private backlog.
        let relaunched = makeStore(backend: CrossingBackend(count: 5))
        let sameDecision = FieldCrossingDecision(
            userID: "user-1", coupleID: "couple-1", defaults: defaults
        )
        await relaunched.considerCrossing(decision: sameDecision)

        #expect(
            !relaunched.owesCrossingDecision,
            "the answer was no, and no is an answer"
        )
    }

    @Test
    func acceptingIsAlsoRememberedAndActuallyCrosses() async {
        let (decision, _) = decision()
        let backend = CrossingBackend(count: 3)
        let store = makeStore(backend: backend)

        await store.considerCrossing(decision: decision)
        let moved = await store.shareSoloHistory(decision: decision)

        #expect(moved == 3)
        #expect(backend.shareCalls == 1)
        #expect(!store.owesCrossingDecision)
        #expect(decision.wasAnswered)
    }

    /// The failure that would otherwise be silent: tapping "bring it across",
    /// having the request fail, and never being asked again — with nothing
    /// shared. A request that moved nothing is not an answer.
    @Test
    func aFailedCrossingIsNotAnAnswer() async {
        let (decision, defaults) = decision()
        let backend = CrossingBackend(count: 7, shareFails: true)
        let store = makeStore(backend: backend)

        await store.considerCrossing(decision: decision)
        let moved = await store.shareSoloHistory(decision: decision)

        #expect(moved == nil)
        #expect(backend.shareCalls == 1)
        #expect(
            store.owesCrossingDecision,
            "nothing crossed, so the question is still open"
        )
        #expect(
            !decision.wasAnswered,
            "and it must still be open on the next launch"
        )

        // The next launch, on the same device, with the backlog still private.
        let relaunched = makeStore(backend: CrossingBackend(count: 7))
        let sameDecision = FieldCrossingDecision(
            userID: "user-1", coupleID: "couple-1", defaults: defaults
        )
        await relaunched.considerCrossing(decision: sameDecision)
        #expect(relaunched.owesCrossingDecision)
    }

    /// The same failure, then a retry that works. The retry is what records
    /// the answer, and it records it once.
    @Test
    func retryingAfterAFailureCrossesAndRemembers() async {
        let (decision, _) = decision()
        let backend = CrossingBackend(count: 7, shareFails: true)
        let store = makeStore(backend: backend)

        await store.considerCrossing(decision: decision)
        #expect(await store.shareSoloHistory(decision: decision) == nil)

        backend.shareFails = false
        let moved = await store.shareSoloHistory(decision: decision)

        #expect(moved == 7)
        #expect(backend.shareCalls == 2)
        #expect(!store.owesCrossingDecision)
        #expect(decision.wasAnswered)
    }

    /// A person who leaves one relationship and begins another is owed the
    /// question again — the key carries both halves for the same reason the
    /// outbox partition does.
    @Test
    func aNewRelationshipAsksAgain() async {
        let (first, defaults) = decision(couple: "couple-1")
        let store = makeStore(backend: CrossingBackend(count: 4))

        await store.considerCrossing(decision: first)
        store.keepSoloHistoryPrivate(decision: first)

        let second = FieldCrossingDecision(
            userID: "user-1", coupleID: "couple-2", defaults: defaults
        )
        #expect(!second.wasAnswered)

        let afterwards = makeStore(backend: CrossingBackend(count: 4))
        await afterwards.considerCrossing(decision: second)
        #expect(afterwards.owesCrossingDecision)
    }

    /// No backend is the gallery and the previews. The protocol default
    /// returns zero, so the disclosure can never appear over a fictional
    /// couple.
    @Test
    func theGalleryIsNeverAskedToCrossAnything() async {
        let (decision, _) = decision()
        let store = FieldStore(now: Self.now)

        await store.considerCrossing(decision: decision)

        #expect(!store.owesCrossingDecision)
    }

    // MARK: The purge contract

    /// Registered in `WELocalData` (1d). Without this the next person to sign
    /// in on the phone inherits an answer about private history they never
    /// gave.
    @Test
    func signingOutForgetsTheAnswer() {
        let (decision, defaults) = decision()
        decision.remember()
        #expect(decision.wasAnswered)

        var subject = WELocalData()
        subject.defaults = defaults
        subject.cancelNotifications = {}
        let root = FileManager.default.temporaryDirectory
            .appending(path: "FieldCrossingTests-\(UUID().uuidString)")
        subject.outbox = FieldOutboxStore(directory: root.appending(path: "o"))
        subject.fieldState = FieldStateCache(directory: root.appending(path: "s"))
        subject.diagnostics = WEDiagnosticsStore(directory: root.appending(path: "d"))
        defer { try? FileManager.default.removeItem(at: root) }

        subject.purge()

        #expect(!decision.wasAnswered)
    }
}
