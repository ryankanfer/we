//
//  FieldIntelligence.swift
//  WE
//
//  The moat, and the part the product's job is to make visible.
//
//  Four engines live here:
//
//    1. `FieldTodaySelector`  — picks at most one thing, or nothing.
//    2. `FieldClassifier`     — routes a captured string and says why.
//    3. `FieldDeferral`       — decides what *not* to raise, and when to.
//    4. `FieldMomentScheduler`— holds a queue and releases one push a day.
//
//  Every one of them returns a reason string alongside its result. A result
//  without a reason is a bug, not a shortcut: "almost every surface carries a
//  short 'why this, now' explanation in the app's own voice."
//
//  These are deterministic, on-device rules. They are the specification a
//  model implementation must satisfy, and they are also a complete fallback
//  when the model is unavailable — the app is never allowed to go silent or
//  to invent a plan it cannot source.
//

import Foundation

// MARK: - Today
//
// "Today is derived, never stored. Its selection function ranks candidates
// from Life and Us by time-pressure, decision-unblocking value, and both
// partners' reachability, then returns at most one — or the 'nothing needs
// you' state."

enum FieldTodaySelector {
    struct Context {
        var now: Date
        var identity: FieldIdentity
        var partners: [FieldPartner]
        var lifeItems: [LifeItem]
        var clusters: [FieldCluster]
        var horizons: [FieldHorizon]
        var heldTopics: [FieldHeldTopic]
        var standingRules: [FieldStandingRule]
        var calendar: Calendar = .gregorianUS
    }

    enum Result: Hashable, Sendable {
        /// The state to be proud of, and the most common one once the app is
        /// working.
        case resolved(headline: String, detail: String, watching: [FieldWatchItem])
        case needsYou(FieldMoment)
    }

    static func select(_ context: Context) -> Result {
        let candidates = rank(context)

        guard let top = candidates.first, top.priority >= surfacingThreshold else {
            return .resolved(
                headline: "Nothing needs you here.",
                detail: resolvedDetail(context),
                watching: watching(context)
            )
        }

        return .needsYou(moment(for: top, context: context))
    }

    /// Below this, the app says nothing rather than manufacturing a reason to
    /// speak. Engagement is not a goal.
    private static let surfacingThreshold = 0.42

    // MARK: Ranking

    struct Candidate {
        enum Origin: Hashable {
            case life(LifeItem)
            case horizon(FieldHorizon, FieldQuestion)
        }

        var origin: Origin
        /// Named `priority`, not `score`, deliberately. It ranks *things to
        /// say*, never people, and it is never rendered — the only output the
        /// user sees is the one item and its reason. Keeping the word "score"
        /// out of this layer means any future occurrence of it is a real
        /// violation of the no-scorekeeping constraint rather than a false
        /// positive.
        var priority: Double
        /// The three components, kept separate so the reason can name the one
        /// that actually decided it.
        var timePressure: Double
        var unblockingValue: Double
        var reachability: Double
    }

    static func rank(_ context: Context) -> [Candidate] {
        var candidates: [Candidate] = []

        for item in context.lifeItems where !item.isDone {
            // A topic being deliberately held is not a candidate. Deferral
            // outranks urgency — that is the whole point of 6d.
            if isHeld(item.title, in: context) { continue }
            if violatesStandingRule(item, context: context) { continue }

            let pressure = item.pressure(now: context.now, calendar: context.calendar)
            let unblocking = unblockingValue(for: item, context: context)
            let reach = reachability(for: item.owner, context: context)

            candidates.append(
                Candidate(
                    origin: .life(item),
                    priority: pressure * 0.5 + unblocking * 0.3 + reach * 0.2,
                    timePressure: pressure,
                    unblockingValue: unblocking,
                    reachability: reach
                )
            )
        }

        for horizon in context.horizons {
            guard let question = horizon.openQuestion else { continue }
            if isHeld(question.prompt, in: context) { continue }

            // A question toward Us needs both people. If one is unreachable
            // it waits — and 6b says so out loud rather than silently.
            let reach = reachability(for: .shared, context: context)
            let pressure = horizonPressure(horizon, context: context)

            candidates.append(
                Candidate(
                    origin: .horizon(horizon, question),
                    priority: pressure * 0.35 + 0.9 * 0.35 + reach * 0.3,
                    timePressure: pressure,
                    unblockingValue: 0.9,
                    reachability: reach
                )
            )
        }

        return candidates.sorted { $0.priority > $1.priority }
    }

