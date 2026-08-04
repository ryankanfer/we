//
//  FieldPurgeAndLoadStateTests.swift
//  WETests
//
//  Phase 1d and 1e.
//
//  The purge test asserts that the container is empty afterwards, rather than
//  asserting that four particular removals happened. That distinction is the
//  whole point of the phase: a test that names the four things it knows about
//  passes forever while a fifth thing quietly accumulates on somebody's phone.
//

import Foundation
import Testing
@testable import WE

// MARK: - 1d. Leaving means leaving

@MainActor
struct WELocalDataTests {
    /// A whole container per test — the real `WELocalData()` points at the
    /// app's own Application Support, and a test that purged it would delete a
    /// developer's captured crash reports and queued writes.
    private func sandbox() -> (WELocalData, URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "WELocalDataTests-\(UUID().uuidString)")
        let suite = "WELocalDataTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        var subject = WELocalData()
        subject.outbox = FieldOutboxStore(
            directory: root.appending(path: "outbox")
        )
        subject.fieldState = FieldStateCache(
            directory: root.appending(path: "state")
        )
        subject.diagnostics = WEDiagnosticsStore(
            directory: root.appending(path: "diagnostics")
        )
        subject.defaults = defaults
        subject.cancelNotifications = {}

        return (subject, root, defaults)
    }

    private func partition() -> FieldOutboxPartition {
        FieldOutboxPartition(userID: "user-1", coupleID: "couple-1")
    }

    private func fill(_ subject: WELocalData) {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        subject.outbox.save(
            [FieldOutboxEntry(
                mutation: .deleteItem(id: "item-1"),
                queuedAt: now
            )],
            for: partition()
        )
        subject.fieldState.save(
            FieldState.empty(nameA: "Ryan", nameB: "Sam", now: now),
            for: partition(),
            at: now
        )
        subject.diagnostics.write(
            WEDiagnosticPayload(
                begin: now,
                end: now,
                json: Data(#"{"crashDiagnostics":[{}]}"#.utf8),
                summary: ["Crash — test"]
            )
        )
        subject.defaults.set("ABC123", forKey: PendingInvitation.defaultsKey)
    }

    /// The plan's acceptance test, stated the way the plan states it.
    @Test
    func nothingSurvivesSigningOut() throws {
        let (subject, root, defaults) = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        fill(subject)

        // Everything really is there first, or the assertion below proves
        // nothing at all.
        for directory in subject.directories {
            #expect(
                FileManager.default.fileExists(atPath: directory.path),
                "\(directory.lastPathComponent) should exist before the purge"
            )
        }
        #expect(defaults.string(forKey: PendingInvitation.defaultsKey) != nil)

        subject.purge()

        for directory in subject.directories {
            #expect(
                !FileManager.default.fileExists(atPath: directory.path),
                "\(directory.lastPathComponent) survived the purge"
            )
        }
        for key in subject.defaultsKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    /// The gap the plan names explicitly: `FieldMomentDelivery.cancel()` was
    /// called from the account surface and from neither pre-couple sign-out
    /// button. It is part of the list now, so it cannot be reached from one
    /// exit and missed by another.
    @Test
    func thePurgeCancelsWhatWasScheduled() {
        let (base, root, _) = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        var cancelled = false
        var subject = base
        subject.cancelNotifications = { cancelled = true }

        subject.purge()

        #expect(cancelled)
    }

    /// Queues belonging to an account this device has since forgotten must go
    /// too — the purge removes containers, not the partitions it can name.
    @Test
    func aForgottenAccountsQueueGoesWithTheRest() {
        let (subject, root, _) = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stranger = FieldOutboxPartition(
            userID: "someone-who-signed-in-last-year",
            coupleID: "couple-9"
        )
        subject.outbox.save(
            [FieldOutboxEntry(
                mutation: .deleteItem(id: "x"),
                queuedAt: now
            )],
            for: stranger
        )

        subject.purge()

        #expect(subject.outbox.load(stranger).isEmpty)
    }

    /// A purge cannot stop at the first thing it fails to remove — that would
    /// leave more behind than one that carries on. Nothing exists here, so
    /// every removal is a no-op, and all of them must still run.
    @Test
    func purgingAnEmptyContainerIsHarmless() {
        let (base, root, _) = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        var cancelled = false
        var subject = base
        subject.cancelNotifications = { cancelled = true }

        subject.purge()
        subject.purge()

        #expect(cancelled, "it reached the end both times")
    }
}

