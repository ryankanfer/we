//
//  FieldDayConversationTests.swift
//  WETests
//
//  The day's conversation on Today: what counts as a look-up, what a look-up
//  may say, whose additions WE answers, and which things may become a shared
//  decision. See `FieldDayConversation`.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct FieldDayConversationTests {
    private func item(
        _ id: String,
        _ title: String,
        owner: FieldOwner = .a,
        done: Bool = false,
        visibility: FieldVisibility? = nil
    ) -> LifeItem {
        LifeItem(
            id: id, title: title, category: .buys, owner: owner,
            dueOn: nil, closesAt: nil, clusterID: nil, source: .captured,
            detail: nil, isTimeCritical: false, isDone: done,
            visibility: visibility
        )
    }

    // MARK: What is a look-up

    /// Only an unmistakable opener. A topic that ends in a question mark is
    /// for the two of you, and is filed, never kept on one phone.
    @Test
    func onlyAQuestionAboutWhatIsWrittenDownIsALookup() {
        #expect(FieldLookupEngine.isLookup("what did we get for dad?"))
        #expect(FieldLookupEngine.isLookup("When is the ferry"))
        #expect(FieldLookupEngine.isLookup("did we book the vet"))
        #expect(!FieldLookupEngine.isLookup("should we do Tahoe?"))
        #expect(!FieldLookupEngine.isLookup("dinner with sam friday"))
        #expect(!FieldLookupEngine.isLookup("is it weird to skip the party?"))
    }

    @Test
    func theSubjectIsWhatIsLeftOfTheQuestion() {
        #expect(FieldLookupEngine.keywords(in: "What did we get for dad's visit?") == ["dad", "visit"])
    }

    // MARK: What a look-up may say

    @Test
    func aLookupPointsOnlyAtRealThingsAndStaysOnThisPhone() {
        var state = FieldState.seed
        state.lifeItems = [
            item("bottle", "A bottle for Ryan's dad", done: true),
            item("ferry", "Book the ferry"),
        ]
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)

        store.lookUp("what did we get for dad?")

        let lookup = store.lookups.last
        #expect(lookup?.itemIDs == ["bottle"])
        #expect(lookup?.foundNothing == false)
        // Nothing was filed and nothing was queued to be sent.
        #expect(store.state.lifeItems.count == 2)
        #expect(store.state.captures.allSatisfy { $0.text != "what did we get for dad?" })
    }

    @Test
    func aLookupThatMatchesNothingSaysSoRatherThanGuessing() {
        var state = FieldState.seed
        state.lifeItems = [item("ferry", "Book the ferry")]
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)

        store.lookUp("what did we decide about the wedding?")
        #expect(store.lookups.last?.foundNothing == true)
    }

    /// A misread costs one tap: the question can be filed for the two of you.
    @Test
    func aLookupCanBeSavedForBothInstead() throws {
        var state = FieldState.seed
        state.lifeItems = []
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)

        store.lookUp("what about the garden fence?")
        let lookup = try #require(store.lookups.last)
        store.saveLookupForUs(lookup)

        #expect(store.lookups.isEmpty)
        #expect(
            store.state.lifeItems.contains { $0.title.localizedCaseInsensitiveContains("garden fence") },
            "filed: \(store.state.lifeItems.map(\.title)), receipt: \(String(describing: store.lastReceipt?.title)), error: \(String(describing: store.captureSaveError))"
        )
    }

    // MARK: The thread

    /// WE answers this person's own additions and never narrates the
    /// partner's — they already saw where it went.
    @Test
    func weRepliesOnlyToYourOwnAdditions() {
        var state = FieldState.seed
        state.lifeItems = [
            item("mine", "Air filter", owner: .a),
            item("theirs", "Gift for dad", owner: .b),
        ]
        state.captures = [
            FieldCapture(id: "mine", text: "air filter", owner: .a, capturedAt: FieldSampleData.today),
            FieldCapture(id: "theirs", text: "gift for dad", owner: .b, capturedAt: FieldSampleData.today),
        ]
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)

        let thread = FieldDayConversation.thread(store: store)
        let filed = thread.compactMap { entry -> String? in
            if case .filed(let id) = entry.kind { return id }
            return nil
        }
        #expect(filed == ["mine"])
        #expect(thread.contains { if case .capture(_, mine: false) = $0.kind { return true }; return false })
    }

    /// The day starts fresh: yesterday's additions are not in the thread,
    /// only in the morning line's link.
    @Test
    func theThreadIsOnlyToday() {
        var state = FieldState.seed
        let yesterday = Calendar.gregorianUS.date(byAdding: .day, value: -1, to: FieldSampleData.today)!
        state.lifeItems = [item("old", "Old thing")]
        state.captures = [FieldCapture(id: "old", text: "old thing", owner: .a, capturedAt: yesterday)]
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)

        #expect(FieldDayConversation.thread(store: store).isEmpty)
        #expect(FieldDayConversation.yesterdayItemIDs(store: store) == ["old"])
    }

    // MARK: Decisions

    /// A private thing can never be put to the partner as a decision.
    @Test
    func onlyASharedThingCanBeProposedAsADecision() {
        var state = FieldState.seed
        state.lifeItems = [item("secret", "Look into a therapist", visibility: .private)]
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)

        #expect(store.proposeDecision(itemID: "secret") == false)
        #expect(store.chatMessages.isEmpty)
    }
}

