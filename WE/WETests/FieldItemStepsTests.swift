//
//  FieldItemStepsTests.swift
//  WETests
//
//  This is a feature whose main promise is *not* doing something, so a good
//  deal of what follows asserts an empty array.
//
//  The single most valuable test here is
//  `aProperNounDestinationStillOffersMaps`. Suppressing a map for a pair of
//  headphones is easy; the trap is doing it with a rule that demands a title
//  prove it names a place, which silently removes the map from Carbone,
//  MoMA and every other real destination anybody writes down. That test is
//  the one standing between a fix and a regression dressed as one.
//
//  The other load-bearing group is the URL rules. Exactly one query item per
//  outbound URL is what makes "I don't take a cut from any of these" a fact
//  about the code rather than a claim in the copy.
//

import Foundation
import Testing

@testable import WE

// MARK: - What gets offered

@MainActor
struct FieldLookupPolicyTests {
    private func item(
        _ title: String,
        _ category: LifeCategory,
        id: String? = nil,
        dueOn: Date? = nil,
        closesAt: Date? = nil,
        isDone: Bool = false,
        sourceURL: String? = nil
    ) -> LifeItem {
        LifeItem(
            id: id ?? title,
            title: title,
            category: category,
            owner: .a,
            dueOn: dueOn,
            closesAt: closesAt,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: isDone,
            sourceURL: sourceURL.flatMap(URL.init(string:))
        )
    }

    private func labels(
        _ title: String,
        _ category: LifeCategory,
        id: String? = nil,
        isDone: Bool = false,
        sourceURL: String? = nil
    ) -> [String] {
        FieldLookupPolicy.choices(
            for: item(
                title,
                category,
                id: id,
                isDone: isDone,
                sourceURL: sourceURL
            )
        ).map(\.label)
    }

    private func destinations(
        _ title: String,
        _ category: LifeCategory,
        sourceURL: String? = nil
    ) -> [FieldLookupDestination] {
        FieldLookupPolicy.choices(
            for: item(title, category, sourceURL: sourceURL)
        ).map(\.destination)
    }

    // MARK: Nothing at all

    /// Rows left by calendar builds that predate private intake stay inert
    /// after an upgrade even though the current app has no import path.
    @Test
    func aLegacyExternalRowIsOfferedNothing() {
        #expect(labels("Standup", .home, id: "cal:1234").isEmpty)
        #expect(labels("Past Lives", .watchlist, id: "cal:9").isEmpty)
    }

    @Test
    func aFinishedThingIsOfferedNothing() {
        #expect(labels("Past Lives", .watchlist, isDone: true).isEmpty)
        #expect(labels("Air filter", .buys, isDone: true).isEmpty)
    }

    /// `FieldOutreach` owns anything with somewhere outward to go. Two systems
    /// offering to handle the same vet appointment is worse than either — and
    /// the section disappears entirely rather than going quiet.
    @Test
    func outreachKeepsWhatItCanAlreadyReach() {
        #expect(labels("Call the vet", .care).isEmpty)
        #expect(labels("Book the dentist", .care).isEmpty)
        #expect(labels("Email the landlord", .home).isEmpty)
        #expect(labels("Text Sam about Saturday", .notes).isEmpty)
        #expect(labels("Call your sister back", .notes).isEmpty)
    }

