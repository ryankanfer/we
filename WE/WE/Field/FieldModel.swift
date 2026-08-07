//
//  FieldModel.swift
//  WE
//
//  The persisted domain from the handoff's "State management" section.
//
//  The naming follows the product's own vocabulary rather than a generic task
//  schema, because the vocabulary *is* the product: Horizons (what you're
//  aiming at), Rhythms (what you repeat to get there), Anchors (what you've
//  already agreed on, so you don't relitigate it), Threads (conversations
//  still open, with no pressure to finish), Seasons (the chapter you're in),
//  and Evidence (proof it's working).
//
//  One structural rule runs through all of it: nothing here stores a score, a
//  streak, a completion percentage, or any value that compares the two
//  partners. `RhythmHealth` is deliberately a two-case enum rather than a
//  count for exactly this reason.
//

import Foundation

// MARK: - Routing
//
// There is one filing system, and it is Life's categories. Every captured
// string resolves to exactly one of them.
//
// It used to resolve to one of three destinations — Life, Ours, or Us ·
// Horizons — where Ours was a drawer *inside* Us that filed under its own
// name. That is one destination too many and two names for one place: the
// person who designed it could not reliably say whether Ours and Us were the
// same thing, which settles the question of whether anybody else could.
//
// So Ours is gone, and **Us cannot be filed to at all.** Us is what Life
// becomes when a question about it is answered — see `FieldPromotion`. The
// receipt never names it, because nothing is ever sent there.

enum FieldZone: Int, CaseIterable, Codable, Sendable, Identifiable {
    case life = 0
    /// Index 1, and the home. Cold launch always lands here.
    case we = 1
    case us = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .life: "LIFE"
        case .we: "TODAY"
        case .us: "US"
        }
    }

    /// The nav renders WE as a mark, not a word, so its nav label differs
    /// from its zone label.
    var navLabel: String {
        switch self {
        case .life: "LIFE"
        case .we: "WE"
        case .us: "US"
        }
    }
}

// MARK: - Partners

struct FieldPartner: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var swatch: FieldSwatch
    var owner: FieldOwner
    /// Windows during which this partner is not reachable. Presence (6b) reads
    /// these to decide who to address, and never to measure who is more
    /// present.
    var awayWindows: [FieldAwayWindow]
    /// Free-text preferences the couple has stated, e.g. "Anything but a
    /// musical". A standing negative preference is a first-class entry.
    var standingPreferences: [String]

    func isAway(on date: Date) -> Bool {
        awayWindows.contains { $0.contains(date) }
    }

    func awayWindow(on date: Date) -> FieldAwayWindow? {
        awayWindows.first { $0.contains(date) }
    }
}

struct FieldAwayWindow: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var start: Date
    var end: Date
    /// "Shooting", "In the Hamptons for work". Used verbatim in the banner.
    var reason: String
    var place: String?

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

// MARK: - Life

