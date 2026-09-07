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
    /// When this write was set aside after `maximumAttempts`.
    ///
    /// Set aside, not discarded. It stays in the queue and stays replayed over
    /// every load, so the thing the person wrote is still on their screen and
    /// still in this file after a relaunch. What it loses is its place at the
    /// head of the queue: `flush()` steps over it, so one write the server
    /// keeps refusing cannot hold up every write behind it.
    ///
    /// Optional, and decoded with `decodeIfPresent` by synthesis, so a queue
    /// written by a build that predates this field still reads.
    var blockedAt: Date?

    init(
        id: UUID = UUID(),
        mutation: FieldMutation,
        queuedAt: Date,
        attempts: Int = 0,
        blockedAt: Date? = nil
    ) {
        self.id = id
        self.mutation = mutation
        self.queuedAt = queuedAt
        self.attempts = attempts
        self.blockedAt = blockedAt
    }
}

/// What the app may honestly say about one item's write.
enum FieldDeliveryState: Sendable, Equatable {
    /// The server has it.
    case shared
    /// On this phone and owed to the server. The ordinary state on a train.
    case savedLocally
    /// Set aside after repeated refusals. Still here, still on screen, and
    /// waiting for somebody to ask for it again.
    case needsAttention
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

/// An unfinished capture, protected and scoped exactly like its outbox.
struct FieldCaptureDraft: Codable {
    var text: String
    var receipt: FieldReceipt?
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

    func save(_ entries: [FieldOutboxEntry], for partition: FieldOutboxPartition) {
        do { try write(entries, for: partition) }
        catch { WELog.persistence.error("Could not persist the outbox") }
    }

    /// A caller acknowledging a save must observe disk errors.
    func write(_ entries: [FieldOutboxEntry], for partition: FieldOutboxPartition) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let data = try encoder.encode(FieldOutboxLog(entries: entries))
        try data.write(to: url(for: partition), options: [.atomic, .completeFileProtection])
    }

    private func draftURL(_ partition: FieldOutboxPartition) -> URL {
        directory.appending(path: "draft-" + partition.filename)
    }

    func loadDraft(_ partition: FieldOutboxPartition) -> FieldCaptureDraft? {
        guard let data = try? Data(contentsOf: draftURL(partition)) else { return nil }
        return try? JSONDecoder().decode(FieldCaptureDraft.self, from: data)
    }

