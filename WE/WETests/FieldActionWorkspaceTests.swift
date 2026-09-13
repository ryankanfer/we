import Foundation
import Testing
@testable import WE

@MainActor
struct FieldActionWorkspaceTests {
    private func makeItem(title: String = "Decide dinner", id: String = "decision", category: LifeCategory = .food) -> LifeItem {
        LifeItem(id: id, title: title, category: category, owner: .shared,
                 dueOn: Date(timeIntervalSince1970: 1800000000), closesAt: nil,
                 clusterID: nil, source: .captured, detail: "Keep the existing context.",
                 isTimeCritical: false, isDone: false, visibility: .private)
    }

    private func makeStore(_ item: LifeItem) -> FieldStore {
        var state = FieldState.empty(nameA: "Alex", nameB: "Sam", now: Date())
        state.lifeItems = [item]
        return FieldStore(state: state)
    }

    @Test func decisionBecomesPlanWithoutCompletingOrChangingVisibility() {
        let item = makeItem()
        let store = makeStore(item)
        #expect(store.saveDecision(on: item.id, choice: "Thai takeout"))
        let saved = store.state.lifeItems[0]
        #expect(saved.title == "Dinner — Thai takeout")
        #expect(saved.detail?.contains("Keep the existing context.") == true)
        #expect(saved.detail?.contains("Thai takeout") == true)
        #expect(saved.dueOn == item.dueOn)
        #expect(saved.visibility == .private)
        #expect(saved.owner == item.owner)
        #expect(!saved.isDone)
        #expect(FieldItemPurpose.resolve(saved) == .task)
    }

    @Test func invalidDecisionLeavesItemUntouched() {
        let item = makeItem()
        let store = makeStore(item)
        #expect(!store.saveDecision(on: item.id, choice: "  \n"))
        #expect(!store.saveDecision(on: item.id, choice: String(repeating: "a", count: 241)))
        #expect(store.state.lifeItems[0] == item)
    }

    @Test func existingPlanCannotBeOverwrittenAsDecision() {
        let item = makeItem(title: "Dinner at home")
        let store = makeStore(item)
        #expect(!store.saveDecision(on: item.id, choice: "Go out"))
        #expect(store.state.lifeItems[0] == item)
    }

    @Test func notesAppendWithoutCompletingItem() {
        let item = makeItem(title: "Clear the guest room")
        let store = makeStore(item)
        #expect(store.saveNextStep(on: item.id, note: "Start with the desk."))
        #expect(store.state.lifeItems[0].detail == "Keep the existing context.\n\nStart with the desk.")
        #expect(!store.state.lifeItems[0].isDone)
    }

    @Test func missingActionDestinationNeverCompletesItem() async {
        let item = makeItem(title: "Something to arrange")
        let store = makeStore(item)
        await store.begin(.none, for: item.id)
        #expect(!store.state.lifeItems[0].isDone)
        #expect(store.itemSaveError != nil)
    }

    @Test func decisionMatchingUsesWholeLeadingWords() {
        #expect(FieldItemPurpose.resolve(makeItem(title: "Choose dinner")) == .decision)
        #expect(FieldItemPurpose.resolve(makeItem(title: "Pickup groceries")) == .task)
        #expect(FieldItemPurpose.resolve(makeItem(title: "Call the decision desk")) == .task)
    }
}