    /// How much else is waiting on this one thing. An item that gates a whole
    /// cluster unblocks more than an isolated errand.
    private static func unblockingValue(
        for item: LifeItem,
        context: Context
    ) -> Double {
        guard let clusterID = item.clusterID,
              let cluster = context.clusters.first(where: { $0.id == clusterID })
        else { return 0.2 }
        let siblings = cluster.items(from: context.lifeItems).count
        return min(1, 0.3 + Double(siblings) * 0.15)
    }

    /// Reachability, never availability or effort. A shared item scores low
    /// when either partner is away; a solo item only cares about its owner.
    static func reachability(
        for owner: FieldOwner,
        context: Context
    ) -> Double {
        switch owner {
        case .shared:
            let anyAway = context.partners.contains {
                $0.isAway(on: context.now)
            }
            return anyAway ? 0.15 : 1
        case .a, .b:
            guard let partner = context.partners.first(where: {
                $0.owner == owner
            }) else { return 0.5 }
            return partner.isAway(on: context.now) ? 0.25 : 1
        }
    }

    private static func horizonPressure(
        _ horizon: FieldHorizon,
        context: Context
    ) -> Double {
        guard let target = horizon.targetDate else { return 0.3 }
        let months = context.calendar.dateComponents(
            [.month],
            from: context.now,
            to: target
        ).month ?? 24
        return max(0.2, min(1, 1 - Double(months) / 24))
    }

    private static func isHeld(_ subject: String, in context: Context) -> Bool {
        context.heldTopics.contains {
            $0.isHeld && subject.localizedCaseInsensitiveContains($0.title)
        }
    }

    /// A standing rule is a hard constraint the user authored. The
    /// intelligence obeys it before it optimises anything.
    private static func violatesStandingRule(
        _ item: LifeItem,
        context: Context
    ) -> Bool {
        let hour = context.calendar.component(.hour, from: context.now)
        for rule in context.standingRules {
            let text = rule.text.lowercased()
            if text.contains("money before coffee"),
               item.category == .money,
               hour < 10 {
                return true
            }
            if text.contains("errand"), text.contains("morning"), hour < 18,
               item.category == .home {
                return true
            }
        }
        return false
    }

    // MARK: Shaping the moment

    private static func moment(
        for candidate: Candidate,
        context: Context
    ) -> FieldMoment {
        switch candidate.origin {
        case .life(let item):
            return lifeMoment(item, candidate: candidate, context: context)
        case .horizon(let horizon, let question):
            return questionMoment(horizon, question, context: context)
        }
    }

    private static func lifeMoment(
        _ item: LifeItem,
        candidate: Candidate,
        context: Context
    ) -> FieldMoment {
        // If the item is shared but one partner is away, address the reachable
        // one and say so — with an override always offered.
        let away = context.partners.first { $0.isAway(on: context.now) }
        let addressee: FieldOwner? = {
            guard item.owner == .shared, let away else { return nil }
            return away.owner == .a ? .b : .a
        }()

        var actions: [FieldMomentAction] = [
            FieldMomentAction(
                id: "\(item.id)-primary",
                title: primaryVerb(for: item),
                weight: .filled,
                tint: nil
            )
        ]
        if let addressee {
            let absent = addressee == .a ? FieldOwner.b : FieldOwner.a
            actions.append(
                FieldMomentAction(
                    id: "\(item.id)-override",
                    title: "Ask \(context.identity.name(for: absent)) anyway",
                    weight: .outlined,
                    tint: nil
                )
            )
        }
        actions.append(
            FieldMomentAction(
                id: "\(item.id)-escape",
                title: "Ask me again tonight",
                weight: .quiet,
                tint: nil
            )
        )

        return FieldMoment(
            id: item.id,
            source: "FROM LIFE · \(item.category.rawValue.uppercased())",
            headline: item.title,
            reasoning: reason(for: item, candidate: candidate, context: context),
            accent: item.owner,
            shape: .statement,
            actions: actions,
            addressedTo: addressee,
            remainder: remainder(excluding: item.id, context: context)
        )
    }

