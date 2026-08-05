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
// For `significantTimeChangeNotification` only — the one thing that tells an
// app the clock was moved or a timezone crossed. Nothing else here touches UI.
import UIKit

// MARK: - Persistence seam
//
// The zones never touch a repository. `FieldBackend` is the whole surface, so
// the Supabase implementation and the in-memory one are interchangeable and
// previews stay honest.

protocol FieldBackend: Sendable {
    /// The member holding this client. Ownership is a persistence fact, not a
    /// presentation default: every capture and filed item derives from this.
    var viewerOwner: FieldOwner { get }

    func load() async throws -> FieldState
    func append(_ capture: FieldCapture) async throws
    func record(_ correction: FieldCorrection) async throws
    func upsert(_ item: LifeItem) async throws
    /// Removing a filed item, for both of them, with no recovery.
    ///
    /// A real delete rather than a `deleted_at` flag: the app tells people the
    /// thing is gone, and a row that is still there but hidden makes that
    /// sentence untrue in the one place it matters.
    func delete(itemID: String) async throws
    /// Answering a promotion question is the only way a horizon is ever
    /// created, so this is the only route by which Us gains anything.
    func upsert(_ horizon: FieldHorizon) async throws
    /// The record that a horizon became real, and every ordinary week that
    /// moved it.
    ///
    /// `field_evidence` was read on every load and written by nothing, so the
    /// whole middle of Us — "what this week did for it" — was whatever seed
    /// data happened to be there, and the "You decided X is real" line a
    /// promotion produced was gone by the next launch. The table was not dead;
    /// the write was missing.
    func upsert(_ evidence: FieldEvidence) async throws
    /// And answering an occasion question is the only way a cluster is. Until
    /// this existed the table was read and never written, so every occasion
    /// any couple had was one that arrived with their seed data.
    func upsert(_ cluster: FieldCluster) async throws
    func answer(question: String, choice: String) async throws
    func setHeld(_ topic: FieldHeldTopic) async throws
    func setStandingRule(_ rule: FieldStandingRule) async throws
    func setIdentity(_ identity: FieldIdentity) async throws
    /// The learned hour, and the last day the app spoke.
    ///
    /// Written because the two controls that change it are real controls: an
    /// hour somebody shifted, or a day they told the app to stay quiet. Both
    /// used to evaporate on relaunch, which is the app forgetting an
    /// instruction it was given while claiming to have learned from it.
    func setDailyMoment(_ moment: FieldDailyMoment) async throws

    /// "I'd welcome a moment together", for the caller's own day.
    ///
    /// Returns nothing, deliberately. The obvious signature hands back the
    /// resulting state so a tap knows immediately whether it bloomed — but
    /// then the offline path has nothing honest to return, and the queue would
    /// have to invent one. Marking and asking are separate calls so that both
    /// have the same meaning whether or not there is a network: the mark is
    /// owed, the state is read.
    func markReady(localDate: String) async throws

    /// Whether the two of them are open to each other today.
    ///
    /// An RPC rather than a read of any table, because the answer has to be
    /// computable without the caller ever being able to see their partner's
    /// row. There is no value meaning "they have, you have not" — see
    /// `FieldReadinessState`.
    func readiness(localDate: String) async throws -> FieldReadiness

    func changes() -> AsyncStream<Void>

    /// How much of this person's solo history has not crossed to their
    /// partner, so the disclosure can name a number before anybody commits.
    func soloHistoryCount() async throws -> Int

    /// Cross it. Returns how many rows moved.
    ///
    /// Scoped server-side to the caller's own rows, so this can never publish
    /// a partner's history — see `field_share_solo_history()` in
    /// `20260803180000_field_solo_visibility.sql`.
    func shareSoloHistory() async throws -> Int
}

/// Defaulted rather than required, so the in-memory backend, the previews, the
/// gallery, and every test fake keep conforming without a line of change.
///
/// Zero is the honest answer for all of them: a backend with no database
/// behind it has no solo era to cross, and returning nothing means the
/// disclosure never appears where it would be meaningless.
extension FieldBackend {
    func soloHistoryCount() async throws -> Int { 0 }
    func shareSoloHistory() async throws -> Int { 0 }

    /// `neither` for the same reason zero is: a backend with no couple behind
    /// it has nobody to be open to, and the mark simply never blooms. Note
    /// which way the default falls — a conformer that forgets to implement
    /// this shows no circle rather than showing one that lies about a partner.
    func markReady(localDate: String) async throws {}
    func readiness(localDate: String) async throws -> FieldReadiness {
        .neither(on: localDate)
    }
}

/// Everything the app persists. One value, so a load is atomic and a
/// realtime change can be diffed in one place.
struct FieldState: Codable, Hashable, Sendable {
    var identity: FieldIdentity
    var partners: [FieldPartner]
    var lifeItems: [LifeItem]
    var clusters: [FieldCluster]
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

    /// What a real couple starts with: nothing.
    ///
    /// This is the live default. `seed` is the fictional couple and belongs
    /// only to the gallery, the previews, and `WE_FIELD=seeded` — reaching a
    /// real screen it reads as the app inventing a relationship, and until
    /// this existed that is exactly what happened between launch and the
    /// first successful load.
    ///
    /// Names come from the session so the app can address people correctly
    /// before it knows anything else about them.
    static func empty(
        nameA: String,
        nameB: String,
        now: Date
    ) -> FieldState {
        FieldState(
            identity: FieldIdentity(
                personA: .clay,
                personB: .slate,
                nameA: nameA,
                nameB: nameB
            ),
            partners: [],
            lifeItems: [],
            clusters: [],
            horizons: [],
            rhythms: [],
            anchors: [],
            threads: [],
            evidence: [],
            seasons: [],
            heldTopics: [],
            standingRules: [],
            corrections: [],
            captures: [],
            // 8:12 is the handoff's learned hour and a defensible first
            // guess. It moves as soon as there is reply data to move it.
            dailyMoment: FieldDailyMoment(
                sendMinute: 8 * 60 + 12,
                queuedCount: 0,
                hourRationale: "I haven't learned your hour yet.",
                replyRateBefore: 0,
                replyRateAfter: 0,
                lastSentOn: nil
            ),
            learningSince: now
        )
    }

