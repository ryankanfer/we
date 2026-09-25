//
//  FieldDayConversation.swift
//  WE
//
//  The day's conversation, as data.
//
//  Today is a conversation now: WE says what matters, each of you adds things
//  in your own words, and WE answers each addition with where it went.
//  Nothing here is stored as a conversation. Every line is derived, on each
//  phone, from what already exists — the moment, today's captures, today's
//  decision proposals, and this person's own private look-ups — so "Today is
//  derived, never stored" still holds.
//
//  Two rules keep it from becoming either a manager or a chatbot:
//
//  1. Anything typed is added to Life, and appears to the partner because it
//     is now a shared thing, not a message. The one thing stored as a message
//     is a proposed decision, because a decision needs the other person to
//     agree and that agreement has to be a record.
//  2. WE only says what it knows. The one kind of question it answers is a
//     look-up, and a look-up can only point at real records. It never
//     composes an answer, and it says "decided" only about a confirmed
//     decision.
//
//  It starts fresh every morning. Yesterday is not a scroll-back; it already
//  lives in Life, and the morning line links there.
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
        "remind me", "find ", "show me", "what about", "what do we",
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
        return lookupOpeners.contains { lowered.hasPrefix($0) }
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
    static func greeting(name: String, hour: Int) -> String {
        let part = switch hour {
        case 5..<12: "Morning"
        case 12..<17: "Afternoon"
        default: "Evening"
        }
        return name.isEmpty ? "\(part)." : "\(part), \(name)."
    }

    static func filed(_ item: LifeItem, dayWord: String?) -> String {
        let place = item.category.word
        if item.visibility == .private {
            return dayWord.map { "Kept in \(place) for \($0), just for you." }
                ?? "Kept in \(place), just for you."
        }
        return dayWord.map { "Added to \(place), \($0)." } ?? "Added to \(place)."
    }

    static func yesterday(count: Int) -> String {
        count == 1
            ? "Yesterday you added one thing."
            : "Yesterday you added \(count.spelled) things."
    }

    static func proposal(by name: String?, title: String) -> String {
        name.map { "\($0) suggests deciding on \(title)." }
            ?? "You suggested deciding on \(title)."
    }

    static func decided(_ title: String) -> String {
        "You both decided on \(title)."
    }

    static func holding(count: Int) -> String {
        count == 1
            ? "I'm holding one thing back for now."
            : "I'm holding \(count.spelled) things back for now."
    }

    static let nothingFound = "I couldn't find that in Life."
    static let found = "Here's what's in Life:"
    static let saveForUs = "Save it for us to talk about"
    static let lookupPrivacy = "Only you see this"
}

// MARK: - The day, assembled

/// One line of the day's conversation.
struct FieldDayEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        /// WE's greeting, for this person only.
        case greeting(String)
        /// "Yesterday you added three things." Item ids to open.
        case yesterday(count: Int, itemIDs: [String])
        /// Something added today, by either of you.
        case capture(FieldCapture, mine: Bool)
        /// WE's reply to one of this person's own additions.
        case filed(itemID: String)
        /// A proposed or confirmed decision.
        case decision(FieldChatMessage)
        /// A private look-up and what WE found.
        case lookup(FieldLookup)
        /// "I'm holding two things back." Opens the deferral screen.
        case holding(count: Int)
    }

    let id: String
    let kind: Kind
    /// Only the thread is ordered by time; the opening lines have none.
    let at: Date?
}

@MainActor
enum FieldDayConversation {
    /// Everything in the thread, in the order it happened today.
    ///
    /// The opening lines — greeting, yesterday, the moment — are drawn by the
    /// view above this list, because they are about the day rather than
    /// events in it.
    static func thread(store: FieldStore) -> [FieldDayEntry] {
        let calendar = Calendar.gregorianUS
        let now = store.now
        let isToday: (Date) -> Bool = { calendar.isDate($0, inSameDayAs: now) }

        var entries: [FieldDayEntry] = []

        for capture in store.state.captures where isToday(capture.capturedAt) {
            let mine = capture.owner == store.speaker
            entries.append(.init(
                id: "capture:\(capture.id)",
                kind: .capture(capture, mine: mine),
                at: capture.capturedAt
            ))
            // WE answers each of this person's own additions. It does not
            // narrate the partner's: they already saw where it went.
            if mine, store.state.lifeItems.contains(where: { $0.id == capture.id }) {
                entries.append(.init(
                    id: "filed:\(capture.id)",
                    kind: .filed(itemID: capture.id),
                    at: capture.capturedAt.addingTimeInterval(0.001)
                ))
            }
        }

        for message in store.chatMessages where message.decision && isToday(message.createdAt) {
            entries.append(.init(
                id: "decision:\(message.id)",
                kind: .decision(message),
                at: message.createdAt
            ))
        }

        for lookup in store.lookups where isToday(lookup.askedAt) {
            entries.append(.init(
                id: "lookup:\(lookup.id)",
                kind: .lookup(lookup),
                at: lookup.askedAt
            ))
        }

        return entries.sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
    }

    /// Life items added yesterday by either of you, visible to this person.
    static func yesterdayItemIDs(store: FieldStore) -> [String] {
        let calendar = Calendar.gregorianUS
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: store.now)
        else { return [] }
        let itemIDs = Set(store.state.lifeItems.map(\.id))
        return store.state.captures
            .filter { calendar.isDate($0.capturedAt, inSameDayAs: yesterday) }
            .map(\.id)
            .filter { itemIDs.contains($0) }
    }
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