/// A Life category. Open, not closed.
///
/// Five are given, because a couple should not have to invent a taxonomy
/// before they can file the first thing they say. Everything after that is
/// earned: when a capture fits none of them, the classifier names one from
/// what was actually said rather than dropping it into Calendar and calling
/// that a decision.
///
/// It is a struct rather than an enum for exactly that reason — the set is not
/// knowable at compile time. `builtIn` is the floor, `LifeStore.lifeCategories`
/// is the truth at any moment.
struct LifeCategory: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    let rawValue: String

    /// Non-failable so a decode can never lose an item. Anything unusable
    /// lands in Notes, which is the category for a thing with no home.
    init(rawValue: String) {
        self.rawValue = Self.normalised(rawValue) ?? "notes"
    }

    /// Free text becoming a category — from the classifier, or from a person
    /// typing one. Fails rather than inventing, so the caller can fall back.
    init?(named raw: String) {
        guard let normalised = Self.normalised(raw) else { return nil }
        self.rawValue = normalised
    }

    static let care = LifeCategory(rawValue: "care")
    static let food = LifeCategory(rawValue: "food")
    static let trips = LifeCategory(rawValue: "trips")
    static let watchlist = LifeCategory(rawValue: "watchlist")
    static let buys = LifeCategory(rawValue: "buys")
    static let money = LifeCategory(rawValue: "money")
    static let home = LifeCategory(rawValue: "home")

    /// Where anything lands that has a subject but no home. Grown rather than
    /// given, so a couple who never needs it never sees the word.
    static let notes = LifeCategory(rawValue: "notes")

    /// Something one of them asked rather than something either has to do.
    ///
    /// A question with no date in it is not an errand, and filing it as one is
    /// how "do we want to do Christmas at your parents?" ends up in a list
    /// between the dry cleaning and the air filter. It is still filed — there
    /// is one filing system and this is a category like any other — it simply
    /// carries no date and nothing chases it.
    ///
    /// Grown rather than given, like Notes: a couple who never asks the app
    /// anything never sees the word.
    static let talk = LifeCategory(rawValue: "talk")

    /// Words that cannot be a category, whatever a row says.
    ///
    /// Calendar was one of the given five until the calendar became a surface
    /// of its own — a view of everything with a date, whatever list it is in.
    /// Removing it from `builtIn` was not enough: categories are derived from
    /// the items that carry them, so a single row still saying `calendar` puts
    /// the word straight back on Life. This makes that impossible rather than
    /// merely unlikely, whether the row is an old one, a hand-edit in the
    /// table editor, or a future bug.
    static let reserved: Set<String> = ["calendar"]

    /// What you start with, in the order Life falls back to when nothing is
    /// pressing: the ones you act on daily first, the ones you settle last.
    ///
    /// There is no Calendar here. A calendar is not a list of things — it is a
    /// view of everything that has a date, whatever list it is in — so it
    /// lives behind the pull on Life and owns nothing. See
    /// `FieldCalendarSurface`.
    static let builtIn: [LifeCategory] = [
        .care, .food, .trips, .watchlist, .buys, .money, .home,
    ]

    var isBuiltIn: Bool { Self.builtIn.contains(self) }

    /// Categories where a date would be a lie.
    ///
    /// A film is not due on Thursday. A trip with a date is not a list item at
    /// all any more — it is a horizon, and the only way it becomes one is by
    /// somebody answering the question the app asks about it. And a question
    /// one of them asked is not due at all: putting a date on a conversation
    /// is how it becomes a chore.
    ///
    /// This is the whole of what used to be the Ours/Life distinction. There
    /// is no second type and no second table: an item with no date already
    /// ranks about 0.24 against a surfacing threshold of 0.42, so it sits
    /// there quietly for as long as it likes.
    static let dateless: Set<LifeCategory> = [.watchlist, .trips, .talk]

    var carriesDates: Bool { !Self.dateless.contains(self) }

    var id: String { rawValue }

    var word: String {
        rawValue.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Rendered on the receipt. It still names the zone, because Life is where
    /// the thing will be when they go looking for it — but the zone is no
    /// longer a choice, so it is the same word every time.
    var label: String { "LIFE · \(rawValue.uppercased())" }

    /// Reads a destination label written before there was one filing system.
    ///
    /// Correction rows round-trip through their label, and a couple's log
    /// predates this change. An old `OURS · EATING` is a Food correction and
    /// must still teach the classifier the same lesson it was recorded to
    /// teach; dropping those rows would silently un-learn things people took
    /// the trouble to tell the app.
    init?(legacyLabel: String) {
        let parts = legacyLabel.split(separator: "·", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let zone = parts.first else { return nil }
        let leaf = parts.dropFirst().first ?? ""

        switch (zone, leaf) {
        case ("us", _): self = .trips
        case ("ours", "eating"): self = .food
        case ("ours", "places"): self = .trips
        case ("ours", "someday"): self = .notes
        default:
            guard let category = LifeCategory(named: leaf.isEmpty ? zone : leaf)
            else { return nil }
            self = category
        }
    }

    /// One or two words. A category is a word you can put above a list, and
    /// anything longer is a sentence pretending to be one.
    static let characterLimit = 18

    private static func normalised(_ raw: String) -> String? {
        let words = raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .filter { $0.isLetter || $0 == " " }
            .split(separator: " ")

        // Refused, not truncated. Taking the first two words of "the whole of
        // everything else" would file things under "The whole" — a heading
        // nobody wrote, standing over a list nobody can predict. Better to
        // fail and let the caller fall back.
        guard (1...2).contains(words.count) else { return nil }

        let cleaned = words.joined(separator: " ")
        guard cleaned.count >= 3, cleaned.count <= characterLimit else {
            return nil
        }
        guard !reserved.contains(cleaned) else { return nil }
        return cleaned
    }

    // Codable by its raw value alone, so a category is a plain string in the
    // database and stays readable in the table editor.
    init(from decoder: any Decoder) throws {
        self.init(
            rawValue: try decoder.singleValueContainer().decode(String.self)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum FieldItemSource: String, Codable, Sendable {
    /// The user typed it into the capture field.
    case captured
    /// The intelligence derived it from something else the user said.
    case inferred
    /// Kept only to decode rows written by calendar builds that predate the
    /// private-intake release. New clients never create this source.
    case imported
}

struct LifeItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var category: LifeCategory
    var owner: FieldOwner
    /// The day it is anchored to, if any. Quiet upkeep has none.
    var dueOn: Date?
    /// A hard cut-off inside the day — "window closes 9pm tonight".
    var closesAt: Date?
    /// The occasion this item belongs to. Items cluster by occasion, not by
    /// category and not by date.
    var clusterID: String?
    var source: FieldItemSource
    /// The optional second line under an item in the takeover.
    var detail: String?
    /// Renders the detail warm when the timing is what makes it matter.
    var isTimeCritical: Bool
    var isDone: Bool
    /// The link this item arrived as, when it arrived from somewhere else.
    ///
    /// Not a column. `field_life_resources` has stored the approved URLs of
    /// every published share since private intake shipped, keyed to the item —
    /// the app simply never read them back. This is that row, attached on
    /// fetch, so the lookup policy can tell a thing somebody bought on Amazon
    /// from a thing somebody wrote down.
    ///
    /// Last in the list and optional on purpose: the memberwise initialiser
    /// keeps its default for every existing call site, and a cached item
    /// written before this field existed decodes to `nil` rather than failing.
    var sourceURL: URL?

    /// How much this item is pressing, 0…1. Feeds both the category ordering
    /// on Life and the Today selection. It is never shown to the user as a
    /// number.
    func pressure(now: Date, calendar: Calendar = .gregorianUS) -> Double {
        guard !isDone else { return 0 }

        // A cut-off inside the day is categorically different from a date. It
        // is the only kind of pressure that cannot be recovered tomorrow, so
        // it floors high rather than ramping from zero, and it owns the band
        // above `dateCeiling` outright — no due date reaches up into it.
        if let closesAt {
            let hours = closesAt.timeIntervalSince(now) / 3600
            if hours <= 0 { return 1 }
            if hours <= 24 { return max(0.85, 1 - hours / 24) }
            return max(0.3, 1 - hours / 72)
        }

        guard let dueOn else { return 0.08 }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: dueOn)
        ).day ?? 99

        // Overdue with no cut-off *decays*. The air filter has been two months
        // over and nothing broke — that is upkeep, not an emergency, and
        // treating it as one is how an assistant starts nagging. Escalating
        // here would also have put an errand in front of the grocery window
        // that closes tonight.
        if days < 0 {
            return max(0.15, 0.55 - Double(-days) / 60)
        }

        // Ramps toward `dateCeiling`, never past it. Due today still ranks
        // below a window closing tonight, because a date slips to tomorrow
        // and a window does not.
        return max(0.1, min(Self.dateCeiling, 1 - Double(days) / 14))
    }

    /// The highest pressure a plain due date can reach. Sits under the 0.85
    /// floor that a within-the-day cut-off starts at, so the two never trade
    /// places on a rounding difference.
    private static let dateCeiling = 0.8

    /// The same ramp, for a date that has no item of its own — an occasion's
    /// anchor. Factored out rather than duplicated so a question about Friday
    /// and the things due on Friday cannot drift apart in how urgent they
    /// think Friday is.
    static func anchorPressure(
        on date: Date,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Double {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 99

        if days < 0 { return max(0.15, 0.55 - Double(-days) / 60) }
        return max(0.1, min(dateCeiling, 1 - Double(days) / 14))
    }
}


/// What the app has to say about the week ahead, in its own voice.
///
/// The type exists; nothing produces one yet. `FieldStore.weekSynthesis`
/// returns nil until something can generate all three parts from the couple's
/// real state — a sentence, its reasoning, and three metrics that are true.
struct FieldWeekSynthesis: Hashable, Sendable {
    struct Metric: Hashable, Sendable {
        var figure: String
        var label: String
    }

    /// "Front-loaded. Three things land before Sunday, then it opens right up."
    var shape: String
    /// The italic line behind an accent border, stating why.
    var reasoning: String
    /// Three columns. The handoff's are `3 / BEFORE SUN`, `$540 / COMMITTED`,
    /// and `Friday / THE ONE TO SETTLE`.
    var metrics: [Metric]
}

/// An occasion-based grouping with a generated rationale.
///
/// "Categories are a filing system; occasions are how people actually think."
/// Every cluster states why it exists — that sentence is the feature, not the
/// list underneath it.
struct FieldCluster: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    /// The grouping rationale, shown italic under the title.
    var rationale: String
    /// Tints the cluster. `.shared` renders neutral.
    var tint: FieldOwner
    /// "FRI", "17–22", "NO DATE".
    var timeframe: String
    var anchorDate: Date?

    func items(from all: [LifeItem]) -> [LifeItem] {
        all.filter { $0.clusterID == id && !$0.isDone }
    }

    func urgency(now: Date, items: [LifeItem]) -> Double {
        self.items(from: items).map { $0.pressure(now: now) }.max() ?? 0
    }
}

// MARK: - An appetite is just an undated item
//
// A film, a restaurant, a place, a craving: these used to be `OursItem`, a
// second type with no dates, no completion and no pressure, living in a second
// table behind a second name. The distinction turns out to need no type at
// all.
//
// A `LifeItem` with no `dueOn` scores about 0.24 in `FieldTodaySelector.rank`,
// against a surfacing threshold of 0.42 — it cannot become the one thing Today
// asks of you, however long it sits there. Appetite is simply what an item
// without a date already does. The one rule to keep is that nothing files a
// date onto one; see `FieldClassifier.receipt`.

// MARK: - Us

struct FieldHorizon: Identifiable, Codable, Hashable, Sendable {
    let id: String
    /// "Japan," — the first line, largest type in the app.
    var title: String
    /// "spring 2027" — the second line. Nil when there is no date.
    var window: String?
    var owner: FieldOwner
    /// True for the one horizon Us leads with. Exactly one may be primary.
    var isPrimary: Bool
    /// The thesis sentence under a primary horizon.
    var thesis: String?
    var targetDate: Date?
    /// The Life items this horizon came from, and which stay in Life. A
    /// horizon is a reading of things already written down, not a new copy of
    /// them somewhere else.
    var linkedLifeItemIDs: [String]
    /// The single open question standing between a wish and a date.
    var openQuestion: FieldQuestion?

    /// "4 mo" / "JUNE 2026" / "NO DATE".
    func countdown(now: Date, calendar: Calendar = .gregorianUS) -> String {
        guard let targetDate else { return "NO DATE" }
        let months = calendar.dateComponents(
            [.month],
            from: now,
            to: targetDate
        ).month ?? 0
        if months <= 0 { return "SOON" }
        if months < 12 { return "\(months) mo" }
        return DateFormatter.fieldMonthYear.string(from: targetDate).uppercased()
    }
}

/// A question the app asks at most one of at a time.
struct FieldQuestion: Identifiable, Codable, Hashable, Sendable {
    let id: String
    /// "Spring or fall?"
    var prompt: String
    /// "It's the only thing standing between a wish and a date."
    var stakes: String
    /// Always present. References this couple's actual state, never generic
    /// category logic.
    var reasoning: String
    /// Exactly two, tinted with the two person colours. Never more.
    var choices: [FieldChoice]
}

struct FieldChoice: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    /// Which person's colour tints the button. Purely to make the two options
    /// visually distinct — it does not assign the choice to that person.
    var tint: FieldOwner
}

