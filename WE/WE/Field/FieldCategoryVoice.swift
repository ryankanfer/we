//
//  FieldCategoryVoice.swift
//  WE
//
//  The one line under a category word, written rather than concatenated.
//
//  On device, through `FoundationModels` — the same route `SoftStartCoordinator`
//  takes for a private note. Nothing about a couple's Life leaves the phone to
//  produce a subtitle, and the app has already promised as much.
//
//  Every failure returns nil, and nil means *use the derived line*. A category
//  is never left blank because a model was busy, unavailable, or wrong.
//

import FoundationModels
import Foundation

enum FieldCategoryVoice {
    /// Long enough for a real clause, short enough to stay one line at 14pt.
    static let characterLimit = 64

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// One line describing what is actually open in a category.
    ///
    /// Returns nil for an empty category, an unavailable model, or a response
    /// that cannot be trusted — all of which mean the same thing to the
    /// caller: say the derived line instead.
    static func subtitle(
        for category: LifeCategory,
        items: [LifeItem],
        now: Date
    ) async -> String? {
        let open = items.filter { !$0.isDone }
        guard !open.isEmpty, isAvailable else { return nil }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            You write one line summarising a shared to-do category for a \
            couple's assistant. Speak plainly and declaratively, in the first \
            person where you speak at all. Never use emoji, exclamation \
            marks, or encouragement. Do not greet, do not advise, do not \
            congratulate, and never compare the two people.

            Describe only what is in the list you are given. Do not invent an \
            item, a date, a place, or a feeling. If two things matter, name \
            both. Return one sentence under \(characterLimit) characters and \
            nothing else.
            """
        )

        do {
            let response = try await session.respond(
                to: prompt(for: category, items: open, now: now),
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 32
                )
            )
            return sanitized(response.content)
        } catch {
            // A failed generation is not an error condition for the screen.
            return nil
        }
    }

    /// The list, as plainly as it can be stated. Titles and timing only — no
    /// owner, because a subtitle that says whose job something is turns a
    /// summary into a comparison between the two people.
    private static func prompt(
        for category: LifeCategory,
        items: [LifeItem],
        now: Date
    ) -> String {
        let calendar = Calendar.gregorianUS
        let lines = items.prefix(8).map { item -> String in
            var line = "- \(item.title)"
            if let closesAt = item.closesAt,
               calendar.isDate(closesAt, inSameDayAs: now) {
                line += " (closes \(DateFormatter.fieldClock.string(from: closesAt)) today)"
            } else if let dueOn = item.dueOn {
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: dueOn)
                ).day ?? 0
                if days < 0 {
                    line += " (\(-days) days overdue)"
                } else if days == 0 {
                    line += " (today)"
                } else if days <= 7 {
                    line += " (\(DateFormatter.fieldWeekday.string(from: dueOn)))"
                }
            }
            return line
        }

        return """
        Category: \(category.word)
        Open items:
        \(lines.joined(separator: "\n"))
        """
    }

    /// First line only, stripped of the decoration models reach for, and
    /// rejected outright if it came back too long — a truncated sentence
    /// reads worse than the derived one it would have replaced.
    static func sanitized(_ content: String) -> String? {
        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let raw = lines.first else { return nil }

        // Checked before trimming, not after: stripping the bullet first
        // turns "- one\n- two" into the perfectly innocent-looking "one" and
        // ships the first row of a list as if it were a sentence.
        let looksLikeAList = lines.count > 1
            && lines.allSatisfy {
                $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*")
            }
        guard !looksLikeAList else { return nil }

        let cleaned = raw.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'“”•-* ")
        )
        guard !cleaned.isEmpty, cleaned.count <= characterLimit else {
            return nil
        }
        return cleaned
    }
}