    static let seed = FieldState(
        identity: FieldSampleData.identity,
        partners: FieldSampleData.partners,
        lifeItems: FieldSampleData.lifeItems + FieldSampleData.mentioned,
        clusters: FieldSampleData.clusters,
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

    /// The same fictional couple as `seed`, renamed and shifted three months
    /// later — `WE_FIELD=demo`, for showing the product as it looks after a
    /// real couple has been using it a while.
    static let demo = FieldState(
        identity: FieldDemoData.identity,
        partners: FieldDemoData.partners,
        lifeItems: FieldDemoData.lifeItems + FieldDemoData.mentioned,
        clusters: FieldDemoData.clusters,
        horizons: FieldDemoData.horizons,
        rhythms: FieldDemoData.rhythms,
        anchors: FieldDemoData.anchors,
        threads: FieldDemoData.threads,
        evidence: FieldDemoData.evidence,
        seasons: [FieldDemoData.season],
        heldTopics: FieldDemoData.heldTopics,
        standingRules: FieldDemoData.standingRules,
        corrections: [],
        captures: FieldDemoData.capturedThisWeek,
        dailyMoment: FieldDemoData.dailyMoment,
        learningSince: FieldDemoData.learningSince
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
    // offset, calendarOpen, activeCluster, captureDraft, lastReceipt.

    /// WE is index 1 and is the home. Cold launch always lands on Today.
    var activeZone: FieldZone = .we
    // Per-zone scroll offset is listed in the handoff's ephemeral state, but
    // it is not stored here: the paging TabView keeps all three zones mounted,
    // so each ScrollView keeps its own position for free. Mirroring it would
    // add a second source of truth that can only ever disagree.
    /// The calendar surface, reached by pulling down on Life. It replaced the
    /// Reminders takeover, whose occasions now sit at the top of Life itself.
    var calendarOpen = false
    var activeClusterIndex = 0
    var captureDraft = ""
    var lastReceipt: FieldReceipt?
    /// Set when the user taps WRONG PLACE — the corrective picker.
    var correctingReceipt: FieldReceipt?

    /// Corrections made to a receipt that has not been sent. They cross with
    /// it, or not at all.
    private var pendingCorrections: [FieldCorrection] = []

    /// Items somebody said to raise with both of them anyway, and the day
    /// they said it. See `raiseWithBoth`.
    private(set) var overriddenAddressing: [String: Date] = [:]

    /// The outward action waiting on a yes.
    ///
    /// Ephemeral on purpose: an app relaunch is not a confirmation, and a
    /// number somebody never looked at is not a number they agreed to call.
    var pendingOutreach: FieldOutreachRequest?

    /// Something the app opened on somebody's behalf, and has not been told
    /// the outcome of. See `FieldMomentView` — it asks, once.
    var awaitingOutcome: FieldOutcomeQuestion?

    /// Category subtitles the on-device model has written, and the shape of
    /// the items each was written about.
    ///
    /// Ephemeral on purpose: a sentence describing a list that has since
    /// changed is worse than no sentence, and regenerating costs one model
    /// call. The fingerprint is what stops an unrelated capture re-running
    /// all five.
    private(set) var writtenSubtitles: [LifeCategory: String] = [:]
    private var subtitleFingerprints: [LifeCategory: Int] = [:]

    /// The instant every derivation is dated against.
    ///
    /// Stored rather than computed, deliberately. `todaySelection` is read
    /// several times a frame and each read has to see the same instant — and
    /// a computed `{ Date() }` would never invalidate anything under
    /// `@Observable`, so midnight would arrive and nothing on screen would
    /// know. One stored observable value means the day turning is one redraw
    /// rather than none. See `FieldClock`.
    private(set) var now: Date

    // MARK: What the app knows, and how sure it is

    /// Whether what the zones are drawing is current, remembered, or missing.
    ///
    /// The app is allowed to say "this is what I last saw." It is not allowed
    /// to say "there is nothing here" when what it means is "I could not
    /// reach the server" — that is the app telling a couple their
    /// relationship is empty, and it is the failure this enum exists to make
    /// impossible to express.
    enum LoadState: Equatable {
        /// Before the first answer. Not a spinner: the zones simply draw
        /// whatever was cached, which is usually right.
        case loading
        case loaded
        /// Reachable once, not now. Carries when.
        case stale(Date)
        /// Never loaded, and nothing cached to fall back on. The only state
        /// that shows a retry.
        case failed
    }

    private(set) var loadState: LoadState = .loading

    /// When the server last answered — from the cache at launch, then from
    /// each successful load. What `.stale` renders.
    private(set) var lastLoadedAt: Date?

    private let clock: FieldClock
    private let backend: FieldBackend?
    /// Where a number comes from. Defaults to the one that finds nobody, for
    /// the same reason `backend` defaults to nil: a preview, a gallery run or
    /// a screenshot must not depend on what is in this machine's address
    /// book, and must never leave the process.
    private let resolver: any FieldTargetResolver
    private let calendar = Calendar.gregorianUS

    /// Both defaults resolve inside the body rather than in the parameter
    /// list. Default argument expressions are evaluated in a nonisolated
    /// context, and under the project's MainActor-by-default isolation
    /// `FieldState.seed` and `FieldSampleData.today` are both main
    /// actor-isolated — so referencing them as defaults warns today and fails
    /// outright in Swift 6 language mode.
    ///
    /// An explicit `now:` *is* a pinned clock: the caller named an instant and
    /// nothing should move it under them. Passing neither is the gallery, and
    /// the gallery's date is the sample couple's.
    init(
        state: FieldState? = nil,
        now: Date? = nil,
        backend: FieldBackend? = nil,
        clock: FieldClock? = nil,
        resolver: (any FieldTargetResolver)? = nil,
        lastLoadedAt: Date? = nil
    ) {
        self.state = state ?? .seed
        self.lastLoadedAt = lastLoadedAt
        self.clock = clock
            ?? now.map { FieldFixedClock(now: $0) }
            ?? FieldFixedClock(now: FieldSampleData.today)
        self.now = self.clock.now
        self.backend = backend
        self.resolver = resolver ?? FieldNoTargetResolver()
        // Nobody, until the server says otherwise. The circle starts closed on
        // every launch and is never restored from disk — there is nothing on
        // disk to restore it from, deliberately.
        self.storedReadiness = .neither(
            on: FieldReadiness.localDate(for: self.clock.now)
        )
    }

    // MARK: The day turning

    /// Re-reads the clock. That is the whole of "the day turned" — nothing is
    /// recomputed here because nothing was ever cached: `todaySelection`,
    /// `thisWeek`, and every pressure value are derived from `now` on read.
    ///
    /// Gated on the day or the hour rather than the instant. `now` is
    /// observable, so writing it on every foreground would redraw all three
    /// zones over a two-second difference nobody can see. The hour is the
    /// finest grain anything actually depends on: `violatesStandingRule`
    /// reads the hour, so does the ambient wash, and everything else reads
    /// the day.
    func tick() {
        guard clock.advances else { return }

        let current = clock.now
        let sameDay = calendar.isDate(current, inSameDayAs: now)
        let sameHour = calendar.component(.hour, from: current)
            == calendar.component(.hour, from: now)
        guard !(sameDay && sameHour) else { return }

        now = current
    }

    /// Keeps `now` true for as long as the app is on screen.
    ///
    /// Two sources, because neither covers the other's case: the calendar day
    /// changing is the only thing that fires for an app left open across
    /// midnight, and the significant time change covers a timezone crossing
    /// or a hand-set clock. Both do the same thing, so there is no ordering
    /// to get wrong. Foregrounding is handled by the caller, which ticks on
    /// the way in — the system posts neither of these for the hours a process
    /// spent suspended.
    func followTheClock() async {
        guard clock.advances else { return }

        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            UIApplication.significantTimeChangeNotification,
        ]

        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask { @MainActor [weak self] in
                    let stream = NotificationCenter.default.notifications(
                        named: name
                    ).map { _ in () }
                    for await _ in stream {
                        self?.tick()
                    }
                }
            }
        }
    }

    // MARK: Derived

    var identity: FieldIdentity { state.identity }

    var speaker: FieldOwner {
        backend?.viewerOwner ?? .a
    }

    /// The two questions the app can ask that are not about a single item.
    ///
    /// `todaySelection` already returns whichever of them won, shaped into a
    /// moment. These expose the proposals themselves, for a surface that needs
    /// to draw the two things being related rather than one headline about
    /// them — which is what the walkthrough does, and it is the reason it can
    /// be said to show the real rule rather than a picture of one.
    var occasionProposal: FieldOccasion.Proposal? {
        FieldOccasion.proposal(selectorContext)
    }

    var promotionProposal: FieldPromotion.Proposal? {
        FieldPromotion.proposal(selectorContext)
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
            // Today's overrides only. Filtered here rather than cleaned up on
            // a timer: the day turning is not an event anything has to
            // subscribe to if every read is dated.
            overriddenAddressing: Set(
                overriddenAddressing
                    .filter { calendar.isDate($0.value, inSameDayAs: now) }
                    .keys
            ),
            calendar: calendar
        )
    }

    private var classifierContext: FieldClassifier.Context {
        FieldClassifier.Context(
            identity: state.identity,
            speaker: speaker,
            now: now,
            lifeItems: state.lifeItems,
            horizons: state.horizons,
            rhythms: state.rhythms,
            corrections: state.corrections,
            lifeCategories: lifeCategories,
            partners: state.partners,
            calendar: calendar
        )
    }

    private var suggestionContext: FieldCaptureSuggestions.Context {
        FieldCaptureSuggestions.Context(
            now: now,
            speaker: speaker,
            lifeItems: state.lifeItems,
            clusters: state.clusters,
            horizons: state.horizons,
            rhythms: state.rhythms,
            partners: state.partners,
            captures: state.captures,
            corrections: state.corrections,
            calendar: calendar
        )
    }

    /// The handful of dated things at the top of Life, grouped by occasion.
    /// Today shows the one thing; this is the set.
    var thisWeek: [FieldTimely.Nudge] {
        FieldTimely.nudges(selectorContext)
    }

    /// What "Caught this week" is actually counting.
    ///
    /// It counted every capture ever, which is a different number with a
    /// different meaning: a couple's second month opened with "Caught this
    /// week · 214", a figure that is not about this week and reads like a
    /// scoreboard — and this app does not keep score.
    var capturesThisWeek: [FieldCapture] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return state.captures.filter { $0.capturedAt >= cutoff }
    }

    /// What the pills under the capture field offer. Read fresh on every
    /// access from this couple's current week and the viewer's own recent
    /// choices; nothing is cached across a capture, correction, or clock tick.
    /// They are generic only when there is honestly nothing yet to read.
    var captureSuggestions: [String] {
        FieldCaptureSuggestions.suggest(suggestionContext)
    }

    /// Every category that exists right now: the five given ones, then any the
    /// intelligence grew, oldest first.
    ///
    /// Derived from the items rather than stored. A category is not a thing a
    /// couple owns, it is the shape of what they have written down — so a
    /// category whose last item is deleted stops existing, with nothing to
    /// clean up and no empty heading left behind.
    var lifeCategories: [LifeCategory] {
        var seen = Set(LifeCategory.builtIn)
        var grown: [LifeCategory] = []

        for item in state.lifeItems where !seen.contains(item.category) {
            seen.insert(item.category)
            grown.append(item.category)
        }
        return LifeCategory.builtIn + grown
    }

    /// What the correction picker offers — every category that exists, so a
    /// thing can be moved into a grown one as easily as a given one.
    var correctionCategories: [LifeCategory] { lifeCategories }

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

    /// Us has nothing to say until there is a horizon or a week's evidence.
    ///
    /// Both are readings of what happens in Life; neither is a thing anybody
    /// fills in here. Until one exists, the sections on Us are headings over
    /// nothing — and a heading over nothing is the app talking to fill the
    /// silence, which is the same fault `FieldLifeZone` guards against.
    var usIsEmpty: Bool {
        state.horizons.isEmpty && state.evidence.isEmpty
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

    /// The week's synthesis, or `nil` when the app has nothing of its own to
    /// say about it — which is currently always. See `synthesisBlock` in
    /// `FieldLifeZone`: the handoff's sentence is prose about the fictional
    /// couple, and no generator has replaced it yet.
    var weekSynthesis: FieldWeekSynthesis? { nil }

    /// Writes any category subtitle whose items have changed shape.
    ///
    /// Sequential rather than concurrent: five simultaneous sessions on a
    /// small on-device model is a worse experience than five quick ones, and
    /// nothing on screen is waiting — each line replaces its derived version
    /// the moment it arrives.
    func refreshSubtitles() async {
        guard FieldCategoryVoice.isAvailable else { return }

        for category in lifeCategories {
            let items = openItems(in: category)
            let fingerprint = Self.fingerprint(items)

            guard subtitleFingerprints[category] != fingerprint else { continue }

            guard !items.isEmpty else {
                subtitleFingerprints[category] = fingerprint
                writtenSubtitles[category] = nil
                continue
            }

            let written = await FieldCategoryVoice.subtitle(
                for: category,
                items: items,
                now: now
            )

            // Recorded either way. A category that produced nothing usable
            // should not be retried on every appearance.
            subtitleFingerprints[category] = fingerprint
            writtenSubtitles[category] = written
        }
    }

    /// Changes exactly when some category's subtitle could need rewriting.
    var subtitleRefreshKey: Int {
        Self.fingerprint(state.lifeItems)
    }

    /// What the subtitle was written about. Titles and completion only —
    /// re-ranking does not change what the sentence says, so it must not
    /// trigger a regeneration.
    private static func fingerprint(_ items: [LifeItem]) -> Int {
        var hasher = Hasher()
        for item in items.sorted(by: { $0.id < $1.id }) {
            hasher.combine(item.id)
            hasher.combine(item.title)
            hasher.combine(item.isDone)
        }
        return hasher.finalize()
    }

    /// The line under a category word, on Life and again in its room.
    ///
    /// Prefers the written version once the model has produced one, and falls
    /// back to the derived summary until then — so the text is real from the
    /// first frame and improves in place, with no spinner and no reflow.
    func subtitle(for category: LifeCategory) -> String {
        writtenSubtitles[category] ?? summary(for: category)
    }

    /// What a category room shows: the few things that earned an explanation,
    /// and everything else, quietly.
    func digest(for category: LifeCategory) -> FieldCategoryDigest.Result {
        FieldCategoryDigest.digest(for: category, context: selectorContext)
    }

    /// The categories, ordered by attention needed.
    ///
    /// "The intelligence orders these by attention needed, not alphabetically
    /// or by a fixed taxonomy." Pressured first, then by how much is open,
    /// with the given order breaking ties so an empty Life still reads in a
    /// stable, deliberate sequence rather than shuffling. Grown categories sit
    /// after the given five on a tie, because a category the app invented has
    /// not earned the top of the screen by existing.
    var categoryOrder: [LifeCategory] {
        let fallback = lifeCategories
        return fallback.sorted { a, b in
            let pressureA = isPressured(a), pressureB = isPressured(b)
            if pressureA != pressureB { return pressureA }

            let countA = openItems(in: a).count
            let countB = openItems(in: b).count
            if countA != countB { return countA > countB }

            let indexA = fallback.firstIndex(of: a) ?? 0
            let indexB = fallback.firstIndex(of: b) ?? 0
            return indexA < indexB
        }
    }

    /// A one-line summary of what is actually open in a category.
    ///
    /// The handoff writes these by hand for the fictional couple. There is no
    /// generator behind them, so rather than print someone else's errands
    /// this names the couple's own most pressing items — and says nothing
    /// when there are none.
    func summary(for category: LifeCategory) -> String {
        let open = openItems(in: category).sorted {
            $0.pressure(now: now, calendar: calendar)
                > $1.pressure(now: now, calendar: calendar)
        }
        guard !open.isEmpty else { return "" }
        return open.prefix(2).map(\.title).joined(separator: " · ")
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
        // Whatever was actually derived, including none.
        //
        // This used to fall back to `FieldSampleData.behaviourChanges` below a
        // count of three, which meant the receipt was *always* fiction: the
        // third card reads a reply rate, nothing in the app writes a reply
        // rate, so the derived count could never reach the threshold. A real
        // couple was shown the fictional couple's changes and told they were
        // their own. An empty receipt is the honest answer to "what have I
        // learned" before anything has been corrected.
        return derived
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

    /// Re-plans the one local notification from what is true right now.
    ///
    /// Called on every scene-phase change rather than once, because a local
    /// notification freezes its content when it is scheduled — so the only
    /// way to avoid a moment arriving about something already done is to
    /// rewrite it whenever the app has the chance.
    func refreshDailyMoment() async {
        await FieldMomentDelivery.refresh(
            state: state,
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
        calendarOpen = false
        activeZone = .we
    }

    func openCalendar() {
        calendarOpen = true
    }

    func closeCalendar() {
        calendarOpen = false
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

    /// Classify what was typed and show where it would go. Nothing is filed
    /// and nothing leaves the phone yet — `send()` is the crossing.
    ///
    /// This is the app's own promise, kept literally: "nothing crosses until
    /// you approve the exact offer."
    func submitCapture() {
        let text = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        lastReceipt = FieldClassifier.classify(text, context: classifierContext)
        captureDraft = ""
    }

    /// File it, for real and in both places.
    ///
    /// Before this existed, `materialise` only ever inserted into the local
    /// `state` — the item appeared, and then vanished on the next load from
    /// Supabase, because nothing wrote it to its destination table. The
    /// backend has always had `upsert` for exactly this and nothing called it.
    func send() {
        guard let receipt = lastReceipt else { return }

        // The chip carries the tidied thought, not the sentence. What was
        // literally typed still travels with the correction, which is the only
        // place it is load-bearing.
        let capture = FieldCapture(
            id: receipt.id,
            text: receipt.title,
            owner: speaker,
            capturedAt: now
        )
        state.captures.insert(capture, at: 0)
        materialise(receipt)

        // Corrections are training signal about the classifier, and they are
        // held back with everything else until the moment of crossing.
        let corrections = pendingCorrections
        pendingCorrections = []
        lastReceipt = nil
        correctingReceipt = nil

        Task { [backend] in
            try? await backend?.append(capture)
            for correction in corrections {
                try? await backend?.record(correction)
            }
        }
        persist(receipt)
    }

    /// Writes the filed item to the one table there now is.
    private func persist(_ receipt: FieldReceipt) {
        guard let item = state.lifeItems.first(where: { $0.id == receipt.id })
        else { return }
        Task { [backend] in try? await backend?.upsert(item) }
    }

    /// Files the captured text into its category. Without this the receipt
    /// would be theatre.
    private func materialise(_ receipt: FieldReceipt) {
        // Matched on the tidied title, so "past lives" and "we should watch
        // past lives" are recognised as the same thing — which is the
        // coincidence the note exists to name, and the highest-value
        // inference the app makes.
        let match = state.lifeItems.first {
            $0.title.localizedCaseInsensitiveCompare(receipt.title)
                == .orderedSame && $0.owner != speaker && !$0.isDone
        }

        state.lifeItems.insert(
            LifeItem(
                id: receipt.id,
                title: receipt.title,
                category: receipt.category,
                owner: match == nil ? speaker : .shared,
                // The day the phrasing named, which is the whole reason for
                // lifting it out of the string: an item with a real date can
                // be ranked, surfaced, and fall due.
                dueOn: receipt.dueOn,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: match == nil ? nil : "Both added it, independently",
                isTimeCritical: false,
                isDone: false
            ),
            at: 0
        )
    }

    /// Puts a captured thing on today, or takes it back off.
    ///
    /// The only way to date something used to be to say the word inside the
    /// sentence and let `FieldPhrasing` lift it out, which works and is
    /// invisible. This is the same act made available to a thumb, and it sets
    /// exactly the same field — nothing is stored on Today, because Today is
    /// derived. A date is what makes an item rank; that is the whole of it.
    ///
    /// Refused where a date would be a lie. A film is not due on Thursday.
    func toggleForToday() {
        guard var receipt = lastReceipt, receipt.category.carriesDates else {
            return
        }
        let calendar = Calendar.gregorianUS
        let today = calendar.startOfDay(for: now)
        let alreadyToday = receipt.dueOn.map {
            calendar.isDate($0, inSameDayAs: today)
        } ?? false

        receipt.dueOn = alreadyToday ? nil : today
        lastReceipt = receipt
    }

    func beginCorrection() {
        correctingReceipt = lastReceipt
    }

    /// Backing out of the picker. Opening "Wrong place" is not a commitment to
    /// move anything — a person who taps it to see the options and decides the
    /// app was right the first time needs a way back that is not sending.
    func cancelCorrection() {
        correctingReceipt = nil
    }

    /// A category this couple names themselves, from the correction picker.
    ///
    /// The classifier grows categories on its own, and it is deliberately
    /// conservative about it — which means it sometimes has no word for a
    /// thing that obviously deserves one. This is the other direction: the
    /// person supplies the heading, and the correction it comes with teaches
    /// the classifier to use it next time, exactly like any other correction.
    ///
    /// Returns the category it filed to, or `nil` when the name is not one —
    /// too long, too short, or a reserved word. The caller says so; this does
    /// not invent a substitute.
    @discardableResult
    func correct(toNewCategory name: String) -> LifeCategory? {
        guard let category = LifeCategory(named: name) else { return nil }
        correct(to: category)
        return category
    }

    /// One tap to a corrected destination. Every correction becomes training
    /// signal that surfaces later in the correction receipt (6a).
    ///
    /// Nothing has been filed yet, so this only changes where it is *about*
    /// to go — there is no materialised object to move and nothing written
    /// remotely to undo. That is the point of correcting before sending.
    func correct(to category: LifeCategory) {
        guard let receipt = correctingReceipt ?? lastReceipt else { return }
        let result = FieldClassifier.correct(
            receipt,
            to: category,
            context: classifierContext
        )
        lastReceipt = result.receipt
        correctingReceipt = nil
        state.corrections.append(result.correction)
        pendingCorrections.append(result.correction)
    }

    /// Walking away without sending. Nothing was written, so there is
    /// nothing to undo.
    func dismissReceipt() {
        lastReceipt = nil
        correctingReceipt = nil
        pendingCorrections = []
    }

    // MARK: Acting on a moment

    func complete(_ itemID: String) {
        guard let index = state.lifeItems.firstIndex(where: { $0.id == itemID })
        else { return }
        state.lifeItems[index].isDone = true
        let item = state.lifeItems[index]
        Task { [backend] in try? await backend?.upsert(item) }
    }

    // MARK: Changing a filed thing
    //
    // Until these existed, filing was one-way. A receipt could be corrected
    // before it was sent — `correct(to:)` — and after that the item's category
    // and date were fixed forever, which made a mistyped word or a cancelled
    // plan permanent. These are the same three acts the capture flow already
    // offers, made available to something already on a page.

    /// An item that came from the phone's own calendar, which this app does
    /// not own. The permission string promises, in these words: "I never add,
    /// change, or delete anything."
    private func isImported(_ itemID: String) -> Bool {
        itemID.hasPrefix("cal:")
    }

    /// Gone, for both of them.
    ///
    /// Refused for an imported event at this seam rather than only in the UI —
    /// a promise the app made about somebody else's calendar should not depend
    /// on which screen the call came from.
    ///
    /// The chip under the capture field goes with it. A capture and the item it
    /// filed share one id, and "it goes from every screen, and there is no
    /// undo" is not true while the proof-of-catch is still sitting there — a
    /// pill for a thing that no longer exists is the app contradicting itself
    /// on the screen a couple looks at most.
    func remove(_ itemID: String) {
        guard !isImported(itemID),
              let index = state.lifeItems.firstIndex(where: { $0.id == itemID })
        else { return }

        state.lifeItems.remove(at: index)
        state.captures.removeAll { $0.id == itemID }
        Task { [backend] in try? await backend?.delete(itemID: itemID) }
    }

    /// Moves a filed item to another category, and teaches the classifier.
    ///
    /// The correction is the point. Moving something by hand is the clearest
    /// signal the app ever gets about where this shape of thing belongs, and
    /// dropping it would make the same mistake again next week. This is why it
    /// records a `FieldCorrection` exactly as `correct(to:)` does for a
    /// receipt.
    func refile(_ itemID: String, to category: LifeCategory) {
        guard !isImported(itemID),
              let index = state.lifeItems.firstIndex(where: { $0.id == itemID }),
              state.lifeItems[index].category != category
        else { return }

        let original = state.lifeItems[index].category
        state.lifeItems[index].category = category

        // Moving into a category that does not carry dates drops the date
        // rather than putting a due date on a film — the same rule
        // `FieldClassifier.correct` applies to a receipt.
        if !category.carriesDates {
            state.lifeItems[index].dueOn = nil
            state.lifeItems[index].closesAt = nil
        }

        let item = state.lifeItems[index]
        let correction = FieldCorrection(
            id: UUID().uuidString,
            input: item.title,
            original: original,
            corrected: category,
            correctedAt: now
        )
        state.corrections.append(correction)

        Task { [backend] in
            try? await backend?.upsert(item)
            try? await backend?.record(correction)
        }
    }

    /// The same act by a name the couple supplies. Returns `nil` when the name
    /// is not a heading — see `LifeCategory(named:)`.
    @discardableResult
    func refile(
        _ itemID: String,
        toNewCategory name: String
    ) -> LifeCategory? {
        guard let category = LifeCategory(named: name) else { return nil }
        refile(itemID, to: category)
        return category
    }

    /// Moves an item on the calendar, or takes it off one.
    ///
    /// `nil` clears the cut-off with the date: a window that closes at 9pm on
    /// no particular day is not a thing, and leaving `closesAt` behind would
    /// keep the item ranking at the top of Today with nothing to show for it.
    func redate(_ itemID: String, to day: Date?) {
        guard !isImported(itemID),
              let index = state.lifeItems.firstIndex(where: { $0.id == itemID }),
              state.lifeItems[index].category.carriesDates
        else { return }

        state.lifeItems[index].dueOn = day.map {
            Calendar.gregorianUS.startOfDay(for: $0)
        }
        if day == nil {
            state.lifeItems[index].closesAt = nil
        }

        let item = state.lifeItems[index]
        Task { [backend] in try? await backend?.upsert(item) }
    }

    func answer(_ question: FieldQuestion, with choice: FieldChoice) {
        // A promotion question has no horizon behind it yet — answering it is
        // what decides whether there is ever going to be one.
        if let proposal = FieldPromotion.proposal(selectorContext),
           proposal.question.id == question.id {
            if choice.id == proposal.affirmative?.id {
                promote(proposal, answering: choice)
            } else {
                // A real answer, not a postponement. "Not this year" is a
                // decision, and the app owes it the same finality it owes a
                // yes.
                decline(question, reason: "You said not this year.")
            }
            return
        }

        // An occasion question has no cluster behind it either, when the
        // occasion is one the app is offering to form.
        if let proposal = FieldOccasion.proposal(selectorContext),
           proposal.question.id == question.id {
            if choice.id == proposal.affirmative?.id {
                attach(proposal)
            } else {
                decline(question, reason: "You said they're not related.")
            }
            return
        }

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

    /// Yes — so a horizon appears in Us, built out of the Life items that
    /// prompted the question.
    ///
    /// **Nothing moves.** The items stay in their category, where the couple
    /// has been looking at them all along; the horizon only points at them.
    /// Made primary when there is no primary, because a couple's first horizon
    /// is by definition the one they are heading for.
    private func promote(
        _ proposal: FieldPromotion.Proposal,
        answering choice: FieldChoice
    ) {
        let horizon = FieldHorizon(
            // A fresh identifier, not the proposal's: the proposal id names a
            // question, and the row this becomes has to be addressable by the
            // database like every other one.
            id: UUID().uuidString,
            title: proposal.subject,
            window: choice.title.lowercased(),
            owner: .shared,
            isPrimary: !state.horizons.contains(where: \.isPrimary),
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: proposal.itemIDs,
            openQuestion: nil
        )
        state.horizons.insert(horizon, at: 0)

        let evidence = FieldEvidence(
            id: UUID().uuidString,
            statement: "You decided \(proposal.subject) is real.",
            owner: .shared,
            horizonID: horizon.id,
            occurredAt: now
        )
        state.evidence.insert(evidence, at: 0)

        // Written, not just shown. A horizon that exists only in memory is
        // the same bug captures had before `persist` existed: it looks filed,
        // and it is gone on the next load.
        //
        // The evidence goes with it, and used not to. This line was the entire
        // reason `field_evidence` looked like a dead table: it was read on
        // every load, and the one thing in the app that produces a row only
        // ever produced it in memory. So the sentence recording that a couple
        // decided something was real survived exactly until they closed the
        // app.
        //
        // The horizon first, in that order: `field_evidence.horizon_id` is a
        // foreign key, and an evidence row that arrived first would have its
        // pointer set to null by `on delete set null`'s cousin — a violated
        // reference — or be rejected outright.
        Task { [backend] in
            try? await backend?.upsert(horizon)
            try? await backend?.upsert(evidence)
        }
    }

    /// Yes — so the two things are shown together, and counted together.
    ///
    /// The same promise `promote` makes, and for the same reason: **nothing
    /// moves.** The item keeps its category, keeps its owner, and stays in the
    /// room the couple has been looking at it in. All that changes is that the
    /// occasion now knows about it — which is what lets Today say "three
    /// things wait on this" truthfully instead of only about seed data.
    ///
    /// When the occasion does not exist yet, this is also the moment it comes
    /// into being. The app never creates an empty one: an occasion with
    /// nothing hanging off it is a date, and the calendar already has those.
    private func attach(_ proposal: FieldOccasion.Proposal) {
        let clusterID = proposal.clusterID ?? form(proposal)
        guard let clusterID else { return }

        setCluster(clusterID, on: proposal.itemID)

        // The anchor joins its own occasion. Without this the visit would sit
        // outside the group it named, and the cluster would claim one member
        // while displaying two.
        if let anchorItemID = proposal.anchorItemID {
            setCluster(clusterID, on: anchorItemID)
        }
    }

    /// Builds the occasion around the thing that dated it.
    ///
    /// The rationale is written in the app's voice and is the only place a
    /// user will ever read *why* these are one group, so it says the true
    /// reason rather than a generic one.
    private func form(_ proposal: FieldOccasion.Proposal) -> String? {
        guard let anchorItemID = proposal.anchorItemID,
              let anchor = state.lifeItems.first(where: {
                  $0.id == anchorItemID
              })
        else { return nil }

        let cluster = FieldCluster(
            id: UUID().uuidString,
            title: FieldOccasion.shortTitle(anchor.title),
            rationale: "You put these together. I'll keep anything else that "
                + "belongs with them here too — and ask first, every time.",
            tint: anchor.owner,
            timeframe: proposal.anchorDate.map {
                DateFormatter.fieldWeekdayShort.string(from: $0).uppercased()
            } ?? "NO DATE",
            anchorDate: proposal.anchorDate
        )
        state.clusters.insert(cluster, at: 0)

        Task { [backend] in try? await backend?.upsert(cluster) }
        return cluster.id
    }

    /// One place that writes the column, so the in-memory item and the row can
    /// never disagree about which occasion it is in.
    private func setCluster(_ clusterID: String?, on itemID: String) {
        guard let index = state.lifeItems.firstIndex(where: {
            $0.id == itemID
        }) else { return }

        state.lifeItems[index].clusterID = clusterID
        let item = state.lifeItems[index]
        Task { [backend] in try? await backend?.upsert(item) }
    }

    /// Not now — with a "now" that ends.
    ///
    /// Every hold used to be written with `surfaceOn: nil`, and
    /// `FieldDeferral.shouldRaise` returns false for a nil date. So "ask me
    /// again tonight" meant "never ask me again", and the button was a lie in
    /// the quietest possible way: it did exactly what it said until the
    /// evening it was supposed to come back.
    func hold(
        id: String,
        subject: String,
        until window: FieldDeferralWindow,
        reason: String
    ) {
        let topic = FieldHeldTopic(
            id: id,
            title: subject,
            timing: window.chip,
            reason: reason,
            surfaceOn: FieldDeferral.surfaceDate(
                window,
                from: now,
                moment: state.dailyMoment,
                calendar: calendar
            ),
            wasOverridden: false,
            wasDismissed: false
        )
        upsertHeld(topic)
    }

    func hold(
        _ question: FieldQuestion,
        until window: FieldDeferralWindow,
        reason: String
    ) {
        hold(
            id: question.id,
            subject: Self.subject(ofQuestion: question),
            until: window,
            reason: reason
        )
    }

    /// What a held row is *about*, read back out of the question's id.
    ///
    /// The id is a route, not a sentence — `promote:japan`, or
    /// `occasion:<cluster>:<item>` — and the topic list shows this string to a
    /// person. An occasion's id is two identifiers and would read as machine
    /// noise, so it is named by the thing it was asked about instead.
    private static func subject(ofQuestion question: FieldQuestion) -> String {
        guard !question.id.hasPrefix("occasion:") else {
            return FieldOccasion.shortTitle(question.prompt)
        }
        return question.id.replacingOccurrences(of: "promote:", with: "")
    }

    /// They said no, which is a different answer from "not now".
    ///
    /// The app promised the thing stays where it is and it stops asking, and
    /// `wasDismissed` is that promise as a fact rather than as a date far
    /// enough out to look like one.
    func decline(_ question: FieldQuestion, reason: String) {
        let subject = Self.subject(ofQuestion: question)
        upsertHeld(
            FieldHeldTopic(
                id: question.id,
                title: subject,
                timing: "NOT NOW",
                reason: reason,
                surfaceOn: nil,
                wasOverridden: false,
                wasDismissed: true
            )
        )
    }

    /// Replaced rather than appended. Holding the same thing twice is one
    /// decision restated, not two rows.
    private func upsertHeld(_ topic: FieldHeldTopic) {
        if let index = state.heldTopics.firstIndex(where: { $0.id == topic.id }) {
            state.heldTopics[index] = topic
        } else {
            state.heldTopics.append(topic)
        }
        Task { [backend] in try? await backend?.setHeld(topic) }
    }

    // MARK: Acting outward

    /// The whole outward path, in one place.
    ///
    /// Every decision inside it is made by a pure function; this only
    /// sequences them and holds the answer for the screen. It opens nothing —
    /// the view does that, after somebody has read what was found and said
    /// yes. That is not a nicety: the worst thing this feature can do is dial
    /// a wrong number, and the only real defence is that a person sees it
    /// first.
    func begin(_ act: FieldAct, for itemID: String) async {
        guard let item = state.lifeItems.first(where: { $0.id == itemID })
        else { return }

        // Nothing to reach anybody about. The button does what it always did.
        let extraction = FieldTargetPhrasing.extract(
            from: item.title,
            act: act,
            identity: state.identity
        )
        guard act != .none, let extraction else {
            complete(itemID)
            return
        }

        // Asked at the tap, and only for a person — this is the first moment
        // the app can explain why it wants the address book, because it is
        // the moment somebody asked it to call somebody.
        if extraction.kind == .person,
           !FieldContactsResolver.wasAsked {
            pendingOutreach = FieldOutreachRequest(
                id: itemID,
                act: act,
                itemTitle: item.title,
                query: extraction.query,
                candidates: [],
                state: .needsContactsPermission
            )
            return
        }

        let candidates = await resolver.resolve(extraction.query)

        pendingOutreach = FieldOutreachRequest(
            id: itemID,
            act: act,
            itemTitle: item.title,
            query: extraction.query,
            candidates: candidates,
            state: candidates.isEmpty ? .foundNothing : .found
        )
    }

    /// Granting contacts and immediately doing the thing that was asked for.
    /// A permission prompt that leaves you back where you started is its own
    /// small insult.
    func grantContactsAndRetry() async {
        guard let request = pendingOutreach else { return }
        _ = await FieldContactsResolver.request()
        pendingOutreach = nil
        await begin(request.act, for: request.id)
    }

    /// The app opened the phone. That is all it knows.
    ///
    /// Whether the vet had a slot is a fact only the person has, so the app
    /// asks once rather than deciding — marking it done here would be the app
    /// claiming to have done something it did not do.
    func outreachDidOpen(_ request: FieldOutreachRequest, target: FieldTarget?) {
        pendingOutreach = nil
        awaitingOutcome = FieldOutcomeQuestion(
            id: request.id,
            question: request.act.pastTense(target: target?.name)
        )
    }

    func resolveOutcome(_ question: FieldOutcomeQuestion, done: Bool) {
        awaitingOutcome = nil
        if done { complete(question.id) }
    }

    func dismissOutreach() {
        pendingOutreach = nil
    }

    /// "Ask Dylan anyway."
    ///
    /// The presence rule re-addresses a shared thing to whoever is here; this
    /// is the person overruling that. It does not send anything, because
    /// there is nothing to send it with — all it does is stop the app
    /// explaining, for the rest of today, that one of them is away.
    ///
    /// Ephemeral and dated on purpose: tomorrow the partner is still away and
    /// the app should say so again rather than quietly carrying an override
    /// forward into a day nobody made it in.
    func raiseWithBoth(_ itemID: String) {
        overriddenAddressing[itemID] = now
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
        persistMoment()
    }

    func skipToday() {
        state.dailyMoment.lastSentOn = now
        persistMoment()
    }

    private func persistMoment() {
        let moment = state.dailyMoment
        Task { [backend] in try? await backend?.setDailyMoment(moment) }
    }

    // MARK: Onboarding (6f)

    func canChooseSwatch(for owner: FieldOwner) -> Bool {
        backend == nil || owner == speaker
    }

    func choose(_ swatch: FieldSwatch, for owner: FieldOwner) {
        // A live device may only choose the colour for the person holding it.
        // Backend-free gallery/previews still allow both rows to be explored.
        guard canChooseSwatch(for: owner) else { return }
        switch owner {
        case .a: state.identity.personA = swatch
        case .b: state.identity.personB = swatch
        case .shared: break
        }
        persistIdentity()
    }

    /// The three questions. Each is skippable, and skipping stores nil rather
    /// than an empty string — "they did not say" is a different fact from
    /// "they said nothing", and the intelligence should not confuse them.
    func answerLivesTogether(_ value: Bool?) {
        state.identity.livesTogether = value
        persistIdentity()
    }

    func answerSavingFor(_ value: String) {
        state.identity.savingFor = trimmedOrNil(value)
        persistIdentity()
    }

    func answerLooksAfter(_ value: String) {
        state.identity.looksAfter = trimmedOrNil(value)
        persistIdentity()
    }

    private func persistIdentity() {
        let identity = state.identity
        Task { [backend] in try? await backend?.setIdentity(identity) }
    }

    /// Whitespace-only input is a skipped question, not an answer.
    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Loading

    func load() async {
        guard let backend else {
            // No backend at all is the gallery and the previews, where the
            // state on hand is the whole truth and there is nothing to wait
            // for.
            loadState = .loaded
            return
        }

        await loadOnce()

        for await _ in backend.changes() {
            await loadOnce()
        }
    }

    /// One attempt, and an honest record of how it went.
    ///
    /// This used to be `try?` twice over, which made a failed load
    /// pixel-identical to a brand new account: both left `state` untouched at
    /// its empty default, and the zones drew somebody's relationship as though
    /// it had never existed. The distinction below is the entire point — the
    /// app is allowed to not know something, and is not allowed to say the
    /// thing is not there.
    private func loadOnce() async {
        guard let backend else { return }

        // The circle rides the same signal as the zones. `changes()` fires on
        // `field_readiness_bloom`, so this is what carries the second person's
        // tap onto the first person's screen without a foreground — and it is
        // deliberately outside the do/catch below, because whether the zones
        // loaded and whether the couple is open to each other are two
        // unrelated questions and neither should suppress the other.
        await refreshReadiness()

        do {
            state = try await backend.load()
            lastLoadedAt = now
            loadState = .loaded
        } catch {
            // Cached data is still worth drawing; it was true recently and
            // saying so is more useful than an empty screen. Without a cache
            // there is nothing honest to draw, and the zones offer a retry.
            loadState = lastLoadedAt.map(LoadState.stale) ?? .failed
        }
    }

    /// For the inline retry the zones offer when there is nothing cached.
    func retryLoad() async {
        loadState = .loading
        await loadOnce()
    }

    // MARK: The solo-to-shared boundary (2a)

    /// How many of this person's solo-era rows have not crossed. Nil until
    /// asked, so the disclosure cannot flash before the number is known.
    private(set) var soloHistoryCount: Int?

    /// Set once the person has answered, either way. Read from
    /// `FieldCrossingDecision`, which remembers it across launches — declining
    /// has to be as durable as accepting, or the app asks again tomorrow and
    /// "keep it to myself" means "not yet".
    private(set) var hasAnsweredCrossing = false

    /// Whether to show the disclosure at all.
    ///
    /// Deliberately requires a positive count rather than merely a partner:
    /// somebody who paired on their first day has no solo history, and asking
    /// them what to do with nothing is a dialog about an empty set.
    var owesCrossingDecision: Bool {
        !hasAnsweredCrossing && (soloHistoryCount ?? 0) > 0
    }

    func considerCrossing(decision: FieldCrossingDecision) async {
        hasAnsweredCrossing = decision.wasAnswered
        guard !hasAnsweredCrossing else { return }
        soloHistoryCount = try? await backend?.soloHistoryCount()
    }

    /// Bring it across, then reload so the zones show the same thing the
    /// partner now sees.
    ///
    /// Nil means nothing crossed. The answer is deliberately *not* recorded in
    /// that case: a failed request is not a decision, and remembering it as one
    /// would mean somebody tapped "bring it across", nothing moved, and they
    /// were never asked again. The question stays open until it is answered by
    /// something that actually happened.
    @discardableResult
    func shareSoloHistory(
        decision: FieldCrossingDecision
    ) async -> Int? {
        guard let backend,
              let shared = try? await backend.shareSoloHistory()
        else { return nil }
        decision.remember()
        hasAnsweredCrossing = true
        await loadOnce()
        return shared
    }

    /// Keep it. Recorded, so it is a decision and not a postponement.
    func keepSoloHistoryPrivate(decision: FieldCrossingDecision) {
        decision.remember()
        hasAnsweredCrossing = true
    }

    // MARK: - The circle

    /// The last answer the server gave, for the day it was about.
    ///
    /// Not in `FieldState`, and that is the important part: readiness is never
    /// written to the cache on disk, never replayed from the outbox, and never
    /// derived on device. It is the one thing here whose truth lives entirely
    /// on the server, because the row that decides it is one this client is not
    /// permitted to read.
    private(set) var storedReadiness: FieldReadiness

    /// The circle, as of today.
    ///
    /// Dated rather than cleared on a timer. An answer about yesterday is not
    /// wrong, it is simply not about now — and a couple who bloomed last night
    /// must not open the app this morning to last night's room still standing.
    /// Reading through the day means midnight resets the circle with no
    /// invalidation to remember and nothing to schedule.
    var circle: FieldReadiness {
        storedReadiness.localDate == todayLocalDate
            ? storedReadiness
            : .neither(on: todayLocalDate)
    }

    var todayLocalDate: String { FieldReadiness.localDate(for: now) }

    /// Whether the mark is a control at all.
    ///
    /// False in the gallery and the previews, which have no backend — and a
    /// mark that can be tapped there would be a control that cannot do the one
    /// thing it exists to do. Everywhere else it is true, because `FieldRoot`
    /// only takes the screen once the session is `.ready`, which is to say
    /// once there is somebody to be open to.
    var isCircleAvailable: Bool { backend != nil }

    /// The day the room was closed, so it does not reopen behind the person
    /// who just closed it.
    ///
    /// Ephemeral on purpose, and the exception that proves the rule about
    /// residue: it is not written down anywhere, so relaunching offers the
    /// room again for as long as the day lasts. That is the right behaviour —
    /// both people are still open, and the app has no business deciding they
    /// have had their moment.
    private var roomClosedOn: String?

    /// Whether to open the room. True only once both have marked and it has
    /// not been closed today.
    var shouldOpenRoom: Bool {
        circle.hasBloomed && roomClosedOn != todayLocalDate
    }

    /// "I'd welcome a moment together."
    ///
    /// Optimistic to `.you` before the network, because the tap has to feel
    /// like it landed and `.you` is the one thing this device can know for
    /// certain about its own action. It is never optimistic to `.both`: that
    /// would be the app inventing a partner's consent, and it is the only
    /// state that puts words on both their screens.
    ///
    /// Idempotent all the way down — the mutation compacts on the day, and
    /// `field_readiness_mark` inserts on conflict do nothing. Tapping twice
    /// records nothing about the second tap, here or anywhere.
    func markReady() async {
        let day = todayLocalDate
        if circle.state == .neither {
            storedReadiness = FieldReadiness(
                state: .you,
                prompt: nil,
                localDate: day
            )
        }

        try? await backend?.markReady(localDate: day)

        // Then ask, rather than trusting the write's own answer. This is what
        // turns "I marked" into "we both did" when the partner got there
        // first, and it is the same call the realtime tick makes — one path to
        // the bloom, not two.
        await refreshReadiness()
    }

    /// Re-read the circle. Called on every load and every realtime tick, so
    /// the second person's tap blooms on the first person's screen without a
    /// foreground.
    ///
    /// A failure leaves the last answer standing rather than resetting to
    /// `neither`. The same rule `loadState` encodes for the zones: the app is
    /// allowed not to know, and is not allowed to say a thing is not there.
    func refreshReadiness() async {
        guard let backend else { return }
        let day = todayLocalDate
        guard let answer = try? await backend.readiness(localDate: day) else {
            return
        }
        storedReadiness = answer
    }

    /// Close the room. Nothing is kept, and nothing about it is recorded —
    /// there is no row, no capture, and no measurement of how long it was open.
    func closeRoom() {
        roomClosedOn = todayLocalDate
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
    let viewerOwner: FieldOwner

    /// Days this viewer has marked. Not part of `FieldState` — readiness is
    /// never loaded with the zones and never cached, and putting it there
    /// would be the one place it could leak onto disk.
    private var markedDays: Set<String> = []

    /// Whether the *other* person has already marked, for the days named here.
    ///
    /// A test seam and a gallery seam, and it has to be one: there is no
    /// second person in this process, so without it the in-memory backend can
    /// reach `.you` and never `.both`, and the bloom would have no reference
    /// implementation to be checked against. Defaults to nobody, so an
    /// ordinary preview shows an ordinary unmarked mark.
    private let partnerMarkedDays: Set<String>

    init(
        state: FieldState = .seed,
        viewerOwner: FieldOwner = .a,
        partnerMarkedDays: Set<String> = []
    ) {
        self.state = state
        self.viewerOwner = viewerOwner
        self.partnerMarkedDays = partnerMarkedDays
    }

    func load() async throws -> FieldState {
        lock.withLock { state }
    }

    // MARK: The writes
    //
    // Every one of them is `FieldMutation.apply`, and none of them is a second
    // description of what a write means.
    //
    // They used to be eleven hand-written bodies, and the cost of that was not
    // theoretical: `setHeld` here upserted correctly for months while the
    // Supabase implementation could not insert at all, so every preview,
    // gallery run, and UI test saw a hold survive and no real couple did. The
    // shared conformance suite closed the gap between *those* two. This closes
    // it between both of them and the outbox's replay, which is the third
    // implementation of the same rules and the newest place for them to drift.

    private func apply(_ mutation: FieldMutation) {
        lock.withLock { mutation.apply(to: &state) }
    }

    func append(_ capture: FieldCapture) async throws {
        apply(.append(capture))
    }

    func record(_ correction: FieldCorrection) async throws {
        apply(.record(correction))
    }

    func upsert(_ item: LifeItem) async throws {
        apply(.upsertItem(item))
    }

    func delete(itemID: String) async throws {
        apply(.deleteItem(id: itemID))
    }

    func upsert(_ horizon: FieldHorizon) async throws {
        apply(.upsertHorizon(horizon))
    }

    func upsert(_ evidence: FieldEvidence) async throws {
        apply(.upsertEvidence(evidence))
    }

    func upsert(_ cluster: FieldCluster) async throws {
        apply(.upsertCluster(cluster))
    }

    func answer(question: String, choice: String) async throws {
        apply(.answer(question: question, choice: choice))
    }

    func setHeld(_ topic: FieldHeldTopic) async throws {
        apply(.setHeld(topic))
    }

    func setStandingRule(_ rule: FieldStandingRule) async throws {
        apply(.setStandingRule(rule))
    }

    func setIdentity(_ identity: FieldIdentity) async throws {
        apply(.setIdentity(identity))
    }

    func setDailyMoment(_ moment: FieldDailyMoment) async throws {
        apply(.setDailyMoment(moment))
    }

    // MARK: The circle
    //
    // Not routed through `apply` like the writes above, because readiness is
    // not in `FieldState` and deliberately never will be — it is not loaded,
    // not cached, and not replayable. `FieldMutation.markReady` says the same
    // thing from the other side.

    func markReady(localDate: String) async throws {
        // Idempotent by construction: a set, so a second tap on the same day
        // is not a second anything. Matches `field_readiness_mark`'s
        // `on conflict do nothing`, and for the same reason — a repeat must
        // leave no trace that could be read as pressure.
        lock.withLock { _ = markedDays.insert(localDate) }
    }

    func readiness(localDate: String) async throws -> FieldReadiness {
        lock.withLock {
            let mine = markedDays.contains(localDate)
            let theirs = partnerMarkedDays.contains(localDate)

            // The ordering is the invariant. `theirs && !mine` falls through
            // to `.neither`, exactly as the RPC's own branches do: a partner
            // who has marked alone is indistinguishable from a partner who has
            // not. If this ever grows a `.partner` case, the schema is no
            // longer the thing enforcing the promise.
            guard mine else { return .neither(on: localDate) }
            guard theirs else {
                return FieldReadiness(
                    state: .you,
                    prompt: nil,
                    localDate: localDate
                )
            }
            return FieldReadiness(
                state: .both,
                prompt: Self.samplePrompt,
                localDate: localDate
            )
        }
    }

    /// One fixed line, not the server's rotation. The rotation is chosen by
    /// `private.field_readiness_prompt` from the couple and the day, and
    /// reimplementing that here would be a second copy of a rule whose whole
    /// point is that both devices read one value.
    static let samplePrompt =
        "What would make tonight feel a little more like yours?"

    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
