//
//  FieldPhrasing.swift
//  WE
//
//  What was said, filed as what it means.
//
//  People do not type list items. They type "reminder to call mom sunday",
//  "we should probably book the vet at some point", "don't forget trash
//  tonight" — the sentence they would have said out loud. Filing that verbatim
//  makes Life read like a transcript of someone's inner monologue, and the day
//  the phrase named is left sitting inside the string where nothing can use
//  it.
//
//  So the input is kept exactly as typed — it is what the correction log
//  learns from and what the chip shows back — and a second, tidied form is
//  what gets filed: the opener dropped, the day lifted out into a real date,
//  the rest left alone. It never paraphrases. Every word in the title was in
//  the input.
//

import Foundation

enum FieldPhrasing {
    struct Result: Hashable, Sendable {
        /// Sentence case, opener removed, day removed. Never empty — it falls
        /// back to the input rather than filing a blank.
        var title: String
        /// The day the phrasing named, resolved against now.
        var dueOn: Date?
        /// True when that day was written out ("nov 1", "10/31",
        /// "Halloween") rather than said relative to now ("friday"). A trip
        /// takes a date only this way: see `LifeCategory.takesAChosenDate`.
        var dateWasWritten = false
    }

    /// Openers, longest first — "remind me to" must win over "remind me".
    private static let openers = [
        "note to self to", "note to self", "don't forget to", "dont forget to",
        "don't forget", "dont forget", "make sure to", "make sure i",
        "make sure we", "remind me to", "reminder to", "remind me", "reminder",
        "i need to", "i have to", "i've got to", "ive got to", "i gotta",
        "we need to", "we have to", "we've got to", "weve got to",
        "i should probably", "we should probably", "i should", "we should",
        "can you", "could you", "please", "let's", "lets", "todo", "to do",
    ]

    /// Hedges that carry no information once the thing is filed. Stripped from
    /// either end only — "maybe" in the middle of a sentence is doing work.
    private static let hedges = [
        "maybe", "probably", "at some point", "sometime", "some time",
        "i guess", "i think", "or something", "if possible", "when you can",
        "when we can", "asap", "please",
    ]

    /// Day phrases, longest first so "next week" is not read as "week".
    ///
    /// Internal rather than private because `FieldTargetPhrasing` strips the
    /// same words when it works out who a sentence is about — "call the vet
    /// friday" is about the vet, not about Friday. The two must agree, and
    /// the only way to guarantee that is for there to be one list.
    static let dayPhrases = [
        "the day after tomorrow", "day after tomorrow", "this weekend",
        "next weekend", "this week", "next week", "tomorrow", "tonight",
        "today", "weekend", "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday", "mon", "tue", "tues", "wed", "thu",
        "thurs", "fri", "sat", "sun",
    ]

    /// Prepositions that only exist to attach the day, and read as debris once
    /// it is gone: "call mom on" → "call mom".
    /// Internal rather than private for the same reason `dayPhrases` is:
    /// `FieldLookupQuery` strips the identical debris when it turns a title
    /// into something to search for.
    static let dayPrepositions = ["on", "by", "for", "this", "next", "before"]

    /// Words that make the day word that follows a thing rather than a time:
    /// "a weekend away", "the sun", "our friday dinner", "last weekend",
    /// "every sunday". Lifting the day out of those leaves "what about a
    /// away?", and the date it files is one nobody named.
    ///
    /// "the" is the exception that proves it, and only after a word that
    /// attaches a time: "fix the sink over the weekend" does name one.
    private static let nounMarkers = [
        "a", "an", "the", "that", "our", "my", "your", "their", "his", "her",
        "its", "every", "each", "one", "last", "whole",
    ]
    private static let theAnchors = dayPrepositions + ["over"]

