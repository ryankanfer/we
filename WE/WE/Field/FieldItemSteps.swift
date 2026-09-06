//
//  FieldItemSteps.swift
//  WE
//
//  The plumbing for leaving the app: where a search can go, which shops it can
//  go to, and the exact phrase that goes with it.
//
//  Everything here is a *destination*, not a fact. The app does not know what
//  a film is streaming on, what a filter costs, or whether a shop has one in.
//  It knows how to open the place where that is written down, and it names the
//  place on the button before anybody taps it.
//
//  *Which* destination to offer for a given item is not decided here — that is
//  `FieldLookupPolicy`, which owns the one live answer. This file used to hold
//  a second, parallel answer (`FieldItemSteps.actions`) that nothing but its
//  own tests ever called; its heuristics moved into the policy rather than
//  being deleted, so the two can no longer drift apart by existing at all.
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

    /// The registrable domain, for recognising a link somebody shared in.
    var domain: String {
        switch self {
        case .amazon: "amazon.com"
        case .bestBuy: "bestbuy.com"
        case .homeDepot: "homedepot.com"
        case .target: "target.com"
        case .walmart: "walmart.com"
        }
    }

    /// The shop a shared link came from, if it came from one of these.
    ///
    /// Anchored at a label boundary rather than matched as a substring, which
    /// is the whole difference between recognising `www.amazon.com` and
    /// trusting `fakeamazon.com` or `amazon.com.someone-elses-domain.example`.
    /// A shop name in a hostname is not a claim anybody should be able to make
    /// by registering a domain that contains it.
    ///
    /// International storefronts (`amazon.co.uk`) and shorteners (`amzn.to`)
    /// are deliberately absent. A shortener cannot be recognised without
    /// resolving it, resolving it is a network call, and nothing in this file
    /// makes one.
    static func from(host: String?) -> FieldRetailer? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return allCases.first {
            host == $0.domain || host.hasSuffix(".\($0.domain)")
        }
    }

    /// The couple's own shops first, then alphabetically. Never randomised,
    /// never weighted, never sold.
    ///
    /// `preferred` is fed by the shop a shared link came from, so an item that
    /// arrived from Amazon offers Amazon first. That is the couple's own
    /// choice reflected back at them, not a placement — every other shop is
    /// still on the list, in the same order, one row down.
    static func ordered(preferred: [FieldRetailer] = []) -> [FieldRetailer] {
        let seen = Set(preferred)
        let rest = allCases
            .filter { !seen.contains($0) }
            .sorted { $0.name < $1.name }
        return preferred + rest
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
