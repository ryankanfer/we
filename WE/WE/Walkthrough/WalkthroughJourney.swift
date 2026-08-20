//
//  WalkthroughJourney.swift
//  WE
//
//  The three spaces in the walkthrough, and the state each one is shown with.
//
//  The point of this file is the thing `FieldStore` already names: the
//  walkthrough "shows the real rule rather than a picture of one". Nothing
//  here writes the app's answers down. Every journey seeds a context and then
//  asks the same functions Today asks — `FieldClassifier.classify`,
//  `FieldOccasion.proposal`, `FieldPromotion.proposal` — so the explanation
//  cannot drift from the behaviour. If a rule changes and the walkthrough
//  starts saying something false, the walkthrough breaks, which is the only
//  way an explanation stays honest over time.
//
//  Each seed is deliberately *narrow*. `FieldOccasion.proposal` returns the
//  first pairing it finds and `FieldPromotion.proposal` the highest-ranked
//  subject; seeding these journeys from the whole of `FieldSampleData` would
//  mean the walkthrough's subject depends on what else happens to be in the
//  couple's life that week. So each journey carries only what its rule needs
//  to fire, and the couple is the sample couple because the specificity is
//  what makes the intelligence legible.
//
//  Dates are relative to `now` rather than fixed the way `FieldSampleData`'s
//  are. An explanation that says "Saturday" has to mean the Saturday coming,
//  and `FieldOccasion.windowInDays` only pulls things in for three weeks — a
//  hardcoded 2025 date would put every occasion journey permanently outside
//  its own window.
//

import Foundation

enum WalkthroughJourney: String, CaseIterable, Identifiable, Sendable {
    /// The home: say one thing and see where it went.
    case today
    /// The details both people have mentioned.
    case life
    /// The possibilities that keep returning.
    case us

    var id: String { rawValue }

    /// The real surface label. Today names itself as home once because a new
    /// person cannot yet know that the centre of the navigation is the place
    /// they will return to.
    var headerLabel: String {
        switch self {
        case .today: "TODAY · HOME"
        case .life: "LIFE"
        case .us: "US"
        }
    }

    var progressIndex: Int {
        Self.ordered.firstIndex(of: self) ?? 0
    }

    var nextTitle: String {
        switch self {
        case .today: "Next: Life"
        case .life: "Next: Us"
        case .us: "Open WE"
        }
    }

    /// The teaching order starts where the app starts, then explains the
    /// spaces on either side. It is an orientation, not a replica of a swipe.
    static var ordered: [WalkthroughJourney] { allCases }

    var next: WalkthroughJourney? {
        let all = Self.ordered
        guard let index = all.firstIndex(of: self),
              index + 1 < all.count
        else { return nil }
        return all[index + 1]
    }
}

// MARK: - The couple, and the week

/// The state the journeys are told against.
///
/// Built per journey rather than shared, and built from `now` rather than from
/// a stored date. `FieldSampleData` is reused for who the couple *are* —
/// identity, colours, names — and for nothing else, because what they have
/// written down has to be controlled per journey for the rule to be the only
/// thing that fires.
enum WalkthroughSeed {
    static let identity = FieldSampleData.identity

    /// No away windows and no standing preferences. Presence and preference
    /// are real rules with their own reasoning lines, and either one firing
    /// inside a journey about filing would explain the wrong thing.
    static let partners: [FieldPartner] = [
        FieldPartner(
            id: "ryan",
            name: "Ryan",
            swatch: .clay,
            owner: .a,
            awayWindows: [],
            standingPreferences: []
        ),
        FieldPartner(
            id: "dylan",
            name: "Dylan",
            swatch: .slate,
            owner: .b,
            awayWindows: [],
            standingPreferences: []
        ),
    ]

    static let calendar: Calendar = .gregorianUS

