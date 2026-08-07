//
//  FieldItemSteps.swift
//  WE
//
//  What the app can honestly offer to do with one filed thing.
//
//  Everything here is a *destination*, not a fact. The app does not know what
//  a film is streaming on, what a filter costs, or whether a shop has one in.
//  It knows how to open the place where that is written down, and it names the
//  place on the button before anybody taps it.
//
//  Nothing in this file touches the network. A query is built, and it sits
//  there until somebody taps — at which point `openURL` hands it to Safari or
//  Maps and the app is no longer involved. There is no key, no cache, no
//  prefetch, and no row in a table anywhere recording what a couple looked up.
//
//  The affiliate rule is structural rather than stated: every URL is built
//  through `URLComponents` with exactly one query item, and there is a test
//  that counts them. A tracking parameter cannot be added here without turning
//  that test red.
//

import Foundation

// MARK: - Where a search goes

/// The two destinations that are not a shop: Apple's map, and a plain web
/// search.
enum FieldSearchLink {
    /// Apple's own search, with the words that were already said.
    static func maps(_ query: String) -> URL? {
        url(base: "http://maps.apple.com/", name: "q", value: query)
    }

    /// A search engine that does not build a profile out of what a couple is
    /// looking for. The app is about to hand over a phrase somebody wrote in a
    /// private list; the least it can do is hand it somewhere that forgets.
    static func web(_ query: String) -> URL? {
        url(base: "https://duckduckgo.com/", name: "q", value: query)
    }

    /// One query item, always. The single choke point every outbound URL in
    /// this file passes through.
    static func url(base: String, name: String, value: String) -> URL? {
        guard var components = URLComponents(string: base),
              !value.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        components.queryItems = [URLQueryItem(name: name, value: value)]
        return components.url
    }
}

// MARK: - Shops

/// A shop the app knows how to search, and nothing else about it.
///
/// No prices, no stock, no ratings, no "recommended" — the app has no source
/// for any of that and says so in the block's own copy. What it has is a
/// search URL with no referral code in it, which is the whole point: WE takes
/// no cut from any of these, and the couple can see that it doesn't because
/// the link has one parameter and it's their own words.
enum FieldRetailer: String, CaseIterable, Hashable, Sendable, Identifiable {
    case amazon
    case bestBuy
    case homeDepot
    case target
    case walmart

    var id: String { rawValue }

    /// As the shop writes it. This is what the row says, so it has to be the
    /// name somebody would recognise on a receipt.
    var name: String {
        switch self {
        case .amazon: "Amazon"
        case .bestBuy: "Best Buy"
        case .homeDepot: "The Home Depot"
        case .target: "Target"
        case .walmart: "Walmart"
        }
    }

    private var base: String {
        switch self {
        case .amazon: "https://www.amazon.com/s"
        case .bestBuy: "https://www.bestbuy.com/site/searchpage.jsp"
        case .homeDepot: "https://www.homedepot.com/s"
        case .target: "https://www.target.com/s"
        case .walmart: "https://www.walmart.com/search"
        }
    }

    private var searchParameter: String {
        switch self {
        case .amazon: "k"
        case .bestBuy: "st"
        case .homeDepot: "q"
        case .target: "searchTerm"
        case .walmart: "q"
        }
    }

    func url(searching query: String) -> URL? {
        FieldSearchLink.url(base: base, name: searchParameter, value: query)
    }

    /// The couple's own shops first, then alphabetically. Never randomised,
    /// never weighted, never sold.
    ///
    /// `preferred` is empty everywhere today — a stored preference list is a
    /// migration, a mutation, and three backends, and nobody has asked for one
    /// yet. It is a parameter rather than a future rewrite so that when
    /// somebody does ask, this is the only line that has to know.
    static func ordered(preferred: [FieldRetailer] = []) -> [FieldRetailer] {
        let seen = Set(preferred)
        let rest = allCases
            .filter { !seen.contains($0) }
            .sorted { $0.name < $1.name }
        return preferred + rest
    }
}

// MARK: - What is on offer

/// One thing the block can put on screen.
///
/// A value rather than a view, so every rule below is testable without
/// rendering anything, and so the destination can be asserted rather than
/// eyeballed.
enum FieldItemAction: Hashable, Sendable, Identifiable {
    /// A plain web search. Today this is the whole of "where to watch" — the
    /// app has no streaming provider and does not pretend to.
    case webSearch(label: String, query: String)
    /// Opens the shop sheet. The choice of shop is the actual question, so it
    /// is asked rather than answered.
    case retailerSearch(label: String, query: String)
    case maps(label: String, query: String)
    /// The on-device model, and only for a task somebody could actually do in
    /// the time named.
    case plan(minutes: Int)
    /// Apple's own new-event sheet, prefilled. The app writes to nobody's
    /// calendar.
    case calendarDraft
    /// Not a button. The one thing the app would need in order to search
    /// usefully, said out loud instead of guessed at.
    case askFor(String)