// MARK: - 1e. Not knowing, said honestly

@MainActor
struct FieldLoadStateTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Fails every load, so "could not reach the server" can be told apart
    /// from "this couple has nothing".
    private final class UnreachableBackend: FieldBackend, @unchecked Sendable {
        let viewerOwner: FieldOwner = .a
        struct Offline: Error {}

        func load() async throws -> FieldState { throw Offline() }
        func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
        func append(_ capture: FieldCapture) async throws {}
        func record(_ correction: FieldCorrection) async throws {}
        func upsert(_ item: LifeItem) async throws {}
        func delete(itemID: String) async throws {}
        func upsert(_ horizon: FieldHorizon) async throws {}
        func upsert(_ cluster: FieldCluster) async throws {}
        func answer(question: String, choice: String) async throws {}
        func setHeld(_ topic: FieldHeldTopic) async throws {}
        func setStandingRule(_ rule: FieldStandingRule) async throws {}
        func setIdentity(_ identity: FieldIdentity) async throws {}
        func setDailyMoment(_ moment: FieldDailyMoment) async throws {}
    }

    private func emptyState() -> FieldState {
        FieldState.empty(nameA: "Ryan", nameB: "Sam", now: Self.now)
    }

    /// The failure this phase exists to make impossible: a couple with history
    /// and no signal being told their relationship is empty.
    @Test
    func aFailedLoadWithACacheReadsAsStaleRatherThanEmpty() async {
        let store = FieldStore(
            state: emptyState(),
            now: Self.now,
            backend: UnreachableBackend(),
            lastLoadedAt: Self.now.addingTimeInterval(-86_400)
        )

        await store.load()

        #expect(store.loadState == .stale(Self.now.addingTimeInterval(-86_400)))
    }

    /// Nothing cached and nothing reachable is the one state that offers a
    /// retry, because it is the only one where the screen is blank and the
    /// person cannot tell why.
    @Test
    func aFailedLoadWithNoCacheReadsAsFailed() async {
        let store = FieldStore(
            state: emptyState(),
            now: Self.now,
            backend: UnreachableBackend()
        )

        await store.load()

        #expect(store.loadState == .failed)
    }

    /// No backend is the gallery and the previews. What is on hand is the
    /// whole truth there, and a retry would be offered for a load that is
    /// never going to happen.
    @Test
    func noBackendIsLoadedRatherThanFailed() async {
        let store = FieldStore(state: emptyState(), now: Self.now)

        await store.load()

        #expect(store.loadState == .loaded)
    }

    @Test
    func aSuccessfulLoadIsLoaded() async {
        let store = FieldStore(
            state: emptyState(),
            now: Self.now,
            backend: FieldMemoryBackend(state: emptyState())
        )

        await store.load()

        #expect(store.loadState == .loaded)
        #expect(store.lastLoadedAt == Self.now)
    }

    /// Retrying while still offline must not silently fall back to `.failed`
    /// when there *is* something cached — the honest answer is still "last
    /// seen", and losing it would blank a screen that had content a moment
    /// earlier.
    @Test
    func retryingWhileStillOfflineKeepsSayingLastSeen() async {
        let seen = Self.now.addingTimeInterval(-3 * 86_400)
        let store = FieldStore(
            state: emptyState(),
            now: Self.now,
            backend: UnreachableBackend(),
            lastLoadedAt: seen
        )

        await store.load()
        await store.retryLoad()

        #expect(store.loadState == .stale(seen))
    }

    // MARK: The wording

    @Test
    func lastSeenIsCountedInDaysRatherThanMinutes() {
        let line = { (days: Int) in
            FieldLoadStateLine.lastSeen(
                Self.now.addingTimeInterval(TimeInterval(-86_400 * days)),
                now: Self.now
            )
        }

        #expect(line(0) == "Last seen today")
        #expect(line(1) == "Last seen yesterday")
        #expect(line(4) == "Last seen 4 days ago")
    }
}
