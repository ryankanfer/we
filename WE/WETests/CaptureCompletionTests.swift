import Testing
import Foundation
@testable import WE

@MainActor struct CaptureCompletionTests {
    @Test func completionRequiresThreeLettersAndNeverInventsSuffix() {
        #expect(FieldCaptureCompletion.match("Fr", titles: ["Friday pasta"]) == nil)
        #expect(FieldCaptureCompletion.match("Fri", titles: ["Friday pasta"])?.text == "Friday pasta")
        #expect(FieldCaptureCompletion.match("Friday pasta", titles: ["Friday pasta"]) == nil)
        #expect(FieldCaptureCompletion.match("Jap", titles: []) == nil)
    }
}
