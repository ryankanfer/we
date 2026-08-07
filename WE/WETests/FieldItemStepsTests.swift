//
//  FieldItemStepsTests.swift
//  WETests
//
//  Stage 4 is a feature whose main promise is *not* doing something, so most
//  of what follows asserts an empty array. The single most valuable test in
//  this file is `aPlainItemIsOfferedNothing`: if that ever goes green while
//  returning a suggestion, the app has started having opinions about a
//  couple's shopping list.
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
struct FieldItemStepsTests {
    private func item(
        _ title: String,
        _ category: LifeCategory,
        id: String? = nil,
        dueOn: Date? = nil,
        closesAt: Date? = nil,
        isDone: Bool = false
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
            isDone: isDone
        )
    }

    private func actions(
        _ title: String,
        _ category: LifeCategory,
        modelAvailable: Bool = true,
        id: String? = nil,
        dueOn: Date? = nil,
        closesAt: Date? = nil,
        isDone: Bool = false
    ) -> [FieldItemAction] {
        FieldItemSteps.actions(
            for: item(
                title,
                category,
                id: id,
                dueOn: dueOn,
                closesAt: closesAt,
                isDone: isDone
            ),
            isModelAvailable: modelAvailable
        )
    }

    /// The one that matters. A sentence about a meal is a sentence about a
    /// meal, and the app has nothing to add to it.
    @Test
    func aPlainItemIsOfferedNothing() {
        #expect(actions("Dinner with the Harrisons", .food).isEmpty)
        #expect(actions("Miso seems off", .care).isEmpty)
        #expect(actions("Sort out the spare keys", .notes).isEmpty)
    }

    /// An imported event is somebody else's record. The calendar permission
    /// string promises the app never adds, changes, or deletes anything, and
    /// this must not become the one control that forgets.
    @Test
    func anImportedEventIsOfferedNothing() {
        #expect(actions("Standup", .home, id: "cal:1234").isEmpty)
        // Even a watchlist row, which would otherwise always offer something.
        #expect(actions("Past Lives", .watchlist, id: "cal:9").isEmpty)
    }

    @Test
    func afinishedThingIsOfferedNothing() {
        #expect(actions("Past Lives", .watchlist, isDone: true).isEmpty)
        #expect(actions("Air filter", .buys, isDone: true).isEmpty)
    }

    /// `FieldOutreach` owns anything with somewhere outward to go. Two systems
    /// offering to handle the same vet appointment is worse than either.
    @Test
    func outreachKeepsWhatItCanAlreadyReach() {
        #expect(actions("Call the vet", .care).isEmpty)
        #expect(actions("Book the dentist", .care).isEmpty)
        #expect(actions("Email the landlord", .home).isEmpty)
        #expect(actions("Text Sam about Saturday", .notes).isEmpty)
    }

    /// The mirror of `FieldOutreach.destination(act:item:target:now:)` with no
    /// target. `.pay` and `.order` fall to `.complete` there — the app has no
    /// idea which banking app, and no shop it is aligned with — which is
    /// exactly the gap this file fills for `.order`. If the two ever disagree,
    /// either a vet gets two competing buttons or the products half silently
    /// disappears.
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
                FieldItemSteps.leavesItToUs(act) == outreachIsDone,
                "\(act) disagrees with FieldOutreach"
            )
        }
    }

    @Test
    func aWatchlistItemOffersOneWebSearch() {
        let offered = actions("Past Lives", .watchlist)
        #expect(offered.count == 1)
        guard case .webSearch(let label, let query) = offered.first else {
            Issue.record("expected a web search, got \(offered)")
            return
        }
        #expect(label == "WHERE TO WATCH")
        #expect(query == "Past Lives where to watch")
    }

    /// No provider, so no claim. The query is the couple's own words plus the
    /// three the app added, and those three are visible in the button.
    @Test
    func theWatchlistSearchSendsNoProviderName() {
        guard case .webSearch(_, let query) = actions(
            "Watch Past Lives this weekend",
            .watchlist
        ).first else {
            Issue.record("expected a web search")
            return
        }
        #expect(query == "Past Lives where to watch")
        #expect(!query.lowercased().contains("netflix"))
        #expect(!query.lowercased().contains("justwatch"))
    }

    /// A filter has a size, and searching without one returns a page of things
    /// that do not fit. The ask comes first and the search still follows it —
    /// it is a sentence, not a gate.
    @Test
    func somethingWithNoSizeIsAskedForOneFirst() {
        let offered = actions("Air filter", .buys)
        #expect(offered.count == 2)
        #expect(offered.first == .askFor("size or model"))
        guard case .retailerSearch(let label, _) = offered.last else {
            Issue.record("expected a shop search, got \(offered)")
            return
        }
        #expect(label == "FIND AN AIR FILTER")
    }

    /// Asking somebody for something they already told you is its own insult.
    @Test
    func aSizeAlreadyGivenIsNotAskedForAgain() {
        let offered = actions("20x25x1 air filter", .buys)
        #expect(offered.count == 1)
        #expect(!offered.contains(.askFor("size or model")))
    }

    /// Named after the thing, not after the act: "replace" is a verb and
    /// nobody goes shopping for one.
    @Test
    func theShopButtonIsNamedAfterTheThing() {
        #expect(FieldItemSteps.subject(of: "replace the air filter") == "air filter")
        #expect(FieldItemSteps.subject(of: "buy batteries") == "batteries")
        #expect(FieldItemSteps.subject(of: "order more coffee filters") == "coffee filters")
        // Nothing substantial left. "FIND OPTIONS" rather than a wrong noun.
        #expect(FieldItemSteps.subject(of: "get some stuff") == nil)
    }

    @Test
    func anErrandWithSomewhereToGoOpensMaps() {
        guard case .maps(let label, let query) = actions(
            "Drop the boxes at the storage unit",
            .home
        ).first else {
            Issue.record("expected Maps")
            return
        }
        #expect(label == "OPEN IN MAPS")
        #expect(!query.isEmpty)
    }

    /// The model's whole remit: a household task, and only when there is a
    /// model to ask. On a phone without one, nothing at all — never a disabled
    /// button explaining what it would have done.
    @Test
    func aPlanIsOfferedOnlyWhenThereIsAModel() {
        #expect(
            actions("Clean the guest room", .home, modelAvailable: true)
                == [.plan(minutes: 15)]
        )
        #expect(
            actions("Clean the guest room", .home, modelAvailable: false)
                .isEmpty
        )
    }

    /// A hard cut-off, and only that. A draft, in Apple's own sheet — the app
    /// writes to nobody's calendar.
    @Test
    func aClosingTimeGetsACalendarDraft() {
        #expect(actions("Recital", .notes, closesAt: Date()) == [.calendarDraft])
    }

    /// The rule that keeps this feature rare. Almost everything a couple files
    /// carries a day, so offering the calendar on a date alone would put the
    /// block under nearly every item in the app — and FIELD is already where a
    /// dated thing lives.
    @Test
    func aDayAloneIsNotAReasonToOfferAnything() {
        #expect(actions("Recital", .notes, dueOn: Date()).isEmpty)
        #expect(actions("Miso's teeth", .care, dueOn: Date()).isEmpty)
    }

    /// The same rule, stated over the seed a couple actually sees. If this
    /// starts failing, the block has become the common case.
    @Test
    func mostOfTheSampleCoupleSLifeIsOfferedNothing() {
        let offered = FieldSampleData.lifeItems.filter {
            !FieldItemSteps.actions(for: $0, isModelAvailable: false).isEmpty
        }
        #expect(
            offered.count * 2 < FieldSampleData.lifeItems.count,
            "the help block reached \(offered.map(\.title))"
        )
    }

    /// Against the real seeded row rather than a hand-built one, because the
    /// UI test drives this exact item: "Air filter" is filed under Home, not
    /// Buys, and it reaches the shop branch through `homeWords` — which is a
    /// different clause from the one the Buys tests cover.
    @Test
    func theSeededAirFilterReachesTheShopBranch() throws {
        let filter = try #require(
            FieldSampleData.lifeItems.first { $0.id == "filter" }
        )
        #expect(filter.category == .home)
        let offered = FieldItemSteps.actions(
            for: filter,
            isModelAvailable: false
        )
        #expect(offered.contains(.askFor("size or model")))
        #expect(offered.contains { $0.identifier == "field.item.help.shop" })
    }

    /// A third button is a menu, and a menu is the app having opinions.
    @Test
    func neverMoreThanTwoThingsToTap() {
        for sample in FieldSampleData.lifeItems {
            for available in [true, false] {
                let tappable = FieldItemSteps
                    .actions(for: sample, isModelAvailable: available)
                    .filter(\.isTappable)
                #expect(
                    tappable.count <= FieldItemSteps.maximumTappable,
                    "\(sample.title) offered \(tappable.count)"
                )
            }
        }
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
