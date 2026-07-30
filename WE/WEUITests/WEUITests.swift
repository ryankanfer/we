import XCTest

final class WEUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryNavigationContextualCreationAndProfile() throws {
        let app = launch(scenario: "empty")

        XCTAssertTrue(
            app.buttons["primaryTab.Today"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["primaryTab.Life"].exists)
        XCTAssertTrue(app.buttons["primaryTab.Us"].exists)
        let addHorizon = app.buttons["Add something ahead"]
        scrollUntilVisible(addHorizon, in: app)
        XCTAssertTrue(addHorizon.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Something coming up?"].exists)
        addHorizon.tap()
        XCTAssertTrue(app.staticTexts["THE HORIZON"].exists)
        app.textFields["What are you hoping toward?"].tap()
        app.textFields["What are you hoping toward?"]
            .typeText("Saturday's party")
        app.buttons["Add Something Ahead"].tap()

        app.buttons["primaryTab.Life"].tap()
        XCTAssertTrue(
            app.staticTexts["Nothing is asking for a place yet."]
                .waitForExistence(timeout: 2)
        )
        app.buttons["Name some care"].tap()
        XCTAssertTrue(app.staticTexts["THE CARE"].exists)
        app.buttons["Cancel"].tap()

        app.buttons["Open shared horizons"].tap()
        app.navigationBars["Ahead"].buttons["Add something ahead"].tap()
        XCTAssertTrue(app.staticTexts["THE HORIZON"].exists)
        app.buttons["Cancel"].tap()

        app.buttons["profileButton"].tap()
        XCTAssertTrue(
            app.navigationBars["Profile"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.buttons["Replay the Living Confluence Promise"].exists
        )
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

        app.terminate()
        app = launch(scenario: "choosinghue")
        XCTAssertTrue(
            app.staticTexts["Choose yours."].waitForExistence(timeout: 4)
        )
        app.buttons["Make it mine"].tap()
        XCTAssertTrue(app.buttons["Enter WE"].waitForExistence(timeout: 2))
        app.buttons["Enter WE"].tap()
        XCTAssertTrue(
            app.buttons["primaryTab.Today"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testOfflineErrorWaitingAndArchivedStates() throws {
        var app = launch(scenario: "offline")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Offline")
            ).firstMatch.waitForExistence(timeout: 4)
        )

        app.terminate()
        app = launch(scenario: "error")
        XCTAssertTrue(
            app.staticTexts["WE could not load."].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["Continue"].exists)

        app.terminate()
        app = launch(scenario: "waiting")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "invitation is at"
                )
            ).firstMatch
                .waitForExistence(timeout: 4)
        )

        app.terminate()
        app = launch(scenario: "archived")
        XCTAssertTrue(
            app.staticTexts["Past relationships"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["View read-only archive"].exists)
    }

    @MainActor
    func testPasswordConfirmedAccountDeletion() throws {
        let app = launch(scenario: "ready")
        XCTAssertTrue(
            app.buttons["profileButton"].waitForExistence(timeout: 4)
        )
        app.buttons["profileButton"].tap()
        openDeleteAccount(in: app)

        app.secureTextFields["Current password"].tap()
        app.secureTextFields["Current password"].typeText("wrong-password")
        app.textFields["Type DELETE"].tap()
        app.textFields["Type DELETE"].typeText("DELETE")
        app.buttons["Delete my account"].tap()
        app.buttons["Delete permanently"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "invalid password"
                )
            ).firstMatch.waitForExistence(timeout: 3)
        )

        let password = app.secureTextFields["Current password"]
        password.tap()
        password.press(forDuration: 1)
        app.menuItems["Select All"].tap()
        password.typeText("correct-password")
        app.buttons["Delete my account"].tap()
        app.buttons["Delete permanently"].tap()

        XCTAssertTrue(
            app.staticTexts["Welcome back."].waitForExistence(timeout: 4)
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
            scenario: "ready",
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
        XCTAssertTrue(
            app.buttons["primaryTab.Today"].waitForExistence(timeout: 4)
        )
    }

    @MainActor
    func testTrustPromiseAndInvitationRemainReachableAtAccessibilityTextSize()
        throws
    {
        let promiseApp = launch(
            scenario: "ready",
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
    func testInsightDetailNavigation() throws {
        let app = launch(scenario: "ready")
        let insight = app.staticTexts["How should tonight feel?"]
        XCTAssertTrue(insight.waitForExistence(timeout: 4))

        let chooseButton = app.buttons["Choose what feels right"]
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 2))
        chooseButton.tap()
        XCTAssertTrue(
            app.staticTexts["Choose what feels right."]
                .waitForExistence(timeout: 2)
        )
        app.buttons["Out of the house"].tap()
        app.buttons["Open together"].tap()
        XCTAssertTrue(
            app.staticTexts["A CLEAR YES"]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testLifeStreamAndPrivateChoiceAreVisible() throws {
        let app = launch(scenario: "ready")

        app.buttons["primaryTab.Life"].tap()
        let lifeStream = app.staticTexts["LIFE STREAM"]
        scrollUntilVisible(lifeStream, in: app, maxSwipes: 6)
        XCTAssertTrue(
            lifeStream.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["Morning coffee by the river"].exists
        )

        app.buttons["Open shared horizons"].tap()
        XCTAssertTrue(app.staticTexts["A QUESTION FOR YOU"].exists)
        XCTAssertTrue(
            app.staticTexts["How should tonight feel?"].exists
        )
    }

    @MainActor
    func testCoreAccessibilityAudit() throws {
        let app = launch(scenario: "empty")
        XCTAssertTrue(
            app.buttons["primaryTab.Today"].waitForExistence(timeout: 4)
        )

        try app.performAccessibilityAudit(
            for: [
                .dynamicType,
                .hitRegion,
                .sufficientElementDescription,
                .textClipped
            ]
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
