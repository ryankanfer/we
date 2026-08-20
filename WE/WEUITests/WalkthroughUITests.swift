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
        let expected: [(button: String, progress: String)] = [
            ("Next: Life", "Step 1 of 3"),
            ("Next: Us", "Step 2 of 3"),
            ("Open WE", "Step 3 of 3"),
        ]

        for (index, screen) in expected.enumerated() {
            let button = index == expected.count - 1
                ? app.buttons["walkthrough.done"]
                : app.buttons["walkthrough.next"]

            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertEqual(button.label, screen.button)
            XCTAssertTrue(app.buttons["walkthrough.skip"].exists)
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.navigation"]
                    .exists
            )
            XCTAssertEqual(
                app.descendants(matching: .any)["walkthrough.progress"].label,
                screen.progress
            )
            button.tap()
        }

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
                "Swipe or tap LIFE and US. Tap WE to come home."
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
        XCTAssertTrue(next.waitForExistence(timeout: 4))
        next.tap()

        XCTAssertTrue(
            app.buttons["walkthrough.done"].waitForExistence(timeout: 4)
        )
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
