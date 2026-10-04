//
//  FieldTodayBrief.swift
//  WE
//
//  Today, as a short brief rather than a transcript.
//
//  The page answers three questions and then stops: what matters now, what
//  did the other person keep, and what is coming. Each answer is one thing,
//  never a list, and each points at a record that already exists. Nothing in
//  here is stored: the brief is read from Life on every draw, the same way
//  `todaySelection` always has been, so editing or deleting an item changes
//  every place it appears at once.
//
//  The selection rules, in one place so they can be tested:
//
//  1. The lead is whatever `FieldTodaySelector` already chose. On a quiet
//     day, when nothing needs anyone, a partner's discovery may lead instead.
//     With neither, the resolved sentence leads, which is the calm state.
//  2. A discovery is something the partner deliberately kept and shared in
//     the last week: their own, shared, open, a reference or a plan rather
//     than a chore. Never a private row of theirs, never a guess.
//  3. Looking ahead is the soonest dated thing after today within ninety
//     days, trips and plans first.
//  4. Nothing appears twice. Order of claim: lead, discovery, ahead.
//  5. Anything else that needs attention today stays one tap away under
//     "more", so the brief never hides an obligation by being short.
//

import Foundation

/// One thing the brief points at.
struct FieldBriefEntry: Identifiable, Hashable {
    let itemID: String
    var id: String { itemID }
    var title: String
    /// One factual line: where it lives, when, who.
    var context: String
    /// Who kept it and when, for a partner's discovery. "Dylan kept this
    /// yesterday."
    var attribution: String? = nil
    var owner: FieldOwner
    var isPrivate: Bool
    /// The page it arrived as, when there is one. The only permitted source
    /// of a picture: nothing is fetched for an item that has no link.
    var sourceURL: URL?
}

struct FieldTodayBrief: Hashable {
    enum Lead: Hashable {
        /// Something needs one of you. The selector's own moment, with the
        /// item behind it when there is one.
        case moment(FieldMoment, fact: String?, sourceURL: URL?)
        /// A quiet day, and the partner kept something.
        case discovery(FieldBriefEntry)
        /// Nothing needs anyone. The sentence the selector already writes.
        case clear(headline: String, detail: String)
    }

    var lead: Lead
    var discovery: FieldBriefEntry?
    var ahead: FieldBriefEntry?
    /// Proposals still waiting on an answer, newest first, at most two.
    var proposalIDs: [String]
    /// Other things with a real reason to be seen today.
    var moreItemIDs: [String]

    /// The item the lead points at, if it points at one.
    var leadItemID: String? {
        switch lead {
        case .moment(let moment, _, _): moment.id
        case .discovery(let entry): entry.itemID
        case .clear: nil
        }
    }
}

@MainActor
enum FieldTodayBriefBuilder {
    /// How far back a partner's discovery may come from.
    static let discoveryWindowDays = 7
    /// How far ahead "Looking ahead" looks.
    static let aheadWindowDays = 90
    static let proposalLimit = 2