    static func tidy(
        _ input: String,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Result {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return Result(title: input, dueOn: nil) }
        let written = namedDate(
            in: original.split(separator: " ").map(String.init),
            now: now, calendar: calendar
        ) != nil

        var words = original.split(separator: " ").map(String.init)
        // A date somebody wrote out ("nov 1", "10/31", "Halloween") is more
        // specific than a relative day, so it is looked for first.
        let day = extractNamedDate(&words, now: now, calendar: calendar)
            ?? extractDay(&words, now: now, calendar: calendar)
        stripOpener(&words)
        stripHedges(&words)

        let title = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))

        // Everything was scaffolding — "reminder for tomorrow" with nothing
        // attached. The input is all there is, so file that.
        guard title.count >= 2 else {
            return Result(
                title: sentenceCased(original), dueOn: day, dateWasWritten: written
            )
        }

        return Result(title: sentenceCased(title), dueOn: day, dateWasWritten: written)
    }

    // MARK: The day

    /// Removes the first day phrase that names a time and returns the date
    /// it names, along with any preposition that was only there to hold it.
    private static func extractDay(
        _ words: inout [String],
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let mention = firstTimeMention(in: words) else { return nil }
        words.removeSubrange(mention.range)
        return date(for: mention.phrase, now: now, calendar: calendar)
    }

    /// True when a day word was said, and every time it was said it was a
    /// thing rather than a time — "what about a weekend away?".
    ///
    /// Deliberately the narrow question. `FieldClassifier` reads "is there a
    /// day in this?" by substring, which also catches "sundays" and
    /// "tomorrow's", and it should go on catching them; the only case it
    /// should give up is the one this file has positively recognised as a
    /// noun.
    static func daysAreOnlyNamedAsThings(_ input: String) -> Bool {
        let words = input.split(separator: " ").map(String.init)
        let anyDay = dayPhrases.contains { phrase in
            !occurrences(of: phrase.split(separator: " ").map(String.init), in: words)
                .isEmpty
        }
        return anyDay && firstTimeMention(in: words) == nil
    }

    /// The first day phrase, longest first, that is being used as a time,
    /// with the range of words that go with it.
    private static func firstTimeMention(
        in words: [String]
    ) -> (phrase: String, range: Range<Int>)? {
        for phrase in dayPhrases {
            let parts = phrase.split(separator: " ").map(String.init)
            // Every occurrence, not just the first: in "plan a weekend away
            // this weekend" the first "weekend" is the thing and the second
            // is the time.
            for start in occurrences(of: parts, in: words) {
                if let from = timeStart(ofDayAt: start, in: words) {
                    return (phrase, from..<(start + parts.count))
                }
            }
        }
        return nil
    }

    /// Where the removal should begin for the day phrase at `start`, or nil
    /// when the words around it say it is a thing and not a time.
    private static func timeStart(ofDayAt start: Int, in words: [String]) -> Int? {
        guard start > 0 else { return start }
        let before = cleaned(words[start - 1])

        // "call mom on sunday" — the "on" goes with it. "on Sunday we
        // leave" would too, but a capture is not a sentence with a
        // subordinate clause, and this is only ever the word directly
        // before the day.
        if dayPrepositions.contains(before) { return start - 1 }

        if nounMarkers.contains(before) {
            // "over the weekend" is a time; "the weekend" alone is the
            // weekend itself — "plan the weekend" has no due date in it.
            if before == "the", start > 1,
               theAnchors.contains(cleaned(words[start - 2])) {
                return start - 2
            }
            return nil
        }

        // Bare, and not held by anything: "call the vet friday about miso".
        return start
    }

    private static func date(
        for phrase: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)

        switch phrase {
        case "today", "tonight":
            return today
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: today)
        case "the day after tomorrow", "day after tomorrow":
            return calendar.date(byAdding: .day, value: 2, to: today)
        case "this week":
            return next(weekday: 7, after: today, calendar: calendar)
        case "next week":
            return calendar.date(byAdding: .day, value: 7, to: today)
        case "weekend", "this weekend":
            return next(weekday: 7, after: today, calendar: calendar)
        case "next weekend":
            return next(weekday: 7, after: today, calendar: calendar)
                .flatMap { calendar.date(byAdding: .day, value: 7, to: $0) }
        default:
            guard let weekday = weekdayIndex(phrase) else { return nil }
            return next(weekday: weekday, after: today, calendar: calendar)
        }
    }

    /// Weekday numbers are 1-based from Sunday, the way `Calendar` counts.
    private static func weekdayIndex(_ phrase: String) -> Int? {
        switch phrase {
        case "sunday", "sun": 1
        case "monday", "mon": 2
        case "tuesday", "tue", "tues": 3
        case "wednesday", "wed": 4
        case "thursday", "thu", "thurs": 5
        case "friday", "fri": 6
        case "saturday", "sat": 7
        default: nil
        }
    }

    /// The coming one. Saying "sunday" on a Sunday means today, not a week
    /// away — the thing is happening, and pushing it out seven days would be
    /// the app disagreeing with the person about what day it is.
    private static func next(
        weekday: Int,
        after today: Date,
        calendar: Calendar
    ) -> Date? {
        let current = calendar.component(.weekday, from: today)
        let delta = (weekday - current + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    // MARK: Dates written out
    //
    // The relative words above were the only dates this file knew, so
    // "Ryan in Bermuda nov 1-5" and "Jake's Halloween party" filed with no
    // day at all and the calendar stayed empty. A person writing a trip or a
    // party names the date the way a calendar would; this reads that.
    //
    // What is lifted out of the title and what stays:
    //  - one day ("dinner at Lilia nov 14") is lifted, like "friday" is
    //  - a span ("nov 1-5") stays in the title, because the item carries one
    //    day and the last day would otherwise be thrown away; it is dated to
    //    the first
    //  - a holiday stays, because "Halloween" in "Halloween party" is the
    //    name of the thing as much as its day

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7,
        "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9,
        "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    /// Longest first, so "christmas eve" wins over "christmas".
    private static let holidays: [(phrase: [String], month: Int, day: Int)] = [
        (["new", "year's", "eve"], 12, 31), (["new", "years", "eve"], 12, 31),
        (["new", "year's", "day"], 1, 1), (["new", "years", "day"], 1, 1),
        (["fourth", "of", "july"], 7, 4), (["4th", "of", "july"], 7, 4),
        (["valentine's", "day"], 2, 14), (["valentines", "day"], 2, 14),
        (["christmas", "eve"], 12, 24),
        (["christmas"], 12, 25), (["xmas"], 12, 25),
        (["halloween"], 10, 31), (["nye"], 12, 31),
        (["valentine's"], 2, 14), (["valentines"], 2, 14),
    ]

    private static let rangeWords: Set<String> = [
        "-", "–", "—", "to", "through", "thru", "until", "til", "till",
    ]

    private struct NamedDate {
        var start: Date
        /// The words to take out of the title, or nil to leave them.
        var lift: Range<Int>?
    }

    private static func extractNamedDate(
        _ words: inout [String],
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let found = namedDate(in: words, now: now, calendar: calendar)
        else { return nil }
        if let lift = found.lift { words.removeSubrange(lift) }
        return found.start
    }

    private static func namedDate(
        in words: [String],
        now: Date,
        calendar: Calendar
    ) -> NamedDate? {
        let today = calendar.startOfDay(for: now)
        let w = words.map(normalized)

        for i in w.indices {
            // "nov 1", "november 1st", "nov 1-5", "nov 1 to 5",
            // "oct 30 - nov 2", "nov 1, 2026"
            if let month = months[w[i]], i + 1 < w.count {
                var end: (month: Int, day: Int)?
                var last = i + 1
                let startDay: Int
                if let span = daySpan(w[i + 1]) {
                    startDay = span.0
                    end = (month, span.1)
                } else if let day = dayNumber(w[i + 1]) {
                    startDay = day
                    if i + 3 < w.count, rangeWords.contains(w[i + 2]) {
                        if let to = dayNumber(w[i + 3]) {
                            end = (month, to); last = i + 3
                        } else if i + 4 < w.count, let toMonth = months[w[i + 3]],
                                  let to = dayNumber(w[i + 4]) {
                            end = (toMonth, to); last = i + 4
                        }
                    }
                } else {
                    continue
                }
                var year: Int?
                if last + 1 < w.count, let y = yearNumber(w[last + 1]) {
                    year = y; last += 1
                }
                guard let start = resolve(
                    month: month, day: startDay, end: end, year: year,
                    today: today, calendar: calendar
                ) else { continue }
                return NamedDate(
                    start: start,
                    lift: end == nil ? liftRange(i...last, in: w) : nil
                )
            }

            // "31st oct", "1st of november"
            if w[i].count > 2, let day = dayNumber(w[i]),
               w[i].last?.isLetter == true {
                var at = i + 1
                if at < w.count, w[at] == "of" { at += 1 }
                if at < w.count, let month = months[w[at]],
                   let start = resolve(
                       month: month, day: day, end: nil, year: nil,
                       today: today, calendar: calendar
                   ) {
                    return NamedDate(start: start, lift: liftRange(i...at, in: w))
                }
            }

            // "10/31", "10/31/26", "11/1-11/5", "11/1-5". Only where it
            // reads as a date: with a year, held by "on"/"by", or last. "3/4
            // cup flour" is a measure, and lifting it filed "Cup flour" due
            // in March.
            if let numeric = numericDate(w[i]),
               numeric.year != nil || i == w.count - 1
                || (i > 0 && dayPrepositions.contains(w[i - 1])),
               let start = resolve(
                   month: numeric.month, day: numeric.day, end: numeric.end,
                   year: numeric.year, today: today, calendar: calendar
               ) {
                return NamedDate(
                    start: start,
                    lift: numeric.end == nil ? liftRange(i...i, in: w) : nil
                )
            }
        }

        for holiday in holidays {
            let n = holiday.phrase.count
            guard w.count >= n else { continue }
            for start in 0...(w.count - n) where Array(w[start..<(start + n)]) == holiday.phrase {
                // "last christmas" is a memory, not a plan.
                if start > 0, w[start - 1] == "last" { continue }
                if let date = resolve(
                    month: holiday.month, day: holiday.day, end: nil,
                    year: nil, today: today, calendar: calendar
                ) {
                    return NamedDate(start: date, lift: nil)
                }
            }
        }
        return nil
    }

    /// The date's words plus a preposition that only held it: "on nov 14".
    private static func liftRange(
        _ span: ClosedRange<Int>,
        in words: [String]
    ) -> Range<Int> {
        let from = span.lowerBound > 0
            && dayPrepositions.contains(words[span.lowerBound - 1])
            ? span.lowerBound - 1 : span.lowerBound
        return from..<(span.upperBound + 1)
    }

    /// A month and day with no year means the coming one: "nov 1" typed in
    /// December is next November. A span that is still going counts as
    /// coming, so a trip typed on its third day stays this year.
    private static func resolve(
        month: Int,
        day: Int,
        end: (month: Int, day: Int)?,
        year: Int?,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            let parts = DateComponents(year: y, month: m, day: d)
            guard let date = calendar.date(from: parts),
                  calendar.dateComponents([.year, .month, .day], from: date) == parts
            else { return nil }
            return date
        }
        if let year { return make(year, month, day) }

        let thisYear = calendar.component(.year, from: today)
        guard let start = make(thisYear, month, day) else {
            // Feb 29 in a year without one: try the next year that has it.
            return make(thisYear + 1, month, day)
        }
        var last = start
        if let end {
            // "dec 30 - jan 2" ends in the following year.
            let endYear = end.month < month ? thisYear + 1 : thisYear
            if let e = make(endYear, end.month, end.day), e >= start { last = e }
        }
        return last < today ? make(thisYear + 1, month, day) : start
    }

    private static func dayNumber(_ word: String) -> Int? {
        var digits = word
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) {
            digits.removeLast(suffix.count)
            break
        }
        guard digits.count <= 2, digits.allSatisfy(\.isNumber),
              let value = Int(digits), (1...31).contains(value)
        else { return nil }
        return value
    }

    /// "1-5", "1st–5th".
    private static func daySpan(_ word: String) -> (Int, Int)? {
        let parts = word.split(whereSeparator: { "-–—".contains($0) })
        guard parts.count == 2,
              let a = dayNumber(String(parts[0])),
              let b = dayNumber(String(parts[1])), b >= a
        else { return nil }
        return (a, b)
    }

    private static func yearNumber(_ word: String) -> Int? {
        guard word.count == 4, word.allSatisfy(\.isNumber),
              let value = Int(word), (2000...2100).contains(value)
        else { return nil }
        return value
    }

    private static func numericDate(
        _ word: String
    ) -> (month: Int, day: Int, year: Int?, end: (month: Int, day: Int)?)? {
        let pattern = #"^(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?(?:[-–—](?:(\d{1,2})/)?(\d{1,2}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: word, range: NSRange(word.startIndex..., in: word)
              )
        else { return nil }
        func group(_ n: Int) -> Int? {
            guard let range = Range(match.range(at: n), in: word) else { return nil }
            return Int(word[range])
        }
        guard let month = group(1), (1...12).contains(month),
              let day = group(2), (1...31).contains(day)
        else { return nil }
        let year = group(3).map { $0 < 100 ? 2000 + $0 : $0 }
        var end: (month: Int, day: Int)?
        if let endDay = group(5) {
            end = (group(4) ?? month, endDay)
        }
        return (month, day, year, end)
    }

    /// Lowercased, outer punctuation off, curly apostrophes made straight.
    private static func normalized(_ word: String) -> String {
        cleaned(word.replacingOccurrences(of: "’", with: "'"))
    }

    // MARK: Openers and hedges

    private static func stripOpener(_ words: inout [String]) {
        for opener in openers.sorted(by: { $0.count > $1.count }) {
            let parts = opener.split(separator: " ").map(String.init)
            guard words.count > parts.count,
                  firstIndex(of: parts, in: words) == 0
            else { continue }
            words.removeFirst(parts.count)
            // One pass only. "i need to remind me to" is not a sentence
            // anybody types, and looping invites eating a real verb.
            return
        }
    }

    private static func stripHedges(_ words: inout [String]) {
        var changed = true
        while changed, words.count > 1 {
            changed = false

            for hedge in hedges {
                let parts = hedge.split(separator: " ").map(String.init)
                guard words.count > parts.count else { continue }

                if firstIndex(of: parts, in: words) == 0 {
                    words.removeFirst(parts.count)
                    changed = true
                }
                if words.count > parts.count,
                   firstIndex(of: parts, in: words) == words.count - parts.count {
                    words.removeLast(parts.count)
                    changed = true
                }
            }
        }
    }

    // MARK: Words

    private static func firstIndex(
        of parts: [String],
        in words: [String]
    ) -> Int? {
        occurrences(of: parts, in: words).first
    }

    private static func occurrences(
        of parts: [String],
        in words: [String]
    ) -> [Int] {
        guard !parts.isEmpty, words.count >= parts.count else { return [] }
        return (0...(words.count - parts.count)).filter { start in
            words[start..<(start + parts.count)].map(cleaned) == parts
        }
    }

    private static func cleaned(_ word: String) -> String {
        word.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ",.;:!?\"'“”")
        )
    }

    /// The first letter only. Anything else the person capitalised — a name, a
    /// place, an acronym — is theirs and stays exactly as they typed it.
    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