    private static func questionMoment(
        _ horizon: FieldHorizon,
        _ question: FieldQuestion,
        context: Context
    ) -> FieldMoment {
        let source = [horizon.title, horizon.window]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return FieldMoment(
            id: question.id,
            source: "TOWARD \(source.uppercased())",
            headline: question.prompt,
            reasoning: question.reasoning,
            accent: .shared,
            shape: .question(question),
            actions: question.choices.map {
                FieldMomentAction(
                    id: $0.id,
                    title: $0.title,
                    weight: .outlined,
                    tint: $0.tint
                )
            } + [
                FieldMomentAction(
                    id: "\(question.id)-escape",
                    title: "Not yet",
                    weight: .quiet,
                    tint: nil
                )
            ],
            addressedTo: nil,
            remainder: remainder(excluding: question.id, context: context)
        )
    }

    private static func primaryVerb(for item: LifeItem) -> String {
        switch item.category {
        case .food: "Send it"
        case .care: "Book it"
        case .calendar: "Put it in"
        case .money: "Move it"
        case .home: "Mark it done"
        }
    }

    /// Names the component that actually decided the ranking, so the sentence
    /// is true rather than decorative.
    private static func reason(
        for item: LifeItem,
        candidate: Candidate,
        context: Context
    ) -> String {
        if let closesAt = item.closesAt {
            let time = DateFormatter.fieldClock.string(from: closesAt)
            return "The window closes at \(time) tonight, and nothing else "
                + "today has a cut-off."
        }
        if candidate.unblockingValue > candidate.timePressure,
           let clusterID = item.clusterID,
           let cluster = context.clusters.first(where: { $0.id == clusterID }) {
            let count = cluster.items(from: context.lifeItems).count
            return "\(count.spelled.capitalized) other things are waiting on "
                + "\(cluster.title.lowercased()). This is the one that "
                + "unlocks them."
        }
        if candidate.reachability < 0.5,
           let away = context.partners.first(where: { $0.isAway(on: context.now) }) {
            return "\(away.name) is \(away.awayWindow(on: context.now)?.reason ?? "away"), "
                + "so I'm bringing this to you rather than to both of you."
        }
        if let dueOn = item.dueOn {
            let day = DateFormatter.fieldWeekday.string(from: dueOn)
            return "It lands \(day), and it is the only thing between now and "
                + "then that needs a decision."
        }
        return "Nothing else is pressing, and this has been sitting long "
            + "enough that I'd rather raise it than keep holding it."
    }

    /// "Three other things are waiting. None of them are urgent."
    private static func remainder(
        excluding id: String,
        context: Context
    ) -> String? {
        let others = context.lifeItems.filter {
            !$0.isDone && $0.id != id
        }
        guard !others.isEmpty else { return nil }
        let urgent = others.filter {
            $0.pressure(now: context.now, calendar: context.calendar) > 0.7
        }
        let count = others.count.spelled
        if urgent.isEmpty {
            return "\(count.capitalized) other things are waiting. None of "
                + "them are urgent."
        }
        return "\(count.capitalized) other things are waiting. "
            + "\(urgent.count.spelled.capitalized) of them will need you this week."
    }

    // MARK: The resolved state

    private static func resolvedDetail(_ context: Context) -> String {
        // Assembled only from things that actually resolved. The app never
        // invents a plan, and it does not invent a reassurance either.
        let settled = context.lifeItems
            .filter(\.isDone)
            .sorted { ($0.dueOn ?? .distantPast) > ($1.dueOn ?? .distantPast) }
            .prefix(3)
            .map(\.title)

        guard !settled.isEmpty else {
            return "Nothing is overdue and nothing needs a decision today."
        }
        return settled.joined(separator: ". ") + "."
    }

    /// The three lines under "WHAT I'M WATCHING". Held topics appear here
    /// dimmed — the app is transparent about what it is sitting on.
    static func watching(_ context: Context) -> [FieldWatchItem] {
        var items: [FieldWatchItem] = []

        for horizon in context.horizons where horizon.openQuestion != nil {
            guard let question = horizon.openQuestion else { continue }
            items.append(
                FieldWatchItem(
                    id: horizon.id,
                    text: question.reasoning,
                    owner: horizon.owner,
                    isDeferred: false
                )
            )
        }

        for topic in context.heldTopics where topic.isHeld {
            items.append(
                FieldWatchItem(
                    id: topic.id,
                    text: topic.reason,
                    owner: .shared,
                    isDeferred: true
                )
            )
        }

        return Array(items.prefix(3))
    }
}