    /// The mirror of `FieldOutreach.destination(act:item:target:now:)` with no
    /// target. `.pay` and `.order` fall to `.complete` there — the app has no
    /// idea which banking app, and no shop it is aligned with. If the two ever
    /// disagree, either a vet gets two competing buttons or the lookup section
    /// silently disappears from half the app.
    @Test
    func theSuppressionRuleAgreesWithOutreachForEveryAct() {
        let subject = item("anything at all", .notes)
        for act in [
            FieldAct.call, .message, .email, .book, .schedule, .pay, .order,
            .none,
        ] {
            let destination = FieldOutreach.destination(
                act: act,
                item: subject,
                target: nil,
                now: Date()
            )
            let outreachIsDone: Bool = {
                if case .complete = destination { return true }
                return false
            }()
            #expect(
                FieldLookupPolicy.leavesItToUs(act) == outreachIsDone,
                "\(act) disagrees with FieldOutreach"
            )
        }
    }

    // MARK: The place rule

    /// **The regression that matters most in this file.**
    ///
    /// The obvious way to stop offering a map for a pair of headphones is to
    /// keep Maps only when the title names a place. It is also the way to
    /// break every restaurant, museum and bar a couple will ever write down,
    /// because none of them contain a word a list would recognise. If this
    /// goes red, the fix for Amazon has made the app worse at places.
    @Test
    func aProperNounDestinationStillOffersMaps() {
        for name in ["Carbone", "Via Carota", "MoMA", "The Standard", "Bemelmans"] {
            #expect(
                destinations(name, .notes).contains(.maps),
                "\(name) lost its map"
            )
        }
    }

    /// The actual complaint. A product is not somewhere you go.
    @Test
    func somethingBoughtIsNotOfferedAMap() {
        #expect(!destinations("Sony WH-1000XM5 headphones", .buys).contains(.maps))
        #expect(!destinations("Order more batteries", .notes).contains(.maps))
        #expect(
            !destinations(
                "Sony WH-1000XM5 Wireless Headphones",
                .notes,
                sourceURL: "https://www.amazon.com/dp/B09XS7JWHH"
            ).contains(.maps),
            "a link from a shop should settle it even when the words do not"
        )
    }

    /// Naming a place promotes the map rather than gating it, so a hardware
    /// store gets both and the map goes first.
    @Test
    func namingAPlaceLeadsWithTheMap() {
        let offered = destinations("Drop the boxes at the storage unit", .home)
        #expect(offered.first == .maps)
    }

    /// A shop chip needs a reason. A hardware store is somewhere to drive to,
    /// not something to add to a basket.
    ///
    /// Not "Hudson vet", which looks like the obvious case and is not: `vet`
    /// is a booking noun in `wordedActs`, so `FieldOutreach` owns it and the
    /// hand-off empties the list before the place rule is ever consulted.
    @Test
    func aPlaceIsNotOfferedAShop() {
        let offered = destinations("Hardware store on Warren", .notes)
        #expect(offered.contains(.maps))
        #expect(!offered.contains(.shops))
    }

    /// Filed under Home rather than Buys, and reaching the shop branch through
    /// `homeWords` — a different clause from the one the Buys tests cover, and
    /// the item the UI test drives.
    @Test
    func theSeededAirFilterStillReachesAShop() throws {
        let filter = try #require(
            FieldSampleData.lifeItems.first { $0.id == "filter" }
        )
        #expect(filter.category == .home)
        let offered = FieldLookupPolicy.choices(for: filter)
        #expect(offered.contains { $0.destination == .shops })
        #expect(!offered.contains { $0.destination == .maps })
    }

    // MARK: The saved link

    @Test
    func aSavedShopLinkLeadsAndNamesTheShop() {
        let offered = FieldLookupPolicy.choices(
            for: item(
                "Sony WH-1000XM5 Wireless Headphones",
                .buys,
                sourceURL: "https://www.amazon.com/dp/B09XS7JWHH"
            )
        )
        #expect(offered.first?.destination == .source)
        #expect(offered.first?.label == "OPEN ON AMAZON")
        #expect(offered.first?.id == "source.open")
    }

    /// A link that is not a shop is still the page they saved.
    @Test
    func aSavedLinkThatIsNotAShopIsStillOffered() {
        let offered = FieldLookupPolicy.choices(
            for: item(
                "A long read about sourdough",
                .notes,
                sourceURL: "https://example.com/sourdough"
            )
        )
        #expect(offered.first?.label == "OPEN THE LINK")
    }

    /// A row in `field_life_resources` is not on its own a reason to hand a
    /// URL to the system opener.
    @Test
    func onlyAnHTTPSLinkIsEverOffered() {
        for unsafe in [
            "http://www.amazon.com/dp/B09XS7JWHH",
            "javascript:alert(1)",
            "file:///etc/passwd",
        ] {
            let offered = FieldLookupPolicy.choices(
                for: item("Something", .buys, sourceURL: unsafe)
            )
            #expect(
                !offered.contains { $0.destination == .source },
                "\(unsafe) was offered"
            )
        }
    }

    /// Nothing from the item goes anywhere, and the sheet says which site it
    /// is rather than a generic phrase.
    @Test
    func theSavedLinkDisclosesTheSiteAndSendsNoneOfTheItem() throws {
        let choice = try #require(
            FieldLookupPolicy.sourceChoice(
                for: item(
                    "Sony WH-1000XM5",
                    .buys,
                    sourceURL: "https://www.amazon.com/dp/B09XS7JWHH"
                ),
                shop: .amazon
            )
        )
        let disclosure = FieldLookupPolicy.disclosure(
            for: FieldLookupRequest(
                choice: choice,
                title: "Sony WH-1000XM5",
                sourceURL: URL(string: "https://www.amazon.com/dp/B09XS7JWHH")
            ),
            clarification: "ignored"
        )
        #expect(disclosure.destination == "Amazon")
        #expect(disclosure.fields == ["Nothing from this item"])
        #expect(disclosure.query == "https://www.amazon.com/dp/B09XS7JWHH")
        // The clarification cannot reach a destination that builds no query.
        #expect(!disclosure.query.contains("ignored"))
    }

    // MARK: Restraint

    /// Three is the cap, and it holds across the whole seeded life rather than
    /// on a hand-picked example.
    @Test
    func neverMoreThanThreeChoices() {
        for sample in FieldSampleData.lifeItems {
            let offered = FieldLookupPolicy.choices(for: sample)
            #expect(
                offered.count <= FieldLookupPolicy.maximumChoices,
                "\(sample.title) offered \(offered.count)"
            )
            #expect(
                Set(offered.map(\.id)).count == offered.count,
                "\(sample.title) offered a duplicate"
            )
        }
    }
}

