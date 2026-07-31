import XCTest

/// UI coverage for the zones.
///
/// These replace the tab-bar tests, which drove `AppShell` and stopped being
/// meaningful the moment `WEApp` handed `.ready` to `FieldRoot`.
///
/// They run against `WE_FIELD=seeded` — the fictional couple, no network — so
/// they exercise the real views and the real store without a Supabase session.
final class FieldZoneUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Navigation

    @MainActor
    func testZoneNavigationByLabelAndBySwipe() throws {
        let app = launchZones()

        let we = app.buttons["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        // Today is the home zone and where a cold launch lands.
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 4))

        app.buttons["field.nav.life"].tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))

        // The mark always returns to Today, from anywhere.
        we.tap()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 4))

        app.buttons["field.nav.us"].tap()
        XCTAssertTrue(app.staticTexts["US"].waitForExistence(timeout: 4))

        // One zone per gesture, always snapped.
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 4))
    }

    // MARK: Category rooms

    @MainActor
    func testACategoryOpensItsRoomAndCloses() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let care = app.buttons["field.life.care"]
        XCTAssertTrue(waitForHittable(care))
        care.tap()

        // Asserted on content. Neither the sheet's root nor its close button
        // surfaces by identifier through a plain-styled Button, but the rows
        // are unambiguous: Life itself never lists an item, so seeing one
        // means the room is up.
        XCTAssertTrue(
            app.staticTexts["Miso's teeth"].waitForExistence(timeout: 6),
            "tapping a category should open its room"
        )
        XCTAssertTrue(app.staticTexts["Dylan's birthday — Sunday"].exists)

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Miso's teeth"].waitForNonExistence(timeout: 4)
        )
    }

    /// The pull-for-Reminders gesture lives on the same screen as the
    /// category buttons. A tap must not start it, and it must still work.
    @MainActor
    func testTappingACategoryDoesNotOpenReminders() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let food = app.buttons["field.life.food"]
        XCTAssertTrue(waitForHittable(food))
        food.tap()

        // If the pull gesture had fired instead, the Reminders takeover
        // would be up and this row would not be.
        XCTAssertTrue(
            app.staticTexts["Send the grocery list"]
                .waitForExistence(timeout: 6),
            "a tap should open the room, not the Reminders takeover"
        )
    }

    // MARK: The account route
    //
    // This is the one that blocks submission: Apple requires in-app account
    // deletion to be reachable, and the zones deliberately carry no chrome.

    @MainActor
    func testAccountIsReachableAndOffersDeletion() throws {
        let app = launchZones()

        let we = app.buttons["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))
        we.press(forDuration: 0.9)

        let signOut = app.buttons["field.account.signOut"]
        XCTAssertTrue(
            signOut.waitForExistence(timeout: 4),
            "long-pressing the mark should open the account surface"
        )

        let delete = app.buttons["field.account.delete"]
        XCTAssertTrue(delete.exists)
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["This cannot be undone."]
                .waitForExistence(timeout: 4)
        )

        // Deletion stays behind both a password and a typed confirmation.
        let confirm = app.buttons["field.account.delete.confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(
            confirm.isEnabled,
            "Deletion must not be armed before both fields are satisfied"
        )

        // "Every request the app makes offers a way to decline it."
        app.buttons["field.account.delete.decline"].tap()
        XCTAssertTrue(signOut.waitForExistence(timeout: 4))
    }

    /// The mark must read as an activatable control, because a bare shape
    /// with two gestures would be invisible to assistive tech.
    ///
    /// **XCUITest cannot enumerate `accessibilityCustomActions`** — there is
    /// no public API for it — so this asserts only what is checkable, and the
    /// "Account" custom action itself has to be verified in the Accessibility
    /// Inspector. That check is the whole VoiceOver route to deletion, so it
    /// is not optional just because it is manual.
    @MainActor
    func testTheMarkIsExposedAsAControl() throws {
        let app = launchZones()

        let we = app.buttons["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))
        XCTAssertEqual(we.label, "WE")
        XCTAssertTrue(we.isHittable)
    }

    // MARK: Capture

    @MainActor
    func testCaptureProducesAReceipt() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.staticTexts["TELL WE ANYTHING"].waitForExistence(timeout: 8)
        )

        // The sample pills submit a canonical input and show its receipt.
        let pill = app.buttons["Try: steak"]
        guard pill.waitForExistence(timeout: 4) else {
            XCTFail("expected the canonical sample phrases")
            return
        }
        pill.tap()

        XCTAssertTrue(
            app.staticTexts["FILED TO"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["WRONG PLACE"].exists)
    }

    // MARK: Reminders

    @MainActor
    func testRemindersTakeoverOpensAndCloses() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))

        let affordance = app.buttons["field.life.reminders"]
        XCTAssertTrue(affordance.waitForExistence(timeout: 4))
        affordance.tap()

        let done = app.buttons["Done"]
        guard done.waitForExistence(timeout: 4) else {
            XCTFail("the Reminders takeover should offer a way out")
            return
        }
        done.tap()

        // The nav bar returns — the takeover is the only surface allowed to
        // cover the mark, and only while open.
        XCTAssertTrue(
            app.buttons["field.nav.we"].waitForExistence(timeout: 4)
        )
    }

    /// Signing out has to actually leave.
    ///
    /// Runs against the live route rather than `WE_FIELD=seeded`, because
    /// seeded mode renders the zones unconditionally and would pass without
    /// the session ever being consulted.
    ///
    /// This failed until `SessionHost` began forwarding the session's own
    /// changes: `@Published var session` fires only when the reference is
    /// replaced, so `WEApp` never re-evaluated and the zones stayed put.
    @MainActor
    func testSigningOutLeavesTheZones() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "ready"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        // Otherwise signing out lands on Soft Start rather than sign in.
        app.launchEnvironment["WE_SKIP_SOFT_START"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += ["-hasSeenLivingConfluencePromise", "YES"]
        app.launch()

        let we = app.buttons["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 10))
        we.press(forDuration: 0.9)

        let signOut = app.buttons["field.account.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 4))
        signOut.tap()

        XCTAssertTrue(
            app.staticTexts["Welcome back."].waitForExistence(timeout: 8),
            "signing out should return to sign in, not leave the zones up"
        )
    }

    // MARK: Onboarding (6f)

    @MainActor
    func testOnboardingAnswersAreOptionalAndReversible() throws {
        let app = launchOnboarding()

        XCTAssertTrue(
            app.staticTexts["Choose a colour each."]
                .waitForExistence(timeout: 8)
        )

        // Three questions and a calendar is the entire cold start.
        XCTAssertTrue(app.staticTexts["Do you live together?"].exists)
        XCTAssertTrue(
            app.staticTexts["What's the one thing you're saving for?"].exists
        )
        XCTAssertTrue(
            app.staticTexts["Who or what else do you look after?"].exists
        )

        let yes = app.buttons["field.onboarding.livesTogether.true"]
        XCTAssertTrue(yes.waitForExistence(timeout: 4))
        yes.tap()
        XCTAssertTrue(yes.isSelected)

        // Tapping the chosen answer again clears it — nothing is compulsory,
        // including having answered.
        yes.tap()
        XCTAssertFalse(yes.isSelected)

        // Finishing is reachable without answering anything at all.
        let finish = app.buttons["field.onboarding.finish"]
        XCTAssertTrue(finish.exists)
        XCTAssertTrue(finish.isEnabled)
    }

    @MainActor
    func testOnboardingOffersTheCalendarWithoutRequiringIt() throws {
        let app = launchOnboarding()
        XCTAssertTrue(
            app.buttons["field.onboarding.calendar.connect"]
                .waitForExistence(timeout: 8)
        )
        // The offer exists and finishing does not depend on taking it.
        XCTAssertTrue(app.buttons["field.onboarding.finish"].isEnabled)
    }

    // MARK: Launch

    /// All three zones stay mounted in the paging TabView, so a category
    /// button exists — and even reports itself hittable — while the page is
    /// still sliding into place. Tapping then lands on whatever is actually
    /// in front. Waiting for the zone label and letting the transition finish
    /// is what makes the tap go where it looks like it goes.
    @MainActor
    private func settleOnLife(_ app: XCUIApplication) {
        _ = app.staticTexts["LIFE"].waitForExistence(timeout: 4)
        usleep(1_200_000)
    }

    /// Existence is not enough on a paging TabView — every zone is mounted at
    /// once, so an element can exist while another page is in front of it.
    @MainActor
    private func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            usleep(200_000)
        }
        return false
    }

    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "choosinghue"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += ["-hasSeenLivingConfluencePromise", "YES"]
        app.launch()
        return app
    }

    private func launchZones() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_FIELD"] = "seeded"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launch()
        return app
    }
}