    /// Midday, so a journey never straddles a day boundary while it is being
    /// read. Every date below is derived from this.
    static func anchor(_ now: Date) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? now
    }

    static func days(_ count: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: anchor(now)) ?? now
    }

    // MARK: Journey 1 — Greek food

    /// What Ryan types. Lowercase and unpunctuated on purpose: the receipt's
    /// `wasRephrased` line only says something when tidying actually happened,
    /// and this journey is partly about that.
    /// "Restaurant" and not "place". The word has to be one the classifier
    /// actually routes on — `eatWords` contains the first and nothing in the
    /// router contains the second, so "that greek place" files to Watchlist as
    /// a title-shaped phrase. Writing the sentence a person would plausibly
    /// type and then asserting the app agrees is the discipline here;
    /// `WalkthroughSeedTests` is what caught it.
    static let capture = "That Greek restaurant Dylan mentioned."

    /// The classifier's context. `lifeItems` is empty of food so the reasoning
    /// is about the category rather than about a near-duplicate, and the
    /// correction log is empty so the route shown is the rule and not
    /// something this couple has already taught it.
    static func classifierContext(now: Date) -> FieldClassifier.Context {
        FieldClassifier.Context(
            identity: identity,
            speaker: .a,
            now: anchor(now),
            lifeItems: [],
            horizons: [],
            rhythms: [],
            corrections: [],
            partners: partners
        )
    }

    // MARK: Journey 2 — Ryan's dad

    /// The dated thing, and the loose thing that turns out to be about it.
    ///
    /// Five days out: inside `FieldOccasion.windowInDays` with room to spare,
    /// and far enough from today that the anchor is not itself the most
    /// pressing thing on the screen.
    static func occasionItems(now: Date) -> [LifeItem] {
        [
            LifeItem(
                id: "wt.visit",
                title: "Ryan's dad is in town",
                category: .care,
                owner: .a,
                dueOn: days(5, from: now),
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            ),
            LifeItem(
                id: "wt.bottle",
                title: "A bottle for Ryan's dad",
                category: .buys,
                owner: .b,
                dueOn: nil,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            ),
        ]
    }

    /// Exactly one open occasion, and nothing else dated. Both readings in
    /// `FieldOccasion` are safe here, but the journey shows the named one —
    /// the sentence says "Ryan's dad" — because that is the reading that does
    /// not depend on there being only one visit.
    static func occasionContext(now: Date) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: anchor(now),
            identity: identity,
            partners: partners,
            lifeItems: occasionItems(now: now),
            clusters: [],
            horizons: [],
            heldTopics: [],
            standingRules: []
        )
    }

    // MARK: Journey 3 — Japan

    /// Twice, which is `FieldPromotion.minimumMentions`, and no more. A third
    /// mention would make the question look like a response to volume; the
    /// rule is that two is already enough.
    ///
    /// Both are in Trips, which is dateless — a promotion is only ever offered
    /// about something that is not already a plan.
    static func promotionItems(now: Date) -> [LifeItem] {
        [
            LifeItem(
                id: "wt.japan.1",
                title: "Japan in the spring",
                category: .trips,
                owner: .a,
                dueOn: nil,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            ),
            LifeItem(
                id: "wt.japan.2",
                title: "Japan rail pass — worth it?",
                category: .trips,
                owner: .b,
                dueOn: nil,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            ),
        ]
    }

    /// No horizons and no held topics: either would be the app having already
    /// asked, and `FieldPromotion` correctly declines to ask twice.
    static func promotionContext(now: Date) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: anchor(now),
            identity: identity,
            partners: partners,
            lifeItems: promotionItems(now: now),
            clusters: [],
            horizons: [],
            heldTopics: [],
            standingRules: []
        )
    }
}

// MARK: - What the engine actually returns

/// The real output, resolved once per journey.
///
/// `nil` is a real possibility and is handled rather than forced. A journey
/// whose rule declines to fire has nothing honest to show, and the surface
/// says so plainly instead of drawing an empty frame — see
/// `WalkthroughJourneyView`. That should not happen, and `WalkthroughTests`
/// asserts it does not; this is what the app does if it ever does.
enum WalkthroughOutcome {
    case movement(FieldReceipt)
    case context(FieldOccasion.Proposal)
    case memory(FieldPromotion.Proposal)

    static func resolve(
        _ journey: WalkthroughJourney,
        now: Date
    ) -> WalkthroughOutcome? {
        switch journey {
        case .today:
            .movement(
                FieldClassifier.classify(
                    WalkthroughSeed.capture,
                    context: WalkthroughSeed.classifierContext(now: now)
                )
            )
        case .life:
            FieldOccasion
                .proposal(WalkthroughSeed.occasionContext(now: now))
                .map(WalkthroughOutcome.context)
        case .us:
            FieldPromotion
                .proposal(WalkthroughSeed.promotionContext(now: now))
                .map(WalkthroughOutcome.memory)
        }
    }

}