// MARK: - Recognising a shop

@MainActor
struct FieldRetailerHostTests {
    /// A shop name inside a hostname is not a claim anybody should be able to
    /// make by registering a domain that contains it.
    @Test
    func onlyTheRealDomainOrItsSubdomainsMatch() {
        #expect(FieldRetailer.from(host: "amazon.com") == .amazon)
        #expect(FieldRetailer.from(host: "www.amazon.com") == .amazon)
        #expect(FieldRetailer.from(host: "smile.amazon.com") == .amazon)
        #expect(FieldRetailer.from(host: "WWW.AMAZON.COM") == .amazon)
        #expect(FieldRetailer.from(host: "www.homedepot.com") == .homeDepot)

        #expect(FieldRetailer.from(host: "fakeamazon.com") == nil)
        #expect(FieldRetailer.from(host: "amazon.com.evil.example") == nil)
        #expect(FieldRetailer.from(host: "notamazon.com") == nil)
        #expect(FieldRetailer.from(host: nil) == nil)
        #expect(FieldRetailer.from(host: "") == nil)
    }

    /// Out of scope on purpose: a shortener cannot be recognised without
    /// resolving it, and resolving it is a network call.
    @Test
    func internationalStorefrontsAndShortenersAreNotGuessedAt() {
        #expect(FieldRetailer.from(host: "www.amazon.co.uk") == nil)
        #expect(FieldRetailer.from(host: "amzn.to") == nil)
    }

    /// The shop a link came from leads; everything else stays alphabetical.
    @Test
    func aSavedShopLeadsTheList() {
        let ordered = FieldRetailer.ordered(
            preferred: [FieldRetailer.from(host: "www.amazon.com")].compactMap { $0 }
        )
        #expect(ordered.first == .amazon)
        #expect(ordered.count == FieldRetailer.allCases.count)
        #expect(Set(ordered).count == ordered.count)
    }
}

// MARK: - The URLs

@MainActor
struct FieldSearchLinkTests {
    /// The affiliate rule, as a fact about the code. A referral tag cannot be
    /// added to any of these without turning this red.
    @Test
    func everyOutboundURLCarriesExactlyOneQueryItem() {
        var urls: [URL] = [
            FieldSearchLink.web("air filter"),
            FieldSearchLink.maps("hardware store"),
        ].compactMap { $0 }

        urls += FieldRetailer.allCases.compactMap {
            $0.url(searching: "20x25x1 air filter")
        }

        #expect(urls.count == FieldRetailer.allCases.count + 2)
        for url in urls {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
            #expect(items.count == 1, "\(url) carries \(items.count)")
        }
    }