    var id: String { label }

    /// Upper case in the source, like every other button in FIELD.
    var label: String {
        switch self {
        case .webSearch(let label, _): label
        case .retailerSearch(let label, _): label
        case .maps(let label, _): label
        case .plan(let minutes): "MAKE A \(minutes)-MINUTE PLAN"
        case .calendarDraft: "ADD TO CALENDAR"
        case .askFor(let what): "What \(what)?"
        }
    }

    /// Where the tap actually goes, named before it is taken. Nothing here is
    /// a surprise once it opens.
    var destination: String? {
        switch self {
        case .webSearch: "Opens a web search"
        case .retailerSearch: "Opens a shop's own search"
        case .maps: "Opens Maps"
        case .plan: "Stays on this phone"
        case .calendarDraft: "Opens your calendar"
        case .askFor: nil
        }
    }

    var isTappable: Bool {
        if case .askFor = self { return false }
        return true
    }

    /// Stable across wording changes, so a UI test asserting a plain item
    /// offers nothing does not start passing because a label was reworded.
    var identifier: String {
        switch self {
        case .webSearch: "field.item.help.web"
        case .retailerSearch: "field.item.help.shop"
        case .maps: "field.item.help.maps"
        case .plan: "field.item.help.plan"
        case .calendarDraft: "field.item.help.calendar"
        case .askFor: "field.item.help.ask"
        }
    }
}

// MARK: - The rules

enum FieldItemSteps {
    /// At most two things to tap. A third is a menu, and a menu is the app
    /// having opinions about an item somebody has already filed.
    static let maximumTappable = 2

    /// What to offer for one item, or nothing at all.
    ///
    /// Pure, and deliberately so: no store, no clock, no network, no model —
    /// `isModelAvailable` is injected rather than read, so every rule below can
    /// be asserted on a device that has no model and on one that does.
    ///
    /// **Nothing is the common answer.** Most items in a couple's Life are a
    /// sentence about a thing that needs doing, and the honest response to
    /// "call your sister back" is an empty array.
    static func actions(
        for item: LifeItem,
        isModelAvailable: Bool
    ) -> [FieldItemAction] {
        // A calendar item is somebody else's record. The sheet already shows
        // it read-only, and this must not be the one control that forgets.
        guard !item.id.hasPrefix("cal:") else { return [] }
        guard !item.isDone else { return [] }

        // Where FieldOutreach already has somewhere to go, it goes there
        // alone. Two systems offering to handle the same vet appointment is
        // worse than either of them doing it.
        guard leavesItToUs(FieldTodaySelector.primaryAct(for: item)) else {
            return []
        }

        let lowered = item.title.lowercased()
        let query = FieldLookupQuery.normalise(item.title)

        if item.category == .watchlist {
            return [.webSearch(
                label: "WHERE TO WATCH",
                query: "\(query) where to watch"
            )]
        }

        if item.category == .buys
            || FieldClassifier.buyWords.contains(where: { lowered.contains($0) })
            || (item.category == .home
                && FieldClassifier.homeWords.contains(where: { lowered.contains($0) })) {
            return shopping(for: item, query: query)
        }

        if namesAPlace(lowered) {
            return [.maps(label: "OPEN IN MAPS", query: query)]
        }

        if isModelAvailable,
           item.category == .home || item.category == .care,
           FieldClassifier.taskVerbs.contains(where: { lowered.contains($0) }) {
            return [.plan(minutes: 15)]
        }

        // A hard cut-off, and only that. `dueOn` was the obvious rule and it
        // is the wrong one: almost everything in a couple's Life carries a
        // day, so offering the calendar on a date alone would put this block
        // under nearly every item in the app — which is the exact failure the
        // gate above exists to prevent. FIELD is already the place a dated
        // thing lives, and it has its own calendar over them.
        //
        // A time something *closes* is different. That is the one shape of
        // date a system alert genuinely serves, and it is rare.
        if item.closesAt != nil {
            return [.calendarDraft]
        }

        return []
    }

    /// True when `FieldOutreach` would mark the thing done and do nothing
    /// outward — which is exactly when there is room for a destination here.
    ///
    /// Mirrors `FieldOutreach.destination(act:item:target:now:)` with no
    /// target: `.pay` and `.order` fall to `.complete` there because paying a
    /// bill means somebody's banking app and the app has no idea which. That
    /// is the gap this file fills for `.order`, and filling it is the entire
    /// products half of this feature — so the two must not drift, and
    /// `FieldItemStepsTests` asserts they agree for every `FieldAct`.
    static func leavesItToUs(_ act: FieldAct) -> Bool {
        switch act {
        case .none, .pay, .order: true
        case .call, .message, .email, .book, .schedule: false
        }
    }

