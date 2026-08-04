//
//  YoursDates.swift
//  WE
//
//  Every date this space says out loud, and the one it never says.
//
//  Two rules from CIRCLE.md §8, and they pull in opposite directions:
//
//    Forgetting is invisible to the partner and *completely legible to the
//    owner*. The owner always knows the exact dates — both the return and the
//    outer bound. Stated at save, available in entry details.
//
//    And never displayed as a countdown on the object.
//
//  So: exact dates in sentences, and nothing anywhere that ticks. The stroke
//  of the mark lightens across the final week — legible if you look, invisible
//  if you do not — and that ramp is computed here rather than in the view, so
//  it can be tested against a stepped clock instead of a screenshot.
//
//  Pure, and takes its instant as an argument. Nothing in this file calls
//  `Date()`.
//

import Foundation

/// `nonisolated`, and it has to be.
///
/// The module builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
/// without this every date computation would belong to the main actor — and
/// the backends that need them are explicitly `Sendable` and therefore are
/// not on it. Same reason this carries its own calendar rather than borrowing
/// `Calendar.gregorianUS` from `FieldModel`, which is main-actor isolated.
nonisolated enum YoursDates {
    /// Arithmetic, in UTC.
    ///
    /// Postgres computes every interval in this feature — `ready_at`,
    /// `decide_by`, `unseen_delete_at` — and it computes them against a UTC
    /// session. A calendar without a fixed zone adds *calendar* weeks in
    /// whatever region the phone is in, so "six weeks" would land an hour away
    /// from the server's answer twice a year, and a different distance again
    /// for a person who travelled. Small, and exactly the kind of small that
    /// turns into "it said the fourteenth and deleted it on the thirteenth".
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Reading, in the device's zone.
    ///
    /// The opposite requirement, and it is not a contradiction: an instant is
    /// a fact the server owns, and the *date* somebody reads for that instant
    /// has to be their own. "Returns on 14 September" is a promise to a person
    /// standing somewhere.
    static let displayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    // MARK: - Intervals
    //
    // Locked #4: six weeks fixed, then twelve, with no per-entry picker. A
    // duration control would make somebody plan document retention at the
    // exact moment they are trying to put down a thought, and predictability
    // is part of the trust mechanism.
    //
    // The server computes these — `private.yours_interval` — and these
    // constants exist so a save can say the right sentence before the round
    // trip returns, and so the tests can assert the two agree.

    static let firstLife = DateComponents(day: 42)
    static let firstRenewal = DateComponents(day: 84)
    /// §6. An offer that did not cross in two weeks was preparation, and the
    /// preparation was the work.
    static let offerLife = DateComponents(day: 14)
    /// The decision window, which begins when the entry is shown and not one
    /// moment earlier.
    static let decisionWindow = DateComponents(day: 7)
    /// One extra week means exactly one extra week.
    static let snooze = DateComponents(day: 7)

    static func interval(forRenewalCount count: Int) -> DateComponents {
        count <= 0 ? firstLife : firstRenewal
    }

    /// What a save can promise before the server answers.
    static func projectedReadyAt(
        renewalCount: Int = 0,
        from now: Date,
        calendar: Calendar = YoursDates.calendar
    ) -> Date {
        calendar.date(
            byAdding: interval(forRenewalCount: renewalCount),
            to: now
        ) ?? now
    }

    /// The end of the seven days, counted from the moment the entry was
    /// actually shown. There is no other origin for this date — that is
    /// locked #5, and it is why nothing here takes `readyAt`.
    static func projectedDecision(
        from presentedAt: Date,
        calendar: Calendar = YoursDates.calendar
    ) -> Date {
        calendar.date(byAdding: decisionWindow, to: presentedAt) ?? presentedAt
    }

    /// Locked #6, mirrored so an optimistic save can state both dates at once.
    static func outerBound(
        after readyAt: Date,
        calendar: Calendar = YoursDates.calendar
    ) -> Date {
        calendar.date(byAdding: DateComponents(year: 1), to: readyAt) ?? readyAt
    }

    // MARK: - Nearing return

    /// How far into the final week an entry is, or nil if it is not there yet.
    ///
    /// Returned as a fraction rather than a date because the mark must stay
    /// ignorant of calendars: a view that knew the date could render it, and
    /// §2 is explicit that this is "never a countdown, never a date on the
    /// object". A `Double` cannot become a number on screen by accident.
    ///
    /// Nil once the entry is actually ready — at that point it is not nearing
    /// anything, it is waiting to be shown.
    static func nearingProgress(
        readyAt: Date,
        now: Date,
        window: TimeInterval = 7 * 86_400
    ) -> Double? {
        let remaining = readyAt.timeIntervalSince(now)
        guard remaining > 0, remaining <= window else { return nil }
        let elapsed = window - remaining
        return min(max(elapsed / window, 0), 1)
    }

    // MARK: - Saying it

    /// "14 September".
    ///
    /// No year, because every date this space states is inside the next
    /// eighteen months and a year makes a sentence read like a contract. The
    /// one exception is the outer bound, which is far enough out that leaving
    /// the year off would be misleading — see `outerBoundSentence`.
    static func spoken(_ date: Date) -> String {
        DateFormatter.yoursDayMonth.string(from: date)
    }

    static func spokenWithYear(_ date: Date) -> String {
        DateFormatter.yoursDayMonthYear.string(from: date)
    }

    /// §8's save detail, in full: the return and the outer bound, together,
    /// once, at the moment of saving.
    static func saveDetail(
        readyAt: Date,
        unseenDeleteAt: Date,
        now: Date,
        calendar: Calendar = YoursDates.displayCalendar
    ) -> String {
        let sameYear = calendar.component(.year, from: readyAt)
            == calendar.component(.year, from: now)
        let returns = sameYear ? spoken(readyAt) : spokenWithYear(readyAt)
        return """
        Returns on \(returns). If it has not reached you, it will disappear \
        by \(spokenWithYear(unseenDeleteAt)).
        """
    }

    /// §8's snooze confirmation. Both dates, stated before the week is
    /// granted, because this is the one window that can run out while nobody
    /// is looking — and consent for that is obtained here or not at all.
    static func snoozeConfirmation(
        returnsOn: Date,
        letGoOn: Date
    ) -> String {
        """
        This will return on \(spoken(returnsOn)). If you do nothing, it will \
        be let go on \(spoken(letGoOn)).
        """
    }
}

// MARK: - Formatters

extension DateFormatter {
    private static func makeYours(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = YoursDates.displayCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    nonisolated static let yoursDayMonth = makeYours("d MMMM")
    nonisolated static let yoursDayMonthYear = makeYours("d MMMM yyyy")
}
