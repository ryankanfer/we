//
//  FieldLookupPolicy.swift
//  WE
//
//  A deterministic, purpose-specific way out of LIFE.
//
//  Nothing runs until somebody chooses a purpose, and the exact phrase that
//  will leave the phone is rendered before it does. The policy sees only the
//  title and an optional clarification written for this lookup. It never sees
//  detail, ownership, dates, relationship history, or a partner.
//

import Foundation

enum WEIntelligencePurpose: String, Codable, Hashable, Sendable {
    case find
    case arrange
    case understand
    case compare
    case make
    case go
    case watch
    case read
    case listen
    case buy
    case contact
}

struct WEOutboundDisclosure: Codable, Hashable, Sendable {
    let destination: String
    let fields: [String]
    let query: String
}

enum FieldLookupDestination: String, Codable, Hashable, Sendable {
    case web
    case maps
    case shops
    /// The link this item arrived as. The only destination that sends none of
    /// the item's own words anywhere — it reopens a page the couple already
    /// reviewed and published.
    case source

    var name: String {
        switch self {
        case .web: "DuckDuckGo"
        case .maps: "Apple Maps"
        case .shops: "the shop you choose"
        case .source: "the link you saved"
        }
    }
}

struct FieldLookupChoice: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let purpose: WEIntelligencePurpose
    let destination: FieldLookupDestination
    let querySuffix: String?

    init(
        _ id: String,
        _ label: String,
        purpose: WEIntelligencePurpose,
        destination: FieldLookupDestination,
        querySuffix: String? = nil
    ) {
        self.id = id
        self.label = label
        self.purpose = purpose
        self.destination = destination
        self.querySuffix = querySuffix
    }
}

struct FieldLookupRequest: Identifiable, Hashable, Sendable {
    let choice: FieldLookupChoice
    let title: String
    /// Only ever read by the `.source` destination, and only ever a link the
    /// couple approved during share review.
    let sourceURL: URL?

    init(choice: FieldLookupChoice, title: String, sourceURL: URL? = nil) {
        self.choice = choice
        self.title = title
        self.sourceURL = sourceURL
    }

    var id: String { "\(choice.id):\(title)" }
}

enum FieldLookupPolicy {
    /// A lookup chip opens the exact-review sheet; it does not go anywhere on
    /// tap. That is why this is three and `FieldItemSteps`' old cap on
    /// *outward* actions was two — a third choice here is one more way to be
    /// asked what you meant, not a third thing the app might do behind you.
    static let maximumChoices = 3

    /// What this app can honestly offer to look up for one item, or nothing.
    ///
    /// **Nothing is a common answer, and it should be.** Most of what a couple
    /// files is a sentence about a thing that needs doing, and the honest
    /// response to "call your sister back" is an empty list and no section on
    /// screen at all.
    static func choices(for item: LifeItem) -> [FieldLookupChoice] {
        // Calendar builds that predated private intake used this prefix.
        guard !item.id.hasPrefix("cal:"), !item.isDone else { return [] }

        // Where FieldOutreach already has somewhere to go, it goes there
        // alone. Two systems offering to handle the same vet appointment is
        // worse than either of them doing it.
        guard leavesItToUs(FieldTodaySelector.primaryAct(for: item)) else {
            return []
        }

        let lowered = item.title.lowercased()
        let shop = FieldRetailer.from(host: item.sourceURL?.host)

        // Positive evidence that this is a thing somebody buys, rather than an
        // absence of evidence that it is a place. See `keepsMaps` below.
        let sellsSomething = shop != nil
            || item.category == .buys
            || FieldClassifier.buyWords.contains { lowered.contains($0) }
            // An air filter is filed under Home, not Buys, and "filter" is a
            // home word rather than a buying one. Without this clause the one
            // item in the sample seed that most obviously needs a shop is the
            // one that stops being offered one.
            || (item.category == .home
                && FieldClassifier.homeWords.contains { lowered.contains($0) })
        let namesPlace = namesAPlace(lowered)

        var ranked = catalogue(for: item.category).filter { choice in
            switch choice.destination {
            case .maps: keepsMaps(namesPlace: namesPlace, sellsSomething: sellsSomething)
            case .shops: sellsSomething
            case .web, .source: true
            }
        }

        // Naming a place promotes Maps rather than gating it: when somebody
        // writes "hardware store" the map is the answer, even though a shop
        // search would also have been offered.
        if namesPlace {
            ranked = ranked.filter { $0.destination == .maps }
                + ranked.filter { $0.destination != .maps }
        }

        if let source = sourceChoice(for: item, shop: shop) {
            ranked.insert(source, at: 0)
        }

        return Array(ranked.prefix(maximumChoices))
    }