    private static func shopping(
        for item: LifeItem,
        query: String
    ) -> [FieldItemAction] {
        let search = FieldItemAction.retailerSearch(
            label: findLabel(for: item),
            query: query
        )
        // A filter has a size and a bulb has a fitting, and searching without
        // one returns a page of things that do not fit. Asking is not a gate —
        // the search is right there underneath it — it is the app naming the
        // one thing it would need in order to be useful.
        guard !carriesASize(item.title) else { return [search] }
        return [.askFor("size or model"), search]
    }

    /// "FIND AN AIR FILTER" — named after the thing, not after the act.
    private static func findLabel(for item: LifeItem) -> String {
        guard let subject = subject(of: item.title) else { return "FIND OPTIONS" }
        let article = "aeiou".contains(subject.lowercased().first ?? "x")
            ? "AN"
            : "A"
        return "FIND \(article) \(subject.uppercased())"
    }

    /// The last two substantial words, because English puts the head noun at
    /// the end: "replace the air filter" is about an air filter, and the first
    /// word left standing is "replace".
    static func subject(of title: String) -> String? {
        let words = FieldClassifier.subjectWords(from: title.lowercased())
            .filter { $0.count >= 3 }
        guard !words.isEmpty else { return nil }
        return words.suffix(2).joined(separator: " ")
    }

    /// A digit anywhere. Crude on purpose — "20x25x1 filter", "60w bulb" and
    /// "size 9 boots" are all somebody having already answered the question,
    /// and asking a person something they just told you is its own insult.
    static func carriesASize(_ title: String) -> Bool {
        title.contains(where: \.isNumber)
    }

    /// Somewhere with an address. Reuses the trades `FieldTargetPhrasing`
    /// already looks up in Maps, plus the everyday errand destinations that
    /// are not a trade.
    private static let errands: Set<String> = [
        "store", "market", "supermarket", "grocery", "groceries", "bakery",
        "butcher", "deli", "hardware", "nursery", "post", "bank", "library",
        "dmv", "cleaners", "laundromat", "storage", "dump", "recycling",
    ]

    private static func namesAPlace(_ lowered: String) -> Bool {
        let words = Set(
            lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        )
        return !words.isDisjoint(with: errands)
            || !words.isDisjoint(with: FieldTargetPhrasing.trades)
    }
}

// MARK: - What gets sent

/// The phrase that leaves, and the promise about it.
///
/// **Invariant, with a test: every word in the output appears in the input.**
/// This function can drop words and it can reorder nothing. The app can never
/// hand a search engine, a shop, or Maps a word the couple did not write —
/// which is what makes "it sends what you typed" a true sentence rather than
/// a reassuring one.
///
/// Never the detail, never the owner, never a date. Those are in the item and
/// they stay in the item.
enum FieldLookupQuery {
    /// Long enough for a film with a subtitle, short enough that nothing else
    /// on the item could have been smuggled in.
    static let characterLimit = 60

    /// The verbs a sentence opens with when it is an errand. Task verbs, plus
    /// "watch" — the one word that routes something to the watchlist and is
    /// not an errand verb, so it is not in `taskVerbs` and would otherwise
    /// survive into "watch past lives where to watch".
    private static let leadingVerbs: Set<String> = Set(
        FieldClassifier.taskVerbs.flatMap { $0.split(separator: " ") }
            .map(String.init)
    ).union(["watch"])

    private static let dayComponents: Set<String> = Set(
        FieldClassifier.dayWords.flatMap { $0.split(separator: " ") }
            .map(String.init)
    )

    static func normalise(_ title: String) -> String {
        var words = title.split(separator: " ").map(String.init)

        // Verbs, from the front only. A "book" in the middle of a sentence is
        // a book.
        while let first = words.first,
              leadingVerbs.contains(cleaned(first)),
              words.count > 1 {
            words.removeFirst()
        }

        words.removeAll { dayComponents.contains(cleaned($0)) }

        // Kept whole words rather than a cut mid-title: a truncated search is
        // a search for something else.
        var kept: [String] = []
        var length = 0
        for word in words {
            let next = length == 0 ? word.count : length + 1 + word.count
            guard next <= characterLimit else { break }
            kept.append(word)
            length = next
        }

        let result = kept.joined(separator: " ")
        // Everything was scaffolding. The title itself is then the most
        // honest thing to send, and it is still only what they wrote.
        return result.isEmpty ? title : result
    }

    private static func cleaned(_ word: String) -> String {
        word.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ",.!?:;'\"")
        )
    }
}