/// Deliberately two cases. The moment this becomes a count of consecutive
/// weeks it is a streak, and streaks are cut from this product.
enum RhythmHealth: String, CaseIterable, Codable, Sendable {
    case running
    case slipping
}

/// What you repeat to get there. Deliberately streak-free: `health` is a
/// two-case signal, and `occurrences` exists only so the season write-up can
/// say "63 Thursdays" in prose. Neither is ever rendered as a streak, a
/// percentage, or a bar.
struct FieldRhythm: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var cadence: String
    var health: RhythmHealth
    var horizonID: String?
    var occurrences: Int
    var lastOccurred: Date?
}

/// What you've already agreed on, so you don't relitigate it.
struct FieldAnchor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var text: String
    var agreedAt: Date
}

/// A conversation still open, with no pressure to finish.
///
/// **Superseded, and nothing produces one.** An open conversation is now a
/// Life item in `LifeCategory.talk`, read back by `FieldTodaySelector.watching`
/// — which keeps one filing system rather than a second destination, and means
/// a question can be found, moved, and finished exactly like anything else.
/// A settled one is that item done, or a `FieldAnchor` if it was agreed.
/// Left in place only so a stored state can still decode; do not build on it.
struct FieldThread: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var question: String
    var openedAt: Date
    var resolvedAt: Date?
    var resolution: String?
}