    static func build(store: FieldStore) -> FieldTodayBrief {
        let calendar = Calendar.gregorianUS
        let now = store.now
        let speaker = store.speaker
        let partner: FieldOwner = speaker == .b ? .a : .b

        // What this person may see at all. A private row of the partner's
        // should never be on this phone; filtering again costs nothing and
        // makes the rule local to the page that must keep it.
        let visible = store.state.lifeItems.filter {
            $0.visibility != .private || $0.owner == speaker
        }
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var claimed: Set<String> = []

        // 1. The lead, from the selector.
        var lead: FieldTodayBrief.Lead
        switch store.todaySelection {
        case .needsYou(let moment):
            let item = byID[moment.id]
            // A question's own stakes are its supporting sentence; a statement
            // gets the facts written on its item.
            let sentence: String?
            if case .question(let question) = moment.shape {
                sentence = question.stakes
            } else {
                sentence = item.map { fact(for: $0, now: now, calendar: calendar) } ?? momentFact(moment)
            }
            lead = .moment(moment, fact: sentence, sourceURL: item?.sourceURL)
            claimed.insert(moment.id)
        case .resolved(let headline, let detail, _):
            lead = .clear(headline: headline, detail: detail)
        }

        // 2. The partner's discovery.
        let discovery = discoveries(
            in: visible,
            captures: store.state.captures,
            partner: partner,
            partnerName: store.identity.name(for: partner),
            now: now,
            calendar: calendar
        )
        .first { !claimed.contains($0.itemID) }

        var discoveryEntry = discovery
        if case .clear = lead, let discovery {
            lead = .discovery(discovery)
            discoveryEntry = nil
        }
        if let discovery { claimed.insert(discovery.itemID) }

        // 3. Looking ahead.
        let ahead = upcoming(in: visible, speaker: speaker, now: now, calendar: calendar)
            .first { !claimed.contains($0.itemID) }
        if let ahead { claimed.insert(ahead.itemID) }

        // 4. Proposals waiting on an answer. A decision is a record of two
        //    people agreeing, so it stays a proposal until the other answers.
        let proposals = store.chatMessages
            .filter { $0.decision && !$0.confirmed }
            .filter { message in
                guard let id = message.context?.id, message.context?.kind == "life" else { return true }
                return byID[id] != nil
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(proposalLimit)
            .map(\.id)

        // 5. The rest of today, reachable.
        let more = store.todayCandidates
            .filter { $0.priority >= FieldTodaySelector.surfacingThreshold }
            .compactMap { candidate -> String? in
                if case .life(let item) = candidate.origin { return item.id }
                return nil
            }
            .filter { byID[$0] != nil && !claimed.contains($0) }

        return FieldTodayBrief(
            lead: lead,
            discovery: discoveryEntry,
            ahead: ahead,
            proposalIDs: Array(proposals),
            moreItemIDs: uniqued(more)
        )
    }

    // MARK: Discovery

    /// Things the partner deliberately kept and shared this week, newest
    /// first. "Deliberately" means there is a capture of theirs behind it:
    /// an item that arrived any other way was not kept by them.
    static func discoveries(
        in items: [LifeItem],
        captures: [FieldCapture],
        partner: FieldOwner,
        partnerName: String,
        now: Date,
        calendar: Calendar
    ) -> [FieldBriefEntry] {
        guard let since = calendar.date(
            byAdding: .day,
            value: -discoveryWindowDays,
            to: calendar.startOfDay(for: now)
        ) else { return [] }

        let kept = Dictionary(
            captures
                .filter { $0.owner == partner && $0.capturedAt >= since && $0.capturedAt <= now }
                .map { ($0.id, $0.capturedAt) },
            uniquingKeysWith: { max($0, $1) }
        )

        return items
            .filter { item in
                item.owner == partner
                    && item.isSharedPresence
                    && !item.isDone
                    && kept[item.id] != nil
                    && [.reference, .plan].contains(FieldItemPurpose.resolve(item))
            }
            .sorted {
                let left = kept[$0.id] ?? .distantPast
                let right = kept[$1.id] ?? .distantPast
                return left == right ? $0.id < $1.id : left > right
            }
            .map { item in
                let day = kept[item.id].map { keptDay($0, now: now, calendar: calendar) } ?? ""
                return FieldBriefEntry(
                    itemID: item.id,
                    title: item.title,
                    context: shortDetail(item) ?? "In \(item.category.word).",
                    attribution: "\(partnerName) kept this \(day)"
                        .trimmingCharacters(in: .whitespaces) + ".",
                    owner: item.owner,
                    isPrivate: false,
                    sourceURL: item.sourceURL
                )
            }
    }

    private static func keptDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        return "on " + date.formatted(.dateTime.weekday(.wide))
    }