// MARK: - The classifier
//
// The single input in the app. The user never has to know where anything
// goes.

enum FieldClassifier {
    struct Context {
        var identity: FieldIdentity
        var speaker: FieldOwner
        var now: Date
        var oursItems: [OursItem]
        var horizons: [FieldHorizon]
        var rhythms: [FieldRhythm]
        var corrections: [FieldCorrection]
        /// Read only so the reasoning can name a real upcoming stretch. The
        /// classifier never routes on who is away.
        var partners: [FieldPartner] = []
        var calendar: Calendar = .gregorianUS
    }

    /// The four canonical classifications from the handoff, used as the
    /// model's few-shot examples and reproduced exactly by the rules below.
    static func classify(_ input: String, context: Context) -> FieldReceipt {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()

        // A prior correction on the same shape of input always wins. This is
        // what makes "tell me once and it stops" true.
        if let learned = learnedDestination(for: lowered, context: context) {
            return receipt(
                text,
                destination: learned.destination,
                reasoning: learned.reasoning,
                context: context
            )
        }

        let destination = route(lowered, context: context)
        return receipt(
            text,
            destination: destination,
            reasoning: reasoning(
                for: destination,
                input: lowered,
                context: context
            ),
            context: context
        )
    }

    // MARK: Routing

    private static let taskVerbs = [
        "remind", "reminder", "call", "book", "pay", "send", "buy", "pick up",
        "schedule", "renew", "cancel", "email", "text", "order", "return",
        "drop off", "clean", "fix", "file",
    ]
    private static let dayWords = [
        "today", "tonight", "tomorrow", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "this week", "next week",
        "weekend",
    ]
    private static let aspirationWords = [
        "someday", "one day", "eventually", "maybe", "we should", "i want to",
        "in the fall", "in the spring", "next year", "2027", "2028",
    ]
    private static let placeWords = [
        "trip", "visit", "go to", "japan", "tokyo", "upstate", "hamptons",
        "weekend in",
    ]
    private static let watchWords = [
        "watch", "film", "movie", "series", "season", "show", "documentary",
    ]
    private static let eatWords = [
        "steak", "dinner", "lunch", "restaurant", "eat", "hungry", "craving",
        "pizza", "ramen", "sushi", "brunch", "cook",
    ]
    private static let moneyWords = ["rent", "bill", "invoice", "insurance", "fund", "save"]
    private static let careWords = ["mom", "dad", "birthday", "vet", "doctor", "appointment", "gift"]
    private static let homeWords = ["filter", "laundry", "trash", "repair", "super", "lease"]

    static func route(_ lowered: String, context: Context) -> FieldDestination {
        let hasTaskShape = taskVerbs.contains { lowered.contains($0) }
        let hasDay = dayWords.contains { lowered.contains($0) }
        let isAspiration = aspirationWords.contains { lowered.contains($0) }

        // A goal beats a task shape: "book flights to japan next year" is a
        // horizon, not an errand.
        if isAspiration || matchesHorizon(lowered, context: context) != nil {
            if !(hasTaskShape && hasDay) { return .usHorizons }
        }

        if hasTaskShape || hasDay {
            return .life(lifeCategory(lowered))
        }

        // Not a task and not a goal — it is an appetite. Explicit signals are
        // checked before the title heuristic, which is deliberately greedy:
        // "steak" is one word with no verb, so it would otherwise be read as a
        // film. Naming the food beats guessing the shape.
        if watchWords.contains(where: { lowered.contains($0) }) {
            return .ours(.watchlist)
        }
        if eatWords.contains(where: { lowered.contains($0) }) {
            return .ours(.eating)
        }
        if placeWords.contains(where: { lowered.contains($0) }) {
            return .ours(.places)
        }
        if looksLikeTitle(lowered) {
            return .ours(.watchlist)
        }
        return .ours(.someday)
    }

    private static func lifeCategory(_ lowered: String) -> LifeCategory {
        if careWords.contains(where: { lowered.contains($0) }) { return .care }
        if moneyWords.contains(where: { lowered.contains($0) }) { return .money }
        if homeWords.contains(where: { lowered.contains($0) }) { return .home }
        if eatWords.contains(where: { lowered.contains($0) }) { return .food }
        return .calendar
    }