/// Plain evidence that ordinary weeks are moving a horizon.
///
/// This is the mechanism that connects Life to Us. It must be plain sentences
/// about real events — never a progress bar, percentage, or chart.
struct FieldEvidence: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var statement: String
    var owner: FieldOwner
    var horizonID: String?
    var occurredAt: Date
}

/// The couple's own name for their current chapter.
struct FieldSeason: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var startedAt: Date
    var endedAt: Date?
    /// Written from real logged data when the chapter closes.
    var narrative: String?
    var decisions: [FieldSeasonDecision]
    /// The honesty that stops this reading as a year-in-review gimmick.
    var oneThingThatDidntHappen: String?

    var isOpen: Bool { endedAt == nil }

    func spanLabel(calendar: Calendar = .gregorianUS) -> String {
        let start = DateFormatter.fieldMonthYear.string(from: startedAt)
        guard let endedAt else { return "SINCE \(start.uppercased())" }
        let end = DateFormatter.fieldMonthYear.string(from: endedAt)
        let months = calendar.dateComponents(
            [.month],
            from: startedAt,
            to: endedAt
        ).month ?? 0
        return "\(start.uppercased()) — \(end.uppercased()) · \(months) MONTHS"
    }
}

struct FieldSeasonDecision: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var text: String
    var decidedOn: Date
}

