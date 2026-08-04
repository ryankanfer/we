//
//  YoursStore.swift
//  WE
//
//  The one place the personal space reads from.
//
//  Shaped like `FieldStore` deliberately — a backend protocol as the whole
//  persistence seam, an in-memory implementation that keeps previews honest,
//  and an `@Observable` store the views bind to — but it is a separate seam,
//  not an extension of that one. `YoursModel.swift` says why.
//
//  WHAT IS DELIBERATELY MISSING
//
//  No cache. `FieldStateCache` writes couple state to disk behind complete
//  file protection, and that is right for a shared field; entry text is a
//  different promise. Nothing in this file persists a body.
//
//  No realtime subscription. `FieldSupabaseBackend` opens a channel keyed on
//  the couple; the equivalent here would be a channel keyed on one account,
//  whose very existence is metadata about a private space. Multi-device
//  agreement comes from the server being authoritative (§11) and from the
//  presentation gate being idempotent within a visit, not from a socket.
//
//  No outbox for writes that carry text. `FieldOutbox` persists mutation
//  payloads so they survive a relaunch — correct there, and here it would put
//  private writing on disk in a second place. The one thing that *is* queued
//  is destruction, and it queues an id. See `YoursDestroyQueue`.
//

import Foundation
import Observation

// MARK: - Persistence seam

protocol YoursBackend: Sendable {
    /// Everything the owner can currently see: living entries, the held
    /// drawer, and any offer not yet sent. Never a feed — §7 is explicit that
    /// a product which visually celebrates accumulation while claiming to
    /// resist it is telling on itself.
    func load() async throws -> YoursSnapshot

    /// Write without deciding what it becomes.
    func save(clientID: String, body: String) async throws -> YoursEntry

    /// Editing. §3: this restarts the current interval and does not demote the
    /// lifecycle stage. §4: it is refused outright on a held entry, which has
    /// its own question.
    func edit(entryID: String, body: String) async throws -> YoursEntry

    /// The gate. Returns the one entry under question, or nil.
    ///
    /// Idempotent within a visit: asking twice presents the same entry rather
    /// than promoting a second, and after something is resolved the next one
    /// waits for the next visit.
    func presentNext(visit: YoursVisit) async throws -> YoursEntry?
    func presentNextOffer(visit: YoursVisit) async throws -> YoursPreparedOffer?

    func keepForNow(entryID: String, visit: YoursVisit) async throws -> YoursEntry
    func hold(entryID: String, visit: YoursVisit?) async throws -> YoursEntry
    func snooze(entryID: String, visit: YoursVisit) async throws -> YoursEntry
    func letThisReturn(entryID: String, body: String?) async throws -> YoursEntry
    func updateHeld(entryID: String, body: String) async throws -> YoursEntry

