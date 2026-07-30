//
//  FieldStore.swift
//  WE
//
//  The one place the zones read from.
//
//  Persisted domain state and ephemeral UI state are kept in separate structs
//  because the handoff draws that line explicitly, and because Today depends
//  on it: "Today is **derived, never stored**." `todaySelection` is a computed
//  property, not a field, so there is no way to accidentally persist it.
//

import Foundation
import Observation

// MARK: - Persistence seam
//
// The zones never touch a repository. `FieldBackend` is the whole surface, so
// the Supabase implementation and the in-memory one are interchangeable and
// previews stay honest.

protocol FieldBackend: Sendable {
    func load() async throws -> FieldState
    func append(_ capture: FieldCapture) async throws
    func record(_ correction: FieldCorrection) async throws
    func upsert(_ item: LifeItem) async throws
    func upsert(_ item: OursItem) async throws
    func answer(question: String, choice: String) async throws
    func setHeld(_ topic: FieldHeldTopic) async throws
    func setStandingRule(_ rule: FieldStandingRule) async throws
    func setIdentity(_ identity: FieldIdentity) async throws
    func changes() -> AsyncStream<Void>
}

/// Everything the app persists. One value, so a load is atomic and a
/// realtime change can be diffed in one place.
struct FieldState: Codable, Hashable, Sendable {
    var identity: FieldIdentity
    var partners: [FieldPartner]
    var lifeItems: [LifeItem]
    var clusters: [FieldCluster]
    var oursItems: [OursItem]
    var horizons: [FieldHorizon]
    var rhythms: [FieldRhythm]
    var anchors: [FieldAnchor]
    var threads: [FieldThread]
    var evidence: [FieldEvidence]
    var seasons: [FieldSeason]
    var heldTopics: [FieldHeldTopic]
    var standingRules: [FieldStandingRule]
    var corrections: [FieldCorrection]
    var captures: [FieldCapture]
    var dailyMoment: FieldDailyMoment
    var learningSince: Date

    static let seed = FieldState(
        identity: FieldSampleData.identity,
        partners: FieldSampleData.partners,
        lifeItems: FieldSampleData.lifeItems,
        clusters: FieldSampleData.clusters,
        oursItems: FieldSampleData.oursItems,
        horizons: FieldSampleData.horizons,
        rhythms: FieldSampleData.rhythms,
        anchors: FieldSampleData.anchors,
        threads: FieldSampleData.threads,
        evidence: FieldSampleData.evidence,
        seasons: [FieldSampleData.season],
        heldTopics: FieldSampleData.heldTopics,
        standingRules: FieldSampleData.standingRules,
        corrections: [],
        captures: FieldSampleData.capturedThisWeek,
        dailyMoment: FieldSampleData.dailyMoment,
        learningSince: FieldSampleData.learningSince
    )
}

// MARK: - Store

@MainActor
@Observable
final class FieldStore {
    // MARK: Persisted

    private(set) var state: FieldState

    // MARK: Ephemeral UI state
    //
    // Listed in the handoff as: activeZone (0–2, default 1), per-zone scroll
    // offset, remindersOpen, activeCluster, captureDraft, lastReceipt.

    /// WE is index 1 and is the home. Cold launch always lands on Today.
    var activeZone: FieldZone = .we
    // Per-zone scroll offset is listed in the handoff's ephemeral state, but
    // it is not stored here: the paging TabView keeps all three zones mounted,
    // so each ScrollView keeps its own position for free. Mirroring it would
    // add a second source of truth that can only ever disagree.
    var remindersOpen = false
    var activeClusterIndex = 0
    var captureDraft = ""
    var lastReceipt: FieldReceipt?
    /// Which Ours list the filter pills have selected.
    var oursFilter: OursList = .watchlist
    /// Set when the user taps WRONG PLACE — the corrective picker.
    var correctingReceipt: FieldReceipt?

    /// Overridden in previews and UI tests so the fixed sample date holds.
    var now: Date

    private let backend: FieldBackend?
    private let calendar = Calendar.gregorianUS

    /// Both defaults resolve inside the body rather than in the parameter
    /// list. Default argument expressions are evaluated in a nonisolated
    /// context, and under the project's MainActor-by-default isolation
    /// `FieldState.seed` and `FieldSampleData.today` are both main
    /// actor-isolated — so referencing them as defaults warns today and fails
    /// outright in Swift 6 language mode.
    init(
        state: FieldState? = nil,
        now: Date? = nil,
        backend: FieldBackend? = nil
    ) {
        self.state = state ?? .seed
        self.now = now ?? FieldSampleData.today
        self.backend = backend
    }

