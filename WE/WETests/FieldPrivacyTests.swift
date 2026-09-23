//
//  FieldPrivacyTests.swift
//  WETests
//
//  "Only me": privacy as a property of one item, chosen on the receipt.
//  The database half is `supabase/tests/private_by_choice.test.sql`; this is
//  the device half — what `send()` marks, what it refuses to infer, and what
//  a shared derivation is allowed to read.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct FieldPrivacyTests {
    private func file(_ text: String, privately: Bool, in store: FieldStore) {
        store.captureDraft = text
        store.submitCapture()
        if privately { store.togglePrivate() }
        store.send()
    }

    @Test
    func filingIsSharedUnlessSomebodyAsks() throws {
        let store = FieldStore()
        file("buy a new kettle", privately: false, in: store)

        let item = try #require(store.state.lifeItems.first)
        #expect(item.visibility != .private)
        #expect(store.state.captures.first?.visibility != .private)
    }

    @Test
    func onlyMeMarksTheItemAndItsCapture() throws {
        let store = FieldStore()
        file("look into a therapist", privately: true, in: store)

        let item = try #require(store.state.lifeItems.first)
        #expect(item.visibility == .private)
        #expect(item.isSharedPresence == false)

        let capture = try #require(store.state.captures.first)
        #expect(capture.id == item.id)
        #expect(capture.visibility == .private)
    }

    /// Turning it on and off again before Send leaves nothing behind.
    @Test
    func theToggleIsOnlyAboutTheReceiptOnScreen() throws {
        let store = FieldStore()
        store.captureDraft = "buy a new kettle"
        store.submitCapture()
        store.togglePrivate()
        store.togglePrivate()
        #expect(store.lastReceipt?.isPrivate == false)
        store.send()
        #expect(store.state.lifeItems.first?.visibility != .private)
    }

    /// A correction carries the words that were typed, so it is exactly as
    /// private as the item — even when "Only me" was turned on after it.
    @Test
    func aCorrectionOnAPrivateReceiptIsPrivate() async throws {
        let backend = FieldMemoryBackend()
        let store = FieldStore(now: FieldSampleData.today, backend: backend)
        store.captureDraft = "look into a therapist"
        store.submitCapture()
        store.beginCorrection()
        store.correct(to: .notes)
        store.togglePrivate()
        store.send()

        #expect(store.state.lifeItems.first?.category == .notes)
        #expect(store.state.lifeItems.first?.visibility == .private)

        // The writes leave on a Task; wait for them to land rather than
        // asserting on a race.
        var sent = try await backend.load()
        for _ in 0..<100 where sent.corrections.isEmpty
            || !sent.lifeItems.contains(where: { $0.visibility == .private }) {
            try await Task.sleep(for: .milliseconds(20))
            sent = try await backend.load()
        }
        let correction = try #require(
            sent.corrections.last { $0.input == "look into a therapist" }
        )
        #expect(correction.visibility == .private)
        #expect(sent.captures.first?.visibility == .private)
    }

    /// Never "both added it" for a private thing: that would tell this person
    /// something about the partner's list by way of their own, and would make
    /// a private item shared-owned.
    @Test
    func aPrivateThingIsNeverMatchedWithThePartners() throws {
        var state = FieldState.seed
        state.lifeItems = [
            LifeItem(
                id: "partner-kettle",
                title: "Buy a new kettle",
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
        let store = FieldStore(state: state, now: FieldSampleData.today)
        store.captureDraft = "Buy a new kettle"
        store.submitCapture()
        store.togglePrivate()
        store.send()

        let filed = try #require(
            store.state.lifeItems.first { $0.id != "partner-kettle" }
        )
        #expect(filed.owner == store.speaker)
        #expect(filed.detail == nil)
    }

    @Test
    func sharingIsOneWay() throws {
        let store = FieldStore()
        file("look into a therapist", privately: true, in: store)
        let id = try #require(store.state.lifeItems.first?.id)

        store.share(id)
        #expect(store.state.lifeItems.first?.visibility == .shared)
        #expect(store.state.captures.first?.visibility == .shared)

        // Nothing on the store offers the reverse, and calling share again on
        // a shared thing changes nothing.
        store.share(id)
        #expect(store.state.lifeItems.first?.visibility == .shared)
    }

    /// The derivations that bring something new into existence for both
    /// people must not read a private row. Two private mentions of Japan are
    /// not a horizon; the same two, shared, are.
    @Test
    func aPrivateThingNeverProposesAHorizon() {
        func trip(_ id: String, _ title: String, _ visibility: FieldVisibility?) -> LifeItem {
            LifeItem(
                id: id,
                title: title,
                category: .trips,
                owner: .a,
                dueOn: nil,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false,
                visibility: visibility
            )
        }

        var state = FieldState.seed
        state.horizons = []
        state.heldTopics = []

        state.lifeItems = [
            trip("a", "Japan in the fall", .private),
            trip("b", "Japan — the Kyoto leg", .private),
        ]
        #expect(FieldStore(state: state, now: FieldSampleData.today).promotionProposal == nil)

        state.lifeItems = [
            trip("a", "Japan in the fall", .shared),
            trip("b", "Japan — the Kyoto leg", .shared),
        ]
        #expect(FieldStore(state: state, now: FieldSampleData.today).promotionProposal != nil)
    }

    /// A row cached before visibility existed decodes as unknown, and unknown
    /// is never sent as a value — see `FieldSupabaseBackend.upsert(_ item:)`.
    @Test
    func aCaptureCachedBeforeVisibilityStillDecodes() throws {
        let json = #"{"id":"c1","text":"steak","owner":"a","capturedAt":0}"#
        let capture = try JSONDecoder().decode(
            FieldCapture.self,
            from: Data(json.utf8)
        )
        #expect(capture.visibility == nil)
    }
}
