//
//  YoursTests.swift
//  WETests
//
//  The lifecycle, the gate, and the constraints on what this space is allowed
//  to say.
//
//  Every date here comes from a `FieldSteppedClock`. Nothing calls `Date()`,
//  for the same reason `FieldTests` does not: the whole feature is a statement
//  about two instants, and a test that waited for one would not be a test.
//

import Foundation
import Testing

@testable import WE

private let start = Date(timeIntervalSince1970: 1_754_265_600) // 4 Aug 2026

@MainActor
private func backend(
    _ clock: FieldSteppedClock? = nil
) -> (YoursMemoryBackend, FieldSteppedClock) {
    // Constructed in the body rather than as a default argument: default
    // argument expressions are evaluated in a nonisolated context, and
    // `FieldSteppedClock` is main-actor here. The same reason `FieldZoneShell`
    // builds its store inside `init` rather than defaulting it.
    let clock = clock ?? FieldSteppedClock(start)
    return (YoursMemoryBackend(clock: clock), clock)
}

/// Asserted to the second rather than to the bit.
///
/// Two routes produce these dates — `Calendar.date(byAdding:)` for the
/// intervals Postgres also computes, and `addingTimeInterval` for the snooze —
/// and at epoch scale a `Date`'s Double has a ulp around a ten-millionth of a
/// second, so the two can disagree in the last bits while naming the same
/// instant. A tolerance of one second is many orders of magnitude below
/// anything this feature can care about: the shortest window in the whole
/// design is seven days.
private func isDays(_ interval: TimeInterval?, _ days: Int) -> Bool {
    guard let interval else { return false }
    return abs(interval - Double(days) * 86_400) < 1
}

// MARK: - Intervals

@Suite("A natural life")
@MainActor
struct YoursIntervalTests {
    @Test("The first life is six weeks")
    func firstLife() {
        let ready = YoursDates.projectedReadyAt(renewalCount: 0, from: start)
        #expect(isDays(ready.timeIntervalSince(start), 42))
    }

    @Test("The first renewal is twelve weeks, not another six")
    func firstRenewal() {
        let ready = YoursDates.projectedReadyAt(renewalCount: 1, from: start)
        #expect(isDays(ready.timeIntervalSince(start), 84))
    }

    @Test("The outer bound tracks ready_at, always")
    func outerBound() {
        let ready = YoursDates.projectedReadyAt(from: start)
        let bound = YoursDates.outerBound(after: ready)
        #expect(bound > ready)
        #expect(
            YoursDates.calendar.dateComponents([.year], from: ready, to: bound)
                .year == 1
        )
    }

    /// §3, and the line CIRCLE.md contradicted itself on: editing restarts the
    /// current interval and does not demote the stage.
    @Test("Editing an entry in its first renewal gets twelve weeks, not six")
    func editKeepsTheStage() async throws {
        let (store, clock) = backend()
        var entry = try await store.save(clientID: "a", body: "first")

        clock.advance(days: 42)
        _ = try await store.presentNext(visit: YoursVisit())
        entry = try await store.keepForNow(entryID: entry.id, visit: YoursVisit())
        #expect(entry.renewalCount == 1)

        clock.advance(days: 1)
        let edited = try await store.edit(entryID: entry.id, body: "second")

        #expect(edited.renewalCount == 1)
        #expect(isDays(edited.readyAt.timeIntervalSince(clock.now), 84))
    }
}

// MARK: - The presentation gate

@Suite("Returns wait until they can be shown")
@MainActor
struct YoursGateTests {
    @Test("Nothing returns before its interval has elapsed")
    func nothingEarly() async throws {
        let (store, clock) = backend()
        _ = try await store.save(clientID: "a", body: "not yet")

        clock.advance(days: 41)
        #expect(try await store.presentNext(visit: YoursVisit()) == nil)
    }

    /// Locked #5, and the reason the whole gate exists: an entry can sit ready
    /// indefinitely without being at risk, because the clock that releases
    /// something only runs once the person has been asked.
    @Test("The decision window starts when the entry is shown, not when it ripens")
    func windowStartsAtPresentation() async throws {
        let (store, clock) = backend()
        _ = try await store.save(clientID: "a", body: "waiting")

        clock.advance(days: 200)
        let presented = try #require(
            try await store.presentNext(visit: YoursVisit())
        )