// MARK: - Deferral (6d)

/// Something the app is deliberately not bringing up yet.
///
/// "Timing is most of tact. You can override any of these — I'd rather be
/// early than sneaky."
struct FieldHeldTopic: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    /// The chip: "3 WEEKS", "SATURDAY", "SPRING".
    var timing: String
    /// Why it is being held. Always specific to this couple.
    var reason: String
    var surfaceOn: Date?
    var wasOverridden: Bool
    /// Set when the user chose to leave it. The app does not re-raise.
    var wasDismissed: Bool

    /// Waiting for its moment. Shown, dimmed, under "what I'm watching" —
    /// which is why a topic somebody has finished with is not one.
    var isHeld: Bool { !wasOverridden && !wasDismissed }

    /// Whether the app should stay off the subject.
    ///
    /// Both answers mean "don't raise this": one is "not yet" and one is
    /// "no". Only an override — the person asking for it now — puts the
    /// subject back in play. Distinguishing the two mattered the moment
    /// "not this year" started setting `wasDismissed` instead of pretending
    /// to be an indefinite hold, because the ranking's filter asked
    /// `isHeld` and a declined topic would have come straight back.
    var isSettled: Bool { !wasOverridden }
}

/// A user-authored constraint on the intelligence's behaviour.
///
/// A real, editable data type — not a setting. "Never money before coffee."
struct FieldStandingRule: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var text: String
    var setAt: Date

    func ageLabel(now: Date, calendar: Calendar = .gregorianUS) -> String {
        let weeks = calendar.dateComponents(
            [.weekOfYear],
            from: setAt,
            to: now
        ).weekOfYear ?? 0
        guard weeks > 0 else { return "Kept since today." }
        return "Kept for \(weeks.spelled) week\(weeks == 1 ? "" : "s")."
    }
}

