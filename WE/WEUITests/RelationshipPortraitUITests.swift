import XCTest

final class RelationshipPortraitUITests: XCTestCase {
    @MainActor func testPortraitEvidenceAndGlassCapture() {
        continueAfterFailure = false
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app)
        app.launchEnvironment["WE_FIELD"] = "seeded"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["field.nav.us"].waitForExistence(timeout: 15))
        app.buttons["field.nav.us"].tap()
        XCTAssertTrue(app.staticTexts["SO US"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "us.relationship-portrait")
        let concept = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "field.us.concept.")).firstMatch
        XCTAssertTrue(concept.exists); concept.tap()
        XCTAssertTrue(app.staticTexts["What connects it"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["field.nav.we"].tap()
        app.buttons["field.capture.open"].tap()
        XCTAssertTrue(app.textViews["field.capture.input"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "capture.glass-panel")
        let input = app.textViews["field.capture.input"]
        input.tap()
        if let existing = input.value as? String, !existing.isEmpty { input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)) }
        input.typeText("Jap")
        let completion = app.buttons["field.capture.completion"]
        for _ in 0..<3 where !completion.isHittable { app.swipeUp() }
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "capture.ghost-completion")
        completion.tap()
        XCTAssertTrue((input.value as? String)?.hasPrefix("Japan") == true)
    }
}
