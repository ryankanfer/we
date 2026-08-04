//
//  FieldOutboxTests.swift
//  WETests
//
//  The five ways an outbox goes wrong, from the plan, plus the two the plan
//  did not name and the implementation found anyway.
//
//  These are written against a fake server that applies mutations to its own
//  `FieldState`, rather than against a mock that counts calls. The difference
//  matters for the first test below: "committed but timed out" is only
//  meaningful if the server *actually commits* before the failure, and a call
//  counter cannot tell you whether the second send produced a second row.
//

import Foundation
import Testing
@testable import WE

// MARK: - A server that can fail in the specific ways that matter

@MainActor
private final class FakeFieldServer: FieldBackend, @unchecked Sendable {
    let viewerOwner: FieldOwner = .a

    /// What the server believes, built by applying every accepted mutation.
    private(set) var state: FieldState

    /// How many sends to reject before accepting anything. Models a phone
    /// that is simply offline.
    var failuresRemaining = 0

    /// Commit, *then* fail. The dangerous case: the write landed and the
    /// client will never know it.
    var commitsBeforeFailing = false

    private(set) var receivedCount = 0

    init(state: FieldState) {
        self.state = state
    }

    struct Offline: Error {}

    private func receive(_ mutation: FieldMutation) throws {
        receivedCount += 1

        if commitsBeforeFailing {
            mutation.apply(to: &state)
            commitsBeforeFailing = false
            throw Offline()
        }

        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Offline()
        }

        mutation.apply(to: &state)
    }

    func load() async throws -> FieldState { state }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func append(_ capture: FieldCapture) async throws {
        try receive(.append(capture))
    }
    func record(_ correction: FieldCorrection) async throws {
        try receive(.record(correction))
    }
    func upsert(_ item: LifeItem) async throws {
        try receive(.upsertItem(item))
    }
    func delete(itemID: String) async throws {
        try receive(.deleteItem(id: itemID))
    }
    func upsert(_ horizon: FieldHorizon) async throws {
        try receive(.upsertHorizon(horizon))
    }
    func upsert(_ cluster: FieldCluster) async throws {
        try receive(.upsertCluster(cluster))
    }
    func answer(question: String, choice: String) async throws {
        try receive(.answer(question: question, choice: choice))
    }
    func setHeld(_ topic: FieldHeldTopic) async throws {
        try receive(.setHeld(topic))
    }
    func setStandingRule(_ rule: FieldStandingRule) async throws {
        try receive(.setStandingRule(rule))
    }
    func setIdentity(_ identity: FieldIdentity) async throws {
        try receive(.setIdentity(identity))
    }
    func setDailyMoment(_ moment: FieldDailyMoment) async throws {
        try receive(.setDailyMoment(moment))
    }
}

// MARK: -

