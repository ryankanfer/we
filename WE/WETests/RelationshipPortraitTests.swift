import Testing
import Foundation
@testable import WE

@MainActor struct RelationshipPortraitTests {
    @Test func completionRequiresThreeLettersAndNeverInventsSuffix() {
        #expect(FieldCaptureCompletion.match("Fr", titles: ["Friday pasta"]) == nil)
        #expect(FieldCaptureCompletion.match("Fri", titles: ["Friday pasta"])?.text == "Friday pasta")
        #expect(FieldCaptureCompletion.match("Friday pasta", titles: ["Friday pasta"]) == nil)
        #expect(FieldCaptureCompletion.match("Jap", titles: []) == nil)
    }
    @Test func privateItemsCannotEnterThePortrait() {
        var state = FieldState.empty(nameA: "A", nameB: "B", now: Date())
        state.lifeItems = [LifeItem(id: "private", title: "Private getaway", category: .notes, owner: .a, source: .captured, isTimeCritical: false, isDone: false, visibility: .private)]
        #expect(FieldRelationshipPortrait.concepts(in: state, now: Date()).isEmpty)
    }
    @Test func repetitionAloneDoesNotEstablishAnOpenPlan() {
        var state = FieldState.empty(nameA: "A", nameB: "B", now: Date())
        state.lifeItems = (1...12).map { LifeItem(id: "\($0)", title: "Japan", category: .notes, owner: .shared, source: .captured, isTimeCritical: false, isDone: false) }
        let concepts = FieldRelationshipPortrait.concepts(in: state, now: Date())
        #expect(concepts.count == 1)
        #expect(concepts.first?.territory == .emerging)
    }
}