    /// The only client-reachable route to destruction.
    func letGo(
        entryID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws

    func prepareOffer(
        entryID: String,
        clientID: String,
        title: String,
        question: String,
        options: [String],
        visit: YoursVisit?
    ) async throws -> YoursPreparedOffer

    func sendOffer(offerID: String) async throws
    func letOfferGo(
        offerID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws

    /// Still here. Called on foreground whether or not this space is opened,
    /// because §5's dormancy rule is about the product and not about this
    /// room.
    func touch() async throws

    func markTaught(_ moment: YoursTeachingMoment) async throws -> YoursOwnerState
}

nonisolated enum YoursTeachingMoment: String, Sendable {
    case promise
    case firstEntry
}

/// What one load returns.
nonisolated struct YoursSnapshot: Codable, Hashable, Sendable {
    var living: [YoursEntry]
    var held: [YoursEntry]
    var offers: [YoursPreparedOffer]
    var ownerState: YoursOwnerState

    static let empty = YoursSnapshot(
        living: [],
        held: [],
        offers: [],
        ownerState: .unknown
    )
}

// MARK: - The store

@MainActor
@Observable
final class YoursStore {
    private(set) var snapshot: YoursSnapshot = .empty
    private(set) var loadFailed = false

    /// The entry currently under question, if one has been presented. At most
    /// one, ever — §5: "Only one entry can be presented at a time."
    private(set) var returned: YoursEntry?
    private(set) var returnedOffer: YoursPreparedOffer?

    /// Ephemeral, and never persisted.
    var draft = ""
    var showsHeldDrawer = false
    /// The entry an offer is being written from, if the composer is open.
    var preparingOffer: YoursEntry?

    /// What was just written, so the surface can state both of its dates once.
    ///
    /// §8 asks for two things that sound contradictory and are not: forgetting
    /// is "completely legible to the owner" — they always know the exact
    /// return and the exact outer bound — and it is never "displayed as a
    /// countdown on the object". This is where the first half happens. It is
    /// said at the moment of saving and then not again.
    private(set) var justSaved: YoursEntry?

    private let backend: YoursBackend
    private let clock: FieldClock
    private var visit: YoursVisit

    init(backend: YoursBackend, clock: FieldClock) {
        self.backend = backend
        self.clock = clock
        visit = YoursVisit()
    }

    var now: Date { clock.now }

    /// A new foreground session. The gate reads this, so it is the thing that
    /// makes "the next entry appears on your next visit" true.
    func beginVisit() {
        visit = YoursVisit()
    }

    // MARK: Reading

    func open() async {
        await reload()
        await presentIfAnythingIsWaiting()
    }

    func reload() async {
        do {
            snapshot = try await backend.load()
            hideQueuedDestructions()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// §11: "Nothing can resurrect an entry once destruction has begun."
    ///
    /// An offline "let go" removes the row locally and queues the destruction,
    /// but the server still has it — so without this the next successful load
    /// would put somebody's released writing back on screen, and the sentence
    /// above would be false in the one situation where it matters most.
    /// Filtered rather than deleted from the snapshot's source, because the
    /// queue is the record of intent and it clears only on confirmation.
    private func hideQueuedDestructions() {
        let queued = Set(YoursDestroyQueue.shared.pending().map(\.entryID))
        guard !queued.isEmpty else { return }
        snapshot.living.removeAll { queued.contains($0.id) }
        snapshot.held.removeAll { queued.contains($0.id) }
        if let returned, queued.contains(returned.id) { self.returned = nil }
    }

    /// Discovered rather than announced.
    ///
    /// §9: no push notification for returns, ever. "Something in Yours is
    /// ready for you" on a lock screen, on a phone lying face up on a shared
    /// counter, tells a partner that something private matured today — timing
    /// metadata escaping the device even though it never touched the database.
    /// So a return is found by opening the space and in no other way.
    func presentIfAnythingIsWaiting() async {
        do {
            returned = try await backend.presentNext(visit: visit)
            if returned == nil {
                returnedOffer = try await backend.presentNextOffer(visit: visit)
            }
        } catch {
            loadFailed = true
        }
    }

    // MARK: Writing

    func save() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        do {
            justSaved = try await backend.save(
                clientID: UUID().uuidString,
                body: body
            )
            await reload()
        } catch {
            loadFailed = true
        }
    }

    func dismissSaveConfirmation() {
        justSaved = nil
    }

    /// §3: "Keep indefinitely is available from the first save, visually
    /// secondary." Two calls rather than one, because permanence is a decision
    /// about an entry and an entry has to exist to be decided about — and
    /// because a combined write would need a second insert path into a table
    /// whose whole safety comes from having one.
    func saveAndHold() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        do {
            let saved = try await backend.save(
                clientID: UUID().uuidString,
                body: body
            )
            _ = try await backend.hold(entryID: saved.id, visit: nil)
            await reload()
        } catch {
            loadFailed = true
        }
    }

    func keepForNow(_ entry: YoursEntry) async {
        await resolve { try await $0.keepForNow(entryID: entry.id, visit: self.visit) }
    }

    func hold(_ entry: YoursEntry, answeringReturn: Bool = true) async {
        await resolve {
            try await $0.hold(
                entryID: entry.id,
                visit: answeringReturn ? self.visit : nil
            )
        }
    }

    func snooze(_ entry: YoursEntry) async {
        await resolve { try await $0.snooze(entryID: entry.id, visit: self.visit) }
    }

    func letThisReturn(_ entry: YoursEntry, body: String? = nil) async {
        await perform { try await $0.letThisReturn(entryID: entry.id, body: body) }
    }

    func updateHeld(_ entry: YoursEntry, body: String) async {
        await perform { try await $0.updateHeld(entryID: entry.id, body: body) }
    }

    /// §11: let go takes effect locally immediately, and nothing can resurrect
    /// an entry once destruction has begun. So the row leaves local state
    /// before the network is consulted, and a failure does not put it back —
    /// `YoursDestroyQueue` carries the intent instead.
    func letGo(
        _ entry: YoursEntry,
        reason: YoursReleaseReason?,
        answeringReturn: Bool = true
    ) async {
        snapshot.living.removeAll { $0.id == entry.id }
        snapshot.held.removeAll { $0.id == entry.id }
        if returned?.id == entry.id { returned = nil }

        do {
            try await backend.letGo(
                entryID: entry.id,
                visit: answeringReturn ? visit : nil,
                reason: reason
            )
            await reload()
        } catch {
            YoursDestroyQueue.shared.enqueue(entryID: entry.id, reason: reason)
        }
    }

    func drainDestroyQueue() async {
        for pending in YoursDestroyQueue.shared.pending() {
            do {
                try await backend.letGo(
                    entryID: pending.entryID,
                    visit: nil,
                    reason: pending.reason
                )
                YoursDestroyQueue.shared.clear(entryID: pending.entryID)
            } catch {
                // Left queued. The next launch tries again, and the server's
                // own sweep is the backstop either way.
            }
        }
    }

    // MARK: Offers

    /// §6: the offer carries "exact wording the person approves", so this
    /// opens a composer rather than deriving anything. Nothing about the
    /// source entry crosses on its own — not its text, not its dates, not the
    /// fact that it matured.
    func beginPreparingOffer(from entry: YoursEntry) {
        preparingOffer = entry
    }

    func prepareOffer(
        from entry: YoursEntry,
        title: String,
        question: String,
        options: [String]
    ) async {
        preparingOffer = nil
        await resolve {
            try await $0.prepareOffer(
                entryID: entry.id,
                clientID: UUID().uuidString,
                title: title,
                question: question,
                options: options,
                visit: self.visit
            )
        }
    }

    func send(_ offer: YoursPreparedOffer) async {
        returnedOffer = nil
        try? await backend.sendOffer(offerID: offer.id)
        await reload()
    }

    func letOfferGo(_ offer: YoursPreparedOffer, reason: YoursReleaseReason?) async {
        returnedOffer = nil
        try? await backend.letOfferGo(
            offerID: offer.id,
            visit: visit,
            reason: reason
        )
        await reload()
    }

    // MARK: The teaching moment

    func markTaught(_ moment: YoursTeachingMoment) async {
        guard let state = try? await backend.markTaught(moment) else { return }
        snapshot.ownerState = state
    }

    var shouldTeachOnFirstEntry: Bool {
        !snapshot.ownerState.taughtOnFirstEntry
    }

    // MARK: Plumbing

    /// Generic over the write's result and then discards it, so a call site
    /// does not have to say `_ =` eleven times. Every one of these returns the
    /// row the server settled on, and the store re-reads afterwards anyway —
    /// §11 makes the server authoritative, so the useful value is the reload,
    /// not the echo.
    private func perform<T>(
        _ write: (YoursBackend) async throws -> T
    ) async {
        do {
            _ = try await write(backend)
            await reload()
        } catch {
            loadFailed = true
        }
    }

    /// A write that also answers the question currently on screen.
    private func resolve<T>(
        _ write: (YoursBackend) async throws -> T
    ) async {
        returned = nil
        returnedOffer = nil
        await perform(write)
    }
}

// MARK: - The reference backend

/// Written so previews, the gallery and the tests exercise the same rules the
/// database does. Where the two could drift — the presentation gate, the
/// interval by stage, one snooze — this mirrors the SQL deliberately, and
/// `YoursBackendConformanceTests` runs the same assertions against both.
/// Main-actor isolated rather than an actor, and the reason is the clock.
///
/// The module builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
/// `FieldClock.now` belongs to the main actor. An `actor` here would have to
/// hop for every single date it reads, which is both noisy and — for a type
/// whose whole job is to be a deterministic stand-in during tests and previews
/// — a source of ordering surprises that the real backend does not have.
///
/// `YoursSupabaseBackend` is the one that does I/O, and it is `Sendable` and
/// off the main actor accordingly. It never reads a clock: every date in this
/// feature is computed by Postgres.
@MainActor
final class YoursMemoryBackend: YoursBackend {
    private var entries: [YoursEntry] = []
    private var offers: [YoursPreparedOffer] = []
    private var ownerState: YoursOwnerState = .unknown
    private var lastResolutionVisit: UUID?
    private let clock: FieldClock

    init(clock: FieldClock, seeded: [YoursEntry] = []) {
        self.clock = clock
        entries = seeded
    }

    func load() async throws -> YoursSnapshot {
        YoursSnapshot(
            living: entries.filter { $0.state != .held }
                .sorted { $0.createdAt > $1.createdAt },
            held: entries.filter { $0.state == .held }
                .sorted { $0.createdAt > $1.createdAt },
            offers: offers.filter { $0.sentAt == nil },
            ownerState: ownerState
        )
    }

    func save(clientID: String, body: String) async throws -> YoursEntry {
        let now = clock.now
        let readyAt = YoursDates.projectedReadyAt(from: now)
        let entry = YoursEntry(
            id: UUID().uuidString,
            clientID: clientID,
            body: body,
            state: .living,
            renewalCount: 0,
            createdAt: now,
            readyAt: readyAt,
            unseenDeleteAt: YoursDates.outerBound(after: readyAt),
            presentedAt: nil,
            decideBy: nil,
            snoozedAt: nil,
            heldAt: nil
        )
        entries.append(entry)
        return entry
    }

    func edit(entryID: String, body: String) async throws -> YoursEntry {
        var entry = try require(entryID)
        guard entry.state != .held else {
            throw YoursError.heldNeedsAnExplicitChoice
        }
        // §3: the current interval restarts; the stage does not move.
        let readyAt = YoursDates.projectedReadyAt(
            renewalCount: entry.renewalCount,
            from: clock.now
        )
        entry = YoursEntry(
            id: entry.id,
            clientID: entry.clientID,
            body: body,
            state: .living,
            renewalCount: entry.renewalCount,
            createdAt: entry.createdAt,
            readyAt: readyAt,
            unseenDeleteAt: YoursDates.outerBound(after: readyAt),
            presentedAt: nil,
            decideBy: nil,
            snoozedAt: entry.snoozedAt,
            heldAt: nil
        )
        replace(entry)
        return entry
    }

    func presentNext(visit: YoursVisit) async throws -> YoursEntry? {
        let now = clock.now

        if let open = entries.first(where: {
            $0.state == .presented && ($0.decideBy ?? now) > now
        }) {
            return open
        }
        if lastResolutionVisit == visit.id { return nil }

        let candidates = entries
            .filter { $0.state == .living || $0.state == .ready }
            .filter { $0.readyAt <= now }
            .sorted { $0.readyAt < $1.readyAt }

        guard let next = candidates.first else { return nil }

        let presented = next.presented(
            at: now,
            decideBy: YoursDates.projectedDecision(from: now)
        )
        replace(presented)
        return presented
    }

    func presentNextOffer(visit: YoursVisit) async throws -> YoursPreparedOffer? {
        let now = clock.now
        if let open = offers.first(where: {
            $0.sentAt == nil && ($0.decideBy ?? now) > now
        }) {
            return open
        }
        if lastResolutionVisit == visit.id { return nil }
        return offers
            .filter { $0.sentAt == nil && $0.presentedAt == nil && $0.readyAt <= now }
            .sorted { $0.readyAt < $1.readyAt }
            .first
    }

    func keepForNow(entryID: String, visit: YoursVisit) async throws -> YoursEntry {
        let entry = try require(entryID)
        guard entry.state == .presented else { throw YoursError.nothingWasAsked }
        guard entry.renewalCount < 1 else { throw YoursError.secondReturnNeedsADecision }

        let renewed = entry.renewed(
            at: clock.now,
            readyAt: YoursDates.projectedReadyAt(
                renewalCount: entry.renewalCount + 1,
                from: clock.now
            )
        )
        replace(renewed)
        lastResolutionVisit = visit.id
        return renewed
    }

    func hold(entryID: String, visit: YoursVisit?) async throws -> YoursEntry {
        let held = try require(entryID).held(at: clock.now)
        replace(held)
        if let visit { lastResolutionVisit = visit.id }
        return held
    }

    func snooze(entryID: String, visit: YoursVisit) async throws -> YoursEntry {
        let entry = try require(entryID)
        guard entry.state == .presented else { throw YoursError.nothingWasAsked }
        guard entry.canSnooze else { throw YoursError.oneWeekOnce }

        let snoozed = entry.snoozed(at: clock.now)
        replace(snoozed)
        lastResolutionVisit = visit.id
        return snoozed
    }

    func letThisReturn(entryID: String, body: String?) async throws -> YoursEntry {
        let entry = try require(entryID)
        let returning = entry.returningToNaturalLife(
            at: clock.now,
            body: body ?? entry.body
        )
        replace(returning)
        return returning
    }

    func updateHeld(entryID: String, body: String) async throws -> YoursEntry {
        let entry = try require(entryID)
        let updated = entry.heldWith(body: body, at: clock.now)
        replace(updated)
        return updated
    }

    func letGo(
        entryID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws {
        entries.removeAll { $0.id == entryID }
        if let visit { lastResolutionVisit = visit.id }
    }

    func prepareOffer(
        entryID: String,
        clientID: String,
        title: String,
        question: String,
        options: [String],
        visit: YoursVisit?
    ) async throws -> YoursPreparedOffer {
        let now = clock.now
        let offer = YoursPreparedOffer(
            id: UUID().uuidString,
            clientID: clientID,
            sourceEntryID: entryID,
            title: title,
            question: question,
            options: options,
            preparedAt: now,
            readyAt: YoursDates.calendar.date(
                byAdding: YoursDates.offerLife, to: now
            ) ?? now,
            presentedAt: nil,
            decideBy: nil,
            sentAt: nil
        )
        offers.append(offer)

        // Preparing is not a renewal, so the count does not move — but the
        // source is not left at the end of its life either.
        if let entry = entries.first(where: { $0.id == entryID }),
           entry.state != .held {
            replace(
                entry.renewedWithoutCounting(
                    readyAt: YoursDates.projectedReadyAt(
                        renewalCount: entry.renewalCount,
                        from: now
                    )
                )
            )
        }
        if let visit { lastResolutionVisit = visit.id }
        return offer
    }

    func sendOffer(offerID: String) async throws {
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else { return }
        offers[index] = offers[index].sent(at: clock.now)
    }

    func letOfferGo(
        offerID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws {
        offers.removeAll { $0.id == offerID && $0.sentAt == nil }
        if let visit { lastResolutionVisit = visit.id }
    }

    func touch() async throws {}

    func markTaught(_ moment: YoursTeachingMoment) async throws -> YoursOwnerState {
        switch moment {
        case .promise: ownerState.taughtInPromise = true
        case .firstEntry: ownerState.taughtOnFirstEntry = true
        }
        return ownerState
    }

    // MARK: -

    private func require(_ id: String) throws -> YoursEntry {
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw YoursError.notFound
        }
        return entry
    }

    private func replace(_ entry: YoursEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            entries.append(entry)
            return
        }
        entries[index] = entry
    }
}

// MARK: - Errors

nonisolated enum YoursError: Error, Equatable, Sendable {
    case notFound
    case nothingWasAsked
    case oneWeekOnce
    case secondReturnNeedsADecision
    case heldNeedsAnExplicitChoice
}