    // MARK: Looking ahead

    /// Dated, open, after today and inside the window. Trips and plans
    /// before anything else, then soonest.
    static func upcoming(
        in items: [LifeItem],
        speaker: FieldOwner,
        now: Date,
        calendar: Calendar
    ) -> [FieldBriefEntry] {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: aheadWindowDays, to: today)
        else { return [] }

        return items
            .filter { !$0.isDone && $0.category.carriesDates }
            .compactMap { item -> (FieldBriefEntry, Date, Bool)? in
                guard let span = span(of: item) else { return nil }
                let (start, end) = span
                let day = calendar.startOfDay(for: start)
                guard day > today, day <= horizon else { return nil }
                let isPlan = FieldItemPurpose.resolve(item) == .plan
                let entry = FieldBriefEntry(
                    itemID: item.id,
                    title: item.title,
                    context: FieldPhrasing.spanLabel(start, end, calendar: calendar),
                    owner: item.owner,
                    isPrivate: item.visibility == .private,
                    sourceURL: item.sourceURL
                )
                return (entry, day, isPlan)
            }
            .sorted {
                if $0.2 != $1.2 { return $0.2 }
                return $0.1 == $1.1 ? $0.0.itemID < $1.0.itemID : $0.1 < $1.1
            }
            .map(\.0)
    }

    /// The first and last day an item is about, read from its timing.
    static func span(of item: LifeItem) -> (start: Date, end: Date?)? {
        if let timing = item.timing, timing.isResolved, let start = timing.anchor ?? item.dueOn {
            return (start, WEObjectTiming.day(timing.endDay))
        }
        if let dueOn = item.dueOn { return (dueOn, nil) }
        return nil
    }

    // MARK: The lead's one sentence

    /// One factual sentence about an item: when, and where if it says.
    /// Built only from what is written on the item.
    static func fact(for item: LifeItem, now: Date, calendar: Calendar) -> String {
        let place = item.place?.trimmingCharacters(in: .whitespaces).nilIfEmpty

        if let closesAt = item.closesAt {
            let time = closesAt.formatted(.dateTime.hour().minute())
            let day = calendar.isDate(closesAt, inSameDayAs: now)
                ? "today"
                : closesAt.formatted(.dateTime.weekday(.wide))
            return "Closes \(day) at \(time)" + (place.map { ", \($0)" } ?? "") + "."
        }

        if let span = span(of: item) {
            let (start, end) = span
            let when = end == nil
                ? dayPhrase(start, now: now, calendar: calendar)
                : FieldPhrasing.spanLabel(start, end, calendar: calendar)
            return when + (place.map { " at \($0)" } ?? "") + "."
        }

        if let place { return "At \(place)." }
        return shortDetail(item) ?? "In \(item.category.word)."
    }

    /// The item's own second line, when it is short enough to be one
    /// sentence on this page.
    static func shortDetail(_ item: LifeItem) -> String? {
        guard let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              detail.count <= 90
        else { return nil }
        return detail.hasSuffix(".") || detail.hasSuffix("?") || detail.hasSuffix("!") ? detail : detail + "."
    }

    /// "Today", "Tomorrow", "Friday", "Was due Monday", "Sep 2".
    static func dayPhrase(_ date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2..<7: return date.formatted(.dateTime.weekday(.wide))
        case ..<0:
            let when = days > -7
                ? date.formatted(.dateTime.weekday(.wide))
                : date.formatted(.dateTime.month(.abbreviated).day())
            return "Was due \(when)"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// A moment with no item behind it: a question's stakes, or the first
    /// sentence of its reasoning.
    private static func momentFact(_ moment: FieldMoment) -> String? {
        let reasoning = moment.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reasoning.isEmpty else { return nil }
        if let end = reasoning.firstIndex(of: ".") {
            return String(reasoning[...end])
        }
        return reasoning
    }

    private static func uniqued(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