// MARK: - Corrections (6a)

/// Every time the user moved something, the reason is kept.
struct FieldCorrection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var input: String
    var original: LifeCategory
    var corrected: LifeCategory
    var correctedAt: Date
}

/// The derived record the correction receipt renders. Every statistic on that
/// screen is about the *app's* behaviour — the app critiques itself and never
/// the users.
struct FieldBehaviourChange: Identifiable, Codable, Hashable, Sendable {
    let id: String
    /// The observed behaviour, as a mono label.
    var observation: String
    /// What the app now does differently.
    var change: String
    /// The outcome, italic and quiet.
    var outcome: String
    var accent: FieldOwner
}

// MARK: - The daily moment (6c)

/// One push per day, at a learned hour. No badge counts, no red dots, no
/// second attempt. The app holds a queue and sends only the single
/// highest-value item.
struct FieldDailyMoment: Codable, Hashable, Sendable {
    /// The learned send hour, in minutes past midnight. 8:12 → 492.
    var sendMinute: Int
    /// Everything being watched but not sent.
    var queuedCount: Int
    /// Why this hour. "It's when you both actually reply."
    var hourRationale: String
    /// Reply rate before and after the hour was learned. Framed as evidence
    /// the app learned the right hour, never as a compliance metric.
    var replyRateBefore: Double
    var replyRateAfter: Double
    var lastSentOn: Date?

    var hourLabel: String {
        let hour = sendMinute / 60
        let minute = sendMinute % 60
        return String(format: "%d:%02d", hour, minute)
    }

    func hasSent(on date: Date, calendar: Calendar = .gregorianUS) -> Bool {
        guard let lastSentOn else { return false }
        return calendar.isDate(lastSentOn, inSameDayAs: date)
    }
}

// MARK: - The capture receipt (5a)

/// What the app filed, where, and why. Produced by the classifier, corrected
/// in one tap.
struct FieldReceipt: Identifiable, Hashable, Sendable {
    let id: String
    /// Exactly what was typed. Kept verbatim: it is what the correction log
    /// learns from, and what the chip under the field shows back.
    var input: String
    /// What gets filed — the same thought, said once and plainly. "reminder to
    /// call mom sunday" is stored as "Call mom", on Sunday.
    var title: String
    /// The day the phrasing named, if it named one.
    var dueOn: Date?
    /// Where it goes. One filing system, so this is a category and never a
    /// zone — nothing is ever filed to Us.
    var category: LifeCategory
    /// References this couple's actual state. That specificity is the entire
    /// product.
    var reasoning: String
    var accent: FieldOwner
    var acknowledged: Bool
    var wasCorrected: Bool

    /// Shown under the destination when tidying actually changed something.
    /// Silent when the title is the input, so the receipt does not narrate a
    /// transformation that did not happen.
    var wasRephrased: Bool {
        title.compare(input, options: .caseInsensitive) != .orderedSame
    }
}

/// A pill under the capture field — something caught this week.
struct FieldCapture: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var text: String
    var owner: FieldOwner
    var capturedAt: Date
}

// MARK: - What Today may surface
//
// Today is derived, never stored. Every candidate carries a reason string.

/// One thing Today may present, drawn from Life or Us at the moment of
/// viewing.
struct FieldMoment: Identifiable, Hashable, Sendable {
    enum Shape: Hashable, Sendable {
        /// (b) Something needs you — one thing, full screen.
        case statement
        /// (c) A question toward Us — two equal-weight tinted choices.
        case question(FieldQuestion)
    }

    let id: String
    /// "FROM LIFE", "FROM LIFE · CARE", "TOWARD JAPAN, 2027".
    var source: String
    /// The statement, as the headline.
    var headline: String
    var reasoning: String
    var accent: FieldOwner
    var shape: Shape
    var actions: [FieldMomentAction]
    /// Addressed to one person when the other is unreachable (6b).
    var addressedTo: FieldOwner?
    /// The honest remainder, closing every Today screen.
    var remainder: String?
}

