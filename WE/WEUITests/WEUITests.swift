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
        // Signed out now lands on the welcome screen, not the account gate.
        // Sign-in is one of its three doors.
        openSignIn(in: app)

        // By identifier: the button's label is uppercased by the Field button
        // style, so matching on the sentence form depends on the accessibility
        // label surviving, which is not something this test is about.
        app.buttons["account.forgotPassword"].tap()
        // No navigation bar to assert on any more: the gates are drawn in the
        // zones' language, which has no title chrome. The headline is the
        // screen's identity, and DONE ✕ is how every covering surface in this
        // app closes.
        XCTAssertTrue(
            app.staticTexts["We'll send a link."]
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
        let createSpace = app.buttons["pairing.createInvitation"]
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
            // Deleting the account returns you to the front door, not to a
            // sign-in form for an account that no longer exists.
            XCTAssertTrue(
                app.buttons["welcome.start"].waitForExistence(timeout: 4)
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
        let sendButton = waitingApp.buttons["waiting.share"]
        scrollUntilVisible(sendButton, in: waitingApp, maxSwipes: 10)
        XCTAssertTrue(sendButton.isHittable)
        let copyButton = waitingApp.buttons["waiting.copy"]
        scrollUntilVisible(copyButton, in: waitingApp, maxSwipes: 4)
        XCTAssertTrue(copyButton.isHittable)
    }

    @MainActor
    func testWelcomeOffersThreeDoorsAndAsksForNothingFirst() throws {
        let app = launch(scenario: "signedout")

        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["welcome.join"].isHittable)
        XCTAssertTrue(app.buttons["welcome.signIn"].isHittable)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "A shared space for"
                )
            ).firstMatch.exists
        )
        // The point of this screen: nothing is asked for before a door is
        // chosen. No credential field, no capture field.
        XCTAssertFalse(app.textFields["Email"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)

        app.buttons["welcome.start"].tap()
        XCTAssertTrue(
            app.staticTexts["Begin on your side."]
                .waitForExistence(timeout: 3),
            "Start a WE space should open account creation, not sign-in"
        )
    }

    @MainActor
    func testWelcomeIsUsableAtAccessibilityTextSizeAndPassesAudit() throws {
        let app = launch(scenario: "signedout", accessibilityTextSize: true)

        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 4)
        )
        // At AX5 the screen scrolls. Every door still has to be reachable —
        // the sign-in one is last, so it is the one that would be stranded.
        for identifier in ["welcome.join", "welcome.signIn"] {
            let door = app.buttons[identifier]
            scrollUntilVisible(door, in: app, maxSwipes: 8)
            XCTAssertTrue(door.isHittable, "\(identifier) should be reachable")
        }

        try app.performAccessibilityAudit(
            for: [
                .hitRegion,
                .sufficientElementDescription,
                .textClipped,
                .trait
            ]
        )
    }

    @MainActor
    func testJoiningWithACodeCarriesItThroughAccountCreation() throws {
        let app = launch(scenario: "signedout")
        XCTAssertTrue(
            app.buttons["welcome.join"].waitForExistence(timeout: 4)
        )
        app.buttons["welcome.join"].tap()

        XCTAssertTrue(
            app.staticTexts["Enter the code."].waitForExistence(timeout: 3)
        )
        let codeField = app.textFields["welcome.joinCode"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 2))
        codeField.tap()
        // Typed lowercase; the field is set to `.characters`, so it arrives
        // uppercase without the binding having to rewrite it. Stripping
        // punctuation and capping length are covered in `InvitationTests`.
        codeField.typeText("wedemo")
        XCTAssertEqual(codeField.value as? String, "WEDEMO")

        app.buttons["welcome.joinCode.continue"].tap()

        // The code is held, and the sheet moves straight on to making an
        // account — joining needs a session, so it cannot happen yet.
        XCTAssertTrue(
            app.staticTexts["Begin on your side."]
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
        // Default on, like the promise. The walkthrough opens over the welcome
        // screen on a first run, and every test below that waits for a welcome
        // button would otherwise fail for a reason that has nothing to do with
        // what it is testing.
        skipsWalkthrough: Bool = true,
        reduceMotion: Bool = false,
        accessibilityTextSize: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = scenario
        app.launchEnvironment["WE_PREVIEW_DELETION_PASSWORD"] =
            "correct-password"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = skipsPromise ? "1" : "0"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] =
            skipsWalkthrough ? "1" : "0"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", skipsPromise ? "YES" : "NO",
            "-hasSeenWalkthrough", skipsWalkthrough ? "YES" : "NO",
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

    /// Signed out opens on the welcome screen. Anything that needs the account
    /// gate goes through its sign-in door first.
    @MainActor
    private func openSignIn(in app: XCUIApplication) {
        XCTAssertTrue(
            app.buttons["welcome.signIn"].waitForExistence(timeout: 4)
        )
        app.buttons["welcome.signIn"].tap()
        XCTAssertTrue(
            app.staticTexts["Welcome back."].waitForExistence(timeout: 3)
        )
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
