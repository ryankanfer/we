//
//  FieldItemVoice.swift
//  WE
//
//  Breaking one thing into fifteen minutes of it.
//
//  On device, through `FoundationModels`, and — like `FieldCategoryVoice` —
//  every failure returns nil. Nil means the button was not offered or the plan
//  is not shown. A plan is a nicety; there is no screen here that breaks
//  without one.
//
//  The line this file must not cross, and the reason it has exactly one entry
//  point: **the model may help somebody plan clearing a guest room. It may
//  never state a synopsis, a streaming service, a price, or whether a shop has
//  one in stock.** Those are facts about the world, and this app has no source
//  for them — so a sentence containing one is not a helpful guess, it is the
//  app making something up in a place a couple has been told they can trust.
//
//  `sanitizedPlan` is where that line is enforced rather than hoped for. It is
//  pure and static, so the tests for it need no model and no simulator.
//

import FoundationModels
import Foundation

/// A plan somebody asked for, while they are looking at it.
///
/// Held on `FieldStore` and nowhere else — see the note on `itemPlan`. It
/// carries its item's id so that a plan cannot outlive the sheet that asked
/// for it and land on whatever is opened next.
struct FieldItemPlan: Hashable, Sendable, Identifiable {
    let itemID: String
    /// Empty while the model is still working. A tap asked for this, so a
    /// moment of "working on it" is an answer to a question rather than a
    /// spinner sitting where content should be.
    var steps: [String] = []
    var isThinking: Bool = true

    var id: String { itemID }
}

enum FieldItemVoice {
    /// One step, on one line, at the sheet's body size.
    static let lineLimit = 72
    /// Fewer than three is not a plan, it is the thing restated. More than
    /// five is a project, and the button said fifteen minutes.
    static let lineCount = 3...5

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// Three to five steps for one task, or nil.
    ///
    /// Nil for: no model, a generation that threw, a cancelled sheet, or any
    /// answer the sanitiser will not vouch for. The caller does not need to
    /// know which — all four mean *show nothing*.
    static func plan(
        for item: LifeItem,
        minutes: Int
    ) async -> [String]? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            You break one household task into the steps somebody could \
            actually finish in \(minutes) minutes. Speak plainly and \
            declaratively. Never use emoji, exclamation marks, or \
            encouragement. Do not greet, do not advise, do not congratulate, \
            and never mention either person by name.

            Use only what the task itself tells you. Never name a product, a \
            brand, a shop, a price, a measurement, or a duration that is not \
            already in the task. If you do not know what is in the room, say \
            the step without saying what is in it.

            Return between \(lineCount.lowerBound) and \(lineCount.upperBound) \
            lines. One step per line, each under \(lineLimit) characters, no \
            numbering and no bullets, and nothing else.
            """
        )

        do {
            let response = try await session.respond(
                to: "Task: \(item.title)",
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 160
                )
            )
            return sanitizedPlan(
                response.content,
                against: source(for: item, minutes: minutes)
            )
        } catch {
            // Includes `CancellationError` when the sheet closed mid-generation.
            return nil
        }
    }

    /// Everything the model was allowed to know, as one string to check its
    /// numbers against.
    static func source(for item: LifeItem, minutes: Int) -> String {
        [item.title, item.detail ?? "", String(minutes)]
            .joined(separator: " ")
    }

    // MARK: - The check

    /// Brand names a model reaches for when it is filling space. Rejected
    /// unless the couple wrote them, in which case they are the couple's own
    /// words coming back.
    private static let brands: Set<String> = [
        "amazon", "walmart", "target", "costco", "ikea", "wayfair", "ebay",
        "netflix", "hulu", "max", "disney", "peacock", "paramount", "prime",
        "clorox", "lysol", "swiffer", "windex", "dyson", "roomba", "3m",
        "filtrete", "honeywell", "nest", "google", "apple", "instacart",
    ]

    private static let forbiddenMarks: Set<Character> = ["$", "£", "€", "%"]
    private static let forbiddenFragments = ["http", "www.", ".com", "://"]

    /// The whole plan, or nothing.
    ///
    /// Rejected wholly rather than line by line, deliberately: a plan missing
    /// its third step is not a shorter plan, it is a wrong one, and somebody
    /// following four steps has no way to see that a fifth was quietly
    /// dropped for saying `$24.99`.
    static func sanitizedPlan(
        _ content: String,
        against source: String
    ) -> [String]? {
        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { stripped($0) }
            .filter { !$0.isEmpty }

        guard lineCount.contains(lines.count) else { return nil }

        let ground = source.lowercased()
        for line in lines {
            guard line.count <= lineLimit else { return nil }
            guard isGrounded(line, in: ground) else { return nil }
        }
        return lines
    }

    /// Numbering and bullets come off; quotes come off; nothing else does.
    /// A step is not truncated to fit — an over-long line rejects the plan,
    /// because half an instruction is worse than none.
    private static func stripped(_ line: String) -> String {
        var text = line
        // "1." / "1)" / "- " / "• " — the decoration, not the step.
        while let first = text.first,
              first.isNumber || "•-*.)".contains(first) || first == " " {
            text.removeFirst()
        }
        return text.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'“” ")
        )
    }

    private static func isGrounded(_ line: String, in ground: String) -> Bool {
        let lowered = line.lowercased()

        guard !line.contains(where: { forbiddenMarks.contains($0) }) else {
            return false
        }
        guard !forbiddenFragments.contains(where: { lowered.contains($0) }) else {
            return false
        }

        // Numeric grounding. Every run of two or more digits must appear
        // verbatim in what the model was given — which kills "$24.99", "1h
        // 47m", "2019", and a phone number, deterministically and without a
        // list of things to look for. A lone digit is allowed: "step 1" and
        // "5 minutes" are shapes of speech, not claims about the world.
        for run in digitRuns(in: lowered) where run.count >= 2 {
            guard ground.contains(run) else { return false }
        }

        // A number the app would be willing to dial is never something the
        // model composed — see the note on `FieldDial.normalised`.
        for word in lowered.split(whereSeparator: { $0 == " " }) {
            if FieldDial.normalised(String(word)) != nil { return false }
        }

        let words = Set(
            lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        for brand in words.intersection(brands) {
            guard ground.contains(brand) else { return false }
        }
        return true
    }

    private static func digitRuns(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