struct FieldMomentAction: Identifiable, Hashable, Sendable {
    enum Weight: Hashable, Sendable {
        case filled
        case outlined
        /// The escape. Always offered.
        case quiet
    }

    /// What the button does, decided where the button is made.
    ///
    /// It used to be inferred at the tap site from `weight`, which is how
    /// "Ask me again tonight" spent its whole life doing nothing: the handler
    /// only knew how to act on the filled one, and the `-primary` / `-escape`
    /// ids that were supposed to distinguish them were parsed nowhere. An
    /// escape that silently does nothing is worse than no escape — the person
    /// tapped it, believed the app, and the same thing came back tomorrow.
    enum Role: Hashable, Sendable {
        /// The filled verb under a statement. `.none` means it only marks the
        /// thing done, which is all this ever did.
        case act(FieldAct)
        case choice(FieldChoice)
        /// "Ask me again tonight." Named `postpone` because `defer` is a
        /// keyword.
        case postpone(FieldDeferralWindow)
        /// "Ask Dylan anyway" — overriding the presence rule (6b).
        case overrideAbsence(FieldOwner)
    }

    let id: String
    var title: String
    var weight: Weight
    var tint: FieldOwner?
    var role: Role
}

/// What a sentence is asking someone to *do*.
///
/// Not a new judgement: `FieldTodaySelector.primaryVerb` has been making it
/// since the beginning by reading the item's own wording, and then keeping
/// only the word it printed on the button. This is the same judgement, kept —
/// which is what lets the button reach the phone instead of only describing
/// what somebody should go and do with it.
enum FieldAct: String, Codable, Hashable, Sendable {
    case call
    case message
    case email
    case book
    case schedule
    case pay
    case order
    /// Nothing in the wording asks for anything outward. The button marks the
    /// thing done.
    case none
}

/// When a held thing comes back.
///
/// A named window rather than a raw date, so the button, the stored topic and
/// the "what I'm holding" line cannot disagree about what "tonight" means.
enum FieldDeferralWindow: String, Codable, Hashable, Sendable {
    /// "Ask me again tonight."
    case thisEvening
    /// "Not yet", on a question.
    case tomorrow

    /// The chip on the held-topic card.
    var chip: String {
        switch self {
        case .thisEvening: "TONIGHT"
        case .tomorrow: "TOMORROW"
        }
    }
}

/// A line in "what I'm watching" on the resolved Today screen.
struct FieldWatchItem: Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    var owner: FieldOwner
    /// Deferred items render at 0.45 — dimmed, because they are being held.
    var isDeferred: Bool
    /// The filed thing this line is reading back, when there is one.
    ///
    /// A watched line is a reading of something: sometimes a Life item, and
    /// sometimes a horizon question or a held topic, which are not items and
    /// have nowhere to open. Only the first kind is reachable, so only the
    /// first kind carries an id — the rest stay text, honestly.
    var itemID: String?
}

// MARK: - Calendar and formatters

extension Calendar {
    static let gregorianUS: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}

extension DateFormatter {
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .gregorianUS
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    nonisolated static let fieldWeekday = make("EEEE")
    /// "FRI" — the form a cluster's timeframe chip takes.
    nonisolated static let fieldWeekdayShort = make("EEE")
    nonisolated static let fieldShortDate = make("d MMM")
    nonisolated static let fieldMonthYear = make("MMMM yyyy")
    nonisolated static let fieldMonthShort = make("MMM yyyy")
    nonisolated static let fieldDayMonth = make("EEE d MMM")
    nonisolated static let fieldDay = make("yyyy-MM-dd")
}

extension Int {
    private static let spelledWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve",
    ]

    /// The season card and the standing-rule card both spell numbers out —
    /// "Kept for eleven weeks" reads as the app talking; "11 weeks" reads as a
    /// metric, and this product does not show metrics about its users.
    ///
    /// Above twelve it falls back to digits, because "sixty-three Thursdays"
    /// starts to read as a flourish rather than a fact.
    var spelled: String {
        Self.spelledWords.indices.contains(self)
            ? Self.spelledWords[self]
            : "\(self)"
    }
}
