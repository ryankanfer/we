//
//  TodayBriefTests.swift
//  WETests
//
//  Today as a brief: what leads, what the partner kept, what is coming, and
//  the rules that keep each honest. Every test builds a small couple from
//  nothing so the seed's own items cannot win a section by accident.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct TodayBriefTests {
    private let calendar = Calendar.gregorianUS
    private let now = FieldSampleData.today

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func item(
        _ id: String,
        _ title: String,
        _ category: LifeCategory = .notes,
        owner: FieldOwner = .b,
        dueOn: Date? = nil,
        closesAt: Date? = nil,
        done: Bool = false,
        url: URL? = nil,
        visibility: FieldVisibility? = nil,
        timing: WEObjectTiming? = nil
    ) -> LifeItem {
        LifeItem(
            timing: timing,
            id: id, title: title, category: category, owner: owner,
            dueOn: dueOn, closesAt: closesAt, clusterID: nil, source: .captured,
            detail: nil, isTimeCritical: false, isDone: done,
            sourceURL: url, visibility: visibility
        )
    }

    private func kept(_ id: String, by owner: FieldOwner = .b, daysAgo: Int = 1) -> FieldCapture {
        FieldCapture(id: id, text: id, owner: owner, capturedAt: day(-daysAgo))
    }

    private func store(
        _ items: [LifeItem],
        captures: [FieldCapture] = [],
        conversation: [FieldChatMessage] = []
    ) -> FieldStore {
        var state = FieldState.seed
        state.lifeItems = items
        state.captures = captures
        state.conversation = conversation
        state.horizons = []
        state.anchors = []
        state.heldTopics = []
        state.standingRules = []
        state.threads = []
        state.evidence = []
        return FieldStore(state: state, now: now)
    }

    private func brief(_ store: FieldStore) -> FieldTodayBrief {
        FieldTodayBriefBuilder.build(store: store)
    }

    private static let bermuda = WEObjectTiming(precision: .day, startDay: "2025-11-01", endDay: "2025-11-05")

    // MARK: The lead

    @Test
    func somethingThatNeedsYouLeadsWithAFactNotAFeeling() {
        let tonight = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
        let grocery = item("grocery", "Send the grocery list", .buys, owner: .a, closesAt: tonight)
        let result = brief(store([grocery]))

        guard case .moment(let moment, let fact, _) = result.lead else {
            Issue.record("expected the closing window to lead, got \(result.lead)")
            return
        }
        #expect(moment.id == "grocery")
        #expect(fact?.hasPrefix("Closes today at") == true)
        #expect(!result.moreItemIDs.contains("grocery"))
    }

    @Test
    func aQuietDayLetsWhatTheyKeptLead() {
        let flowers = item("flowers", "Flower shop on Elm")
        let result = brief(store([flowers], captures: [kept("flowers")]))

        guard case .discovery(let entry) = result.lead else {
            Issue.record("expected the discovery to lead, got \(result.lead)")
            return
        }
        #expect(entry.itemID == "flowers")
        #expect(entry.attribution == "Dylan kept this yesterday.")
        #expect(result.discovery == nil, "the same thing twice")
    }

    @Test
    func anEmptyDayIsCalmAndComplete() {
        let result = brief(store([]))
        guard case .clear(let headline, _) = result.lead else {
            Issue.record("expected the clear state, got \(result.lead)")
            return
        }
        #expect(!headline.isEmpty)
        #expect(result.discovery == nil)
        #expect(result.ahead == nil)
        #expect(result.proposalIDs.isEmpty)
    }

    // MARK: Discovery eligibility

    @Test
    func onlyTheirOwnSharedRecentKeptThingIsADiscovery() {
        let items = [
            item("mine", "Linen shop", owner: .a),
            item("secret", "Ring sizes", visibility: .private),
            item("chore", "Call the plumber", .home),
            item("old", "Wine bar on 5th"),
            item("done", "Bakery", done: true),
            item("untracked", "Book shop"),
        ]
        let captures = [
            kept("mine", by: .a),
            kept("secret"),
            kept("chore"),
            kept("old", daysAgo: 12),
            kept("done"),
        ]
        let result = brief(store(items, captures: captures))

        #expect(result.leadItemID == nil, "nothing here is eligible: \(result.lead)")
        #expect(result.discovery == nil)
    }

    @Test
    func theNewestDiscoveryWinsAndTheChoiceIsStable() {
        let items = [item("older", "Wine bar on 5th"), item("newer", "Flower shop on Elm")]
        let captures = [kept("older", daysAgo: 3), kept("newer", daysAgo: 1)]
        let first = brief(store(items, captures: captures))
        let again = brief(store(items.reversed(), captures: captures.reversed()))

        #expect(first.leadItemID == "newer")
        #expect(first == again)
    }

    // MARK: Looking ahead

    @Test
    func lookingAheadPrefersTheTripAndSkipsTodayAndThePast() {
        let items = [
            item("trip", "Bermuda", .trips, owner: .a, timing: Self.bermuda),
            item("soon", "Parks gala", owner: .a, dueOn: day(2)),
            item("today", "Dentist", .care, owner: .a, dueOn: now),
            item("past", "Old thing", owner: .a, dueOn: day(-3)),
        ]
        let result = brief(store(items))

        #expect(result.ahead?.itemID == "trip")
        #expect(result.ahead?.context == "Nov 1 to 5")
    }

    @Test
    func farAwayIsNotAhead() {
        let items = [item("later", "Lisbon", .trips, owner: .a, dueOn: day(200))]
        #expect(brief(store(items)).ahead == nil)
    }

    @Test
    func aPrivateUpcomingThingIsLabelledAndTheirsNeverShows() {
        let mine = item("mine", "Surprise weekend", .trips, owner: .a, visibility: .private, timing: Self.bermuda)
        let theirs = item("theirs", "Their secret trip", .trips, owner: .b, dueOn: day(5), visibility: .private)
        let result = brief(store([mine, theirs]))

        #expect(result.ahead?.itemID == "mine")
        #expect(result.ahead?.isPrivate == true)

        let onlyTheirs = brief(store([theirs]))
        #expect(onlyTheirs.ahead == nil)
    }

    // MARK: Nothing twice, and nothing stale

    @Test
    func aKeptTripIsADiscoveryOnceAndNeverAlsoAhead() {
        let trip = item("trip", "Bermuda", .trips, timing: Self.bermuda)
        let result = brief(store([trip], captures: [kept("trip")]))

        #expect(result.leadItemID == "trip")
        #expect(result.ahead == nil)
        #expect(result.discovery == nil)
    }

    @Test
    func finishingOrDeletingTakesItOffThePage() {
        let flowers = item("flowers", "Flower shop on Elm")
        let trip = item("trip", "Bermuda", .trips, owner: .a, timing: Self.bermuda)
        let store = store([flowers, trip], captures: [kept("flowers")])

        #expect(brief(store).leadItemID == "flowers")
        #expect(brief(store).ahead?.itemID == "trip")

        store.complete("flowers")
        #expect(brief(store).leadItemID == nil)

        store.remove("trip")
        #expect(brief(store).ahead == nil)
    }

    // MARK: Proposals

    @Test
    func aProposalStaysAProposalUntilItIsAnswered() {
        let table = item("table", "Book the anniversary table", .food, owner: .a)
        let open = FieldChatMessage(
            id: "open", body: "Book the anniversary table", sender: .b,
            createdAt: day(-1), context: FieldChatContext(kind: "life", id: "table"),
            decision: true, confirmed: false
        )
        let settled = FieldChatMessage(
            id: "settled", body: "Book the anniversary table", sender: .b,
            createdAt: day(-2), context: FieldChatContext(kind: "life", id: "table"),
            decision: true, confirmed: true
        )
        let result = brief(store([table], conversation: [open, settled]))
        #expect(result.proposalIDs == ["open"])
    }

    @Test
    func aProposalAboutSomethingGoneIsNotShown() {
        let orphan = FieldChatMessage(
            id: "orphan", body: "Gone", sender: .b, createdAt: day(-1),
            context: FieldChatContext(kind: "life", id: "deleted"),
            decision: true, confirmed: false
        )
        #expect(brief(store([], conversation: [orphan])).proposalIDs.isEmpty)
    }

    // MARK: The one sentence

    @Test
    func theSentenceIsBuiltFromWhatIsWritten() {
        let trip = item("trip", "Bermuda", .trips, timing: Self.bermuda)
        #expect(FieldTodayBriefBuilder.fact(for: trip, now: now, calendar: calendar) == "Nov 1 to 5.")

        var dinner = item("dinner", "Dinner", .food, dueOn: day(1))
        dinner.place = "Lilia"
        #expect(FieldTodayBriefBuilder.fact(for: dinner, now: now, calendar: calendar) == "Tomorrow at Lilia.")

        let undated = item("film", "Past Lives", .watchlist)
        #expect(FieldTodayBriefBuilder.fact(for: undated, now: now, calendar: calendar) == "In \(LifeCategory.watchlist.word).")
    }
}