    /// Maps stays unless there is a reason it should not.
    ///
    /// The tempting rule is the opposite one — keep Maps only when the title
    /// names a place — and it is wrong. "Carbone", "Via Carota", "MoMA", "The
    /// Standard" and "Bemelmans" are all somewhere you go, and not one of them
    /// contains a word a keyword list would recognise. A gate would quietly
    /// delete the right answer for every proper noun a couple writes down,
    /// which is most of the places they actually mean.
    ///
    /// So this is deliberately lopsided, the same way
    /// `FieldTargetPhrasing` already defaults a target to `.place`: a Maps
    /// chip that should not have been offered costs one useless search, and a
    /// Maps chip that should have been offered and wasn't costs the feature.
    static func keepsMaps(namesPlace: Bool, sellsSomething: Bool) -> Bool {
        namesPlace || !sellsSomething
    }

    /// Reopening the page this item arrived as.
    ///
    /// Offered only for `https`. `IncomingShareParser.canonicalHTTPSURL`
    /// already refuses anything else at intake, so this is the second lock on
    /// the same door: a row existing in `field_life_resources` is not on its
    /// own a reason to hand a URL to the system opener.
    static func sourceChoice(
        for item: LifeItem,
        shop: FieldRetailer?
    ) -> FieldLookupChoice? {
        guard let url = item.sourceURL,
              url.scheme?.lowercased() == "https"
        else { return nil }

        return FieldLookupChoice(
            "source.open",
            shop.map { "OPEN ON \($0.name.uppercased())" } ?? "OPEN THE LINK",
            purpose: shop == nil ? .understand : .buy,
            destination: .source
        )
    }

    /// True when `FieldOutreach` would mark the thing done and do nothing
    /// outward — which is exactly when there is room for a destination here.
    ///
    /// Mirrors `FieldOutreach.destination(act:item:target:now:)` with no
    /// target: `.pay` and `.order` fall to `.complete` there because paying a
    /// bill means somebody's banking app and the app has no idea which. The
    /// two must not drift, and `FieldItemStepsTests` asserts they agree for
    /// every `FieldAct`.
    static func leavesItToUs(_ act: FieldAct) -> Bool {
        switch act {
        case .none, .pay, .order: true
        case .call, .message, .email, .book, .schedule: false
        }
    }

    /// Somewhere with an address. Reuses the trades `FieldTargetPhrasing`
    /// already looks up in Maps, plus the everyday errand destinations that
    /// are not a trade.
    ///
    /// A promoter, never a gate — see `keepsMaps`.
    static let errands: Set<String> = [
        "store", "market", "supermarket", "grocery", "groceries", "bakery",
        "butcher", "deli", "hardware", "nursery", "post", "bank", "library",
        "dmv", "cleaners", "laundromat", "storage", "dump", "recycling",
    ]

    static func namesAPlace(_ lowered: String) -> Bool {
        let words = Set(
            lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        )
        return !words.isDisjoint(with: errands)
            || !words.isDisjoint(with: FieldTargetPhrasing.trades)
    }