        #expect(presented.presentedAt == clock.now)
        #expect(isDays(presented.decideBy?.timeIntervalSince(clock.now), 7))
    }

    @Test("The oldest ready entry is the one presented")
    func chronological() async throws {
        let (store, clock) = backend()
        _ = try await store.save(clientID: "older", body: "first written")
        clock.advance(days: 1)
        _ = try await store.save(clientID: "newer", body: "second written")

        clock.advance(days: 42)
        let presented = try await store.presentNext(visit: YoursVisit())
        #expect(presented?.clientID == "older")
    }

    @Test("Asking twice in one visit presents the same entry, never a second")
    func idempotentWithinAVisit() async throws {
        let (store, clock) = backend()
        _ = try await store.save(clientID: "a", body: "one")
        _ = try await store.save(clientID: "b", body: "two")
        clock.advance(days: 42)

        let visit = YoursVisit()
        let first = try await store.presentNext(visit: visit)
        let second = try await store.presentNext(visit: visit)

        #expect(first?.id == second?.id)
    }

    @Test("The next entry waits for the next visit")
    func nextVisitOnly() async throws {
        let (store, clock) = backend()
        let a = try await store.save(clientID: "a", body: "one")
        _ = try await store.save(clientID: "b", body: "two")
        clock.advance(days: 42)

        let visit = YoursVisit()
        _ = try await store.presentNext(visit: visit)
        _ = try await store.keepForNow(entryID: a.id, visit: visit)

        #expect(try await store.presentNext(visit: visit) == nil)
        #expect(try await store.presentNext(visit: YoursVisit()) != nil)
    }
}

// MARK: - One week, once

@Suite("Give me a week")
@MainActor
struct YoursSnoozeTests {
    @Test("A snooze returns in seven days and ends fourteen days out")
    func exactlyOneWeek() async throws {
        let (store, clock) = backend()
        let entry = try await store.save(clientID: "a", body: "not now")
        clock.advance(days: 42)

        let visit = YoursVisit()
        _ = try await store.presentNext(visit: visit)
        let snoozed = try await store.snooze(entryID: entry.id, visit: visit)

        #expect(isDays(snoozed.readyAt.timeIntervalSince(clock.now), 7))
        #expect(isDays(snoozed.decideBy?.timeIntervalSince(clock.now), 14))
        #expect(snoozed.canSnooze == false)
    }

    @Test("There is no second snooze")
    func onlyOnce() async throws {
        let (store, clock) = backend()
        let entry = try await store.save(clientID: "a", body: "not now")
        clock.advance(days: 42)

        var visit = YoursVisit()
        _ = try await store.presentNext(visit: visit)
        _ = try await store.snooze(entryID: entry.id, visit: visit)

        clock.advance(days: 7)
        visit = YoursVisit()
        _ = try await store.presentNext(visit: visit)

        await #expect(throws: YoursError.oneWeekOnce) {
            _ = try await store.snooze(entryID: entry.id, visit: visit)
        }
    }
}

// MARK: - Held

@Suite("Held is a state, not a destination")
@MainActor
struct YoursHeldTests {
    @Test("Letting something return gives a fresh first life and clears history")
    func letThisReturn() async throws {
        let (store, clock) = backend()
        let entry = try await store.save(clientID: "a", body: "keep this")
        clock.advance(days: 42)

        let visit = YoursVisit()
        _ = try await store.presentNext(visit: visit)
        _ = try await store.keepForNow(entryID: entry.id, visit: visit)
        _ = try await store.hold(entryID: entry.id, visit: nil)

        let returning = try await store.letThisReturn(entryID: entry.id, body: nil)

        #expect(returning.state == .living)
        #expect(returning.renewalCount == 0)
        #expect(returning.heldAt == nil)
        #expect(isDays(returning.readyAt.timeIntervalSince(clock.now), 42))
    }

    /// §4. New words do not inherit permanence.
    @Test("A held entry cannot be edited by writing over it")
    func heldNeedsAChoice() async throws {
        let (store, _) = backend()
        let entry = try await store.save(clientID: "a", body: "permanent")
        _ = try await store.hold(entryID: entry.id, visit: nil)

        await #expect(throws: YoursError.heldNeedsAnExplicitChoice) {
            _ = try await store.edit(entryID: entry.id, body: "quietly different")
        }
    }

    @Test("Update Held overwrites and stays held")
    func updateHeld() async throws {
        let (store, _) = backend()
        let entry = try await store.save(clientID: "a", body: "permanent")
        _ = try await store.hold(entryID: entry.id, visit: nil)

        let updated = try await store.updateHeld(
            entryID: entry.id, body: "still permanent"
        )
        #expect(updated.state == .held)
        #expect(updated.body == "still permanent")
    }
}

// MARK: - Nothing resurrects

