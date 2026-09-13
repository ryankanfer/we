import XCTest

final class IntelligenceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app, maximumDynamicType: large)
        app.launchEnvironment["WE_FIELD"] = "seeded"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_INTELLIGENCE_PREVIEW"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["Saved in Life"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor func testPrivateCaptureSurvivesTerminationAndIsSearchable() {
        var app = launch()
        let title = "Durability example \(UUID().uuidString.prefix(8))"
        app.buttons["Bring it in"].tap()
        let text = app.textFields["intelligence.capture.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText(title)
        app.buttons["intelligence.capture.save"].tap()
        XCTAssertTrue(app.navigationBars["Saved in Life"].waitForExistence(timeout: 5))
        app.terminate()
        app = launch()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText(title)
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only Me"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Why this?"].firstMatch.exists)
        keepScreenshot(of: app, named: "intelligence.private-search")
    }

    @MainActor func testRecoveryAndSourceReviewAtLargestType() {
        let app = launch(large: true)
        let recovery = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Needs attention")).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 5)); recovery.tap()
        XCTAssertTrue(app.navigationBars["Needs attention"].waitForExistence(timeout: 5))
        let open = app.buttons["Open and review"].firstMatch
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(app.navigationBars["Saved item"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only Me"].firstMatch.exists)
        keepScreenshot(of: app, named: "intelligence.recovery.accessibility5")
    }
}
