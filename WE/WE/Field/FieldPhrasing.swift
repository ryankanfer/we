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
        /// The last day, when what was named was a span — "nov 1 to 5".
        /// Nil for a single day, and always after `dueOn` when set.
        var endsOn: Date? = nil
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

        var words = splitRanges(original.split(separator: " ").map(String.init))
        // A date somebody wrote out beats a weekday word: "dinner fri nov 7"
        // is on the seventh, whatever Friday that is. The weekday is still
        // lifted out, so it does not linger in the title.
        let named = extractNamedDate(&words, now: now, calendar: calendar)
        let weekday = extractDay(&words, now: now, calendar: calendar)
        let day = named?.start ?? weekday
        stripOpener(&words)
        stripHedges(&words)

        let title = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))

        // Everything was scaffolding — "reminder for tomorrow" with nothing
        // attached. The input is all there is, so file that.
        guard title.count >= 2 else {
            return Result(title: sentenceCased(original), dueOn: day, endsOn: named?.end)
        }

        return Result(title: sentenceCased(title), dueOn: day, endsOn: named?.end)
    }

    /// The written-out date in a sentence, if there is one, without tidying
    /// anything. For routing, which needs to know "Bermuda nov 1-5" names a
    /// stretch of days before it decides where Bermuda goes.
    static func namedDate(
        in input: String,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> (start: Date, end: Date?)? {
        var words = splitRanges(input.split(separator: " ").map(String.init))
        return extractNamedDate(&words, now: now, calendar: calendar)
    }

    /// "Nov 1", "Nov 1 to 5", "Nov 28 to Dec 3". How a span is said back,
    /// everywhere it is said back, so the composer, the calendar and Us agree.
    static func spanLabel(
        _ start: Date,
        _ end: Date?,
        calendar: Calendar = .gregorianUS
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let first = formatter.string(from: start)
        guard let end, !calendar.isDate(end, inSameDayAs: start) else { return first }
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        formatter.dateFormat = sameMonth ? "d" : "MMM d"
        return "\(first) to \(formatter.string(from: end))"
    }

    // MARK: Written-out dates
    //
    // "nov 1", "november 1st", "11/1", "the 14th", and spans of them: "nov 1
    // to 5", "nov 1-5", "nov 28 to dec 3", "11/1-11/5". Weekday words were the
    // only dates this file understood, so a trip typed the way people type
    // trips had nowhere to put its days and lost them.

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7,
        "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12,
        "december": 12,
    ]

    /// Words that join the two ends of a span.
    private static let rangeJoiners: Set<String> = [
        "to", "through", "thru", "until", "til", "till", "-", "–", "—",
    ]

    /// "1-5" and "11/1–11/5" as three words, so a span reads the same
    /// whichever way it was typed. Only where it is plainly a date — after a
    /// month, or written with a slash — so "2-3 people" keeps its hyphen.
    private static func splitRanges(_ words: [String]) -> [String] {
        var result: [String] = []
        for (index, word) in words.enumerated() {
            let afterMonth = index > 0 && months[cleaned(words[index - 1])] != nil
            let parts = word.split(
                omittingEmptySubsequences: false,
                whereSeparator: { "-–—".contains($0) }
            ).map(String.init)
            guard parts.count == 2,
                  afterMonth || word.contains("/"),
                  parts.allSatisfy({ $0.first?.isNumber == true })
            else {
                result.append(word)
                continue
            }
            result += [parts[0], "-", parts[1]]
        }
        return result
    }

    /// What a number before it is measuring. "1/2 cup" is half a cup, not
    /// the second of January.
    private static let measures: Set<String> = [
        "cup", "cups", "tsp", "tbsp", "lb", "lbs", "oz", "kg", "g", "inch",
        "inches", "in", "ft", "mile", "miles", "dozen", "gallon", "gallons",
    ]

    /// A day of the month, "5", "5th", "21st". Nil for anything else.
    private static func dayNumber(_ word: String, ordinalOnly: Bool = false) -> Int? {
        var text = cleaned(word)
        let suffixes = ["st", "nd", "rd", "th"]
        let hadSuffix = suffixes.contains { text.hasSuffix($0) }
        if hadSuffix { text.removeLast(2) }
        guard !ordinalOnly || hadSuffix,
              !text.isEmpty, text.allSatisfy(\.isNumber),
              let value = Int(text), (1...31).contains(value)
        else { return nil }
        return value
    }

    /// One written-out date starting at `index`: the month and day it names,
    /// a year if one was given, and how many words it took.
    private static func dateAt(
        _ index: Int,
        in words: [String]
    ) -> (month: Int, day: Int, year: Int?, length: Int)? {
        guard index < words.count else { return nil }
        let word = cleaned(words[index])

        // "nov 1", "november 1st", "nov 1 2027".
        if let month = months[word], index + 1 < words.count,
           let day = dayNumber(words[index + 1]) {
            if index + 2 < words.count, let year = yearNumber(words[index + 2]) {
                return (month, day, year, 3)
            }
            return (month, day, nil, 2)
        }

        // "1 nov", "1st of november".
        if let day = dayNumber(words[index]), index + 1 < words.count {
            if let month = months[cleaned(words[index + 1])] {
                return (month, day, nil, 2)
            }
            if cleaned(words[index + 1]) == "of", index + 2 < words.count,
               let month = months[cleaned(words[index + 2])] {
                return (month, day, nil, 3)
            }
        }

        // "11/1", "11/1/27".
        let numeric = word.split(separator: "/").map(String.init)
        let measured = index + 1 < words.count && measures.contains(cleaned(words[index + 1]))
        if !measured, (2...3).contains(numeric.count),
           let month = Int(numeric[0]), (1...12).contains(month),
           let day = Int(numeric[1]), (1...31).contains(day) {
            let year = numeric.count == 3 ? Int(numeric[2]).map { $0 < 100 ? 2000 + $0 : $0 } : nil
            return (month, day, year, 1)
        }
        return nil
    }

    private static func yearNumber(_ word: String) -> Int? {
        let text = cleaned(word)
        guard text.count == 4, let value = Int(text), (2000...2100).contains(value)
        else { return nil }
        return value
    }

    /// Removes the first written-out date, or span of them, and returns the
    /// days it names. A date with no year that has already gone by this year
    /// is next year's: nobody plans a trip for last November.
    private static func extractNamedDate(
        _ words: inout [String],
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date?)? {
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: today)

        for index in words.indices {
            var startParts: (month: Int, day: Int, year: Int?, length: Int)?
            if let found = dateAt(index, in: words) {
                startParts = found
            } else if cleaned(words[index]) == "the", index + 1 < words.count,
                      let day = dayNumber(words[index + 1], ordinalOnly: true) {
                // "the 14th": this month's, or next month's once it has passed.
                let month = calendar.component(.month, from: today)
                let past = day < calendar.component(.day, from: today)
                startParts = (past ? month % 12 + 1 : month, day, nil, 2)
            }
            guard let start = startParts else { continue }

            var consumed = start.length
            var endParts: (month: Int, day: Int, year: Int?)?
            let joinerIndex = index + consumed
            if joinerIndex < words.count, rangeJoiners.contains(cleaned(words[joinerIndex])) {
                if let end = dateAt(joinerIndex + 1, in: words) {
                    endParts = (end.month, end.day, end.year)
                    consumed += 1 + end.length
                } else if joinerIndex + 1 < words.count,
                          let day = dayNumber(words[joinerIndex + 1]) {
                    // "nov 28 to 3" runs into the next month.
                    let month = day < start.day ? start.month % 12 + 1 : start.month
                    endParts = (month, day, nil)
                    consumed += 2
                }
            }

            func resolve(_ month: Int, _ day: Int, _ year: Int) -> Date? {
                let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
                // Refuses "feb 31" rather than quietly filing March 3.
                guard let date, calendar.component(.day, from: date) == day else { return nil }
                return calendar.startOfDay(for: date)
            }

            var year = start.year ?? thisYear
            guard var startDate = resolve(start.month, start.day, year) else { continue }
            var endDate: Date?
            if let endParts {
                let endYear = endParts.year ?? (endParts.month < start.month ? year + 1 : year)
                endDate = resolve(endParts.month, endParts.day, endYear)
            }
            if start.year == nil, (endDate ?? startDate) < today {
                year += 1
                startDate = resolve(start.month, start.day, year) ?? startDate
                endDate = endDate.flatMap { calendar.date(byAdding: .year, value: 1, to: $0) }
            }
            if let end = endDate, end <= startDate { endDate = nil }

            // "from nov 1", "on the 14th": the word that only held the date
            // goes with it.
            var from = index
            if from > 0, (dayPrepositions + ["from"]).contains(cleaned(words[from - 1])) {
                from -= 1
            }
            words.removeSubrange(from..<(index + consumed))
            return (startDate, endDate)
        }
        return nil
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
