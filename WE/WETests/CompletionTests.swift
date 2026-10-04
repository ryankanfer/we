//
//  CompletionTests.swift
//  WETests
//
//  The complete icon that replaced "Mark complete": finishing says the item's
//  own verb, and it can be taken back.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct FieldCompletionTests {
    private func item(_ title: String, _ category: LifeCategory) -> LifeItem {
        LifeItem(
            id: UUID().uuidString, title: title, category: category, owner: .a,
            dueOn: nil, closesAt: nil, clusterID: nil, source: .captured,
            detail: nil, isTimeCritical: false, isDone: false
        )
    }

    @Test
    func finishingSaysTheItemsOwnVerb() {
        #expect(FieldItemPurpose.completionVerb(item("Call mom", .care)) == "Called")
        #expect(FieldItemPurpose.completionVerb(item("Book the vet", .care)) == "Booked")
        #expect(FieldItemPurpose.completionVerb(item("Olive oil", .buys)) == "Bought")
        #expect(FieldItemPurpose.completionVerb(item("Past Lives", .watchlist)) == "Watched")
        #expect(FieldItemPurpose.completionVerb(item("Bermuda", .trips)) == "We went")
        #expect(FieldItemPurpose.completionVerb(item("Air filter", .home)) == "Done")
    }

    @Test
    func aFinishCanBeTakenBack() {
        let task = item("Call mom", .care)
        var state = FieldState.seed
        state.lifeItems.append(task)
        let store = FieldStore(state: state)

        store.complete(task.id)
        #expect(store.state.lifeItems.first { $0.id == task.id }?.isDone == true)

        store.reopen(task.id)
        #expect(store.state.lifeItems.first { $0.id == task.id }?.isDone == false)
    }

    @Test
    func reopeningSomethingOpenChangesNothing() {
        let task = item("Call mom", .care)
        var state = FieldState.seed
        state.lifeItems.append(task)
        let store = FieldStore(state: state)

        store.reopen(task.id)
        #expect(store.state.lifeItems.first { $0.id == task.id }?.isDone == false)
    }

    /// Only me is held until a day, and WE asks then. The button says that.
    @Test
    func holdingAsksRatherThanShares() {
        #expect(WEOnlyMeCopy.holdPrompt == "Ask me on a day")
    }
}
