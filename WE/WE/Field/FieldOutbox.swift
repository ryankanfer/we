//
//  FieldOutbox.swift
//  WE
//
//  A write that has been made but not yet accepted by the server.
//
//  Every mutation in `FieldStore` is `Task { try? await backend?.… }`. There
//  are seventeen of them and each one is a promise the app cannot keep: the
//  task is not awaited, the error is discarded, and nothing anywhere remembers
//  that the write was attempted. Typing something on a train and locking the
//  phone loses it, and the app never says so — the item is on screen until the
//  next load quietly replaces it with the truth.
//
//  This sits between `FieldStore` and `FieldSupabaseBackend` as a decorator,
//  which is what keeps those seventeen call sites untouched. It is also what
//  keeps ~176 existing tests passing against `FieldMemoryBackend`: the seam
//  they were written against has not moved.
//
//  Durability alone would not be enough, and the three properties below are
//  the ones that are easy to get subtly wrong:
//
//  1. **A retry must not duplicate.** The dangerous failure is not the write
//     that failed — it is the write that succeeded and then timed out on the
//     way back, which is indistinguishable from one that never arrived. Every
//     mutation therefore carries a client-generated identity and every backend
//     write is an upsert on it, so sending twice writes once. See
//     `20260803120000_field_mutation_idempotency.sql`.
//  2. **A reload must not erase a pending write.** Realtime can deliver a
//     snapshot while a mutation is still queued. Returning that snapshot
//     unmodified would blink the user's own writing off the screen. `load()`
//     replays what is still pending over whatever the server just said.
//  3. **An account switch must not leak.** The queue is partitioned by user
//     *and* couple, so signing into a different account cannot flush one
//     person's unsent writes into somebody else's relationship.
//

import Foundation
import os

// MARK: - What is stored

/// One queued write, and the identity that makes sending it twice safe.
struct FieldOutboxEntry: Codable, Sendable {
    let id: UUID
    let mutation: FieldMutation
    let queuedAt: Date
    /// Counted so that a write the server will *never* accept — a row that
    /// violates a constraint, a mutation from a build two versions ago —
    /// cannot retry at the head of the queue forever.
    var attempts: Int

    init(
        id: UUID = UUID(),
        mutation: FieldMutation,
        queuedAt: Date,
        attempts: Int = 0
    ) {
        self.id = id
        self.mutation = mutation
        self.queuedAt = queuedAt
        self.attempts = attempts
    }
}

/// The file's envelope.
///
/// Versioned from the first release rather than the first change. An outbox
/// holds writes the user believes they have made, so the format has to be able
/// to say "I do not understand this" without either crashing or silently
/// applying half of something.
struct FieldOutboxLog: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var entries: [FieldOutboxEntry]

    init(version: Int = Self.currentVersion, entries: [FieldOutboxEntry] = []) {
        self.version = version
        self.entries = entries
    }
}

/// Whose queue this is.
///
/// Both halves matter. The user alone is not enough — a person can leave one
/// relationship and begin another, and writes queued for the first must never
/// arrive in the second.
struct FieldOutboxPartition: Hashable, Sendable {
    let userID: String
    let coupleID: String

    /// Both components are sanitised and joined, rather than hashed, so that
    /// a directory listing during support is readable.
    var filename: String {
        "\(Self.safe(userID))-\(Self.safe(coupleID)).json"
    }