@Suite("Let go stays gone")
@MainActor
struct YoursDestroyQueueTests {
    private func queue() -> YoursDestroyQueue {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        return YoursDestroyQueue(directory: directory)
    }

    @Test("A queued destruction survives being written and read back")
    func roundTrips() {
        let queue = queue()
        queue.enqueue(entryID: "one", reason: .noLongerTrue)

        let pending = queue.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.entryID == "one")
        #expect(pending.first?.reason == .noLongerTrue)
    }

    @Test("Queueing the same entry twice queues it once")
    func idempotent() {
        let queue = queue()
        queue.enqueue(entryID: "one", reason: nil)
        queue.enqueue(entryID: "one", reason: .resolved)
        #expect(queue.pending().count == 1)
    }

    @Test("Confirmation is the only thing that clears it")
    func clearsOnConfirmation() {
        let queue = queue()
        queue.enqueue(entryID: "one", reason: nil)
        queue.clear(entryID: "two")
        #expect(queue.pending().count == 1)
        queue.clear(entryID: "one")
        #expect(queue.pending().isEmpty)
    }

    /// The queue carries an identifier and a reason. It must never carry the
    /// words — that is the entire point of not reusing `FieldOutbox`, which
    /// persists mutation payloads.
    @Test("The queue never holds the entry's text")
    func holdsNoText() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let queue = YoursDestroyQueue(directory: directory)
        queue.enqueue(entryID: "one", reason: .notReady)

        let file = directory.appendingPathComponent("yours-destroy.json")
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(!written.contains("body"))
        #expect(written.contains("one"))
    }
}

// MARK: - Taking it back

/// A backend that is exactly the memory one until the network is asked to
/// destroy something, at which point it is a phone in a lift.
///
/// Written out longhand rather than by making `YoursMemoryBackend` injectable:
/// that type also backs the seeded and gallery runs, and a failure switch on it
/// is a switch somebody can leave on in a build people look at.
@MainActor
private final class YoursOfflineLetGoBackend: YoursBackend {
    private let wrapped: YoursMemoryBackend
    private(set) var letGoAttempts = 0

    init(_ wrapped: YoursMemoryBackend) { self.wrapped = wrapped }

    private struct Offline: Error {}

