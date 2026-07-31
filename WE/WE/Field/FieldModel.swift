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
// The rule that governs all content placement. Every captured string resolves
// to exactly one of these.

enum FieldDestination: Codable, Hashable, Sendable, CaseIterable {
    /// An obligation, upkeep, or coordination.
    case life(LifeCategory)
    /// An appetite — a film, a restaurant, a place, a craving.
    case ours(OursList)
    /// An intention, aspiration, or progress.
    case usHorizons

    static var allCases: [FieldDestination] {
        LifeCategory.allCases.map(FieldDestination.life)
            + OursList.allCases.map(FieldDestination.ours)
            + [.usHorizons]
    }

    /// Rendered on the receipt in the destination's own colour.
    var label: String {
        switch self {
        case .life(let category): "LIFE · \(category.rawValue.uppercased())"
        case .ours(let list): "OURS · \(list.rawValue.uppercased())"
        case .usHorizons: "US · HORIZONS"
        }
    }

    var zone: FieldZone {
        switch self {
        case .life: .life
        case .ours, .usHorizons: .us
        }
    }
}

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

enum LifeCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case food
    case care
    case calendar
    case money
    case home

    var id: String { rawValue }

    var word: String { rawValue.capitalized }
}

enum FieldItemSource: String, Codable, Sendable {
    /// The user typed it into the capture field.
    case captured
    /// The intelligence derived it from something else the user said.
    case inferred
    /// It came from a connected calendar.
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

// MARK: - Ours
//
// Not to-dos. Appetite. No dates, no completion, no pressure. This is the raw
// material the intelligence uses when it needs an idea.

enum OursList: String, CaseIterable, Codable, Sendable, Identifiable {
    case watchlist
    case eating
    case places
    case someday

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }
}

/// A classification the model produces for taste-shaped input. "Tastes" is
/// the receipt's wording for the eating list.
extension OursList {
    var receiptWord: String {
        switch self {
        case .eating: "TASTES"
        default: label
        }
    }
}

struct OursItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var list: OursList
    var addedBy: FieldOwner
    var addedAt: Date
    /// True when both partners added the same thing independently. The
    /// highest-value inference in the app — surface these prominently.
    var bothAdded: Bool
    /// When both added it, the gap between the two additions, phrased.
    var coincidenceNote: String?
    /// An Ours item can be tagged to a horizon: Tokyo Story → Japan 2027.
    var horizonID: String?
    /// A standing note is a preference rather than an item — "Anything but a
    /// musical". It never gets suggested, only respected.
    var isStandingNote: Bool

    var displayOwner: FieldOwner { bothAdded ? .shared : addedBy }

    /// The mono provenance line under the title.
    func provenance(
        identity: FieldIdentity,
        horizonTitle: String?,
        now: Date = Date()
    ) -> String {
        if bothAdded, let coincidenceNote {
            return coincidenceNote.uppercased()
        }
        if let horizonTitle {
            return "TAGGED TO \(horizonTitle.uppercased())"
        }
        if isStandingNote {
            return "\(identity.name(for: addedBy).uppercased()) · A STANDING NOTE"
        }
        return "\(identity.name(for: addedBy).uppercased()) · \(Self.relative(addedAt, now: now))"
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 3600 {
            return "\(max(1, Int(seconds / 60))) MIN AGO"
        }
        if seconds < 86_400 * 6 {
            let day = DateFormatter.fieldWeekday.string(from: date)
            return day.uppercased()
        }
        return DateFormatter.fieldShortDate.string(from: date).uppercased()
    }
}

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
    var linkedLifeItemIDs: [String]
    var linkedOursItemIDs: [String]
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

    var isHeld: Bool { !wasOverridden && !wasDismissed }
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
    var original: FieldDestination
    var corrected: FieldDestination
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
    var input: String
    var destination: FieldDestination
    /// References this couple's actual state. That specificity is the entire
    /// product.
    var reasoning: String
    var accent: FieldOwner
    var acknowledged: Bool
    var wasCorrected: Bool
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

    let id: String
    var title: String
    var weight: Weight
    var tint: FieldOwner?
}

/// A line in "what I'm watching" on the resolved Today screen.
struct FieldWatchItem: Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    var owner: FieldOwner
    /// Deferred items render at 0.45 — dimmed, because they are being held.
    var isDeferred: Bool
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