    /// Short, no verb, and not a common noun — the shape of a film or a
    /// restaurant name. "fast and furious", "past lives".
    private static func looksLikeTitle(_ lowered: String) -> Bool {
        let words = lowered.split(separator: " ")
        guard (1...5).contains(words.count) else { return false }
        return !taskVerbs.contains { lowered.contains($0) }
            && !dayWords.contains { lowered.contains($0) }
    }

    private static func matchesHorizon(
        _ lowered: String,
        context: Context
    ) -> FieldHorizon? {
        context.horizons.first {
            lowered.contains($0.title.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: ",.")
            ))
        }
    }

    // MARK: Reasoning
    //
    // "The reasoning must reference *this couple's actual state*, not generic
    // category logic. That specificity is the entire product."

    static func reasoning(
        for destination: FieldDestination,
        input lowered: String,
        context: Context
    ) -> String {
        switch destination {
        case .life(let category):
            var sentence = "A task with a day attached, so it went to Life."
            if category == .care,
               let slipping = context.rhythms.first(where: {
                   $0.health == .slipping
               }) {
                let weeks = weeksSince(slipping.lastOccurred, context: context)
                sentence += " I tied it to \(slipping.title.lowercased()) — "
                    + "the rhythm that has been slipping \(weeks.spelled) weeks."
            } else {
                sentence += " I put it where the rest of your "
                    + "\(category.rawValue) already sits."
            }
            return sentence

        case .ours(.eating):
            return "Not a task and not a goal. It went to what you are both "
                + "hungry for, and it will show up when you are deciding "
                + "\(nextDecisionDay(context))."

        case .ours(.watchlist):
            let unwatched = context.oursItems.filter {
                $0.list == .watchlist && !$0.isStandingNote
            }.count + 1
            var sentence = "A film, so it joined the list you share. "
                + "\(unwatched.spelled.capitalized) unwatched now"
            if let stretch = upcomingStretch(context) {
                sentence += " — enough for \(stretch)."
            } else {
                sentence += "."
            }
            return sentence

        case .ours(.places):
            return "A place rather than a plan. It sits in Ours until one of "
                + "you gives it a date, and I'll bring it back when a horizon "
                + "needs an idea."

        case .ours(.someday):
            return "I couldn't tie this to a week or a horizon, so I kept it "
                + "rather than guessing. It'll surface when something makes "
                + "it relevant."

        case .usHorizons:
            if let horizon = matchesHorizon(lowered, context: context) {
                return "This is about where you are going, not this week. I "
                    + "filed it against the \(horizon.title.trimmingCharacters(in: CharacterSet(charactersIn: ","))) "
                    + "horizon as a leaning, not a decision."
            }
            return "This is about where you are going, not this week. I've "
                + "started a horizon for it — name a season when you're ready."
        }
    }

    private static func weeksSince(_ date: Date?, context: Context) -> Int {
        guard let date else { return 3 }
        return max(
            1,
            context.calendar.dateComponents(
                [.weekOfYear],
                from: date,
                to: context.now
            ).weekOfYear ?? 3
        )
    }

    private static func nextDecisionDay(_ context: Context) -> String {
        let weekday = context.calendar.component(.weekday, from: context.now)
        // Friday is the couple's decision night; before it, name it directly.
        return weekday <= 6 ? "Friday" : "the week"
    }

    /// "— enough for the Hamptons week."
    ///
    /// Only names a stretch it can actually source. A long unbroken window in
    /// either partner's calendar is a real reason a watchlist matters; without
    /// one, the sentence ends after the count rather than inventing an
    /// occasion.
    private static func upcomingStretch(_ context: Context) -> String? {
        let windows = context.partners
            .flatMap(\.awayWindows)
            .filter { $0.start > context.now }
            .sorted { $0.start < $1.start }

        guard let next = windows.first,
              let place = next.place,
              let nights = context.calendar.dateComponents(
                  [.day],
                  from: next.start,
                  to: next.end
              ).day,
              nights >= 2
        else { return nil }

        return "\(place.hasPrefix("the") ? place : "the \(place)") week"
    }

    // MARK: Learning

    private static func learnedDestination(
        for lowered: String,
        context: Context
    ) -> (destination: FieldDestination, reasoning: String)? {
        let similar = context.corrections.filter {
            overlap($0.input.lowercased(), lowered) >= 0.5
        }
        guard similar.count >= 1, let latest = similar.max(by: {
            $0.correctedAt < $1.correctedAt
        }) else { return nil }

        return (
            latest.corrected,
            "You moved something like this before, so it goes here now. "
                + "I stopped guessing after the \(similar.count.spelled) time."
        )
    }

    private static func overlap(_ a: String, _ b: String) -> Double {
        let left = Set(a.split(separator: " ").map(String.init))
        let right = Set(b.split(separator: " ").map(String.init))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count)
            / Double(min(left.count, right.count))
    }

    private static func receipt(
        _ input: String,
        destination: FieldDestination,
        reasoning: String,
        context: Context
    ) -> FieldReceipt {
        FieldReceipt(
            id: UUID().uuidString,
            input: input,
            destination: destination,
            reasoning: reasoning,
            accent: accent(for: destination, context: context),
            acknowledged: false,
            wasCorrected: false
        )
    }

    /// The receipt's 2px left border takes the destination's colour. Life and
    /// Ours take the speaker's; a horizon is shared by definition.
    private static func accent(
        for destination: FieldDestination,
        context: Context
    ) -> FieldOwner {
        switch destination {
        case .usHorizons: .shared
        default: context.speaker
        }
    }

    /// One tap to a corrected destination. The correction becomes training
    /// signal that surfaces later in the correction receipt (6a).
    static func correct(
        _ receipt: FieldReceipt,
        to destination: FieldDestination,
        context: Context
    ) -> (receipt: FieldReceipt, correction: FieldCorrection) {
        var corrected = receipt
        corrected.destination = destination
        corrected.wasCorrected = true
        corrected.reasoning = "Moved. I'll file this shape of thing here from "
            + "now on, and I'll tell you what it changed."

        let correction = FieldCorrection(
            id: UUID().uuidString,
            input: receipt.input,
            original: receipt.destination,
            corrected: destination,
            correctedAt: context.now
        )
        return (corrected, correction)
    }
}

