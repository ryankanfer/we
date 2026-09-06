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
        // Recent iOS simulators can offer to save the test password from a
        // separate system window after the app has already advanced. Decline
        // it so this test measures the invitation route, not Passwords UI.
        let declinePasswordSave = app.buttons["Not Now"]
        if declinePasswordSave.waitForExistence(timeout: 2) {
            declinePasswordSave.tap()
        }
        let createSpace = app.buttons["pairing.createInvitation"]
        createSpace.tap()
        // "The invitation is at the threshold" was the register of the
        // specification document that produced it. The screen names the
        // person it is for instead, and falls back to "For them." until it
        // has been told who that is.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "For ")
            ).firstMatch
                .waitForExistence(timeout: 3)
        )

        // Colour, and nothing else. The three questions that used to follow
        // the blend are cut, and the step counter with them.
        app.terminate()
        app = launch(scenario: "choosinghue")
        XCTAssertTrue(
            app.staticTexts["Choose yours."].waitForExistence(timeout: 6)
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
    func testRetiredPromiseDoesNotInterruptTheCurrentWaitingScreen() throws {
        let app = launch(
            scenario: "waiting",
            skipsPromise: false
        )

        XCTAssertTrue(
            app.buttons["accountButton"].waitForExistence(timeout: 8),
            "a returning person should land on the current setup screen"
        )
        XCTAssertFalse(
            app.staticTexts["Yours stays yours."].exists,
            "the retired Promise must not present itself at launch"
        )
    }

    /// The three beats, in the order `WEBeat.allCases` performs them.
    ///
    /// Held here as one list because two tests walk it and they drifted apart
    /// once already: both were still asserting the pre-`3bc6dca` wording, and
    /// tapping a "Continue" button that `WEPromiseViewTests` separately
    /// forbids the Promise from ever having.
    private static let beatTitles = [
        "Yours stays yours.",
        "Nothing moves without you.",
        "What opens, opens together.",
    ]

    @MainActor
    func testLivingConfluencePromiseSupportsReducedMotion() throws {
        let app = launch(
            scenario: "waiting",
            skipsPromise: false,
            reduceMotion: true
        )
        replayPromise(in: app)

        // By identifier rather than by label. The way to give a beat is a
        // single affordance whose wording is still moving, and a test that
        // spells the wording is a test that goes stale the next time it does.
        for title in Self.beatTitles {
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 4),
                "the Promise should reach \(title)"
            )
            app.buttons["we.promise.give"].tap()
        }

        // What this test is about is that all three beats are reachable and
        // dismissable with Reduce Motion on. Where it lands afterwards
        // depends on the session state and belongs to other tests.
        XCTAssertTrue(
            app.staticTexts[Self.beatTitles[0]].waitForNonExistence(timeout: 4),
            "the Promise should be gone once it has been read through"
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
        replayPromise(in: promiseApp)

        // Every beat, including the last: the point is that the way to give a
        // beat stays reachable at this text size, and the last beat is the one
        // with the most words above the affordance.
        for title in Self.beatTitles {
            XCTAssertTrue(
                promiseApp.staticTexts[title].waitForExistence(timeout: 4),
                "the Promise should reach \(title)"
            )
            let give = promiseApp.buttons["we.promise.give"]
            scrollUntilVisible(give, in: promiseApp, maxSwipes: 8)
            XCTAssertTrue(give.isHittable, "\(title) must stay givable")
            give.tap()
        }
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
        // One question, and no description of the category underneath it.
        XCTAssertTrue(
            app.staticTexts["Who are you making this with?"].exists
        )
        // The point of this screen: nothing is asked for before a door is
        // chosen. No credential field, no capture field.
        XCTAssertFalse(app.textFields["Email"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)

        app.buttons["welcome.start"].tap()
        XCTAssertTrue(
            app.staticTexts["Begin on your side."]
                .waitForExistence(timeout: 3),
            "Begin should open account creation, not sign-in"
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

        // Told, not asked — before the code field, and above it. Somebody
        // arriving here was invited by a person, and the first sentence says
        // so even before the network has said who.
        XCTAssertTrue(
            app.staticTexts["Someone is waiting for you."]
                .waitForExistence(timeout: 3)
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

        // The code buys one thing before it buys an account: the name of the
        // person waiting. `invitation_greeting` answers it without a session,
        // which is the whole reason this screen can exist at all.
        XCTAssertTrue(
            app.staticTexts["Ryan is waiting."].waitForExistence(timeout: 4)
        )
        app.buttons["welcome.joinCode.continue"].tap()

        // The code is held, and the sheet moves straight on to making an
        // account — joining needs a session, so it cannot happen yet.
        XCTAssertTrue(
            app.staticTexts["Begin on your side."]
                .waitForExistence(timeout: 3)
        )
    }


    @MainActor
    private func replayPromise(in app: XCUIApplication) {
        let account = app.buttons["accountButton"]
        XCTAssertTrue(account.waitForExistence(timeout: 4))
        account.tap()

        let replay = app.buttons["See the beginning again"]
        scrollUntilVisible(replay, in: app, maxSwipes: 8)
        XCTAssertTrue(replay.isHittable)
        replay.tap()
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
        // The walkthrough opens over the welcome screen on a first run, and
        // every test below that waits for a welcome button would otherwise fail
        // for a reason that has nothing to do with what it is testing.
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
            // Whether the invitation has left this phone is device-local
            // state in `@AppStorage`, and it decides whether the waiting
            // screen shows the invitation or the stillness. It survives a
            // relaunch, so without resetting it here one test that shares
            // silently changes which screen the next one opens on.
            "-we.invitation.sent", "NO",
            "-we.invitee.name", "",
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
