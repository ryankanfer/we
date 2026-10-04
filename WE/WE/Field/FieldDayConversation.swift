//
//  FieldDayConversation.swift
//  WE
//
//  Look ups and proposed decisions: the two things that used to make Today
//  a transcript, kept as rules now that neither is drawn there.
//
//  1. Anything typed is added to Life, and appears to the partner because it
//     is now a shared thing, not a message. The one thing stored as a message
//     is a proposed decision, because a decision needs the other person to
//     agree and that agreement has to be a record.
//  2. WE only says what it knows. The one kind of question it answers is a
//     look up, and a look up can only point at real records. It never
//     composes an answer, and it says "decided" only about a confirmed
//     decision. Look ups are answered in Ask WE (`FieldAskSheet`).
//

import Foundation

// MARK: - A private look-up

/// "What did we get for dad?" — asked of WE, answered only with links.
///
/// Held in memory on this phone and nowhere else. Never filed, never sent,
/// never on the partner's screen: checking on something is not a thing to
/// share, and some of what people check on is sensitive.
struct FieldLookup: Identifiable, Hashable, Sendable {
    let id: String
    let question: String
    let askedAt: Date
    /// Life items, most relevant first.
    let itemIDs: [String]
    /// Confirmed decisions that match.
    let decisionIDs: [String]
    /// Messages from the retired chat that match, read-only.
    let earlierMessageIDs: [String]

    var foundNothing: Bool {
        itemIDs.isEmpty && decisionIDs.isEmpty && earlierMessageIDs.isEmpty
    }
}

enum FieldLookupEngine {
    /// Openers that make a question about what is already written down,
    /// rather than a topic to talk about. "Should we do Tahoe?" is a topic and
    /// is filed; "What did we decide about Tahoe?" is a look-up.
    static let lookupOpeners: [String] = [
        "what did", "what was", "what were", "what's the", "what is the",
        "when did", "when is", "when's", "where did", "where is", "where's",
        "did we", "did i", "did you", "have we", "have i", "who ",
        // "Remind me" only when what follows is a question. "Remind me to
        // call mom tomorrow" is the most natural way there is to write down
        // a plan, and reading every "remind me" as a look-up turned it into a
        // search that saved nothing.
        "remind me what", "remind me when", "remind me where", "remind me who",
        "remind me how", "remind me if", "remind me whether", "remind me which",
        "find ", "show me", "what about", "what do we",
    ]

    static let stopwords: Set<String> = [
        "what", "when", "where", "who", "why", "how", "did", "does", "do",
        "was", "were", "is", "are", "the", "a", "an", "we", "i", "you",
        "our", "my", "your", "for", "to", "of", "on", "in", "at", "about",
        "get", "got", "have", "has", "had", "decide", "decided", "say",
        "said", "remind", "me", "find", "show", "that", "this", "it", "and",
        "or", "with", "again", "any", "there", "thing", "things", "last",
        "yesterday", "week", "s", "whats", "wheres", "whens", "doing",
    ]

    /// Only an unmistakable opener counts. A question that merely ends in a
    /// question mark is a topic for the two of you and is filed to Talk, as
    /// it always has been: misreading a topic as a look-up would keep on one
    /// phone something the person meant to share.
    static func isLookup(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard lookupOpeners.contains(where: { lowered.hasPrefix($0) }) else { return false }
        // "Find" is the one opener that is also an errand. "Find a sitter for
        // saturday" is something to do on a day, not a question about what is
        // already written down; "what did we book for saturday" still is.
        if lowered.hasPrefix("find ") { return !FieldClassifier.namesADate(lowered) }
        return true
    }

    static func keywords(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    /// How many keywords a piece of text contains. "dad" finds "dad's", and a
    /// word longer than four letters also matches without its last letter,
    /// so "gifts" finds "gift".
    static func hits(_ words: [String], in text: String) -> Int {
        let haystack = text.lowercased()
        return words.filter { word in
            haystack.contains(word)
                || (word.count > 4 && haystack.contains(String(word.dropLast())))
        }.count
    }

    static func rank<T>(
        _ candidates: [T],
        words: [String],
        text: (T) -> String,
        limit: Int
    ) -> [T] {
        candidates
            .map { ($0, hits(words, in: text($0))) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

// MARK: - What WE says

enum FieldDayCopy {
    static func decided(_ title: String) -> String {
        "You both decided on \(title)."
    }

    static func holding(count: Int) -> String {
        count == 1
            ? "One thing is held back for now."
            : "\(count.spelled.capitalized) things are held back for now."
    }

    static let nothingFound = "That isn't in Life."
    static let found = "Here's what's in Life:"
    static let saveForUs = "Save it for us to talk about"
}

// MARK: - The store's side

extension FieldStore {
    /// Asks WE to find something. Private, in memory, and answered only with
    /// records this person can already see.
    func lookUp(_ question: String) {
        let words = FieldLookupEngine.keywords(in: question)
        let items = FieldLookupEngine.rank(
            state.lifeItems,
            words: words,
            text: { [$0.title, $0.detail ?? "", $0.category.word].joined(separator: " ") },
            limit: 3
        )
        let decisions = FieldLookupEngine.rank(
            chatMessages.filter { $0.decision && $0.confirmed },
            words: words,
            text: { [$0.body, $0.context.flatMap(chatContextTitle) ?? ""].joined(separator: " ") },
            limit: 2
        )
        let earlier = FieldLookupEngine.rank(
            chatMessages.filter { !$0.decision },
            words: words,
            text: \.body,
            limit: 2
        )
        lookups.append(FieldLookup(
            id: UUID().uuidString,
            question: question,
            askedAt: now,
            itemIDs: items.map(\.id),
            decisionIDs: decisions.map(\.id),
            earlierMessageIDs: earlier.map(\.id)
        ))
    }

    /// Files a look-up's question for the two of you instead, when WE read it
    /// as a look-up and the person meant it as a topic.
    func saveLookupForUs(_ lookup: FieldLookup) {
        lookups.removeAll { $0.id == lookup.id }
        captureDraft = lookup.question
        submitCapture()
        send()
    }

    /// Proposes a shared item as a decision. The partner agrees, or not.
    @discardableResult
    func proposeDecision(itemID: String) -> Bool {
        guard let item = state.lifeItems.first(where: { $0.id == itemID }),
              item.isSharedPresence
        else { return false }
        return sendConversation(
            item.title,
            context: FieldChatContext(kind: "life", id: itemID),
            decision: true
        )
    }

    func hasProposedDecision(itemID: String) -> Bool {
        chatMessages.contains { $0.decision && $0.context?.id == itemID }
    }
}
