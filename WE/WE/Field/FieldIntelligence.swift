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
// partners' reachability, then returns at most one — or the resolved state."
//
// The resolved state is phrased as a resolution rather than an absence
// ("Today is clear."), and it is still the app declining to speak: nothing is
// manufactured to fill it. On an account with nothing to reason over yet it
// says that instead, because claiming a clear day the app cannot see is the
// one reassurance it has not earned.

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
            let (headline, detail) = resolved(context)
            return .resolved(
                headline: headline,
                detail: detail,
                watching: watching(context)
            )
        }

        return .needsYou(moment(for: top, context: context))
    }

    /// Below this, the app says nothing rather than manufacturing a reason to
    /// speak. Engagement is not a goal.
    ///
    /// Shared with `FieldCategoryDigest`, deliberately: an item earns an
    /// explanation inside a category room for the same reason it would have
    /// earned the whole of Today. One bar, not two.
    static let surfacingThreshold = 0.42

    // MARK: Ranking

    struct Candidate {
        enum Origin: Hashable {
            case life(LifeItem)
            case horizon(FieldHorizon, FieldQuestion)
            /// A thing said twice with no date on it, and the one question
            /// that would settle whether it is real. See `FieldPromotion`.
            case promotion(FieldPromotion.Proposal)
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

        // At most one, and only when there is something to ask about. It
        // deliberately outranks quiet upkeep and deliberately loses to
        // anything with a real cut-off: a question about next year should
        // never arrive in front of a thing closing tonight.
        if let proposal = FieldPromotion.proposal(context) {
            let reach = reachability(for: .shared, context: context)
            candidates.append(
                Candidate(
                    origin: .promotion(proposal),
                    priority: 0.25 * 0.5 + 0.9 * 0.3 + reach * 0.2,
                    timePressure: 0.25,
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
        case .promotion(let proposal):
            return promotionMoment(proposal, context: context)
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

    /// The question that turns a thing said twice into a horizon — or leaves
    /// it exactly where it is, which is the answer the app must be equally
    /// happy with.
    private static func promotionMoment(
        _ proposal: FieldPromotion.Proposal,
        context: Context
    ) -> FieldMoment {
        FieldMoment(
            id: proposal.question.id,
            source: "FROM LIFE · \(proposal.category.rawValue.uppercased())",
            headline: proposal.question.prompt,
            reasoning: proposal.question.reasoning,
            accent: .shared,
            shape: .question(proposal.question),
            actions: proposal.question.choices.map {
                FieldMomentAction(
                    id: $0.id,
                    title: $0.title,
                    weight: .outlined,
                    tint: $0.tint
                )
            } + [
                FieldMomentAction(
                    id: "\(proposal.question.id)-escape",
                    title: "Ask me another time",
                    weight: .quiet,
                    tint: nil
                )
            ],
            addressedTo: nil,
            remainder: remainder(excluding: proposal.question.id, context: context)
        )
    }

    /// The verb on the button under a moment.
    ///
    /// The five given categories each have one that reads like the thing you
    /// actually do. A category the app grew has no such knowledge behind it,
    /// so it says the honest general one rather than guessing that Pets are
    /// booked and Taxes are sent.
    private static func primaryVerb(for item: LifeItem) -> String {
        switch item.category {
        case .food: "Send it"
        case .care: "Book it"
        case .money: "Move it"
        case .buys: "Order it"
        default: "Mark it done"
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

    /// Both halves of the resolved state, derived together so they can never
    /// disagree — a headline claiming a clear day over a detail admitting the
    /// app knows nothing would be worse than either alone.
    private static func resolved(
        _ context: Context
    ) -> (headline: String, detail: String) {
        // Nothing to reason over at all. Saying the day is clear here would be
        // a claim the app has not earned: it isn't clear, it is unknown, and
        // the honest version of that says so. Done items count — a couple who
        // finished everything has a history and is not new.
        if context.lifeItems.isEmpty,
           context.horizons.isEmpty,
           context.clusters.isEmpty {
            return (
                "I'm still learning your week.",
                "Say anything below and I'll start sorting it. Today shows "
                    + "one thing at a time, or nothing at all."
            )
        }

        // Assembled only from things that actually resolved. The app never
        // invents a plan, and it does not invent a reassurance either.
        let settled = context.lifeItems
            .filter(\.isDone)
            .sorted { ($0.dueOn ?? .distantPast) > ($1.dueOn ?? .distantPast) }
            .prefix(3)
            .map(\.title)

        guard !settled.isEmpty else {
            return (
                "Today is clear.",
                "Nothing is overdue and nothing needs a decision today."
            )
        }
        return ("Today is clear.", settled.joined(separator: ". ") + ".")
    }

    /// The three lines under "WHAT I'M WATCHING". Held topics appear here
    /// dimmed — the app is transparent about what it is sitting on.
    ///
    /// A question one of them asked leads, because somebody just chose to
    /// raise it and three horizon questions should not push it off the end of
    /// a list that only holds three. It is not a copy of anything: it is the
    /// Life item read back, the same way a horizon is a reading of the items
    /// underneath it.
    static func watching(_ context: Context) -> [FieldWatchItem] {
        var items: [FieldWatchItem] = []

        if let asked = context.lifeItems.first(where: {
            $0.category == .talk && !$0.isDone
        }) {
            items.append(
                FieldWatchItem(
                    id: asked.id,
                    text: "\(asked.title) — "
                        + "\(context.identity.name(for: asked.owner)) asked. "
                        + "No date on it.",
                    owner: asked.owner,
                    isDeferred: false
                )
            )
        }

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
        var lifeItems: [LifeItem]
        var horizons: [FieldHorizon]
        var rhythms: [FieldRhythm]
        var corrections: [FieldCorrection]
        /// Every Life category that currently exists — the given ones and any
        /// this couple has grown. An existing category always beats starting
        /// another one that means the same thing.
        var lifeCategories: [LifeCategory] = LifeCategory.builtIn
        /// Read only so the reasoning can name a real upcoming stretch. The
        /// classifier never routes on who is away.
        var partners: [FieldPartner] = []
        var calendar: Calendar = .gregorianUS
    }

    /// Everything resolves to a category. There is nowhere else to send it.
    static func classify(_ input: String, context: Context) -> FieldReceipt {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()

        // A prior correction on the same shape of input always wins. This is
        // what makes "tell me once and it stops" true.
        if let learned = learnedCategory(for: lowered, context: context) {
            return receipt(
                text,
                category: learned.category,
                reasoning: learned.reasoning,
                context: context
            )
        }

        let category = route(lowered, context: context)
        return receipt(
            text,
            category: category,
            reasoning: reasoning(
                for: category,
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
        "drop off", "clean", "fix", "file", "pack", "confirm", "rsvp", "wrap",
    ]
    private static let dayWords = [
        "today", "tonight", "tomorrow", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "this week", "next week",
        "weekend",
    ]
    /// How a question opens when it is one. Checked alongside a literal "?",
    /// because most people do not type the mark on a phone.
    private static let questionOpeners = [
        "do we", "do you", "should we", "should i", "what about",
        "how do you feel", "what do you think", "are we", "can we",
        "would you", "have we", "have you", "did we",
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
    private static let buyWords = [
        "amazon", "cart", "order", "delivery", "shipping", "returns", "buy",
        "batteries", "refill", "restock",
    ]

    /// Where a capture goes. A category, always — there is no other kind of
    /// answer this function can give.
    ///
    /// An aspiration no longer routes anywhere different. "japan in the fall
    /// maybe" is a trip you have mentioned, filed in Trips like any other; it
    /// becomes a horizon in Us only when somebody answers the question the app
    /// asks about it. See `FieldPromotion`.
    static func route(_ lowered: String, context: Context) -> LifeCategory {
        let hasTaskShape = taskVerbs.contains { lowered.contains($0) }
        let hasDay = dayWords.contains { lowered.contains($0) }
        let isAspiration = aspirationWords.contains { lowered.contains($0) }

        // A trip named as a wish, or a place already on a horizon, is still a
        // trip. Checked first so "japan in the fall maybe" does not fall into
        // the title heuristic and come out a film.
        let namesAPlace = placeWords.contains { lowered.contains($0) }
        if !(hasTaskShape && hasDay),
           matchesHorizon(lowered, context: context) != nil
               || (isAspiration && namesAPlace) {
            return .trips
        }

        // A question, and nothing was asked of anybody. Checked after Trips —
        // "should we do japan in the fall?" is a trip they have mentioned, and
        // `FieldPromotion` already owns whether it becomes real — but before
        // the task shape, so "should we call the plumber?" is read as the
        // question it is rather than an errand somebody has been assigned.
        //
        // A day word disqualifies it. "Are we free tomorrow?" has a date in it
        // and belongs to the day, not to the pile of things to talk about.
        if !hasDay, isQuestion(lowered) {
            return .talk
        }

        if hasTaskShape || hasDay {
            return lifeCategory(lowered, context: context)
        }

        // An obligation noun with no verb around it is still an obligation.
        // "rent" is not an appetite, and before this it fell through to the
        // title heuristic and was filed as a film. Appetite words are
        // deliberately excluded here — "steak" is a craving, and only ever a
        // craving, until a verb or a day says otherwise.
        if careWords.contains(where: { lowered.contains($0) })
            || moneyWords.contains(where: { lowered.contains($0) })
            || homeWords.contains(where: { lowered.contains($0) }) {
            return lifeCategory(lowered, context: context)
        }

        // Explicit signals before the title heuristic, which is deliberately
        // greedy: "steak" is one word with no verb, so it would otherwise be
        // read as a film. Naming the food beats guessing the shape.
        if watchWords.contains(where: { lowered.contains($0) }) {
            return .watchlist
        }
        if eatWords.contains(where: { lowered.contains($0) }) {
            return .food
        }
        if namesAPlace {
            return .trips
        }
        if buyWords.contains(where: { lowered.contains($0) }) {
            return .buys
        }
        if looksLikeTitle(lowered) {
            return .watchlist
        }
        // A subject with no home. Grown rather than given, so a couple who
        // never says anything unplaceable never sees the word.
        return invented(from: lowered) ?? .notes
    }

    /// Asked, rather than stated. The mark when it is there, and the opening
    /// when it is not — a question typed without punctuation is still a
    /// question, and on a phone it usually is.
    static func isQuestion(_ lowered: String) -> Bool {
        if lowered.hasSuffix("?") { return true }
        return questionOpeners.contains { lowered.hasPrefix($0) }
    }

    /// Domains a couple reliably has, and the word they would use for each.
    /// Checked after the five given categories and before anything is
    /// invented, so "book the dog's shots" grows Pets once and then keeps
    /// going there instead of growing Dog, Vet, and Shots.
    private static let namedDomains: [(category: String, words: [String])] = [
        ("health", ["dentist", "therapy", "therapist", "prescription", "refill",
                    "pharmacy", "checkup", "check up", "bloodwork", "physio",
                    "gym", "workout", "run", "meds"]),
        ("pets", ["dog", "cat", "puppy", "kitten", "litter", "groomer",
                  "walker", "kibble", "shots"]),
        ("car", ["car", "oil change", "tires", "tyres", "registration", "dmv",
                 "parking", "gas", "mechanic", "inspection"]),
        ("travel", ["flight", "flights", "passport", "visa", "hotel", "airbnb",
                    "airport", "packing", "pack", "itinerary", "boarding"]),
        ("work", ["deck", "standup", "stand up", "review", "offsite", "client",
                  "invoice", "deadline", "interview", "resume", "onboarding"]),
        ("admin", ["taxes", "tax", "license", "licence", "renewal", "form",
                   "paperwork", "passport photo", "notary", "bank", "claim"]),
        ("garden", ["plants", "water the", "repot", "seeds", "yard", "lawn"]),
    ]

    /// Words that are never a category on their own — too general to name a
    /// list, or grammar rather than subject.
    private static let uncategorisable: Set<String> = [
        "thing", "things", "stuff", "something", "anything", "everything",
        "some", "with", "that", "this", "them", "they", "there", "here",
        "about", "from", "into", "then", "than", "when", "what", "just",
        "need", "want", "have", "get", "got", "make", "take", "keep", "look",
        "back", "over", "again", "more", "less", "before", "after",
    ]

    /// The category for something with a verb or a day on it.
    ///
    /// The given ones first, then a category this couple already grew, then a
    /// known domain, and only then something new. Notes is the last resort,
    /// reached by failing to find a subject at all.
    static func lifeCategory(
        _ lowered: String,
        context: Context
    ) -> LifeCategory {
        if careWords.contains(where: { lowered.contains($0) }) { return .care }
        if moneyWords.contains(where: { lowered.contains($0) }) { return .money }
        if homeWords.contains(where: { lowered.contains($0) }) { return .home }
        if eatWords.contains(where: { lowered.contains($0) }) { return .food }

        // Something they already have a place for, checked before Buys: "buy"
        // and "order" are generic verbs attached to half of what anybody says,
        // and a couple who grew Pets means Pets when they say "order more pets
        // food" — not a shopping list.
        if let existing = context.lifeCategories.first(where: {
            !$0.isBuiltIn && lowered.contains($0.rawValue)
        }) {
            return existing
        }

        // Checked here as well as in `route`, because "buy" and "order" are
        // task verbs — without this, "buy batteries" reaches invention and
        // grows a category called Batteries.
        if buyWords.contains(where: { lowered.contains($0) }) { return .buys }

        if let domain = namedDomains.first(where: { domain in
            domain.words.contains { lowered.contains($0) }
        }), let category = LifeCategory(named: domain.category) {
            return category
        }

        return invented(from: lowered) ?? .notes
    }

    /// A category named from what was actually said.
    ///
    /// Deliberately conservative. It takes the subject of the sentence — the
    /// first substantial word that is not the verb, the day, or a filler — and
    /// only when that word is long enough to read as a heading. A wrong
    /// category is one tap to fix; a category called "The" is a mess the
    /// couple has to live in.
    static func invented(from lowered: String) -> LifeCategory? {
        let words = lowered
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)

        for word in words {
            guard word.count >= 4,
                  !uncategorisable.contains(word),
                  !taskVerbs.contains(where: { word.hasPrefix($0) }),
                  !dayWords.contains(word),
                  !aspirationWords.contains(word)
            else { continue }
            return LifeCategory(named: word)
        }
        return nil
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
        for category: LifeCategory,
        input lowered: String,
        context: Context
    ) -> String {
        // Naming what it is *not* matters more than naming what it is. The
        // couple gave nothing here; the app grew a heading on its own, and it
        // should say so plainly enough to be argued with.
        guard context.lifeCategories.contains(category) else {
            let existing = context.lifeCategories
                .prefix(3)
                .map(\.word)
                .joined(separator: ", ")
            return "This didn't sit with \(existing), so I started "
                + "\(category.word). If that's wrong, move it and I'll drop it."
        }

        let hasDay = dayWords.contains { lowered.contains($0) }

        switch category {
        case .watchlist:
            let unwatched = openItems(in: .watchlist, context: context).count + 1
            var sentence = "A film, so it joined the list you share. "
                + "\(unwatched.spelled.capitalized) unwatched now"
            if let stretch = upcomingStretch(context) {
                sentence += " — enough for \(stretch)."
            } else {
                sentence += "."
            }
            return sentence

        case .food where !hasDay:
            return "No day on it, so I read it as an appetite rather than an "
                + "errand. It'll come back when you're deciding "
                + "\(nextDecisionDay(context))."

        case .trips:
            // Named, when there is a name to use. The reasoning has to
            // reference this couple's actual state — a sentence about "a
            // place" could have been written about anybody.
            if let horizon = matchesHorizon(lowered, context: context) {
                let title = horizon.title.trimmingCharacters(
                    in: CharacterSet(charactersIn: ",. ")
                )
                return "You're already headed for \(title), so this sits with "
                    + "the rest of it — in Trips, where you can see it, not "
                    + "filed away somewhere you'd have to remember to look."
            }

            var sentence = "A place, not a plan. It sits in Trips with no date "
                + "on it"
            let mentioned = openItems(in: .trips, context: context).count + 1
            if mentioned >= 3 {
                sentence += " — that's \(mentioned.spelled) now, so at some "
                    + "point I'll ask whether one of them is real."
            } else {
                sentence += ", and if it starts looking real I'll ask."
            }
            return sentence

        case .buys:
            return "Something to get rather than something to do. It waits "
                + "with the rest of what you need ordered."

        case .talk:
            let open = openItems(in: .talk, context: context).count + 1
            var sentence = "You asked something rather than named a task, so "
                + "there's no date on it and nothing will chase you about it. "
                + "I'll keep it where you can both see it"
            if open >= 3 {
                sentence += " — that's \(open.spelled) open now, so one of "
                    + "them is probably worth an evening."
            } else {
                sentence += "."
            }
            return sentence

        case .notes:
            return "I couldn't tie this to a week or a list, so I kept it "
                + "rather than guessing. It'll surface when something makes "
                + "it relevant."

        case .care:
            if let slipping = context.rhythms.first(where: {
                $0.health == .slipping
            }) {
                let weeks = weeksSince(slipping.lastOccurred, context: context)
                return "Something for one of them, so it went to Care. I tied "
                    + "it to \(slipping.title.lowercased()) — the rhythm that "
                    + "has been slipping \(weeks.spelled) weeks."
            }
            return "Something for one of them, so it went to Care, where the "
                + "rest of what you two look after already sits."

        default:
            let opening = hasDay
                ? "A task with a day attached."
                : "A thing to do, with no day on it yet."
            return opening + " I put it where the rest of your "
                + "\(category.rawValue) already sits."
        }
    }

    private static func openItems(
        in category: LifeCategory,
        context: Context
    ) -> [LifeItem] {
        context.lifeItems.filter { $0.category == category && !$0.isDone }
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

    private static func learnedCategory(
        for lowered: String,
        context: Context
    ) -> (category: LifeCategory, reasoning: String)? {
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
        category: LifeCategory,
        reasoning: String,
        context: Context
    ) -> FieldReceipt {
        // Routing reads the sentence; filing reads the thought. Tidying runs
        // after the route is decided, so removing "reminder to" can never
        // change where something goes.
        let phrasing = FieldPhrasing.tidy(
            input,
            now: context.now,
            calendar: context.calendar
        )

        return FieldReceipt(
            id: UUID().uuidString,
            input: input,
            title: phrasing.title,
            dueOn: category.carriesDates ? phrasing.dueOn : nil,
            category: category,
            reasoning: reasoning,
            // The receipt's 2pt left border takes the speaker's colour.
            // Nothing is filed jointly any more, because nothing crosses into
            // a shared space that has to be reached by both of you.
            accent: context.speaker,
            acknowledged: false,
            wasCorrected: false
        )
    }

    /// One tap to a corrected category. The correction becomes training signal
    /// that surfaces later in the correction receipt (6a).
    static func correct(
        _ receipt: FieldReceipt,
        to category: LifeCategory,
        context: Context
    ) -> (receipt: FieldReceipt, correction: FieldCorrection) {
        var corrected = receipt
        corrected.category = category
        corrected.wasCorrected = true
        // Moving into a category that keeps dates recovers the day the
        // phrasing named; moving into one that does not drops it, rather than
        // putting a due date on a film.
        corrected.dueOn = category.carriesDates
            ? FieldPhrasing.tidy(
                receipt.input,
                now: context.now,
                calendar: context.calendar
            ).dueOn
            : nil
        corrected.reasoning = "Moved. I'll file this shape of thing here from "
            + "now on, and I'll tell you what it changed."

        let correction = FieldCorrection(
            id: UUID().uuidString,
            input: receipt.input,
            original: receipt.category,
            corrected: category,
            correctedAt: context.now
        )
        return (corrected, correction)
    }
}

// MARK: - What to suggest under the field
//
// The four phrases under the capture field started life as a demo affordance —
// the same four strings whatever was going on, for whoever was holding the
// phone. Four constants under an input that claims to know this couple is the
// one place in the app that most obviously does not.
//
// So they are read from state: a stretch someone is about to leave for, a
// rhythm that has slipped, an occasion with nothing bought for it, a horizon
// with no ideas attached. The canned four survive only as the honest fallback
// — a couple on their first day has nothing to intuit from, and inventing a
// suggestion for them would be exactly the failure this replaces.

enum FieldCaptureSuggestions {
    struct Context {
        var now: Date
        var lifeItems: [LifeItem]
        var clusters: [FieldCluster]
        var horizons: [FieldHorizon]
        var rhythms: [FieldRhythm]
        var partners: [FieldPartner]
        var calendar: Calendar = .gregorianUS

        func open(_ category: LifeCategory) -> [LifeItem] {
            lifeItems.filter { $0.category == category && !$0.isDone }
        }

        /// Whether this couple has given the app anything to be specific
        /// about. Absence is never itself a signal.
        var hasSomethingToReadFrom: Bool {
            !lifeItems.isEmpty || !clusters.isEmpty || !horizons.isEmpty
                || !rhythms.isEmpty || !partners.isEmpty
        }
    }

    /// Four fits two lines on the narrowest phone. More is a menu, and a menu
    /// under a text field tells people to pick rather than to speak.
    static let limit = 4

    static func suggest(_ context: Context) -> [String] {
        // Nothing written down, nothing to read. Checked once, here, rather
        // than left to each rule: two of them independently treated an empty
        // list as evidence of a thin list, which is how a couple on their
        // first day got told what to have for dinner on Friday by an app that
        // had never met them.
        guard context.hasSomethingToReadFrom else {
            return FieldSampleData.canonicalInputs
        }

        var phrases: [String] = []

        for candidate in [
            packing(context),
            slippingRhythm(context),
            occasion(context),
            decisionNight(context),
            horizonIdea(context),
            emptyWatchlist(context),
        ] {
            guard let candidate,
                  !phrases.contains(where: {
                      $0.caseInsensitiveCompare(candidate) == .orderedSame
                  })
            else { continue }
            phrases.append(candidate)
            if phrases.count == limit { break }
        }

        // Nothing to read yet. Say the four that teach the field what it is
        // for, rather than half a screen of guesses about strangers.
        return phrases.isEmpty ? FieldSampleData.canonicalInputs : phrases
    }

    /// Someone is leaving within the fortnight and nothing about it is filed.
    private static func packing(_ context: Context) -> String? {
        let soon = context.partners
            .flatMap(\.awayWindows)
            .filter {
                $0.start > context.now
                    && days(from: context.now, to: $0.start, context) <= 14
            }
            .sorted { $0.start < $1.start }

        guard let next = soon.first, let place = next.place else { return nil }
        let phrase = "pack for \(place.lowercased())"
        guard !mentioned(place, in: context) else { return nil }
        return phrase
    }

    /// A rhythm that has slipped is the app's own evidence that something is
    /// being forgotten. Offering it back is the least it can do with that.
    private static func slippingRhythm(_ context: Context) -> String? {
        guard let slipping = context.rhythms.first(where: {
            $0.health == .slipping
        }) else { return nil }

        let subject = slipping.title.lowercased()
        guard !mentioned(subject, in: context) else { return nil }
        return "\(subject) this week"
    }

    /// An occasion inside three weeks with nothing bought for it.
    private static func occasion(_ context: Context) -> String? {
        let upcoming = context.clusters
            .compactMap { cluster -> (FieldCluster, Int)? in
                guard let date = cluster.anchorDate else { return nil }
                let delta = days(from: context.now, to: date, context)
                guard delta >= 0, delta <= 21 else { return nil }
                return (cluster, delta)
            }
            .sorted { $0.1 < $1.1 }

        guard let (cluster, _) = upcoming.first else { return nil }

        let alreadyHandled = context.lifeItems.contains {
            $0.clusterID == cluster.id
                && !$0.isDone
                && $0.title.localizedCaseInsensitiveContains("gift")
        }
        guard !alreadyHandled else { return nil }
        return "gift for \(cluster.title.lowercased())"
    }

    /// Friday is the couple's decision night. Before it, with the eating list
    /// thin, the useful thing to say is what they feel like.
    private static func decisionNight(_ context: Context) -> String? {
        let weekday = context.calendar.component(.weekday, from: context.now)
        // Wednesday through Friday — near enough that dinner is a live
        // question, not a hypothetical.
        guard (4...6).contains(weekday) else { return nil }

        guard context.open(.food).count < 3 else { return nil }
        return "dinner friday"
    }

    /// A horizon nobody has put an idea against yet.
    private static func horizonIdea(_ context: Context) -> String? {
        let horizon = context.horizons.first(where: \.isPrimary)
            ?? context.horizons.first
        guard let horizon, horizon.linkedLifeItemIDs.count < 2 else {
            return nil
        }

        let subject = horizon.title
            .trimmingCharacters(in: CharacterSet(charactersIn: ",. "))
            .lowercased()
        guard !subject.isEmpty else { return nil }
        return "\(subject) ideas"
    }

    private static func emptyWatchlist(_ context: Context) -> String? {
        guard context.open(.watchlist).isEmpty else { return nil }
        return "something to watch"
    }

    // MARK: Reading the state

    /// Whether this couple has already said something about a subject. A
    /// suggestion for a thing already filed is the app not having read its own
    /// screen.
    private static func mentioned(_ subject: String, in context: Context) -> Bool {
        context.lifeItems.contains {
            !$0.isDone && $0.title.localizedCaseInsensitiveContains(subject)
        }
    }

    private static func days(
        from: Date,
        to: Date,
        _ context: Context
    ) -> Int {
        context.calendar.dateComponents(
            [.day],
            from: context.calendar.startOfDay(for: from),
            to: context.calendar.startOfDay(for: to)
        ).day ?? 0
    }
}

// MARK: - This week
//
// The handful of things with a date on them, at the top of Life.
//
// Today and this section read the same state at different resolutions, and
// that is the whole distinction between the two screens: **Today shows the one
// thing**, full width, because a person who opens the app should be told what
// to do and not handed a list. **Life shows the set**, because a person who
// has gone looking wants to see the shape of the week.
//
// It is grouped by occasion rather than by date or category, which is the rule
// the Reminders takeover was built on before this replaced it: "categories are
// a filing system; occasions are how people actually think." An occasion names
// itself and the thing it is waiting on — "Dylan's wedding — Rhinebeck, drive
// or train" — and never invents an errand nobody wrote down.

enum FieldTimely {
    struct Nudge: Identifiable, Hashable, Sendable {
        let id: String
        /// "Ryan's dad in town". The occasion, or the item itself when there
        /// is no occasion to name.
        var occasion: String
        /// What it is waiting on. Nil when the occasion is the whole story.
        var ask: String?
        var tint: FieldOwner
        var dueOn: Date?
    }

    /// Four. Above that it stops being the shape of a week and becomes a list,
    /// and Life already has somewhere for lists.
    static let limit = 4

    /// How far ahead "this week" reaches. Ten days rather than seven: a
    /// Saturday wedding stops being news on the Sunday before it, and that is
    /// exactly when there is still time to do something about it.
    static let horizonInDays = 10

    static func nudges(_ context: FieldTodaySelector.Context) -> [Nudge] {
        var nudges = occasions(context)

        // Dated things nobody has attached to an occasion. They are timely by
        // themselves, so they are named by themselves.
        let claimed = Set(
            context.clusters.flatMap { $0.items(from: context.lifeItems) }
                .map(\.id)
        )
        for item in soon(context) where !claimed.contains(item.id) {
            nudges.append(
                Nudge(
                    id: item.id,
                    occasion: item.title,
                    ask: nil,
                    tint: item.owner,
                    dueOn: item.dueOn
                )
            )
        }

        return Array(
            nudges
                .sorted { left, right in
                    switch (left.dueOn, right.dueOn) {
                    case let (l?, r?): return l < r
                    case (nil, _): return false
                    case (_, nil): return true
                    }
                }
                .prefix(limit)
        )
    }

    private static func occasions(
        _ context: FieldTodaySelector.Context
    ) -> [Nudge] {
        context.clusters.compactMap { cluster -> Nudge? in
            let open = cluster.items(from: context.lifeItems)
                .filter { !$0.isDone }
                .sorted {
                    $0.pressure(now: context.now, calendar: context.calendar)
                        > $1.pressure(now: context.now, calendar: context.calendar)
                }

            // An occasion with nothing open is an occasion that has been
            // handled. Saying its name anyway would be the app taking credit
            // for a quiet week.
            guard let leading = open.first else { return nil }

            let anchor = cluster.anchorDate ?? leading.dueOn
            guard let anchor, within(anchor, of: context) else { return nil }

            return Nudge(
                id: cluster.id,
                occasion: cluster.title,
                ask: leading.title,
                tint: cluster.tint,
                dueOn: anchor
            )
        }
    }

    private static func soon(
        _ context: FieldTodaySelector.Context
    ) -> [LifeItem] {
        context.lifeItems.filter { item in
            guard !item.isDone, item.clusterID == nil else { return false }
            guard let dueOn = item.dueOn else { return false }
            return within(dueOn, of: context)
        }
    }

    /// Inside the window, and not already behind us by more than a day.
    /// Something a fortnight overdue is upkeep, not news — it belongs in its
    /// category, where the room can say so quietly.
    private static func within(
        _ date: Date,
        of context: FieldTodaySelector.Context
    ) -> Bool {
        let days = context.calendar.dateComponents(
            [.day],
            from: context.calendar.startOfDay(for: context.now),
            to: context.calendar.startOfDay(for: date)
        ).day ?? 0
        return days >= -1 && days <= horizonInDays
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

// MARK: - How something becomes a horizon
//
// Us is not a place you can file to. There is no button, no destination, and
// no branch of the classifier that reaches it — a trip you mention goes into
// Trips with everything else you have mentioned.
//
// It becomes a horizon exactly one way: the app notices you have said the same
// thing more than once, asks a single question about it, and you answer yes.
// Then a horizon appears in Us, linked to the Life items it came from — and
// **those items stay in Life.** A horizon is a reading of things already
// written down, not a copy of them somewhere else. If it moved them, the list
// where you actually look for it would quietly empty itself out.
//
// Saying "not this year" is a real answer and gets a real consequence: the
// subject is held (6d), so the app stops asking. Timing is most of tact.

enum FieldPromotion {
    struct Proposal: Identifiable, Hashable, Sendable {
        var id: String
        /// "Japan" — the subject both mentions share.
        var subject: String
        var category: LifeCategory
        /// The Life items this came from. They do not move.
        var itemIDs: [String]
        var question: FieldQuestion

        var affirmative: FieldChoice? { question.choices.first }
    }

    /// Twice. Once is a passing remark, and asking about a passing remark is
    /// the app manufacturing a conversation.
    static let minimumMentions = 2

    static func proposal(_ context: FieldTodaySelector.Context) -> Proposal? {
        // Only from the categories that hold no dates. A thing with a date is
        // already a plan; asking whether you plan to do it would be absurd.
        let candidates = context.lifeItems.filter {
            !$0.isDone && !$0.category.carriesDates
        }

        var bySubject: [String: [LifeItem]] = [:]
        for item in candidates {
            guard let subject = subject(of: item) else { continue }
            bySubject[subject, default: []].append(item)
        }

        let ranked = bySubject
            .filter { $0.value.count >= minimumMentions }
            .sorted { left, right in
                left.value.count == right.value.count
                    ? left.key < right.key
                    : left.value.count > right.value.count
            }

        for (subject, items) in ranked {
            // Already asked and answered, or held. The app does not ask twice.
            guard !isHeld(subject, in: context),
                  !hasHorizon(subject, in: context)
            else { continue }

            return Proposal(
                id: "promote:\(subject)",
                subject: subject.capitalized,
                category: items[0].category,
                itemIDs: items.map(\.id),
                question: question(
                    subject: subject.capitalized,
                    mentions: items.count,
                    context: context
                )
            )
        }
        return nil
    }

    /// The one thing worth asking, asked once.
    ///
    /// The stakes line names what is actually at issue — that a thing said
    /// twice is either real or it isn't, and the app cannot tell from the
    /// outside. Two choices, never three: this is a question about intent, and
    /// intent does not have a middle.
    private static func question(
        subject: String,
        mentions: Int,
        context: FieldTodaySelector.Context
    ) -> FieldQuestion {
        let year = context.calendar.component(.year, from: context.now)

        return FieldQuestion(
            id: "promote:\(subject.lowercased())",
            prompt: "Is \(subject) something you're actually doing?",
            stakes: "If it is, I'll start keeping track of what moves it. If "
                + "it isn't, it stays on the list and I stop asking.",
            reasoning: "You've both mentioned \(subject) \(mentions.spelled) "
                + "times and neither of you has put a date on it. That's the "
                + "only reason I'm asking.",
            choices: [
                FieldChoice(
                    id: "promote:\(subject.lowercased()):yes",
                    title: "Yes, by \(year + 1)",
                    tint: .a
                ),
                FieldChoice(
                    id: "promote:\(subject.lowercased()):no",
                    title: "Not this year",
                    tint: .b
                ),
            ]
        )
    }

    /// The first substantial word of a title, which for a place or a title is
    /// the thing itself: "Japan in the fall" and "Japan flights" share Japan.
    static func subject(of item: LifeItem) -> String? {
        let words = item.title.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)

        return words.first { $0.count >= 4 && !stopWords.contains($0) }
    }

    private static let stopWords: Set<String> = [
        "the", "some", "that", "this", "with", "from", "about", "book",
        "maybe", "something", "another", "trip", "visit", "weekend", "watch",
    ]

    private static func isHeld(
        _ subject: String,
        in context: FieldTodaySelector.Context
    ) -> Bool {
        context.heldTopics.contains {
            $0.isHeld && $0.title.localizedCaseInsensitiveContains(subject)
        }
    }

    private static func hasHorizon(
        _ subject: String,
        in context: FieldTodaySelector.Context
    ) -> Bool {
        context.horizons.contains {
            $0.title.localizedCaseInsensitiveContains(subject)
        }
    }
}

// MARK: - Headings inside a room
//
// What a category does when it gets big.
//
// It does not split. A dense Trips becoming Trips and International Trips
// would hand the couple a hierarchy to maintain, and hierarchy is what makes
// filing systems confusing — the exact problem this whole change exists to
// remove. Instead the *room* groups itself under headings it derives, which
// re-form as the contents change and are never stored anywhere.
//
// It only groups along a dimension it can actually source. There is no generic
// fallback: a room with nothing real to divide it by renders flat, because
// headings invented to justify the feature are worse than no headings at all.
// It never groups by owner — a heading reading "Yours" over a list of chores
// is a comparison between two people wearing an organisational hat.

enum FieldGrouping {
    /// A heading needs to earn its line. Two items under it is a heading with
    /// nothing to organise.
    static let minimumPerGroup = 2

    static func groups(
        _ items: [LifeItem],
        context: FieldTodaySelector.Context
    ) -> [FieldCategoryDigest.Group] {
        guard items.count >= minimumPerGroup * 2 else { return [] }

        // A category where most things carry a date is organised by when.
        // Nothing else competes with that — "next week" is the reason a person
        // opened the room.
        let dated = items.filter { $0.dueOn != nil }
        if dated.count * 2 > items.count {
            return byTime(items, context: context)
        }

        for dimension in [byDistance, byForm] {
            let grouped = dimension(items)
            if grouped.count >= 2 { return grouped }
        }
        return []
    }

    // MARK: When

    private static func byTime(
        _ items: [LifeItem],
        context: FieldTodaySelector.Context
    ) -> [FieldCategoryDigest.Group] {
        var buckets: [(heading: String, items: [LifeItem])] = [
            ("This week", []), ("This month", []), ("Later", []), ("No date", []),
        ]

        for item in items {
            guard let dueOn = item.dueOn else {
                buckets[3].items.append(item)
                continue
            }
            let days = context.calendar.dateComponents(
                [.day],
                from: context.calendar.startOfDay(for: context.now),
                to: context.calendar.startOfDay(for: dueOn)
            ).day ?? 0

            switch days {
            case ..<8: buckets[0].items.append(item)
            case 8..<32: buckets[1].items.append(item)
            default: buckets[2].items.append(item)
            }
        }

        return assemble(buckets)
    }

    // MARK: Where

    private static let abroad = [
        "japan", "tokyo", "kyoto", "italy", "rome", "florence", "paris",
        "france", "lisbon", "portugal", "spain", "barcelona", "madrid",
        "mexico", "iceland", "greece", "london", "thailand", "vietnam",
        "korea", "seoul", "berlin", "amsterdam", "morocco", "peru", "chile",
    ]
    private static let athome = [
        "upstate", "hamptons", "brooklyn", "queens", "vermont", "maine",
        "catskills", "hudson", "chicago", "california", "texas", "florida",
        "montauk", "cape cod", "big sur", "road trip", "rhinebeck",
    ]

    private static func byDistance(
        _ items: [LifeItem]
    ) -> [FieldCategoryDigest.Group] {
        var buckets: [(heading: String, items: [LifeItem])] = [
            ("Abroad", []), ("Closer to home", []), ("Everything else", []),
        ]

        for item in items {
            let title = item.title.lowercased()
            if abroad.contains(where: { title.contains($0) }) {
                buckets[0].items.append(item)
            } else if athome.contains(where: { title.contains($0) }) {
                buckets[1].items.append(item)
            } else {
                buckets[2].items.append(item)
            }
        }

        // Only a real split counts. Everything landing in "Everything else" is
        // the app failing to recognise anything, dressed up as organisation.
        guard !buckets[0].items.isEmpty, !buckets[1].items.isEmpty else {
            return []
        }
        return assemble(buckets)
    }

    // MARK: What shape

    private static let episodic = [
        "season", " s1", " s2", " s3", " s4", " s5", "series", "show",
        "episode", "documentary", "docuseries",
    ]

    private static func byForm(
        _ items: [LifeItem]
    ) -> [FieldCategoryDigest.Group] {
        var buckets: [(heading: String, items: [LifeItem])] = [
            ("An evening", []), ("Something longer", []),
        ]

        for item in items {
            let title = item.title.lowercased()
            if episodic.contains(where: { title.contains($0) }) {
                buckets[1].items.append(item)
            } else {
                buckets[0].items.append(item)
            }
        }

        guard buckets.allSatisfy({ $0.items.count >= minimumPerGroup }) else {
            return []
        }
        return assemble(buckets)
    }

    private static func assemble(
        _ buckets: [(heading: String, items: [LifeItem])]
    ) -> [FieldCategoryDigest.Group] {
        let filled = buckets.filter { !$0.items.isEmpty }
        // One heading over everything is not a grouping, it is a title.
        guard filled.count >= 2 else { return [] }
        return filled.map {
            FieldCategoryDigest.Group(heading: $0.heading, items: $0.items)
        }
    }
}

// MARK: - A category, read closely
//
// What a Life category room shows. Life itself stays calm and enumerates
// nothing — "an early version put the full Reminders list inline and it
// swamped the page" — so the detail lives one tap behind each category word.
//
// The room splits into two bands rather than explaining every row, because a
// reason under all of them would recreate exactly the wall the zone avoids.

enum FieldCategoryDigest {
    /// An item that earned an explanation, and the explanation.
    struct Row: Identifiable, Hashable, Sendable {
        var item: LifeItem
        /// Nil when nothing about this item is worth saying out loud.
        var reason: String?

        var id: String { item.id }
    }

    /// A heading inside a room, and the things under it.
    struct Group: Identifiable, Hashable, Sendable {
        var heading: String
        var items: [LifeItem]

        var id: String { heading }
    }

    struct Result: Hashable, Sendable {
        /// Ranked, explained, and never more than `pressingLimit`.
        var pressing: [Row]
        /// Everything else, in the same ranked order. Titles only.
        var quiet: [LifeItem]
        /// The quiet band, divided under derived headings. Empty below the
        /// density threshold, or whenever no honest dimension exists — in
        /// which case the room renders `quiet` flat, exactly as before.
        var groups: [Group] = []

        var isEmpty: Bool { pressing.isEmpty && quiet.isEmpty }
        var total: Int { pressing.count + quiet.count }
    }

    /// Above this many open items, a flat list stops being readable and the
    /// room starts grouping itself.
    ///
    /// Grouping rather than splitting, deliberately. Splitting Trips into
    /// Trips and International Trips would introduce a hierarchy — folders
    /// inside folders — which is the thing that makes filing systems confusing
    /// in the first place. A heading inside one room organises the same
    /// content with no new category, no navigation depth, and nothing for
    /// anybody to maintain. The headings re-form as the contents change, and
    /// nothing about them is stored.
    static let densityThreshold = 8

    /// Three is a judgement, not a constraint of the data: a category having a
    /// terrible week should still open to something a person can read in one
    /// breath. The rest drop to quiet rather than disappearing.
    static let pressingLimit = 3

    static func digest(
        for category: LifeCategory,
        context: FieldTodaySelector.Context
    ) -> Result {
        // Ranked by the same weighting Today uses, so the room agrees with
        // the rest of the app about what matters. Horizons are dropped —
        // they are not Life items and do not belong in a category.
        let ranked = FieldTodaySelector.rank(context).compactMap { candidate
            -> (LifeItem, FieldTodaySelector.Candidate)? in
            guard case .life(let item) = candidate.origin,
                  item.category == category
            else { return nil }
            return (item, candidate)
        }

        // `rank` drops anything held or suppressed by a standing rule, which
        // is correct for Today but would silently lose items here. A room is
        // where you go to see what is actually in a category.
        let rankedIDs = Set(ranked.map(\.0.id))
        let unranked = context.lifeItems.filter {
            $0.category == category && !$0.isDone && !rankedIDs.contains($0.id)
        }

        var pressing: [Row] = []
        var quiet: [LifeItem] = []
        // Only the top-ranked item of a cluster is the one others wait on.
        // Without this every member of the same occasion says "three things
        // wait on this", which is not false so much as useless — the same
        // sentence three times, explaining nothing about any of them.
        var claimedClusters: Set<String> = []

        for (item, candidate) in ranked {
            if pressing.count < pressingLimit,
               candidate.priority >= FieldTodaySelector.surfacingThreshold {
                let leadsCluster: Bool
                if let clusterID = item.clusterID {
                    leadsCluster = claimedClusters.insert(clusterID).inserted
                } else {
                    leadsCluster = false
                }

                pressing.append(
                    Row(
                        item: item,
                        reason: briefReason(
                            for: item,
                            candidate: candidate,
                            context: context,
                            leadsCluster: leadsCluster
                        )
                    )
                )
            } else {
                quiet.append(item)
            }
        }

        let rest = quiet + unranked
        return Result(
            pressing: pressing,
            quiet: rest,
            groups: pressing.count + rest.count > densityThreshold
                ? FieldGrouping.groups(rest, context: context)
                : []
        )
    }

    /// One short line, true when read beside four others.
    ///
    /// `FieldTodaySelector.reason(for:candidate:context:)` cannot be reused:
    /// its copy is written for the single thing surfaced today and says so —
    /// "nothing else today has a cut-off", "it is the only thing between now
    /// and then". Repeated down a list those become false. This states a fact
    /// about the item alone, or says nothing.
    /// - Parameter leadsCluster: whether this is the item its occasion is
    ///   actually waiting on. Only the lead may say so; the rest fall through
    ///   to their own dates.
    static func briefReason(
        for item: LifeItem,
        candidate: FieldTodaySelector.Candidate,
        context: FieldTodaySelector.Context,
        leadsCluster: Bool = false
    ) -> String? {
        let calendar = context.calendar

        // A cut-off inside the day is the one thing that cannot be recovered
        // tomorrow, so it always speaks first.
        if let closesAt = item.closesAt,
           calendar.isDate(closesAt, inSameDayAs: context.now) {
            return "Closes \(DateFormatter.fieldClock.string(from: closesAt))."
        }

        // Named without a pronoun — the app knows the name and has no business
        // guessing anything else.
        if candidate.reachability < 0.5,
           let away = context.partners.first(where: {
               $0.owner == item.owner && $0.isAway(on: context.now)
           }),
           let window = away.awayWindow(on: context.now) {
            let back = DateFormatter.fieldWeekday.string(from: window.end)
            return "\(away.name)'s — away until \(back)."
        }

        guard let dueOn = item.dueOn else {
            // Nothing of its own to report, so its relationship to the rest
            // of the occasion is the only thing left worth saying. Last,
            // deliberately: a date is concrete and specific to this item,
            // where "three things wait on this" is true of several at once
            // and reads as the same sentence repeated.
            if leadsCluster,
               candidate.unblockingValue > candidate.timePressure,
               let clusterID = item.clusterID,
               let cluster = context.clusters.first(where: {
                   $0.id == clusterID
               }) {
                let waiting = cluster.items(from: context.lifeItems).count - 1
                if waiting > 0 {
                    return "\(waiting.spelled.capitalized) "
                        + "\(waiting == 1 ? "thing waits" : "things wait") "
                        + "on this."
                }
            }
            return nil
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: context.now),
            to: calendar.startOfDay(for: dueOn)
        ).day ?? 0

        if days < 0 {
            // Overdue upkeep decays rather than escalating, so this states the
            // fact flatly and does not nag about it.
            //
            // Rounded, not truncated: the air filter is 59 days over and the
            // domain calls that "two months over" in its own copy. Calendar
            // month arithmetic would call it one, which is how a true fact
            // ends up sounding like a lie.
            let over = -days
            if over >= 28 {
                let months = max(1, Int((Double(over) / 30.44).rounded()))
                return "\(months.spelled.capitalized) "
                    + "\(months == 1 ? "month" : "months") over."
            }
            return "\(over.spelled.capitalized) "
                + "\(over == 1 ? "day" : "days") over."
        }

        if days == 0 { return "Today." }
        if days <= 7 {
            return "Lands \(DateFormatter.fieldWeekday.string(from: dueOn))."
        }
        return nil
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

        // Repeated moves *out of* a dated category mean the app was reading
        // appetite as obligation — treating "steak" as an errand.
        let datedToDateless = corrections.filter {
            $0.original.carriesDates && !$0.corrected.carriesDates
        }
        if datedToDateless.count >= 2 {
            changes.append(
                FieldBehaviourChange(
                    id: "not-a-task",
                    observation: "You told me “not a task” \(datedToDateless.count.spelled) times",
                    change: "Things you mention without a day stay undated now.",
                    outcome: "“Steak” is an appetite. “Groceries” is a task. "
                        + "I can tell them apart now.",
                    accent: .a
                )
            )
        }

        // Repeated moves into Trips mean the app was reading a plan as an
        // errand — the thing people are least willing to have wrong.
        let deletions = corrections.filter {
            $0.original != .trips && $0.corrected == .trips
        }
        if deletions.count >= 2 {
            changes.append(
                FieldBehaviourChange(
                    id: "stopped-inventing",
                    observation: "You moved \(deletions.count.spelled) things into Trips",
                    change: "A place with no date is a trip you mentioned, not "
                        + "an errand. I file it that way now.",
                    outcome: "And when one of them starts looking real, I ask "
                        + "rather than deciding.",
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