    @Test
    func aShopSearchCarriesTheCouplesOwnWords() {
        guard let url = FieldRetailer.target.url(searching: "air filter"),
              let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first
        else {
            Issue.record("no URL")
            return
        }
        #expect(item.value == "air filter")
    }

    @Test
    func anEmptyQueryOpensNothing() {
        #expect(FieldSearchLink.web("") == nil)
        #expect(FieldSearchLink.maps("   ") == nil)
        #expect(FieldRetailer.amazon.url(searching: "") == nil)
    }

    /// Ordered, never randomised — and the same twice, so a shop cannot climb
    /// the list by being asked for again.
    @Test
    func shopsAreAlphabeticalAndStable() {
        let names = FieldRetailer.ordered().map(\.name)
        #expect(names == names.sorted())
        #expect(FieldRetailer.ordered() == FieldRetailer.ordered())
    }

    /// The seam a stored preference list would arrive through. Preferred
    /// shops lead; everything else stays alphabetical behind them.
    @Test
    func preferredShopsLeadAndTheRestStayAlphabetical() {
        let ordered = FieldRetailer.ordered(preferred: [.walmart])
        #expect(ordered.first == .walmart)
        #expect(ordered.count == FieldRetailer.allCases.count)
        #expect(Set(ordered).count == ordered.count)
        #expect(ordered.dropFirst().map(\.name) == ordered.dropFirst().map(\.name).sorted())
    }
}

// MARK: - What leaves the phone

@MainActor
struct FieldLookupQueryTests {
    /// The promise, as an invariant. The app can drop words from what a couple
    /// wrote; it can never add one.
    @Test
    func everyWordSentWasAWordTheyWrote() {
        let titles = FieldSampleData.lifeItems.map(\.title) + [
            "Watch Past Lives this weekend",
            "Pick up the dry cleaning tomorrow",
            "Buy 20x25x1 air filter",
            "Book the vet on Tuesday",
        ]

        for title in titles {
            let written = Set(
                title.lowercased().split(separator: " ").map(String.init)
            )
            let sent = Set(
                FieldLookupQuery.normalise(title)
                    .lowercased()
                    .split(separator: " ")
                    .map(String.init)
            )
            #expect(sent.isSubset(of: written), "\(title) grew a word")
        }
    }

    @Test
    func theVerbAndTheDayComeOff() {
        #expect(
            FieldLookupQuery.normalise("Watch Past Lives this weekend")
                == "Past Lives"
        )
        #expect(
            FieldLookupQuery.normalise("Buy batteries tomorrow") == "batteries"
        )
    }

    /// A verb in the middle of a sentence is not scaffolding. "The book club"
    /// is about a book.
    @Test
    func onlyALeadingVerbComesOff() {
        #expect(FieldLookupQuery.normalise("The book club") == "The book club")
    }

    /// Everything was scaffolding. The title is then the most honest thing to
    /// send, and it is still only what they wrote.
    @Test
    func aTitleOfNothingButScaffoldingIsSentWhole() {
        #expect(FieldLookupQuery.normalise("tomorrow") == "tomorrow")
        #expect(!FieldLookupQuery.normalise("Buy").isEmpty)
    }

    /// Cut at a word, never mid-title: a truncated search is a search for
    /// something else.
    @Test
    func aLongTitleIsCutAtAWord() {
        let long = String(repeating: "alpha ", count: 30)
        let sent = FieldLookupQuery.normalise(long)
        #expect(sent.count <= FieldLookupQuery.characterLimit)
        #expect(!sent.hasSuffix(" "))
    }
}

// MARK: - What the model is allowed to say

@MainActor
struct FieldItemVoiceTests {
    private let source = "clear the guest room 15"

    private func plan(_ lines: [String]) -> [String]? {
        FieldItemVoice.sanitizedPlan(
            lines.joined(separator: "\n"),
            against: source
        )
    }