    func writeDraft(_ draft: FieldCaptureDraft, for partition: FieldOutboxPartition) throws {
        if draft.text.isEmpty && draft.receipt == nil {
            if FileManager.default.fileExists(atPath: draftURL(partition).path) {
                try FileManager.default.removeItem(at: draftURL(partition))
            }
            return
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try JSONEncoder().encode(draft).write(
            to: draftURL(partition), options: [.atomic, .completeFileProtection]
        )
    }

    /// Part of the Phase 1d purge contract.
    func remove(_ partition: FieldOutboxPartition) {
        try? FileManager.default.removeItem(at: url(for: partition))
        try? FileManager.default.removeItem(at: draftURL(partition))
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

    func captureDraft() -> FieldCaptureDraft? { store.loadDraft(partition) }
    func saveCaptureDraft(_ draft: FieldCaptureDraft) throws {
        try store.writeDraft(draft, for: partition)
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

    func upsert(_ evidence: FieldEvidence) async throws {
        try await enqueue(.upsertEvidence(evidence))
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

    /// Queued, like every other write to `FieldState`. Putting a group away on
    /// a train is a decision about a shared page, not about a network, and it
    /// means the same thing whenever it lands.
    func setCategoryHidden(_ category: String, hidden: Bool) async throws {
        try await enqueue(.setCategoryHidden(category: category, hidden: hidden))
    }

    // MARK: The circle
    //
    // Queued, unlike the crossing above. The two look similar — both are a
    // person deciding something about their partner — but the crossing names a
    // number on screen and must not take effect silently hours later against a
    // set that has changed. A mark names nothing and changes nothing: it is
    // "I'd welcome a moment today", it carries its own day, and it means the
    // same thing whenever it lands.

    func markReady(localDate: String) async throws {
        try await enqueue(.markReady(localDate: localDate))
    }

    /// Flushed first, then asked.
    ///
    /// A mark sitting in the queue is not on the server, so the RPC cannot see
    /// it and would answer `neither` to somebody who has already tapped. The
    /// flush is what makes the state on screen and the rows behind it the same
    /// set — the same reasoning as `soloHistoryCount`, and unlike it this one
    /// is best effort: a queued mark that will not drain should still let the
    /// screen show what the server currently knows rather than throwing away
    /// the read.
    func readiness(localDate: String) async throws -> FieldReadiness {
        try? await flush()
        return try await base.readiness(localDate: localDate)
    }

    // MARK: The queue itself

    /// Durable first, then sent.
    ///
    /// The order is the point: the write is on disk before the network is
    /// touched, so the process dying at any instant after this returns leaves
    /// the mutation recoverable. The send is still attempted immediately,
    /// because the overwhelmingly common case is that it works and nobody
    /// should wait for a flush to notice.
    /// Persist a logical save atomically before the interface acknowledges it.
    /// Network delivery is separate; all constituent mutations survive a restart.
    func stage(_ mutations: [FieldMutation]) throws {
        try lock.withLock {
            let next = Self.compacted(_entries + mutations.map {
                FieldOutboxEntry(mutation: $0, queuedAt: now())
            })
            try store.write(next, for: partition)
            _entries = next
        }
    }

    func replayPending(over state: FieldState) -> FieldState {
        var result = state
        for entry in pending { entry.mutation.apply(to: &result) }
        return result
    }

    private func enqueue(_ mutation: FieldMutation) async throws {
        try stage([mutation])
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

        while let entry = pending.first(where: { $0.blockedAt == nil }) {
            do {
                try await entry.mutation.send(to: base)
                remove(entry.id)
            } catch {
                // Losing connectivity is not evidence that a write is invalid.
                // Leave it eligible for the next reconnect/foreground flush.
                if !(error is CancellationError),
                   (error as NSError).domain != NSURLErrorDomain {
                    recordFailure(of: entry.id)
                }
                throw error
            }
        }
    }

    /// Ask again for writes that were set aside.
    ///
    /// `itemID` nil means all of them. Attempts reset, because the person
    /// asking is new information: the last five failures may have been a
    /// server that was down, and holding the count against them would mean one
    /// bad afternoon permanently disabled the retry.
    func retryDelivery(itemID: String? = nil) async {
        lock.withLock {
            for index in _entries.indices
            where _entries[index].blockedAt != nil
                && (itemID == nil
                    || Self.subjectID(of: _entries[index].mutation) == itemID) {
                _entries[index].blockedAt = nil
                _entries[index].attempts = 0
            }
            store.save(_entries, for: partition)
        }
        try? await flush()
    }

    /// Drain the queue. Called when connectivity returns and when the app
    /// comes back to the foreground; both are moments when the reason a write
    /// failed may have just stopped being true.
    ///
    /// Deliberately does not clear `blockedAt`: an automatic retry may not
    /// resurrect a write the server has refused five times, or a phone
    /// reconnecting would retry it forever. Only a person can.
    func flushPending() async {
        try? await flush()
    }

    // MARK: What the app may say about one item

    /// The item id a mutation is about, when it is about one.
    ///
    /// A capture and the item it becomes share an id, so both answer here and
    /// an item's status covers the whole life of the thing that was typed.
    private static func subjectID(of mutation: FieldMutation) -> String? {
        switch mutation.subject {
        case .item(let id), .capture(let id): id
        default: nil
        }
    }

    func deliveryState(forItem id: String) -> FieldDeliveryState {
        let mine = pending.filter { Self.subjectID(of: $0.mutation) == id }
        guard !mine.isEmpty else { return .shared }
        return mine.contains { $0.blockedAt != nil }
            ? .needsAttention
            : .savedLocally
    }

    /// Every item the app currently owes the server something for, split by
    /// what it may say about them. One pass, because a zone asks about every
    /// row it draws and `deliveryState(forItem:)` per row is quadratic.
    func deliveryStates() -> [String: FieldDeliveryState] {
        var result: [String: FieldDeliveryState] = [:]
        for entry in pending {
            guard let id = Self.subjectID(of: entry.mutation) else { continue }
            if entry.blockedAt != nil {
                result[id] = .needsAttention
            } else if result[id] == nil {
                result[id] = .savedLocally
            }
        }
        return result
    }

    /// Everything, gone. The outbox half of the Phase 1d purge contract.
    func purge() {
        lock.withLock { _entries = [] }
        store.remove(partition)
    }

    // MARK: -

    private func remove(_ id: UUID) {
        lock.withLock {
            _entries.removeAll { $0.id == id }
            store.save(_entries, for: partition)
        }
    }

    private func recordFailure(of id: UUID) {
        var abandoned: FieldOutboxEntry?  // set aside, not dropped

        lock.withLock {
            guard let index = _entries.firstIndex(where: { $0.id == id })
            else { return }

            _entries[index].attempts += 1
            if _entries[index].attempts >= Self.maximumAttempts,
               _entries[index].blockedAt == nil {
                // Set aside rather than retried forever. This is a write the
                // server has refused five times; leaving it at the head of the
                // queue means every *later* write is stuck behind it, which
                // turns one rejected mutation into all of them.
                //
                // It used to be *removed* here, which solved that and created
                // a worse problem: the write was gone, the person was never
                // told, and the item stayed on screen because the local state
                // still had it — the app quietly disagreeing with the server
                // about something somebody wrote. It stays in the queue now,
                // marked, so `deliveryState(forItem:)` can say so on the item
                // itself and `retryDelivery` can pick it up again.
                _entries[index].blockedAt = now()
                abandoned = _entries[index]
            }
            store.save(_entries, for: partition)
        }

        if let abandoned {
            WELog.persistence.error(
                """
                Setting a queued write aside after \
                \(abandoned.attempts, privacy: .public) attempts. It stays in \
                the queue and the item now reports needsAttention.
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