    func letGo(
        entryID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws {
        letGoAttempts += 1
        throw Offline()
    }

    /// Everything else is the real thing.
    func load() async throws -> YoursSnapshot { try await wrapped.load() }
    func save(clientID: String, body: String) async throws -> YoursEntry {
        try await wrapped.save(clientID: clientID, body: body)
    }
    func edit(entryID: String, body: String) async throws -> YoursEntry {
        try await wrapped.edit(entryID: entryID, body: body)
    }
    func presentNext(visit: YoursVisit) async throws -> YoursEntry? {
        try await wrapped.presentNext(visit: visit)
    }
    func presentNextOffer(visit: YoursVisit) async throws -> YoursPreparedOffer? {
        try await wrapped.presentNextOffer(visit: visit)
    }
    func keepForNow(entryID: String, visit: YoursVisit) async throws -> YoursEntry {
        try await wrapped.keepForNow(entryID: entryID, visit: visit)
    }
    func hold(entryID: String, visit: YoursVisit?) async throws -> YoursEntry {
        try await wrapped.hold(entryID: entryID, visit: visit)
    }
    func snooze(entryID: String, visit: YoursVisit) async throws -> YoursEntry {
        try await wrapped.snooze(entryID: entryID, visit: visit)
    }
    func letThisReturn(entryID: String, body: String?) async throws -> YoursEntry {
        try await wrapped.letThisReturn(entryID: entryID, body: body)
    }
    func updateHeld(entryID: String, body: String) async throws -> YoursEntry {
        try await wrapped.updateHeld(entryID: entryID, body: body)
    }
    func prepareOffer(
        entryID: String,
        clientID: String,
        title: String,
        question: String,
        options: [String],
        visit: YoursVisit?
    ) async throws -> YoursPreparedOffer {
        try await wrapped.prepareOffer(
            entryID: entryID,
            clientID: clientID,
            title: title,
            question: question,
            options: options,
            visit: visit
        )
    }
    func sendOffer(offerID: String) async throws {
        try await wrapped.sendOffer(offerID: offerID)
    }
    func letOfferGo(
        offerID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws {
        try await wrapped.letOfferGo(
            offerID: offerID,
            visit: visit,
            reason: reason
        )
    }
    func touch() async throws { try await wrapped.touch() }
    func markTaught(_ moment: YoursTeachingMoment) async throws -> YoursOwnerState {
        try await wrapped.markTaught(moment)
    }
}

/// Nothing is listed on this surface any more, so the save receipt is the only
/// moment an entry is visible between being written and returning six weeks
/// later — and therefore the only moment a mistake is catchable. The thing that
/// must never happen is an undone entry coming back.
@Suite("Undo, and the entry never comes back")
@MainActor
struct YoursUndoTests {
    @Test("Undoing a save destroys the entry rather than hiding the receipt")
    func undoOnline() async {
        let (memory, clock) = backend()
        let store = YoursStore(backend: memory, clock: clock)
        await store.open()

        store.draft = "written by accident"
        await store.save()
        #expect(store.justSaved != nil)
        #expect(try! await memory.load().living.count == 1)

        await store.undoSave()

        #expect(store.justSaved == nil)
        #expect(store.snapshot.living.isEmpty)
        // The one that matters: gone from the backend, not just from the view.
        // A reload is what a relaunch does.
        #expect(try! await memory.load().living.isEmpty)
    }

    @Test("Undo with no receipt on screen does nothing at all")
    func undoWithoutASave() async {
        let (memory, clock) = backend()
        let store = YoursStore(backend: memory, clock: clock)
        await store.open()

        store.draft = "kept on purpose"
        await store.save()
        store.dismissSaveConfirmation()

        await store.undoSave()
        #expect(try! await memory.load().living.count == 1)
    }

    /// The race this exists to pin: an undo that fails at the network must not
    /// leave the entry alive locally *or* forget the intent. `letGo` drops the
    /// row before it consults the network and puts the destruction in
    /// `YoursDestroyQueue`, which drains on the next open — so reconnecting
    /// finishes the job instead of undoing the undo.
    @Test("An undo made offline is still an undo after reconnecting")
    func undoOffline() async {
        let (memory, clock) = backend()
        let queue = YoursDestroyQueue.shared
        for pending in queue.pending() { queue.clear(entryID: pending.entryID) }

        let offline = YoursOfflineLetGoBackend(memory)
        let store = YoursStore(backend: offline, clock: clock)
        await store.open()

        store.draft = "written by accident, on a train"
        await store.save()
        let saved = store.justSaved
        #expect(saved != nil)

        await store.undoSave()

        // Locally it is already gone — §11 does not wait for a network to tell
        // somebody their own decision took effect.
        #expect(store.justSaved == nil)
        #expect(store.snapshot.living.isEmpty)
        #expect(offline.letGoAttempts == 1)

        // And the intent survived, keyed to the entry rather than to the words.
        let pending = queue.pending()
        #expect(pending.contains { $0.entryID == saved?.id })

        // Reconnected: the queue drains against a backend that works, and the
        // entry is destroyed for real. Nothing here reinstates it.
        let reconnected = YoursStore(backend: memory, clock: clock)
        await reconnected.drainDestroyQueue()
        #expect(try! await memory.load().living.isEmpty)
        #expect(!queue.pending().contains { $0.entryID == saved?.id })

        // A relaunch reads from the backend, so this is what the next launch
        // would show.
        await reconnected.open()
        #expect(reconnected.snapshot.living.isEmpty)
    }
}

// MARK: - Nearing return

@Suite("The stroke lightens, and never counts")
struct YoursNearingTests {
    @Test("There is no ramp until the final week")
    func nilBeforeTheWeek() {
        let readyAt = start.addingTimeInterval(20 * 86_400)
        #expect(YoursDates.nearingProgress(readyAt: readyAt, now: start) == nil)
    }

    @Test("The ramp runs zero to one across the final week")
    func rampsAcrossTheWeek() {
        let readyAt = start.addingTimeInterval(7 * 86_400)
        let atStart = YoursDates.nearingProgress(readyAt: readyAt, now: start)
        let midway = YoursDates.nearingProgress(
            readyAt: readyAt,
            now: start.addingTimeInterval(3.5 * 86_400)
        )
        #expect(atStart == 0)
        #expect(midway == 0.5)
    }

    @Test("Once it is ready it is not nearing anything")
    func nilOnceReady() {
        let readyAt = start.addingTimeInterval(-1)
        #expect(YoursDates.nearingProgress(readyAt: readyAt, now: start) == nil)
    }
}

// MARK: - What this space is not allowed to say

/// The same shape as `FieldConstraintTests`: the constraint is on the whole
/// set of strings rather than on any one of them, so it is asserted over the
/// whole set.
@Suite("No numerals, no counts, no guilt")
struct YoursCopyTests {
    private static let everything: [String] = [
        YoursCopy.compose, YoursCopy.saved, YoursCopy.undoSave,
        YoursCopy.empty,
        YoursCopy.returnQuestion, YoursCopy.keepForNow, YoursCopy.letGo,
        YoursCopy.keepIndefinitely, YoursCopy.keepOnlyForMe,
        YoursCopy.prepareAnOffer, YoursCopy.letItGo, YoursCopy.snooze,
        YoursCopy.heldDrawer, YoursCopy.letThisReturn,
        YoursCopy.letThisReturnDetail, YoursCopy.letGoNow,
        YoursCopy.heldEditQuestion, YoursCopy.updateHeld,
        YoursCopy.reviewHeld, YoursCopy.prepareOffer, YoursCopy.send,
        YoursCopy.releaseReasonPrompt, YoursCopy.releaseReasonDecline,
        YoursCopy.teachingTitle, YoursCopy.teachingBody,
        YoursCopy.deletionAssurance, YoursCopy.dormancyDisclosure,
        YoursCopy.outerBoundDisclosure,
    ]

    /// A numeral in this product is a metric, and this product does not show
    /// metrics about its users. Durations are spelled — "six weeks", "ninety
    /// days" — exactly as the rest of the app spells them.
    ///
    /// One exemption, and it is the interesting one. §8 mandates the deletion
    /// assurance verbatim — "unrecoverable within 24 hours" — and that string
    /// contains a digit. It is exempt because it is not a measurement *of the
    /// person*: it is a claim about infrastructure, and the whole reason it is
    /// worded that way is that a rounder promise would be one the
    /// infrastructure cannot yet demonstrate. Spelling it "twenty-four" to
    /// satisfy this rule would be dressing a service-level guarantee up as
    /// prose.
    @Test("Nothing in the copy contains a digit, bar the deletion guarantee")
    func noDigits() {
        for line in Self.everything where line != YoursCopy.deletionAssurance {
            #expect(
                line.rangeOfCharacter(from: .decimalDigits) == nil,
                "\(line) contains a numeral"
            )
        }
    }

    @Test("No streaks, counts, percentages or overdue states")
    func noMetrics() {
        let forbidden = [
            "streak", "%", "percent", "overdue", "remaining", "left",
            "days left", "count", "total", "score",
        ]
        for line in Self.everything {
            let lowered = line.lowercased()
            for word in forbidden {
                #expect(!lowered.contains(word), "\(line) contains \(word)")
            }
        }
    }

    /// §2's bounded exception, asserted as a bound.
    ///
    /// If a third surface starts saying the word, this fails — which is the
    /// intent. Making it wordless again after it has been learned is the whole
    /// design; widening the exception is a product decision, not a copy edit.
    @Test("The word appears in exactly one string, plus the spoken name")
    func theWordIsBounded() {
        let uses = Self.everything.filter { $0.contains("Yours") }
        #expect(uses == [YoursCopy.teachingTitle])
        #expect(YoursCopy.accessibilityName == "Yours")
    }

    /// §8 and §14. Until the key service closes, the product may not claim a
    /// thing is gone the instant it is asked to be.
    @Test("Deletion copy promises a measurable outcome, not an instant one")
    func deletionCopyIsCapped() {
        let lowered = YoursCopy.deletionAssurance.lowercased()
        #expect(lowered.contains("unrecoverable"))
        #expect(!lowered.contains("instant"))
        #expect(!lowered.contains("immediately"))
    }
}

// MARK: - Dates the owner is told

@Suite("Completely legible to the owner")
struct YoursDateSentenceTests {
    @Test("The save detail names both the return and the outer bound")
    func saveDetail() {
        let readyAt = YoursDates.projectedReadyAt(from: start)
        let sentence = YoursDates.saveDetail(
            readyAt: readyAt,
            unseenDeleteAt: YoursDates.outerBound(after: readyAt),
            now: start
        )
        #expect(sentence.contains(YoursDates.spoken(readyAt)))
        #expect(sentence.contains("disappear"))
    }

    @Test("The snooze confirmation names the exact final date")
    func snoozeConfirmation() {
        let returnsOn = start.addingTimeInterval(7 * 86_400)
        let letGoOn = returnsOn.addingTimeInterval(7 * 86_400)
        let sentence = YoursDates.snoozeConfirmation(
            returnsOn: returnsOn,
            letGoOn: letGoOn
        )
        #expect(sentence.contains(YoursDates.spoken(returnsOn)))
        #expect(sentence.contains(YoursDates.spoken(letGoOn)))
    }
}