@MainActor
struct FieldOutboxTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func emptyState() -> FieldState {
        FieldState.empty(nameA: "Ryan", nameB: "Sam", now: Self.now)
    }

    private func store() -> FieldOutboxStore {
        FieldOutboxStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "FieldOutboxTests-\(UUID().uuidString)")
        )
    }

    private func partition(
        user: String = "user-1",
        couple: String = "couple-1"
    ) -> FieldOutboxPartition {
        FieldOutboxPartition(userID: user, coupleID: couple)
    }

    private func item(
        id: String = "item-1",
        title: String = "Call the plumber"
    ) -> LifeItem {
        LifeItem(
            id: id,
            title: title,
            category: .notes,
            owner: .a,
            source: .captured,
            isTimeCritical: false,
            isDone: false
        )
    }

    // MARK: 1. Committed, then timed out

    /// The plan's first named failure, and the one that decides whether an
    /// outbox is safe to have at all. The server accepts the write and the
    /// response never arrives, so the client retries something that already
    /// happened. One row must exist afterwards, not two.
    @Test
    func aWriteThatCommittedAndThenTimedOutIsNotDuplicated() async throws {
        let store = store()
        defer { store.removeAll() }

        let server = FakeFieldServer(state: emptyState())
        server.commitsBeforeFailing = true

        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition(),
            store: store,
            now: { Self.now }
        )

        // The write commits on the server and the client sees a failure.
        await #expect(throws: (any Error).self) {
            try await outbox.upsert(self.item())
        }
        #expect(server.state.lifeItems.count == 1)
        #expect(outbox.pending.count == 1, "it must still believe it is unsent")

        // The retry sends the same mutation again.
        try await outbox.flush()

        #expect(server.receivedCount == 2, "it really did send twice")
        #expect(
            server.state.lifeItems.count == 1,
            "and the second send wrote nothing new"
        )
        #expect(outbox.isEmpty)
    }

    // MARK: 2. A reload arriving while a write is pending

    /// The plan's second named failure. Realtime delivers a snapshot that
    /// predates a queued write; returning it unmodified would take what
    /// somebody just typed off the screen while the app is working correctly.
    @Test
    func aReloadDoesNotEraseAPendingWrite() async throws {
        let store = store()
        defer { store.removeAll() }

        let server = FakeFieldServer(state: emptyState())
        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition(),
            store: store,
            now: { Self.now }
        )

        server.failuresRemaining = 99
        await #expect(throws: (any Error).self) {
            try await outbox.upsert(self.item(title: "Book the ferry"))
        }

        // The server knows nothing about it.
        #expect(server.state.lifeItems.isEmpty)

        // The app, reloading, still has to see it.
        let loaded = try await outbox.load()
        #expect(loaded.lifeItems.map(\.title) == ["Book the ferry"])
    }

    /// And the replay must not resurrect what it already sent — otherwise
    /// every load doubles the queue's contents onto the server's.
    @Test
    func aReloadAfterASuccessfulSendShowsTheRowOnlyOnce() async throws {
        let store = store()
        defer { store.removeAll() }

        let server = FakeFieldServer(state: emptyState())
        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition(),
            store: store,
            now: { Self.now }
        )

        try await outbox.upsert(item())
        let loaded = try await outbox.load()

        #expect(outbox.isEmpty)
        #expect(loaded.lifeItems.count == 1)
    }

    // MARK: 3. An account switch with writes still queued

    /// The plan's third named failure. Two partitions, one device. A write
    /// queued for one relationship must be invisible to the other — this is
    /// the privacy half of the phase, not just the correctness half.
    @Test
    func queuedWritesCannotCrossIntoAnotherCouple() async throws {
        let store = store()
        defer { store.removeAll() }

        let first = FakeFieldServer(state: emptyState())
        first.failuresRemaining = 99

        let hers = FieldOutbox(
            wrapping: first,
            partition: partition(user: "user-1", couple: "couple-1"),
            store: store,
            now: { Self.now }
        )
        await #expect(throws: (any Error).self) {
            try await hers.upsert(self.item(title: "Ours, privately"))
        }
        #expect(hers.pending.count == 1)

        // A different account on the same phone.
        let second = FakeFieldServer(state: emptyState())
        let theirs = FieldOutbox(
            wrapping: second,
            partition: partition(user: "user-2", couple: "couple-2"),
            store: store,
            now: { Self.now }
        )

        #expect(theirs.isEmpty, "the other queue must not be adopted")

        try await theirs.flush()
        let loaded = try await theirs.load()

        #expect(second.receivedCount == 0)
        #expect(loaded.lifeItems.isEmpty)
    }

    /// The same user, a new relationship. The couple half of the partition is
    /// load-bearing on its own.
    @Test
    func queuedWritesDoNotFollowAPersonIntoANewRelationship() async throws {
        let store = store()
        defer { store.removeAll() }

        let before = FakeFieldServer(state: emptyState())
        before.failuresRemaining = 99
        let old = FieldOutbox(
            wrapping: before,
            partition: partition(user: "user-1", couple: "couple-1"),
            store: store,
            now: { Self.now }
        )
        await #expect(throws: (any Error).self) {
            try await old.upsert(self.item())
        }

        let after = FakeFieldServer(state: emptyState())
        let new = FieldOutbox(
            wrapping: after,
            partition: partition(user: "user-1", couple: "couple-2"),
            store: store,
            now: { Self.now }
        )

        #expect(new.isEmpty)
    }

    // MARK: 4. A deletion made before the phone reconnected

    /// The plan's fourth named failure. Create, edit, edit, delete — all
    /// offline. The server must not be told about a row that was already gone
    /// before it heard of it.
    @Test
    func aDeleteMadeOfflineSupersedesTheEditsBeforeIt() async throws {
        let store = store()
        defer { store.removeAll() }

        let server = FakeFieldServer(state: emptyState())
        server.failuresRemaining = 99

        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition(),
            store: store,
            now: { Self.now }
        )

        for title in ["Plumber", "Call the plumber", "Call the plumber back"] {
            await #expect(throws: (any Error).self) {
                try await outbox.upsert(self.item(title: title))
            }
        }
        await #expect(throws: (any Error).self) {
            try await outbox.delete(itemID: "item-1")
        }

        #expect(
            outbox.pending.count == 1,
            "four writes about one item are one write"
        )

        server.failuresRemaining = 0
        try await outbox.flush()

        #expect(server.receivedCount == 5, "four failed sends, then one that worked")
        #expect(server.state.lifeItems.isEmpty)
        #expect(outbox.isEmpty)
    }

    /// Compaction must not reorder unrelated work. An edit collapsing into a
    /// create still has to arrive before a later, different write.
    @Test
    func compactionKeepsTheOrderOfWhatSurvives() async throws {
        let store = store()
        defer { store.removeAll() }

        let server = FakeFieldServer(state: emptyState())
        server.failuresRemaining = 99
        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition(),
            store: store,
            now: { Self.now }
        )

        for title in ["First", "First, edited"] {
            await #expect(throws: (any Error).self) {
                try await outbox.upsert(self.item(id: "a", title: title))
            }
        }
        await #expect(throws: (any Error).self) {
            try await outbox.upsert(self.item(id: "b", title: "Second"))
        }

        let subjects = outbox.pending.map(\.mutation.subject)
        #expect(subjects == [.item("a"), .item("b")])
    }

    // MARK: 5. Files that cannot be read

    @Test
    func aCorruptOutboxFileIsQuarantinedRatherThanFatal() throws {
        let store = store()
        defer { store.removeAll() }

        let partition = partition()
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        try Data("{ not json".utf8).write(to: store.url(for: partition))

        #expect(store.load(partition).isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: store.url(for: partition).path
            ),
            "the unreadable file is moved aside"
        )

        let quarantined = try FileManager.default.contentsOfDirectory(
            atPath: store.directory.path
        )
        .filter { $0.hasPrefix("quarantined-") }
        #expect(
            quarantined.count == 1,
            "and kept, because it is the only evidence of what was lost"
        )
    }

    @Test
    func anOutboxFileFromAnotherVersionIsNotReplayed() throws {
        let store = store()
        defer { store.removeAll() }

        let partition = partition()
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        let fromTheFuture = """
        {"version": \(FieldOutboxLog.currentVersion + 1), "entries": []}
        """
        try Data(fromTheFuture.utf8).write(to: store.url(for: partition))

        #expect(store.load(partition).isEmpty)
    }

    @Test
    func aCorruptStateCacheIsDiscardedRatherThanFatal() throws {
        let cache = FieldStateCache(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "FieldStateCacheTests-\(UUID().uuidString)")
        )
        defer { cache.removeAll() }

        let partition = partition()
        try FileManager.default.createDirectory(
            at: cache.directory,
            withIntermediateDirectories: true
        )
        try Data("half a file".utf8).write(to: cache.url(for: partition))

        #expect(cache.load(partition) == nil)
        #expect(
            !FileManager.default.fileExists(
                atPath: cache.url(for: partition).path
            )
        )
    }

    @Test
    func aStateCacheFromAnotherVersionIsNotUsed() throws {
        let cache = FieldStateCache(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "FieldStateCacheTests-\(UUID().uuidString)")
        )
        defer { cache.removeAll() }

        let partition = partition()
        cache.save(emptyState(), for: partition, at: Self.now)
        #expect(cache.load(partition) != nil)

        // Rewrite the same file with a version this build does not know.
        let url = cache.url(for: partition)
        var json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as! [String: Any]
        json["version"] = CachedFieldState.currentVersion + 1
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        #expect(cache.load(partition) == nil)
    }

    // MARK: The state cache, round trip

    @Test
    func theStateCacheReturnsWhatItWasGiven() throws {
        let cache = FieldStateCache(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "FieldStateCacheTests-\(UUID().uuidString)")
        )
        defer { cache.removeAll() }

        var state = emptyState()
        state.lifeItems = [item(title: "Renter's insurance")]

        cache.save(state, for: partition(), at: Self.now)
        let loaded = try #require(cache.load(partition()))

        #expect(loaded.state.lifeItems.map(\.title) == ["Renter's insurance"])
        #expect(loaded.savedAt == Self.now)
    }

    /// Same partitioning rule as the outbox, for the same reason.
    @Test
    func theStateCacheIsNotSharedBetweenAccounts() throws {
        let cache = FieldStateCache(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "FieldStateCacheTests-\(UUID().uuidString)")
        )
        defer { cache.removeAll() }

        var state = emptyState()
        state.lifeItems = [item()]
        cache.save(state, for: partition(user: "user-1"), at: Self.now)

        #expect(cache.load(partition(user: "user-2")) == nil)
    }

    // MARK: Durability and giving up

    /// The whole point: the queue outlives the process that made it.
    @Test
    func queuedWritesSurviveTheAppBeingKilled() async throws {
        let store = store()
        defer { store.removeAll() }

        let partition = partition()
        let dying = FakeFieldServer(state: emptyState())
        dying.failuresRemaining = 99

        let before = FieldOutbox(
            wrapping: dying,
            partition: partition,
            store: store,
            now: { Self.now }
        )
        await #expect(throws: (any Error).self) {
            try await before.upsert(self.item(title: "Typed on a train"))
        }

        // A new process, a new outbox, the same file.
        let relaunched = FakeFieldServer(state: emptyState())
        let after = FieldOutbox(
            wrapping: relaunched,
            partition: partition,
            store: store,
            now: { Self.now }
        )

        #expect(after.pending.count == 1)

        try await after.flush()
        #expect(relaunched.state.lifeItems.map(\.title) == ["Typed on a train"])
    }

    /// A write the server keeps refusing must eventually stop blocking the
    /// ones behind it. One rejected mutation should cost one mutation, not
    /// every mutation made after it.
    @Test
    func aWriteTheServerKeepsRefusingIsEventuallySetAside() async throws {
        let store = store()
        defer { store.removeAll() }

        let server = FakeFieldServer(state: emptyState())
        server.failuresRemaining = .max

        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition(),
            store: store,
            now: { Self.now }
        )

        await #expect(throws: (any Error).self) {
            try await outbox.upsert(self.item())
        }

        // Each flush is one more attempt. The first happened on enqueue.
        for _ in 1..<FieldOutbox.maximumAttempts {
            try? await outbox.flush()
        }

        #expect(outbox.isEmpty, "it gave up rather than retrying forever")
    }

    @Test
    func purgeLeavesNothingOnDisk() async throws {
        let store = store()
        defer { store.removeAll() }

        let partition = partition()
        let server = FakeFieldServer(state: emptyState())
        server.failuresRemaining = 99

        let outbox = FieldOutbox(
            wrapping: server,
            partition: partition,
            store: store,
            now: { Self.now }
        )
        await #expect(throws: (any Error).self) {
            try await outbox.upsert(self.item())
        }
        #expect(!outbox.isEmpty)

        outbox.purge()

        #expect(outbox.isEmpty)
        #expect(store.load(partition).isEmpty)
    }
}