    // MARK: Derived

    var identity: FieldIdentity { state.identity }

    var speaker: FieldOwner {
        // Which of the two is holding the phone. Until multi-device identity
        // is wired this is person A; it never affects routing, only the tint
        // on a capture chip.
        .a
    }

    private var selectorContext: FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: now,
            identity: state.identity,
            partners: state.partners,
            lifeItems: state.lifeItems,
            clusters: state.clusters,
            horizons: state.horizons,
            heldTopics: state.heldTopics,
            standingRules: state.standingRules,
            calendar: calendar
        )
    }

    private var classifierContext: FieldClassifier.Context {
        FieldClassifier.Context(
            identity: state.identity,
            speaker: speaker,
            now: now,
            oursItems: state.oursItems,
            horizons: state.horizons,
            rhythms: state.rhythms,
            corrections: state.corrections,
            partners: state.partners,
            calendar: calendar
        )
    }

    /// Derived on every read. Never stored, never cached across a change.
    var todaySelection: FieldTodaySelector.Result {
        FieldTodaySelector.select(selectorContext)
    }

    var todayCandidates: [FieldTodaySelector.Candidate] {
        FieldTodaySelector.rank(selectorContext)
    }

    var watching: [FieldWatchItem] {
        FieldTodaySelector.watching(selectorContext)
    }

    var primaryHorizon: FieldHorizon? {
        state.horizons.first(where: \.isPrimary)
    }

    var otherHorizons: [FieldHorizon] {
        state.horizons.filter { !$0.isPrimary }
    }

    var currentSeason: FieldSeason? {
        state.seasons.first(where: \.isOpen)
    }

    /// Clusters ordered by urgency, most pressing first.
    var orderedClusters: [FieldCluster] {
        state.clusters.sorted {
            $0.urgency(now: now, items: state.lifeItems)
                > $1.urgency(now: now, items: state.lifeItems)
        }
    }

    var activeCluster: FieldCluster? {
        let ordered = orderedClusters
        guard ordered.indices.contains(activeClusterIndex) else {
            return ordered.first
        }
        return ordered[activeClusterIndex]
    }

    func items(in cluster: FieldCluster) -> [LifeItem] {
        cluster.items(from: state.lifeItems)
    }

    func openItems(in category: LifeCategory) -> [LifeItem] {
        state.lifeItems.filter { $0.category == category && !$0.isDone }
    }

    /// The count beside a category word. Warm when something in it is
    /// time-pressured, quiet otherwise.
    func isPressured(_ category: LifeCategory) -> Bool {
        openItems(in: category).contains {
            $0.isTimeCritical || $0.pressure(now: now, calendar: calendar) > 0.7
        }
    }

    func summary(for category: LifeCategory) -> String {
        FieldSampleData.categorySummaries[category] ?? ""
    }

    var oursForFilter: [OursItem] {
        state.oursItems.filter { $0.list == oursFilter }
    }

    func count(for list: OursList) -> Int {
        FieldSampleData.oursCounts[list]
            ?? state.oursItems.filter { $0.list == list }.count
    }

    func horizonTitle(_ id: String?) -> String? {
        guard let id else { return nil }
        guard let horizon = state.horizons.first(where: { $0.id == id })
        else { return nil }
        return [horizon.title, horizon.window]
            .compactMap { $0 }
            .joined(separator: " ")
            .replacingOccurrences(of: ", ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }

    var heldTopics: [FieldHeldTopic] {
        FieldDeferral.holding(
            state.heldTopics,
            context: FieldDeferral.Context(
                now: now,
                identity: state.identity,
                partners: state.partners,
                standingRules: state.standingRules,
                calendar: calendar
            )
        )
    }

    var behaviourChanges: [FieldBehaviourChange] {
        let derived = FieldLearning.behaviourChanges(
            from: state.corrections,
            identity: state.identity,
            moment: state.dailyMoment,
            now: now,
            calendar: calendar
        )
        // Until enough corrections exist to derive from, the receipt shows the
        // seeded set rather than an empty screen — it is a periodic surface,
        // not a live one.
        return derived.count >= 3 ? derived : FieldSampleData.behaviourChanges
    }

    var monthsLearning: Int {
        FieldLearning.monthsLearning(
            since: state.learningSince,
            now: now,
            calendar: calendar
        )
    }

    var momentDecision: FieldMomentScheduler.Decision {
        FieldMomentScheduler.decide(
            moment: state.dailyMoment,
            candidates: todayCandidates,
            selection: todaySelection,
            now: now,
            calendar: calendar
        )
    }

    /// The partner who is away right now, if either is. Drives 6b.
    var absentPartner: FieldPartner? {
        state.partners.first { $0.isAway(on: now) }
    }

    var presentPartner: FieldPartner? {
        guard let absent = absentPartner else { return nil }
        return state.partners.first { $0.id != absent.id }
    }

    // MARK: Navigation

    func go(to zone: FieldZone) {
        activeZone = zone
    }

    /// Tapping the WE mark always returns to Today. A hard requirement.
    func returnHome() {
        remindersOpen = false
        activeZone = .we
    }

    func openReminders() {
        activeClusterIndex = 0
        remindersOpen = true
    }

    func closeReminders() {
        remindersOpen = false
    }

    func advanceCluster() {
        let count = orderedClusters.count
        guard count > 0 else { return }
        activeClusterIndex = min(activeClusterIndex + 1, count - 1)
    }

    func retreatCluster() {
        activeClusterIndex = max(activeClusterIndex - 1, 0)
    }

    var isOnLastCluster: Bool {
        activeClusterIndex >= orderedClusters.count - 1
    }

    var nextCluster: FieldCluster? {
        let ordered = orderedClusters
        let next = activeClusterIndex + 1
        return ordered.indices.contains(next) ? ordered[next] : nil
    }

    // MARK: Capture

    func submitCapture() {
        let text = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let receipt = FieldClassifier.classify(text, context: classifierContext)
        lastReceipt = receipt
        captureDraft = ""

        let capture = FieldCapture(
            id: receipt.id,
            text: text,
            owner: speaker,
            capturedAt: now
        )
        state.captures.insert(capture, at: 0)
        materialise(receipt)

        Task { [backend] in try? await backend?.append(capture) }
    }

    /// Files the captured text into the zone its destination names. Without
    /// this the receipt would be theatre.
    private func materialise(_ receipt: FieldReceipt) {
        switch receipt.destination {
        case .life(let category):
            state.lifeItems.insert(
                LifeItem(
                    id: receipt.id,
                    title: receipt.input,
                    category: category,
                    owner: speaker,
                    dueOn: nil,
                    closesAt: nil,
                    clusterID: nil,
                    source: .captured,
                    detail: nil,
                    isTimeCritical: false,
                    isDone: false
                ),
                at: 0
            )
        case .ours(let list):
            let match = state.oursItems.first {
                $0.title.localizedCaseInsensitiveCompare(receipt.input)
                    == .orderedSame && $0.addedBy != speaker
            }
            state.oursItems.insert(
                OursItem(
                    id: receipt.id,
                    title: receipt.input,
                    list: list,
                    addedBy: match == nil ? speaker : .shared,
                    addedAt: now,
                    bothAdded: match != nil,
                    coincidenceNote: match == nil
                        ? nil
                        : "Both added it, independently",
                    horizonID: nil,
                    isStandingNote: false
                ),
                at: 0
            )
        case .usHorizons:
            // A leaning, not a decision — it does not create a horizon on its
            // own, it attaches to the primary one.
            guard let index = state.horizons.firstIndex(where: \.isPrimary)
            else { return }
            state.horizons[index].linkedOursItemIDs.append(receipt.id)
        }
    }

    func acknowledgeReceipt() {
        lastReceipt?.acknowledged = true
    }

    func beginCorrection() {
        correctingReceipt = lastReceipt
    }

    /// One tap to a corrected destination. Every correction becomes training
    /// signal that surfaces later in the correction receipt (6a).
    func correct(to destination: FieldDestination) {
        guard let receipt = correctingReceipt ?? lastReceipt else { return }
        let result = FieldClassifier.correct(
            receipt,
            to: destination,
            context: classifierContext
        )
        lastReceipt = result.receipt
        correctingReceipt = nil
        state.corrections.append(result.correction)

        // Move the materialised object to where it should have gone.
        state.lifeItems.removeAll { $0.id == receipt.id }
        state.oursItems.removeAll { $0.id == receipt.id }
        materialise(result.receipt)

        Task { [backend] in try? await backend?.record(result.correction) }
    }

    func dismissReceipt() {
        lastReceipt = nil
        correctingReceipt = nil
    }

    // MARK: Acting on a moment

    func complete(_ itemID: String) {
        guard let index = state.lifeItems.firstIndex(where: { $0.id == itemID })
        else { return }
        state.lifeItems[index].isDone = true
        let item = state.lifeItems[index]
        Task { [backend] in try? await backend?.upsert(item) }
    }

    func answer(_ question: FieldQuestion, with choice: FieldChoice) {
        guard let index = state.horizons.firstIndex(where: {
            $0.openQuestion?.id == question.id
        }) else { return }

        // Answering a horizon question turns a wish into a date, which is the
        // only reason the app asked.
        state.horizons[index].openQuestion = nil
        state.horizons[index].window = "\(choice.title.lowercased()) 2027"

        state.evidence.insert(
            FieldEvidence(
                id: UUID().uuidString,
                statement: "You chose \(choice.title.lowercased()).",
                owner: .shared,
                horizonID: state.horizons[index].id,
                occurredAt: now
            ),
            at: 0
        )

        Task { [backend] in
            try? await backend?.answer(
                question: question.id,
                choice: choice.id
            )
        }
    }

    // MARK: Deferral (6d)

    func raiseNow(_ topic: FieldHeldTopic) {
        guard let index = state.heldTopics.firstIndex(where: { $0.id == topic.id })
        else { return }
        state.heldTopics[index].wasOverridden = true
        let updated = state.heldTopics[index]
        Task { [backend] in try? await backend?.setHeld(updated) }
    }

    func leaveIt(_ topic: FieldHeldTopic) {
        guard let index = state.heldTopics.firstIndex(where: { $0.id == topic.id })
        else { return }
        state.heldTopics[index].wasDismissed = true
        let updated = state.heldTopics[index]
        Task { [backend] in try? await backend?.setHeld(updated) }
    }

    func addStandingRule(_ text: String) {
        let rule = FieldStandingRule(
            id: UUID().uuidString,
            text: text,
            setAt: now
        )
        state.standingRules.append(rule)
        Task { [backend] in try? await backend?.setStandingRule(rule) }
    }

    // MARK: The daily moment (6c)

    func shiftMoment(byHours delta: Int) {
        let shifted = state.dailyMoment.sendMinute + delta * 60
        state.dailyMoment.sendMinute = min(max(shifted, 5 * 60), 22 * 60)
    }

    func skipToday() {
        state.dailyMoment.lastSentOn = now
    }

    // MARK: Onboarding (6f)

    func choose(_ swatch: FieldSwatch, for owner: FieldOwner) {
        switch owner {
        case .a: state.identity.personA = swatch
        case .b: state.identity.personB = swatch
        case .shared: break
        }
        let identity = state.identity
        Task { [backend] in try? await backend?.setIdentity(identity) }
    }

    // MARK: Loading

    func load() async {
        guard let backend else { return }
        if let loaded = try? await backend.load() {
            state = loaded
        }
        for await _ in backend.changes() {
            if let refreshed = try? await backend.load() {
                state = refreshed
            }
        }
    }
}

// MARK: - In-memory backend
//
// Used by previews, UI tests, and the simulation mode. It is the reference
// implementation of `FieldBackend`, and every rule it enforces is one the
// Supabase implementation must also enforce.

final class FieldMemoryBackend: FieldBackend, @unchecked Sendable {
    private var state: FieldState
    private let lock = NSLock()

    init(state: FieldState = .seed) {
        self.state = state
    }

    func load() async throws -> FieldState {
        lock.withLock { state }
    }

    func append(_ capture: FieldCapture) async throws {
        lock.withLock { state.captures.insert(capture, at: 0) }
    }

    func record(_ correction: FieldCorrection) async throws {
        lock.withLock { state.corrections.append(correction) }
    }

    func upsert(_ item: LifeItem) async throws {
        lock.withLock {
            if let index = state.lifeItems.firstIndex(where: { $0.id == item.id }) {
                state.lifeItems[index] = item
            } else {
                state.lifeItems.insert(item, at: 0)
            }
        }
    }

    func upsert(_ item: OursItem) async throws {
        lock.withLock {
            if let index = state.oursItems.firstIndex(where: { $0.id == item.id }) {
                state.oursItems[index] = item
            } else {
                state.oursItems.insert(item, at: 0)
            }
        }
    }

    func answer(question: String, choice: String) async throws {}

    func setHeld(_ topic: FieldHeldTopic) async throws {
        lock.withLock {
            if let index = state.heldTopics.firstIndex(where: { $0.id == topic.id }) {
                state.heldTopics[index] = topic
            }
        }
    }

    func setStandingRule(_ rule: FieldStandingRule) async throws {
        lock.withLock { state.standingRules.append(rule) }
    }

    func setIdentity(_ identity: FieldIdentity) async throws {
        lock.withLock { state.identity = identity }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