// MARK: Links from the + card

@MainActor
struct FieldLinkCaptureTests {
    @Test
    func aPlainSiteDecidesWhereALinkGoes() {
        #expect(FieldLinkReader.category(for: URL(string: "https://www.apple.com/airpods-pro/")!) == .buys)
        #expect(FieldLinkReader.category(for: URL(string: "https://tv.apple.com/show/severance")!) == .watchlist)
        #expect(FieldLinkReader.category(for: URL(string: "https://letterboxd.com/film/past-lives/")!) == .watchlist)
        #expect(FieldLinkReader.category(for: URL(string: "https://cooking.nytimes.com/recipes/1-pasta")!) == .food)
        #expect(FieldLinkReader.category(for: URL(string: "https://www.airbnb.com/rooms/1")!) == .trips)
        // A lookalike is not the store.
        #expect(FieldLinkReader.category(for: URL(string: "https://fakeamazon.com/x")!) == nil)
        #expect(FieldLinkReader.category(for: URL(string: "https://someblog.net/thoughts")!) == nil)
    }

    @Test
    func aSentLinkBecomesALifeItemThatKeepsTheLink() throws {
        var state = FieldState.seed
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)
        let url = URL(string: "https://www.apple.com/airpods-pro/")!

        store.captureDraft = "AirPods Pro 3"
        store.submitCapture()
        store.attachLink(url)
        store.send()

        let item = try #require(store.state.lifeItems.first { $0.sourceURL == url })
        #expect(item.category == .buys)
        #expect(item.title == "AirPods Pro 3")
    }

    @Test
    func aPrivateLinkStaysPrivate() throws {
        var state = FieldState.seed
        state.conversation = []
        let store = FieldStore(state: state, now: FieldSampleData.today)
        let url = URL(string: "https://www.etsy.com/listing/1")!

        store.captureDraft = "Ring for the anniversary"
        store.submitCapture()
        store.attachLink(url)
        store.togglePrivate()
        store.send()

        let item = try #require(store.state.lifeItems.first { $0.sourceURL == url })
        #expect(item.visibility == .private)
        #expect(!item.isSharedPresence)
    }

    @Test
    func aLinkInTheWordsIsFound() {
        #expect(FieldLinkReader.firstLink(in: "look https://muji.us/duvet nice")?.host() == "muji.us")
        #expect(FieldLinkReader.firstLink(in: "call mom sunday") == nil)
    }
}

// MARK: Decision notices

@MainActor
struct FieldDecisionNoticeTests {
    /// Unset reads as on, because the server sends unless someone said no.
    @Test
    func noticesAreOnUntilTurnedOff() async {
        var state = FieldState.seed
        state.chatPreferences = nil
        let store = FieldStore(state: state, now: FieldSampleData.today)
        #expect(store.decisionNoticesOn)

        await store.setDecisionNotices(false)
        #expect(!store.decisionNoticesOn)
    }

    /// Today showing the partner's proposal marks it seen, so the notifier
    /// does not count it as unread.
    @Test
    func aPartnersProposalIsSeenOnceTodayShowsIt() async throws {
        var state = FieldState.seed
        state.chatPreferences = nil
        state.conversation = [
            FieldChatMessage(body: "Tahoe", sender: .b, decision: true)
        ]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        await store.markDecisionsSeen()
        let mine = try #require(store.state.chatPreferences?.first { $0.owner == store.speaker })
        #expect(mine.readAt != nil)
    }
}