    /// Every purpose this category could plausibly serve, before anything is
    /// known about the item itself. `choices(for:)` is what narrows it.
    static func catalogue(for category: LifeCategory) -> [FieldLookupChoice] {
        switch category {
        case .care:
            [
                .init("care.find", "FIND CARE", purpose: .find, destination: .maps),
                .init(
                    "care.appointment",
                    "APPOINTMENT",
                    purpose: .arrange,
                    destination: .web,
                    querySuffix: "official appointment"
                ),
                .init("care.supplies", "SUPPLIES", purpose: .buy, destination: .shops),
                .init("care.understand", "UNDERSTAND", purpose: .understand, destination: .web),
            ]
        case .food:
            [
                .init("food.cook", "COOK", purpose: .make, destination: .web, querySuffix: "recipe"),
                .init("food.shop", "SHOP", purpose: .buy, destination: .shops),
                .init("food.order", "ORDER", purpose: .arrange, destination: .web, querySuffix: "order"),
                .init("food.go", "GO SOMEWHERE", purpose: .go, destination: .maps),
            ]
        case .trips:
            [
                .init("trips.getThere", "GET THERE", purpose: .go, destination: .maps),
                .init("trips.stay", "STAY", purpose: .find, destination: .web, querySuffix: "places to stay"),
                .init("trips.do", "DO", purpose: .find, destination: .maps, querySuffix: "things to do"),
                .init("trips.research", "RESEARCH", purpose: .understand, destination: .web),
            ]
        case .watchlist:
            [
                .init("watch.watch", "WATCH", purpose: .watch, destination: .web, querySuffix: "where to watch"),
                .init("watch.read", "READ", purpose: .read, destination: .web, querySuffix: "where to read"),
                .init("watch.listen", "LISTEN", purpose: .listen, destination: .web, querySuffix: "where to listen"),
                .init("watch.learn", "LEARN", purpose: .understand, destination: .web),
            ]
        case .buys:
            [
                .init("buys.online", "BUY ONLINE", purpose: .buy, destination: .shops),
                .init("buys.nearby", "NEARBY", purpose: .go, destination: .maps),
                .init("buys.compare", "COMPARE", purpose: .compare, destination: .web, querySuffix: "compare"),
                .init("buys.secondhand", "SECONDHAND", purpose: .buy, destination: .web, querySuffix: "secondhand"),
            ]
        case .money:
            [
                .init("money.pay", "PAY", purpose: .arrange, destination: .web, querySuffix: "official payment"),
                .init("money.contact", "CONTACT PROVIDER", purpose: .contact, destination: .web, querySuffix: "official contact"),
                .init("money.understand", "UNDERSTAND", purpose: .understand, destination: .web),
                .init("money.compare", "COMPARE CAREFULLY", purpose: .compare, destination: .web, querySuffix: "official comparison"),
            ]
        case .home:
            [
                .init("home.diy", "DIY", purpose: .make, destination: .web, querySuffix: "how to"),
                .init("home.professional", "PROFESSIONAL HELP", purpose: .find, destination: .maps),
                .init("home.part", "BUY A PART", purpose: .buy, destination: .shops),
                .init("home.nearby", "NEARBY", purpose: .go, destination: .maps),
            ]
        default:
            [
                .init("other.information", "INFORMATION", purpose: .understand, destination: .web),
                .init("other.place", "PLACE", purpose: .go, destination: .maps),
                .init("other.product", "PRODUCT", purpose: .buy, destination: .shops),
                .init("other.service", "PERSON OR SERVICE", purpose: .find, destination: .web),
            ]
        }
    }

    static func disclosure(
        for request: FieldLookupRequest,
        clarification: String
    ) -> WEOutboundDisclosure {
        // Opening a saved link still reaches that site — WE is simply not
        // composing anything to send it. So the destination row names the site
        // and the query row shows the whole URL, because "the exact thing that
        // happens" is the promise this sheet makes, not "nothing happens".
        if request.choice.destination == .source {
            guard let url = request.sourceURL else {
                return WEOutboundDisclosure(
                    destination: FieldLookupDestination.source.name,
                    fields: [],
                    query: ""
                )
            }
            return WEOutboundDisclosure(
                destination: FieldRetailer.from(host: url.host)?.name
                    ?? url.host
                    ?? FieldLookupDestination.source.name,
                fields: ["Nothing from this item"],
                query: url.absoluteString
            )
        }

        return WEOutboundDisclosure(
            destination: request.choice.destination.name,
            fields: clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ["LIFE title"]
                : ["LIFE title", "lookup clarification"],
            query: query(for: request, clarification: clarification)
        )
    }

    static func query(
        for request: FieldLookupRequest,
        clarification: String
    ) -> String {
        let base = FieldLookupQuery.normalise(request.title)
        let note = clarification
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return [base, note.isEmpty ? nil : String(note), request.choice.querySuffix]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
