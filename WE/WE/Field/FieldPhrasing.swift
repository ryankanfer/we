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
    private static let dayPrepositions = ["on", "by", "for", "this", "next", "before"]

    static func tidy(
        _ input: String,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Result {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return Result(title: input, dueOn: nil) }

        var words = original.split(separator: " ").map(String.init)
        let day = extractDay(&words, now: now, calendar: calendar)
        stripOpener(&words)
        stripHedges(&words)

        let title = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))

        // Everything was scaffolding — "reminder for tomorrow" with nothing
        // attached. The input is all there is, so file that.
        guard title.count >= 2 else {
            return Result(title: sentenceCased(original), dueOn: day)
        }

        return Result(title: sentenceCased(title), dueOn: day)
    }

    // MARK: The day

    /// Removes the first day phrase it finds and returns the date it names,
    /// along with any preposition that was only there to hold it.
    private static func extractDay(
        _ words: inout [String],
        now: Date,
        calendar: Calendar
    ) -> Date? {
        for phrase in dayPhrases {
            let parts = phrase.split(separator: " ").map(String.init)
            guard let start = firstIndex(of: parts, in: words) else { continue }

            let end = start + parts.count
            var removeFrom = start

            // "call mom on sunday" — the "on" goes with it. "on Sunday we
            // leave" would too, but a capture is not a sentence with a
            // subordinate clause, and this is only ever the word directly
            // before the day.
            if start > 0,
               dayPrepositions.contains(cleaned(words[start - 1])) {
                removeFrom = start - 1
            }

            words.removeSubrange(removeFrom..<end)
            return date(for: phrase, now: now, calendar: calendar)
        }
        return nil
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
        guard !parts.isEmpty, words.count >= parts.count else { return nil }
        for start in 0...(words.count - parts.count) {
            let slice = words[start..<(start + parts.count)].map(cleaned)
            if slice == parts { return start }
        }
        return nil
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