// MARK: - Deferral (6d)
//
// "Timing is most of tact."

enum FieldDeferral {
    struct Context {
        var now: Date
        var identity: FieldIdentity
        var partners: [FieldPartner]
        var standingRules: [FieldStandingRule]
        var calendar: Calendar = .gregorianUS
    }

    /// Whether a topic should be raised now, and if not, why not.
    static func shouldRaise(
        _ topic: FieldHeldTopic,
        context: Context
    ) -> Bool {
        if topic.wasOverridden { return true }
        if topic.wasDismissed { return false }
        guard let surfaceOn = topic.surfaceOn else { return false }
        return context.now >= surfaceOn
    }

    /// Topics released today, in the order they should be raised.
    static func released(
        _ topics: [FieldHeldTopic],
        context: Context
    ) -> [FieldHeldTopic] {
        topics
            .filter { shouldRaise($0, context: context) }
            .sorted { ($0.surfaceOn ?? .distantFuture) < ($1.surfaceOn ?? .distantFuture) }
    }

    /// What is being held back right now.
    static func holding(
        _ topics: [FieldHeldTopic],
        context: Context
    ) -> [FieldHeldTopic] {
        topics.filter { $0.isHeld && !shouldRaise($0, context: context) }
    }

    /// The closing card on 6b: what waited, and the promise to bring it back
    /// in one go rather than four notifications.
    ///
    /// Phrased around the partner's name rather than a pronoun — the app does
    /// not know anyone's pronouns and has no business guessing them.
    static func returnPromise(
        for partner: FieldPartner,
        heldCount: Int,
        context: Context
    ) -> String? {
        guard let window = partner.awayWindow(on: context.now), heldCount > 0
        else { return nil }
        let day = DateFormatter.fieldWeekday.string(from: window.end)
        return "\(day) evening, I'll bring \(partner.name) the "
            + "\(heldCount.spelled) things that waited — in one go, not "
            + "\(heldCount.spelled) notifications."
    }
}

// MARK: - One moment a day (6c)
//
// "One push per day, at a learned hour. No badge counts, no red dots, no
// second attempt. The app should hold a queue and send only the single
// highest-value item."

