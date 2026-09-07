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
        next.tap()
        let item = app.buttons["walkthrough.savedItem"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let done = app.buttons["field.item.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["Space for you. Room for both."].waitForExistence(timeout: 5))
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
                "Put a thought down. See where it goes. Find it when you need it."
            ].waitForExistence(timeout: 5)
        )
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
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        }
        app.launch()
        return app
    }
}
