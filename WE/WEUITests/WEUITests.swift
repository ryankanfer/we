import XCTest

final class WEUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Keep authentication ahead of deletion tests. iOS can retain its
    // password-saving view service between UI test cases after deletion.
    @MainActor
    func testAAuthRecoveryPairingAndHueRoutes() throws {
        var app = launch(scenario: "signedout")
        XCTAssertTrue(
            app.staticTexts["Welcome back."].waitForExistence(timeout: 4)
        )

        app.buttons["Forgot password?"].tap()
        XCTAssertTrue(
            app.navigationBars["Password reset"]
                .waitForExistence(timeout: 2)
        )
        app.buttons["Done"].tap()

        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("ryan@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("password")
        app.buttons["accountSubmitButton"].tap()

        XCTAssertTrue(
            app.staticTexts["Your side is ready."]
                .waitForExistence(timeout: 3)
        )
        let createSpace = app.buttons["Create an invitation"]
        createSpace.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "invitation is at"
                )
            ).firstMatch
                .waitForExistence(timeout: 3)
        )

        // Hue choice is 6f now — colour, three questions, and a calendar,
        // drawn in the zones' language rather than the old picker's.
        app.terminate()
        app = launch(scenario: "choosinghue")
        XCTAssertTrue(
            app.staticTexts["Choose a colour each."]
                .waitForExistence(timeout: 6)
        )
        app.buttons["field.onboarding.finish"].tap()
        XCTAssertTrue(
            app.buttons["field.nav.we"].waitForExistence(timeout: 8)
        )
    }


    @MainActor
    func testAccountDeletionIsReachableBeforeAndDuringPairing() throws {
        for scenario in ["archived", "waiting"] {
            let app = launch(scenario: scenario)
            XCTAssertTrue(
                app.buttons["accountButton"].waitForExistence(timeout: 4)
            )
            app.buttons["accountButton"].tap()
            XCTAssertTrue(
                app.navigationBars["Profile"].waitForExistence(timeout: 2)
            )
            deleteCurrentPreviewAccount(in: app)
            XCTAssertTrue(
                app.staticTexts["Welcome back."]
                    .waitForExistence(timeout: 4)
            )
            app.terminate()
        }
    }

    @MainActor
    func testLivingConfluencePromiseSupportsReducedMotion() throws {
        let app = launch(
            scenario: "waiting",
            skipsPromise: false,
            reduceMotion: true
        )

        XCTAssertTrue(
            app.staticTexts["Yours stays yours."]
                .waitForExistence(timeout: 4)
        )
        app.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["You see what crosses."].exists
        )
        app.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["Shared is a new space."].exists
        )
        app.buttons["Enter WE"].tap()
        // What this test is about is that all three panels are reachable and
        // dismissable with Reduce Motion on. Where it lands afterwards
        // depends on the session state and belongs to other tests.
        let firstPanel = app.staticTexts["Yours stays yours."]
        XCTAssertTrue(
            firstPanel.waitForNonExistence(timeout: 4),
            "the Promise should be gone once it has been entered"
        )
    }

    @MainActor
    func testTrustPromiseAndInvitationRemainReachableAtAccessibilityTextSize()
        throws
    {
        let promiseApp = launch(
            scenario: "waiting",
            skipsPromise: false,
            accessibilityTextSize: true
        )

        for expectedTitle in [
            "Yours stays yours.",
            "You see what crosses.",
        ] {
            XCTAssertTrue(
                promiseApp.staticTexts[expectedTitle]
                    .waitForExistence(timeout: 4)
            )
            let continueButton = promiseApp.buttons["Continue"]
            scrollUntilVisible(continueButton, in: promiseApp, maxSwipes: 8)
            XCTAssertTrue(continueButton.isHittable)
            continueButton.tap()
        }

        XCTAssertTrue(
            promiseApp.staticTexts["Shared is a new space."]
                .waitForExistence(timeout: 4)
        )
        let enterButton = promiseApp.buttons["Enter WE"]
        scrollUntilVisible(enterButton, in: promiseApp, maxSwipes: 8)
        XCTAssertTrue(enterButton.isHittable)
        promiseApp.terminate()

        let waitingApp = launch(
            scenario: "waiting",
            accessibilityTextSize: true
        )
        let sendButton = waitingApp.buttons["Send the invitation"]
        scrollUntilVisible(sendButton, in: waitingApp, maxSwipes: 10)
        XCTAssertTrue(sendButton.isHittable)
        let copyButton = waitingApp.buttons["Copy"]
        scrollUntilVisible(copyButton, in: waitingApp, maxSwipes: 4)
        XCTAssertTrue(copyButton.isHittable)
    }

    @MainActor
    func testSoftStartDeliversValueBeforeAccountAndPreviewsExactOffer()
        throws
    {
        let app = launch(
            scenario: "signedout",
            skipsSoftStart: false
        )
        resetSoftStartIfNeeded(in: app)

        let privateInput = app.textViews["softStart.input"]
        XCTAssertTrue(privateInput.waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Begin with"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(app.textFields["Email"].exists)

        let privateNote = "I would love a quieter Friday evening."
        privateInput.tap()
        privateInput.typeText(privateNote)
        app.buttons["softStart.prepare"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "One thing you"
                )
            ).firstMatch.waitForExistence(timeout: 12)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "Prepared on this iPhone"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(app.textFields["Email"].exists)

        app.buttons["proposal.offer"].tap()
        XCTAssertTrue(
            app.staticTexts["Offer only this"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["A quieter Friday"].exists)
        XCTAssertTrue(app.staticTexts["How should Friday feel?"].exists)
        XCTAssertTrue(app.staticTexts["Quiet · Open · Social"].exists)
        XCTAssertFalse(app.textViews[privateNote].exists)

        app.buttons["offer.confirm"].tap()
        XCTAssertTrue(
            app.staticTexts["Welcome back."]
                .waitForExistence(timeout: 3)
        )
    }


    @MainActor
    private func scrollUntilVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4
    ) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    private func launch(
        scenario: String,
        skipsPromise: Bool = true,
        reduceMotion: Bool = false,
        skipsSoftStart: Bool = true,
        accessibilityTextSize: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = scenario
        app.launchEnvironment["WE_PREVIEW_DELETION_PASSWORD"] =
            "correct-password"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = skipsPromise ? "1" : "0"
        app.launchEnvironment["WE_SKIP_SOFT_START"] =
            skipsSoftStart ? "1" : "0"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", skipsPromise ? "YES" : "NO",
            "-UIAccessibilityReduceMotionEnabled",
            reduceMotion ? "YES" : "NO"
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

    @MainActor
    private func resetSoftStartIfNeeded(in app: XCUIApplication) {
        if app.buttons["offer.confirm"].waitForExistence(timeout: 1) {
            app.buttons["Your proposal"].tap()
        }

        if app.buttons["proposal.keep"].waitForExistence(timeout: 1) {
            app.buttons["Delete and start again"].tap()
            app.sheets.buttons["Delete and start again"].tap()
        }
    }

    @MainActor
    private func deleteCurrentPreviewAccount(in app: XCUIApplication) {
        openDeleteAccount(in: app)
        app.secureTextFields["Current password"].tap()
        app.secureTextFields["Current password"]
            .typeText("correct-password")
        app.textFields["Type DELETE"].tap()
        app.textFields["Type DELETE"].typeText("DELETE")
        app.buttons["Delete my account"].tap()
        app.buttons["Delete permanently"].tap()
    }

    @MainActor
    private func openDeleteAccount(in app: XCUIApplication) {
        let deleteButton = app.buttons["Delete account…"]
        for _ in 0..<4 where !deleteButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()
    }

}
