import XCTest

final class WEUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNativeTabsContextualCreationAndProfile() throws {
        let app = launch(scenario: "empty")

        XCTAssertTrue(app.tabBars.buttons["WE"].waitForExistence(timeout: 4))
        app.tabBars.buttons["Life"].tap()
        XCTAssertTrue(
            app.staticTexts["Nothing needs naming right now."].exists
        )
        app.navigationBars["Life"].buttons["Name some care"].tap()
        XCTAssertTrue(app.staticTexts["THE CARE"].exists)
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Ahead"].tap()
        XCTAssertTrue(app.staticTexts["The horizon is open."].exists)
        app.navigationBars["Ahead"].buttons["Hold a new intention"].tap()
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
            app.staticTexts["Make this space yours."]
                .waitForExistence(timeout: 3)
        )
        let createSpace = app.buttons["Create our space"]
        createSpace.tap()
        XCTAssertTrue(
            app.staticTexts["Your side is ready."]
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
        XCTAssertTrue(app.tabBars.buttons["WE"].waitForExistence(timeout: 3))
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
            app.staticTexts["Your side is ready."]
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
            app.staticTexts["Nothing crosses without both."].exists
        )
        app.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["What opens, opens together."].exists
        )
        app.buttons["Hold to join"].press(forDuration: 0.5)
        XCTAssertTrue(app.tabBars.buttons["WE"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testInsightDetailNavigation() throws {
        let app = launch(scenario: "ready")
        let insight = app.staticTexts["What kind of dinner fits tonight?"]
        XCTAssertTrue(insight.waitForExistence(timeout: 4))
        insight.tap()

        XCTAssertTrue(
            app.navigationBars["Insight"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["Neither preference needs to become a rejection."]
                .exists
        )
        XCTAssertTrue(app.staticTexts["Answer privately."].exists)
        app.buttons["The little Thai place"].tap()
        app.buttons["Submit my answer"].tap()
        XCTAssertTrue(
            app.staticTexts["A mutual match."]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testLifeStreamAndPrivateChoiceAreVisible() throws {
        let app = launch(scenario: "ready")

        app.tabBars.buttons["Life"].tap()
        XCTAssertTrue(
            app.staticTexts["LIFE STREAM"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["Morning coffee by the river"].exists
        )

        app.tabBars.buttons["Ahead"].tap()
        XCTAssertTrue(app.staticTexts["CHOOSE PRIVATELY"].exists)
        XCTAssertTrue(
            app.staticTexts["What kind of dinner fits tonight?"].exists
        )
    }

    @MainActor
    func testCoreAccessibilityAudit() throws {
        let app = launch(scenario: "empty")
        XCTAssertTrue(app.tabBars.buttons["WE"].waitForExistence(timeout: 4))

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
    private func launch(
        scenario: String,
        skipsPromise: Bool = true,
        reduceMotion: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = scenario
        app.launchEnvironment["WE_PREVIEW_DELETION_PASSWORD"] =
            "correct-password"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = skipsPromise ? "1" : "0"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", skipsPromise ? "YES" : "NO",
            "-UIAccessibilityReduceMotionEnabled",
            reduceMotion ? "YES" : "NO"
        ]
        app.launch()
        return app
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
