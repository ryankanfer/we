//
//  WalkthroughUITests.swift
//  WEUITests
//
//  The walkthrough's whole job is to be read. These tests cover the parts a
//  running app can answer: presentation, reachability, explicit navigation,
//  and whether the last button actually finishes.
//

import XCTest

final class WalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: When it plays

    @MainActor
    func testItPlaysOnceOnAFirstRunAndNotAgain() throws {
        let app = launchIntoWalkthrough()
        XCTAssertTrue(
            app.buttons["walkthrough.next"].waitForExistence(timeout: 5)
        )

        app.buttons["walkthrough.skip"].tap()
        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 4),
            "Dismissing the walkthrough should leave the welcome screen"
        )

        app.terminate()
        let second = XCUIApplication()
        second.launchEnvironment["WE_REPOSITORY"] = "preview"
        second.launchEnvironment["WE_PREVIEW_SCENARIO"] = "signedout"
        second.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        second.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        second.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
        ]
        second.launch()

        XCTAssertTrue(
            second.buttons["welcome.start"].waitForExistence(timeout: 5),
            "The walkthrough should not play a second time"
        )
        XCTAssertFalse(
            second.buttons["walkthrough.next"].exists,
            "The orientation should not be up on a second run"
        )
    }

    // MARK: The three spaces

    @MainActor
    func testEveryScreenIsExplicitAndCanBeReadToTheEnd() throws {
        let app = launchIntoWalkthrough()
        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let submit = app.buttons["field.capture.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
        let save = app.buttons["field.receipt.send"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let item = app.buttons["walkthrough.savedItem"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let done = app.buttons["field.item.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["Life together.\nSpace for yourself."].waitForExistence(timeout: 5))
        next.tap()

        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 4),
            "Finishing should hand the screen back"
        )
    }

    @MainActor
    func testTodayExplainsHowToMoveAndComeHome() throws {
        let app = launchIntoWalkthrough()

        XCTAssertTrue(
            app.staticTexts[
                "Make room for\nthe good part."
            ].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testBackNavigationAndSpaceOverview() throws {
        let app = launchIntoWalkthrough()
        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        app.buttons["field.capture.submit"].tap()
        XCTAssertTrue(app.staticTexts["You decide what\ngets saved."].waitForExistence(timeout: 5))
        app.buttons["walkthrough.back"].tap()
        XCTAssertTrue(app.textViews["field.capture.input"].waitForExistence(timeout: 5))
        app.buttons["field.capture.submit"].tap()
        app.buttons["field.receipt.dismiss"].tap()
        XCTAssertTrue(app.staticTexts["Start with\na thought."].waitForExistence(timeout: 5))
        app.buttons["walkthrough.back"].tap()
        next.tap()
        app.buttons["field.capture.submit"].tap()
        let save = app.buttons["field.receipt.send"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        // Opening the example is optional: the visible way forward stays enabled.
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        app.buttons["walkthrough.space.0"].tap()
        XCTAssertTrue(app.staticTexts["Keep the details close."].exists)
        app.buttons["walkthrough.space.2"].tap()
        XCTAssertTrue(app.staticTexts["Choose what comes next, together."].exists)
        app.buttons["walkthrough.back"].tap()
        XCTAssertTrue(app.buttons["walkthrough.savedItem"].exists)
        app.buttons["walkthrough.skip"].tap()
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 5))
    }

    // MARK: Reachable

    @MainActor
    func testTodayPassesTheAuditAtAccessibilityTextSize() throws {
        let app = launchIntoWalkthrough(accessibilityTextSize: true)
        XCTAssertTrue(
            app.buttons["walkthrough.next"].waitForExistence(timeout: 5)
        )

        try app.performAccessibilityAudit(
            for: [
                .hitRegion,
                .sufficientElementDescription,
                .textClipped,
                .trait,
            ]
        )
    }

    /// Us is the densest screen — two examples, a question, and two answers —
    /// and therefore the one most likely to clip at AX5.
    @MainActor
    func testUsPassesTheAuditAtAccessibilityTextSize() throws {
        let app = launchIntoWalkthrough(accessibilityTextSize: true)
        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.textViews["field.capture.input"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .textClipped]
        )
    }

    // MARK: -

    /// A first run, signed out, with the promise out of the way — the one
    /// state `WalkthroughGate` opens in.
    @MainActor
    private func launchIntoWalkthrough(
        accessibilityTextSize: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "signedout"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "0"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
            "-hasSeenWalkthrough", "NO",
        ]
        if accessibilityTextSize {
            app.launchEnvironment["WE_TEST_DYNAMIC_TYPE"] = "accessibility5"
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        }
        app.launch()
        return app
    }
}