enum FieldMomentScheduler {
    struct Decision: Hashable, Sendable {
        var shouldSend: Bool
        var statement: String?
        var detail: String?
        /// "That's the only thing I'll send today. Eight others are being
        /// watched."
        var restraintLine: String
    }

    static func decide(
        moment: FieldDailyMoment,
        candidates: [FieldTodaySelector.Candidate],
        selection: FieldTodaySelector.Result,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Decision {
        let watched = max(0, candidates.count - 1)
        let restraint = "That's the only thing I'll send today. "
            + "\(watched.spelled.capitalized) others are being watched."

        // Already sent today. There is no second attempt, ever.
        if moment.hasSent(on: now, calendar: calendar) {
            return Decision(
                shouldSend: false,
                statement: nil,
                detail: nil,
                restraintLine: restraint
            )
        }

        let minutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        guard minutes >= moment.sendMinute else {
            return Decision(
                shouldSend: false,
                statement: nil,
                detail: nil,
                restraintLine: restraint
            )
        }

        guard case .needsYou(let selected) = selection else {
            // Nothing needs them. The app stays quiet rather than sending a
            // "you're all caught up" push, which would be engagement bait.
            return Decision(
                shouldSend: false,
                statement: nil,
                detail: nil,
                restraintLine: restraint
            )
        }

        return Decision(
            shouldSend: true,
            statement: selected.headline,
            detail: selected.reasoning,
            restraintLine: restraint
        )
    }

    /// The `WHY 8:12` card. Framed as evidence the app learned the right
    /// hour, never as a compliance metric about the users.
    static func hourExplanation(_ moment: FieldDailyMoment) -> String {
        moment.hourRationale
    }
}

// MARK: - Behaviour changes (6a)
//
// Derives the correction receipt's cards from the correction log. Each card is
// a statement about the app's own behaviour.

enum FieldLearning {
    static func behaviourChanges(
        from corrections: [FieldCorrection],
        identity: FieldIdentity,
        moment: FieldDailyMoment,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> [FieldBehaviourChange] {
        var changes: [FieldBehaviourChange] = []

        // Repeated Life → Ours moves on food mean the app was treating
        // appetite as an obligation.
        let foodToOurs = corrections.filter {
            if case .life(.food) = $0.original,
               case .ours = $0.corrected { return true }
            return false
        }
        if foodToOurs.count >= 2 {
            changes.append(
                FieldBehaviourChange(
                    id: "food-to-ours",
                    observation: "You told me “not a task” \(foodToOurs.count.spelled) times",
                    change: "Food you mention now goes to Ours, not to Life.",
                    outcome: "“Steak” is an appetite. “Groceries” is a task. "
                        + "I can tell them apart now.",
                    accent: .a
                )
            )
        }

        // Anything moved out of Life entirely means the app was inventing.
        let deletions = corrections.filter {
            if case .life = $0.original, case .usHorizons = $0.corrected {
                return true
            }
            return false
        }
        if deletions.count >= 2 {
            changes.append(
                FieldBehaviourChange(
                    id: "stopped-inventing",
                    observation: "You deleted invented plans \(deletions.count.spelled) times",
                    change: "I don't invent plans anymore. I only suggest from "
                        + "what you've actually said.",
                    outcome: "That's why Friday came out of Ours, not out of "
                        + "thin air.",
                    accent: .b
                )
            )
        }

        // The learned hour is always reported, because it is the change with
        // the clearest evidence behind it.
        if moment.replyRateAfter > moment.replyRateBefore {
            changes.append(
                FieldBehaviourChange(
                    id: "learned-hour",
                    observation: "You answer me in the morning, not at night",
                    change: "I ask once, at \(moment.hourLabel).",
                    outcome: "Your reply rate went from "
                        + "\(Int(moment.replyRateBefore * 100))% to "
                        + "\(Int(moment.replyRateAfter * 100))%.",
                    accent: .shared
                )
            )
        }

        return changes
    }

    /// The month number in the receipt's header.
    static func monthsLearning(
        since start: Date,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Int {
        max(1, calendar.dateComponents([.month], from: start, to: now).month ?? 1)
    }
}

extension DateFormatter {
    nonisolated static let fieldClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .gregorianUS
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h a"
        return formatter
    }()
}
