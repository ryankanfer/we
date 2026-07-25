//
//  WETests.swift
//  WETests
//
//  Created by Ryan Kanfer on 7/24/26.
//

import Testing
@testable import WE

@MainActor
struct WETests {
    @Test
    func happyPathRevealsBothAnswersTogether() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 1)

        #expect(state.readiness == .requested)
        #expect(TrustCore.project(state, for: "ry")?.phase == .waiting)
        #expect(TrustCore.project(state, for: "dylan")?.phase == .invited)

        state = try TrustCore.acceptReveal(state, by: "dylan", at: 2)
        #expect(state.visibility == .mutual)

        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Keep it",
            note: "I want the time away with you."
        )

        let dylanView = TrustCore.project(state, for: "dylan")
        #expect(dylanView?.partnerResponse == nil)
        #expect(dylanView?.phase == .answering)
        #expect(TrustCore.project(state, for: "ry")?.phase == .held)

        state = try TrustCore.submitResponse(
            state,
            by: "dylan",
            choice: "Keep it"
        )

        #expect(state.responses["ry"]?.status == .revealed)
        #expect(state.responses["dylan"]?.status == .revealed)
        #expect(TrustCore.answersMatch(state) == true)
        #expect(
            TrustCore.project(state, for: "dylan")?.partnerResponse?.note
                == "I want the time away with you."
        )
    }

    @Test
    func mismatchDoesNotDecideAnything() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        state = try TrustCore.acceptReveal(state, by: "dylan", at: 1)
        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Keep it"
        )
        state = try TrustCore.submitResponse(
            state,
            by: "dylan",
            choice: "Change it"
        )

        #expect(TrustCore.answersMatch(state) == false)
        #expect(state.resolution == nil)

        state = try TrustCore.resolve(
            state,
            type: .leftOpen,
            at: 2
        )
        #expect(state.resolution?.type == .leftOpen)
    }

    @Test
    func oneAnswerIsNeverProjectedBeforeBothSubmit() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "dylan", at: 0)
        state = try TrustCore.acceptReveal(state, by: "ry", at: 1)
        state = try TrustCore.saveDraft(
            state,
            by: "ry",
            choice: "Change it",
            note: "a private draft"
        )
        #expect(
            TrustCore.project(state, for: "dylan")?.partnerResponse == nil
        )

        state = try TrustCore.submitResponse(
            state,
            by: "ry",
            choice: "Change it",
            note: "a private note"
        )
        #expect(
            TrustCore.project(state, for: "dylan")?.partnerResponse == nil
        )
    }

    @Test
    func declineStaysPrivate() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        let before = TrustCore.project(state, for: "ry")

        state = try TrustCore.declineReveal(state, by: "dylan")
        let after = TrustCore.project(state, for: "ry")

        #expect(after?.phase == before?.phase)
        #expect(after?.phase == .waiting)

        state = try TrustCore.acceptReveal(state, by: "dylan", at: 5)
        #expect(state.visibility == .mutual)
    }

    @Test
    func withdrawalLeavesNoPartnerTrace() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.requestReveal(state, by: "ry", at: 0)
        state = try TrustCore.withdrawReveal(state, by: "ry")

        let dylanView = TrustCore.project(state, for: "dylan")
        #expect(dylanView?.phase == .open)
        #expect(dylanView?.initiatorID == nil)
        #expect(dylanView?.requestedAt == nil)
    }

    @Test
    func privateItemsStayHiddenFromNonOwner() {
        let state = TrustCore.initialState(
            visibility: .private,
            ownerID: "ry"
        )
        #expect(TrustCore.project(state, for: "dylan") == nil)
        #expect(TrustCore.project(state, for: "ry") != nil)
    }

    @Test
    func invalidTransitionsThrow() throws {
        var state = TrustCore.initialState()

        #expect(throws: TrustTransitionError.self) {
            try TrustCore.acceptReveal(state, by: "dylan", at: 0)
        }
        #expect(throws: TrustTransitionError.self) {
            try TrustCore.submitResponse(
                state,
                by: "ry",
                choice: "Keep it"
            )
        }

        state = try TrustCore.requestReveal(state, by: "ry", at: 0)

        #expect(throws: TrustTransitionError.self) {
            try TrustCore.acceptReveal(state, by: "ry", at: 1)
        }
        #expect(throws: TrustTransitionError.self) {
            try TrustCore.withdrawReveal(state, by: "dylan")
        }
        #expect(throws: TrustTransitionError.self) {
            try TrustCore.dismissSuggestion(state, by: "dylan")
        }
    }

    @Test
    func dismissalIsIndividual() throws {
        var state = TrustCore.initialState()
        state = try TrustCore.dismissSuggestion(state, by: "ry")

        #expect(TrustCore.project(state, for: "ry")?.dismissed == true)
        #expect(TrustCore.project(state, for: "dylan")?.dismissed == false)
    }
}
