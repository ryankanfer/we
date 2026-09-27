import Foundation
import Testing
@testable import WE

@MainActor
struct FieldGoalTests {
    func item(_ title: String, visibility: FieldVisibility = .shared) -> LifeItem {
        LifeItem(id: UUID().uuidString, title: title, category: .trips, owner: .shared,
                 dueOn: nil, closesAt: nil, clusterID: nil, source: .captured,
                 detail: nil, isTimeCritical: false, isDone: false, visibility: visibility)
    }
    func goal() -> FieldHorizon {
        FieldHorizon(goalPlan: .init(kind: .trip), id: UUID().uuidString, title: "Japan trip", window: nil, owner: .shared, isPrimary: false, thesis: nil, targetDate: nil, linkedLifeItemIDs: [], openQuestion: nil)
    }
    @Test func needsDistinctSharedEvidence() {
        let items = [item("Flights to Japan"), item("Kyoto hotel ideas"), item("Tokyo trip next spring")]
        #expect(FieldGoalSuggestions.suggestions(items: items, goals: []).first?.id == "japan")
        #expect(FieldGoalSuggestions.suggestions(items: Array(items.prefix(2)), goals: []).isEmpty)
        #expect(FieldGoalSuggestions.suggestions(items: [items[0], item("Flights to Japan"), item("Flights to Japan")], goals: []).isEmpty)
    }
    @Test func privateContentNeverContributes() {
        let items = [item("Flights to Japan"), item("Kyoto hotel ideas"), item("Tokyo trip next spring", visibility: .private)]
        #expect(FieldGoalSuggestions.suggestions(items: items, goals: []).isEmpty)
    }
    @Test func evidenceAttachesToExistingGoalWithoutDuplicate() {
        var goal = goal()
        let items = [item("Flights to Japan"), item("Kyoto hotel ideas"), item("Tokyo trip next spring")]
        let suggestion = FieldGoalSuggestions.suggestions(items: items, goals: [goal]).first
        #expect(suggestion?.existingGoalID == goal.id)
        goal.linkedLifeItemIDs = items.map(\.id)
        #expect(FieldGoalSuggestions.suggestions(items: items, goals: [goal]).isEmpty)
    }
    @Test func negativesAndExistingDogCareAreNotAspirations() {
        #expect(FieldGoalSuggestions.topics("Don't want a Japan trip", category: .trips).isEmpty)
        #expect(FieldGoalSuggestions.topics("Walk the dog", category: .home).isEmpty)
        #expect(FieldGoalSuggestions.topics("Could we adopt a dog?", category: .home).contains("getting a dog"))
    }
    @Test func agreementRequiresTwoDifferentPeople() {
        var plan = FieldGoalPlan()
        plan.approvedOwners = [.a, .a, .shared]
        #expect(!plan.isBuilding)
        plan.approvedOwners.append(.b)
        #expect(plan.isBuilding)
    }
    @Test func nextStepPersistsLinkAndCanBeOpenedInLife() {
        let goal = goal()
        var state = FieldState.empty(nameA: "Alex", nameB: "Sam", now: Date())
        state.horizons = [goal]
        let store = FieldStore(state: state)
        #expect(store.addGoalTask(goalID: goal.id, title: "Compare flight dates"))
        #expect(store.state.horizons[0].linkedLifeItemIDs == [store.state.lifeItems[0].id])
        #expect(store.state.lifeItems[0].isSharedPresence)
        #expect(!store.state.lifeItems[0].isDone)
        #expect(store.state.lifeItems[0].category == .trips)
        #expect(FieldItemPurpose.resolve(store.state.lifeItems[0]) == .task)
    }
    @Test func oneAgreementDoesNotCommitAndCanBeWithdrawn() async {
        var state = FieldState.empty(nameA: "Alex", nameB: "Sam", now: Date())
        let goal = goal(); state.horizons = [goal]
        let store = FieldStore(state: state)
        await store.approveGoal(goal.id)
        #expect(store.state.horizons[0].goalPlan?.approvedOwners == [.a])
        #expect(store.state.horizons[0].goalPlan?.isBuilding == false)
        await store.approveGoal(goal.id, approved: false)
        #expect(store.state.horizons[0].goalPlan?.approvedOwners.isEmpty == true)
    }
    @Test func invalidProgressDoesNotSave() {
        var goal = goal(); goal.goalPlan?.saved = -1
        let store = FieldStore(state: .empty(nameA: "Alex", nameB: "Sam", now: Date()))
        #expect(!store.saveGoal(goal))
        #expect(store.state.horizons.isEmpty)
    }
    @Test func legacyHorizonDecodesWithoutGoalPlan() throws {
        let data = try JSONEncoder().encode(goal())
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "goalPlan")
        let legacy = try JSONDecoder().decode(FieldHorizon.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.goalPlan == nil)
    }
}