    private static func safe(_ value: String) -> String {
        let cleaned = value.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}

// MARK: - The file

/// The on-disk half, separated from the queue itself so the recovery paths can
/// be tested without a backend.
struct FieldOutboxStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "WE/FieldOutbox", directoryHint: .isDirectory)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Never throws. A queue that cannot be read is empty, and the file is
    /// moved aside rather than deleted — see `quarantine`.
    func load(_ partition: FieldOutboxPartition) -> [FieldOutboxEntry] {
        let url = url(for: partition)
        guard let data = try? Data(contentsOf: url) else { return [] }

        guard let log = try? decoder.decode(FieldOutboxLog.self, from: data)
        else {
            WELog.persistence.error(
                "Outbox file could not be read; quarantining it."
            )
            quarantine(partition)
            return []
        }

        guard log.version == FieldOutboxLog.currentVersion else {
            // A queue written by a different build of the app. Applying it
            // would mean guessing at what a mutation from another version
            // meant, and guessing about somebody's unsent writes is worse
            // than admitting they were lost.
            WELog.persistence.error(
                """
                Outbox file is version \(log.version, privacy: .public), \
                expected \(FieldOutboxLog.currentVersion, privacy: .public); \
                quarantining it.
                """
            )
            quarantine(partition)
            return []
        }

        return log.entries
    }

    func save(
        _ entries: [FieldOutboxEntry],
        for partition: FieldOutboxPartition
    ) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            let data = try encoder.encode(FieldOutboxLog(entries: entries))
            try data.write(
                to: url(for: partition),
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            // Nothing useful to do: the write is still in memory and will be
            // retried. Saying so is the point — this is the failure that
            // silently costs somebody their sentence.
            WELog.persistence.error(
                "Could not persist the outbox: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Part of the Phase 1d purge contract.
    func remove(_ partition: FieldOutboxPartition) {
        try? FileManager.default.removeItem(at: url(for: partition))
    }

    /// Everything, for sign-out and account deletion — including partitions
    /// belonging to accounts this device has since forgotten about.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Moved aside, not deleted.
    ///
    /// A file that cannot be decoded is the one artefact that explains why
    /// somebody's writes vanished. Deleting it destroys the only evidence; the
    /// quarantined copy is small, is never read again, and can travel with a
    /// feedback report.
    func quarantine(_ partition: FieldOutboxPartition) {
        let source = url(for: partition)
        let destination = directory.appending(
            path: "quarantined-\(Date().timeIntervalSince1970)-"
                + partition.filename
        )
        try? FileManager.default.moveItem(at: source, to: destination)
    }

    func url(for partition: FieldOutboxPartition) -> URL {
        directory.appending(path: partition.filename)
    }
}

// MARK: - The queue

/// A `final class` guarded by a lock rather than an `actor`, matching
/// `FieldSupabaseBackend` and `FieldMemoryBackend` exactly.
///
/// Not a stylistic choice. This target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type in `FieldModel`
/// — and `FieldState` with them — is main-actor isolated. An actor cannot
/// touch those without their conformances becoming main-actor-isolated
/// conformances used off the main actor, and making the whole domain layer
/// `nonisolated` to satisfy one queue is a refactor of the entire Field layer
/// wearing an outbox as a disguise. The lock is the idiom already in the file
/// next door, and it holds nothing across a suspension point.
final class FieldOutbox: FieldBackend, @unchecked Sendable {
    /// How many times a single write may fail before it is set aside. Five
    /// flushes of a genuinely offline phone is minutes, not hours, so this
    /// only reaches a write the server is actively refusing.
    static let maximumAttempts = 5

    let viewerOwner: FieldOwner

    private let base: any FieldBackend
    private let store: FieldOutboxStore
    private let cache: FieldStateCache?
    private let partition: FieldOutboxPartition
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var _entries: [FieldOutboxEntry]
    private var isFlushing = false

    init(
        wrapping base: any FieldBackend,
        partition: FieldOutboxPartition,
        store: FieldOutboxStore = FieldOutboxStore(),
        cache: FieldStateCache? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.base = base
        self.viewerOwner = base.viewerOwner
        self.partition = partition
        self.store = store
        self.cache = cache
        self.now = now
        self._entries = store.load(partition)
    }

    // MARK: What to draw before the network answers (1c)

    /// The last snapshot the server gave us, with everything still queued
    /// replayed on top.
    ///
    /// Both halves are needed and it is easy to ship only the first. A cache
    /// alone shows a relaunched app the state as of the last *successful*
    /// load — which is a screen missing the thing somebody typed on the train
    /// just before the phone died. The queue is what puts it back.
    func cachedState() -> (state: FieldState, savedAt: Date)? {
        guard let cached = cache?.load(partition) else { return nil }
        var state = cached.state
        for entry in pending {
            entry.mutation.apply(to: &state)
        }
        // The date is the server's, not the queue's: it answers "when did the
        // app last actually know this", which is what a zone showing stale
        // data has to be able to say.
        return (state, cached.savedAt)
    }

    // MARK: What is waiting

    var pending: [FieldOutboxEntry] { lock.withLock { _entries } }

    var isEmpty: Bool { pending.isEmpty }

    // MARK: Reading

    /// The server's answer, with everything still unsent replayed on top.
    ///
    /// The replay is the whole reason this method is overridden rather than
    /// forwarded. Without it, a realtime tick arriving a moment after somebody
    /// captures something returns a snapshot that predates their write, and
    /// what they just typed disappears from the screen while the app is
    /// working perfectly.
    func load() async throws -> FieldState {
        // Best effort, and deliberately not fatal: a failed flush must not
        // stop a read that would otherwise succeed.
        try? await flush()

        let server = try await base.load()

        // The *server's* answer is what gets cached, not the replayed one.
        // Writing the replayed state would record writes the server has not
        // accepted as though it had, and the next launch would have no way to
        // tell the difference between something confirmed and something still
        // owed. The queue is persisted separately and replayed on top; the two
        // files compose, and neither lies about what the other knows.
        cache?.save(server, for: partition, at: now())

        var state = server
        for entry in pending {
            entry.mutation.apply(to: &state)
        }
        return state
    }

    func changes() -> AsyncStream<Void> {
        base.changes()
    }

    // MARK: The boundary (2a)
    //
    // Forwarded rather than queued. Crossing your solo history is a decision
    // somebody makes while looking at a screen that names what will cross, and
    // queueing it would mean answering that question while offline and having
    // it take effect silently, hours later, with the number possibly changed.
    // If the network is not there, the honest outcome is that nothing crossed.

    func soloHistoryCount() async throws -> Int {
        // Flushed for the same reason the crossing itself is, and before it:
        // a queued row is not on the server, so the counting RPC cannot see
        // it — but the crossing's own flush would put it there moments later
        // and cross it. Counting after the same flush is what makes the number
        // on screen and the rows that move the same set. If the queue will not
        // drain, this throws and nobody is asked, which is the honest outcome:
        // a disclosure cannot name what it cannot count.
        try await flush()
        return try await base.soloHistoryCount()
    }

    func shareSoloHistory() async throws -> Int {
        // Anything still queued is not on the server yet, so it cannot be
        // crossed by an RPC that reads rows. Flushing again here covers what
        // was written between the disclosure appearing and the tap.
        try await flush()
        return try await base.shareSoloHistory()
    }

    // MARK: Writing

    func append(_ capture: FieldCapture) async throws {
        try await enqueue(.append(capture))
    }

    func record(_ correction: FieldCorrection) async throws {
        try await enqueue(.record(correction))
    }

    func upsert(_ item: LifeItem) async throws {
        try await enqueue(.upsertItem(item))
    }

    func delete(itemID: String) async throws {
        try await enqueue(.deleteItem(id: itemID))
    }

    func upsert(_ horizon: FieldHorizon) async throws {
        try await enqueue(.upsertHorizon(horizon))
    }

    func upsert(_ cluster: FieldCluster) async throws {
        try await enqueue(.upsertCluster(cluster))
    }

    func answer(question: String, choice: String) async throws {
        try await enqueue(.answer(question: question, choice: choice))
    }

    func setHeld(_ topic: FieldHeldTopic) async throws {
        try await enqueue(.setHeld(topic))
    }

    func setStandingRule(_ rule: FieldStandingRule) async throws {
        try await enqueue(.setStandingRule(rule))
    }

    func setIdentity(_ identity: FieldIdentity) async throws {
        try await enqueue(.setIdentity(identity))
    }

    func setDailyMoment(_ moment: FieldDailyMoment) async throws {
        try await enqueue(.setDailyMoment(moment))
    }

    // MARK: The queue itself

    /// Durable first, then sent.
    ///
    /// The order is the point: the write is on disk before the network is
    /// touched, so the process dying at any instant after this returns leaves
    /// the mutation recoverable. The send is still attempted immediately,
    /// because the overwhelmingly common case is that it works and nobody
    /// should wait for a flush to notice.
    private func enqueue(_ mutation: FieldMutation) async throws {
        let snapshot: [FieldOutboxEntry] = lock.withLock {
            _entries.append(
                FieldOutboxEntry(mutation: mutation, queuedAt: now())
            )
            _entries = Self.compacted(_entries)
            return _entries
        }
        store.save(snapshot, for: partition)

        try await flush()
    }

    /// Send what is waiting, oldest first, stopping at the first failure.
    ///
    /// Stopping rather than continuing keeps the order a person made their
    /// changes in, and avoids making eleven doomed network calls on a phone
    /// that is simply offline. A write the server actively refuses would block
    /// the queue behind it, which is what `maximumAttempts` is for.
    func flush() async throws {
        // The lock is never held across the `await` below. It guards the
        // queue, not the network.
        let shouldFlush: Bool = lock.withLock {
            guard !isFlushing, !_entries.isEmpty else { return false }
            isFlushing = true
            return true
        }
        guard shouldFlush else { return }
        defer { lock.withLock { isFlushing = false } }

        while let entry = pending.first {
            do {
                try await entry.mutation.send(to: base)
                remove(entry.id)
            } catch {
                recordFailure(of: entry.id)
                throw error
            }
        }
    }

    /// Everything, gone. The outbox half of the Phase 1d purge contract.
    func purge() {
        lock.withLock { _entries = [] }
        store.remove(partition)
    }

    // MARK: -

    private func remove(_ id: UUID) {
        let snapshot: [FieldOutboxEntry] = lock.withLock {
            _entries.removeAll { $0.id == id }
            return _entries
        }
        store.save(snapshot, for: partition)
    }

    private func recordFailure(of id: UUID) {
        var abandoned: FieldOutboxEntry?

        let snapshot: [FieldOutboxEntry] = lock.withLock {
            guard let index = _entries.firstIndex(where: { $0.id == id })
            else { return _entries }

            _entries[index].attempts += 1
            if _entries[index].attempts >= Self.maximumAttempts {
                // Set aside rather than retried forever. This is a write the
                // server has refused five times; leaving it at the head of the
                // queue means every *later* write is stuck behind it, which
                // turns one rejected mutation into all of them.
                abandoned = _entries.remove(at: index)
            }
            return _entries
        }

        store.save(snapshot, for: partition)

        if let abandoned {
            WELog.persistence.error(
                """
                Giving up on a queued write after \
                \(abandoned.attempts, privacy: .public) attempts.
                """
            )
        }
    }

    /// Collapse queued writes about the same thing, keeping the newest.
    ///
    /// Someone editing one item four times while offline made four writes and
    /// means one. Each is a whole-row upsert, so the last is the only one the
    /// server would end up with anyway — and a queued delete supersedes the
    /// edits before it, because they share a subject.
    ///
    /// Order is preserved rather than rebuilt: a create followed by an edit
    /// collapses to the edit, which still has to be sent before an unrelated
    /// later mutation that might depend on it.
    private static func compacted(
        _ entries: [FieldOutboxEntry]
    ) -> [FieldOutboxEntry] {
        var lastIndex: [FieldMutation.Subject: Int] = [:]
        for (index, entry) in entries.enumerated()
        where entry.mutation.supersedesEarlierWritesToTheSameSubject {
            lastIndex[entry.mutation.subject] = index
        }

        return entries.enumerated().compactMap { index, entry in
            guard entry.mutation.supersedesEarlierWritesToTheSameSubject else {
                return entry
            }
            return lastIndex[entry.mutation.subject] == index ? entry : nil
        }
    }
}