    @Test
    func acleanPlanSurvives() {
        let steps = [
            "Strip the bed and start a wash.",
            "Clear the surfaces into one box.",
            "Vacuum, starting at the far corner.",
            "Put fresh sheets on.",
        ]
        #expect(plan(steps) == steps)
    }

    /// Numbering and bullets are decoration, not steps.
    @Test
    func numberingComesOff() {
        let cleaned = plan([
            "1. Strip the bed.",
            "2. Clear the surfaces.",
            "3. Vacuum the floor.",
        ])
        #expect(cleaned == [
            "Strip the bed.", "Clear the surfaces.", "Vacuum the floor.",
        ])
    }

    /// The whole plan goes, not the offending line. Somebody following four
    /// steps has no way to see that a fifth was quietly dropped.
    @Test
    func aPriceRejectsTheWholePlan() {
        #expect(plan([
            "Strip the bed and start a wash.",
            "Order a mattress protector for $24.99.",
            "Vacuum the floor.",
        ]) == nil)
    }

    /// Numeric grounding. A number the model was not given is a number it
    /// composed, whatever it is attached to.
    @Test
    func aNumberThatWasNotGivenRejectsThePlan() {
        #expect(plan([
            "Strip the bed and start a wash.",
            "Let the paint cure for 48 hours.",
            "Vacuum the floor.",
        ]) == nil)
    }

    /// The minutes and the title are the ground. A number that *is* in them
    /// passes — the rule is grounding, not a ban on digits.
    @Test
    func aNumberFromTheSourcePasses() {
        #expect(plan([
            "Set a timer for 15 minutes.",
            "Strip the bed and start a wash.",
            "Vacuum the floor.",
        ]) != nil)
    }

    /// A lone digit is a shape of speech, not a claim about the world.
    @Test
    func aSingleDigitIsNotAClaim() {
        #expect(plan([
            "Do 1 surface at a time.",
            "Strip the bed.",
            "Vacuum the floor.",
        ]) != nil)
    }

    @Test
    func aBrandTheyDidNotNameRejectsThePlan() {
        #expect(plan([
            "Strip the bed and start a wash.",
            "Wipe the sills with Clorox.",
            "Vacuum the floor.",
        ]) == nil)
    }

    /// A number this app would be willing to dial is never something a model
    /// composed. See the note on `FieldDial.normalised`.
    @Test
    func aPhoneShapedRunRejectsThePlan() {
        #expect(plan([
            "Strip the bed and start a wash.",
            "Call 5551234567 about the carpet.",
            "Vacuum the floor.",
        ]) == nil)
    }

    @Test
    func aLinkRejectsThePlan() {
        #expect(plan([
            "Strip the bed and start a wash.",
            "Read the guide at example.com first.",
            "Vacuum the floor.",
        ]) == nil)
    }

    /// Fewer than three is the thing restated; more than five is a project,
    /// and the button said fifteen minutes.
    @Test
    func aPlanOfTheWrongLengthIsNotAPlan() {
        #expect(plan(["Strip the bed.", "Vacuum."]) == nil)
        #expect(plan(Array(repeating: "Tidy one shelf.", count: 6)) == nil)
    }

    /// Rejected rather than truncated: half an instruction is worse than none.
    @Test
    func anOverlongStepIsRejectedRatherThanCut() {
        #expect(plan([
            "Strip the bed.",
            String(repeating: "a", count: FieldItemVoice.lineLimit + 1),
            "Vacuum the floor.",
        ]) == nil)
    }

    /// Ported from `FieldCategoryVoice`: the check happens before the bullet
    /// is stripped, so a list cannot arrive disguised as a sentence.
    @Test
    func theSourceIsTheTitleAndTheMinutesAndNothingElse() {
        let subject = LifeItem(
            id: "1",
            title: "Clear the guest room",
            category: .home,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: "Ryan's parents, August",
            isTimeCritical: false,
            isDone: false
        )
        let ground = FieldItemVoice.source(for: subject, minutes: 15)
        #expect(ground.contains("Clear the guest room"))
        #expect(ground.contains("15"))
        #expect(ground.contains("Ryan's parents"))
    }
}
