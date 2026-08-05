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

    // MARK: Day one

    /// Us before it holds anything explains what it will hold. Until this
    /// existed the screen rendered two headings over nothing and the fictional
    /// couple's reasoning line.
    @MainActor
    func testUsExplainsItselfBeforeItHoldsAnything() throws {
        let app = launchEmpty()
        XCTAssertTrue(
            app.buttons["field.nav.us"].waitForExistence(timeout: 12)
        )
        app.buttons["field.nav.us"].tap()

        XCTAssertTrue(
            app.otherElements["field.us.empty"].waitForExistence(timeout: 6)
        )
        // The seed's reasoning line must not be anywhere near a real account.
        XCTAssertFalse(
            app.staticTexts
                .matching(
                    NSPredicate(
                        format: "label CONTAINS[c] %@",
                        "Three ordinary things"
                    )
                )
                .firstMatch
                .exists
        )
    }

    /// A clear day is not a dead end. Something put on today comes straight
    /// back as the thing Today shows — which is the whole of why the control
    /// exists.
    @MainActor
    func testForTodayPutsSomethingOnTheClearDay() throws {
        let app = launchEmpty()
        let input = app.textFields["field.capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 12))

        input.tap()
        input.typeText("call the plumber")

        let dismissKeyboard = app.buttons["field.capture.dismiss"]
        XCTAssertTrue(
            waitForHittable(dismissKeyboard),
            "the capture keyboard must offer a reliable way back to the field"
        )
        dismissKeyboard.tap()

        let submit = app.buttons["field.capture.submit"]
        XCTAssertTrue(
            waitForHittable(submit),
            "the visible File it control must be hittable after dismissing the keyboard"
        )
        submit.tap()

        let forToday = app.buttons["field.receipt.today"]
        XCTAssertTrue(forToday.waitForExistence(timeout: 6))
        forToday.tap()
        // Tapping it reads as "Not today", which is the only confirmation the
        // control itself gives — the date chip above carries the rest.
        let todayStateUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS[c] %@",
                "Not today"
            ),
            object: forToday
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [todayStateUpdated], timeout: 6),
            .completed,
            "the receipt must confirm that the captured item is now for today"
        )

        app.buttons["field.receipt.send"].tap()

        // The hero is the plumber now, not the resolved line.
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "plumber")
                )
                .firstMatch
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(app.staticTexts["Today is clear."].exists)
    }

    // MARK: The escapes, and reaching the phone

    /// "Ask me again tonight" was wired to nothing at all: the handler
    /// switched on a button's weight and only knew what to do with the filled
    /// one. Tapping it left the same hero on screen — which is exactly what a
    /// person who tapped it would not have noticed, and would have been
    /// promised anyway.
    @MainActor
    func testTheEscapeOnAStatementActuallyDefersIt() throws {
        let app = launchZones()

        let hero = app.staticTexts["Send the grocery list"]
        XCTAssertTrue(hero.waitForExistence(timeout: 8))

        let escape = app.buttons["field.moment.postpone"]
        XCTAssertTrue(waitForHittable(escape))
        XCTAssertEqual(escape.label, "ASK ME AGAIN TONIGHT")
        escape.tap()

        // Something else is the day's one thing now, or the day is clear.
        // Either is a real answer; the same hero coming back is not.
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: hero
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [gone], timeout: 6),
            .completed,
            "a deferred thing came straight back"
        )
    }

    /// The safety story, end to end.
    ///
    /// The app is about to act outward on somebody's behalf, so it stops and
    /// shows what it found first. This runs on an empty account with the
    /// resolver that finds nobody — which is the *common* case and the one
    /// most likely to be a dead end, so it is the one worth driving: it has
    /// to say plainly that it has no number, refuse to guess at one, and
    /// still leave a way to finish the thing.
    @MainActor
    func testReachingOutStopsForAConfirmationAndNeverGuesses() throws {
        let app = launchEmpty()
        let input = app.textFields["field.capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 12))

        input.tap()
        input.typeText("call the vet friday")

        let dismissKeyboard = app.buttons["field.capture.dismiss"]
        XCTAssertTrue(waitForHittable(dismissKeyboard))
        dismissKeyboard.tap()

        let submit = app.buttons["field.capture.submit"]
        XCTAssertTrue(waitForHittable(submit))
        submit.tap()

        let send = app.buttons["field.receipt.send"]
        XCTAssertTrue(waitForHittable(send))
        send.tap()

        let sent = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: send
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [sent], timeout: 6),
            .completed,
            "the receipt never crossed"
        )

        // The wording decides the verb, and the verb is the one that reaches
        // a phone. Addressed by role: every button style uppercases its
        // label, and the words change with the thing.
        let act = app.buttons["field.moment.act"]
        XCTAssertTrue(
            waitForHittable(act),
            "a thing that says 'call' offered no way to make one"
        )
        XCTAssertEqual(act.label, "MAKE THE CALL")
        act.tap()

        let confirmation = app.otherElements["field.outreach.confirm"]
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 8),
            "the app acted outward without stopping to show what it found"
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    NSPredicate(
                        format: "label CONTAINS[c] %@",
                        "not going to guess"
                    )
                )
                .firstMatch
                .waitForExistence(timeout: 4),
            "a missing number has to be said out loud, not papered over"
        )
        // And it is not a dead end.
        XCTAssertTrue(app.buttons["field.outreach.complete"].exists)
        XCTAssertTrue(app.buttons["field.outreach.dismiss"].exists)
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
        //
        // A row is a button now — tapping one opens the item, to move it or
        // take it off — so it answers to `buttons`, not `staticTexts`.
        XCTAssertTrue(
            app.buttons["Miso's teeth"].waitForExistence(timeout: 6),
            "tapping a category should open its room"
        )
        XCTAssertTrue(app.buttons["Dylan's birthday — Sunday"].exists)

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Miso's teeth"].waitForNonExistence(timeout: 4)
        )
    }

    /// Tapping a row opens the item, and the item can be moved and removed.
    ///
    /// Filing used to be one-way: a receipt could be corrected before it was
    /// sent, and after that an item's word and its day were fixed forever.
    @MainActor
    func testAnItemCanBeMovedAndRemoved() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let care = app.buttons["field.life.care"]
        XCTAssertTrue(waitForHittable(care))
        care.tap()

        let row = app.buttons["Miso's teeth"]
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()

        XCTAssertTrue(
            app.buttons["field.item.remove"].waitForExistence(timeout: 4),
            "tapping a row should open the item"
        )

        // Its current home stays visible and selected; the rest remain move
        // destinations.
        let current = app.buttons["field.item.currentCategory"]
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        XCTAssertTrue(current.isSelected)

        let destination = app.buttons
            .matching(identifier: "field.correction.option")
            .firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        destination.tap()

        // Removing it, which is the one act on this screen that asks first.
        let remove = app.buttons["field.item.remove"]
        XCTAssertTrue(waitForHittable(remove))
        remove.tap()
        app.buttons["Remove it"].firstMatch.tap()

        // The sheet closes with the thing it was about, and the row is gone
        // from the room underneath it.
        XCTAssertTrue(row.waitForNonExistence(timeout: 4))
    }

    /// The pull-for-calendar gesture lives on the same screen as the category
    /// buttons. A tap must not start it, and it must still work.
    @MainActor
    func testTappingACategoryDoesNotOpenTheCalendar() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let food = app.buttons["field.life.food"]
        XCTAssertTrue(waitForHittable(food))
        food.tap()

        // If the pull gesture had fired instead, the calendar would be up and
        // this row would not be.
        XCTAssertTrue(
            app.buttons["Send the grocery list"]
                .waitForExistence(timeout: 6),
            "a tap should open the room, not the calendar"
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

    // MARK: The circle

    /// The intelligence mark is a real button with a real label.
    ///
    /// It spent its whole life as decoration — inside a combined
    /// accessibility element and `accessibilityHidden(true)` besides. Both
    /// were right for an ornament and wrong the moment it became the only
    /// control on the screen: a button folded into a combined label is not a
    /// button to VoiceOver, and this is the entire route to the circle.
    ///
    /// Unlike the account action, this one *is* checkable — it is an ordinary
    /// button rather than a custom action — so it is asserted here rather than
    /// left to the Accessibility Inspector.
    @MainActor
    func testTheCircleMarkIsALabelledButtonAndTeachesOnce() throws {
        let app = launchZones()

        let mark = app.buttons["field.circle.mark"]
        XCTAssertTrue(
            mark.waitForExistence(timeout: 8),
            "the mark is not exposed as a button at all"
        )
        XCTAssertFalse(
            mark.label.isEmpty,
            "the only control on this screen has no label"
        )
        XCTAssertTrue(mark.isHittable)

        mark.tap()

        // Taught at the moment of the first tap, because that is the moment
        // the question arises: a tap that visibly does nothing is
        // incomprehensible without it.
        let teaching = app.otherElements["field.circle.teaching"]
        XCTAssertTrue(
            teaching.waitForExistence(timeout: 4),
            "the first tap explained nothing"
        )

        app.buttons["Alright"].tap()
        XCTAssertFalse(
            teaching.waitForExistence(timeout: 1),
            "the teaching stayed up after being dismissed"
        )

        // And the tap counted. Nothing here says anything about the partner —
        // this is the app telling one person what they themselves did.
        XCTAssertTrue(
            app.staticTexts["Noted, just for you."]
                .waitForExistence(timeout: 4),
            "the mark landed and said nothing back"
        )

        // The room must not have opened: one person is not both of them.
        XCTAssertFalse(
            app.otherElements["field.circle.room"].exists,
            "one person's tap opened a shared room"
        )
    }

    // MARK: Capture

    @MainActor
    func testCaptureProducesAReceipt() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.staticTexts["TELL WE ANYTHING"].waitForExistence(timeout: 8)
        )

        // A pill submits its phrase and shows the receipt. Addressed by
        // identifier, not by words: the suggestions are read from this
        // couple's own week, so no test can know them in advance.
        let pill = app.buttons
            .matching(identifier: "field.capture.suggestion")
            .firstMatch
        guard pill.waitForExistence(timeout: 4) else {
            XCTFail("expected at least one suggestion under the field")
            return
        }
        pill.tap()

        XCTAssertTrue(
            app.staticTexts["FILED TO"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["WRONG PLACE"].exists)
    }

    // MARK: The calendar

    /// Pulling down on Life opens the month. It replaced the Reminders
    /// takeover, whose occasions now sit at the top of Life itself.
    @MainActor
    func testCalendarOpensAndCloses() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))

        let affordance = app.buttons["field.life.calendar"]
        XCTAssertTrue(affordance.waitForExistence(timeout: 4))
        affordance.tap()

        XCTAssertTrue(
            app.otherElements["field.calendar"].waitForExistence(timeout: 4),
            "pulling down on Life should open the calendar"
        )

        // By label, not identifier: an identifier on a plain-styled Button
        // does not surface, which the category-room test above already
        // documents the hard way.
        let done = app.buttons["Done"]
        guard done.waitForExistence(timeout: 4) else {
            XCTFail("the calendar should offer a way out")
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
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
            "-hasSeenWalkthrough", "YES",
        ]
        app.launch()

        let we = app.buttons["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 10))
        we.press(forDuration: 0.9)

        let signOut = app.buttons["field.account.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 4))
        signOut.tap()

        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 8),
            "signing out should return to the welcome screen, not leave the "
                + "zones up"
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

    // MARK: Rendered contracts

    /// Stable attachment names are part of the CI contract: the visual-diff
    /// job exports these from the xcresult and compares them to the committed
    /// reference set.
    @MainActor
    func testRenderedContractCapturesTheThreeZones() throws {
        let app = launchZones()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 8))
        keepScreenshot(of: app, named: "golden.field.today.seeded")

        app.buttons["field.nav.life"].tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))
        keepScreenshot(of: app, named: "golden.field.life.seeded")

        app.buttons["field.nav.us"].tap()
        XCTAssertTrue(app.staticTexts["US"].waitForExistence(timeout: 4))
        keepScreenshot(of: app, named: "golden.field.us.seeded")
    }

    @MainActor
    func testEmptyUsAtMaximumAccessibilitySettings() throws {
        let app = launchEmpty(maximumAccessibility: true)
        let us = app.buttons["field.nav.us"]
        XCTAssertTrue(us.waitForExistence(timeout: 12))
        us.tap()

        let empty = app.otherElements["field.us.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 6))
        XCTAssertTrue(
            empty.label.contains("This is the long view"),
            "the empty state must explain itself as one coherent element"
        )
        keepScreenshot(
            of: app,
            named: "golden.field.us.empty.accessibility5"
        )
    }

    /// XCTest's audit produces structured issues in the xcresult, which makes
    /// an accessibility failure reviewable instead of a bare boolean.
    @MainActor
    func testCriticalZonesPassAccessibilityAudit() throws {
        let app = launchEmpty(maximumAccessibility: true)
        XCTAssertTrue(
            app.textFields["field.capture.input"]
                .waitForExistence(timeout: 12)
        )

        try app.performAccessibilityAudit(for: [
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ])

        app.buttons["field.nav.us"].tap()
        XCTAssertTrue(
            app.otherElements["field.us.empty"].waitForExistence(timeout: 6)
        )
        try app.performAccessibilityAudit(for: [
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ])
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

    // MARK: - ○ Yours
    //
    // The way in is an upward drag on the navigation bar, and there is no
    // control for it. That is the point: §2 wants the room wordless, and a
    // permanent button in the chrome is the loudest possible way to describe
    // somewhere private. What the bar carries instead is a hint, once.

    /// The nav bar holds LIFE / WE / US and nothing else.
    @MainActor
    func testTheNavigationBarCarriesNoControlForYours() {
        let app = launchZones()
        let we = app.descendants(matching: .any)["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        XCTAssertFalse(
            app.descendants(matching: .any)["field.nav.yours"].exists,
            "the personal mark is back in the navigation bar"
        )
    }

    /// §2: nothing in the chrome carries a badge or a count. "Yours, one
    /// waiting" would be the forbidden count, read aloud.
    @MainActor
    func testTheChromeCarriesNoCount() {
        let app = launchZones()
        let we = app.descendants(matching: .any)["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        XCTAssertEqual(we.label, "WE")
        for label in [we.label, app.descendants(matching: .any)["field.nav.life"].label] {
            XCTAssertTrue(
                label.rangeOfCharacter(from: .decimalDigits) == nil,
                "the chrome is carrying a count: \(label)"
            )
        }
    }

    /// §7: it opens onto somewhere to write, and on nothing at all when there
    /// is nothing — not onto a feed, and not onto an empty inbox with a zero
    /// in it.
    @MainActor
    func testSwipingUpOnTheNavBarOpensOntoWritingAndAQuietEmptyState() {
        let app = launchZones()
        swipeUpOnTheNavigationBar(app)

        XCTAssertTrue(
            app.textViews["yours.compose"].waitForExistence(timeout: 5),
            "the swipe did not open the space"
        )
        XCTAssertTrue(app.staticTexts["Nothing is waiting for you."].exists)
    }

    /// The close control used to have the whole screen as its hit region — the
    /// positioning frame sat outside the `Button` — so a tap anywhere
    /// dismissed the room, including a tap meant for the writing field. Both
    /// halves are asserted, because fixing one without the other is how it
    /// broke in the first place.
    @MainActor
    func testTheCloseControlDismissesAndTheRestOfTheScreenDoesNot() {
        let app = launchZones()
        swipeUpOnTheNavigationBar(app)

        let compose = app.textViews["yours.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5))

        // A raw coordinate in the lower middle of the screen — nowhere near
        // the glyph, and deliberately not an element query. The regression was
        // positional: the close button's layout frame was the whole window
        // while it drew in the corner, so *empty space* was a dismiss target.
        // Only a point tap can catch that coming back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            .tap()

        XCTAssertTrue(
            compose.waitForExistence(timeout: 2),
            "tapping empty space inside the room dismissed it"
        )

        app.descendants(matching: .any)["yours.close"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["field.nav.we"]
                .waitForExistence(timeout: 5),
            "the close control did not dismiss the room"
        )
    }

    /// Coordinate-driven rather than `app.swipeUp()`, which would drag the
    /// zone's scroll view instead of the bar.
    ///
    /// Also clears the first-entry teaching sheet. It is `interactiveDismiss`
    /// disabled and covers the room, so without this every assertion about
    /// what the room does is really an assertion about a sheet sitting on top
    /// of it — the element is found, and nothing on it can be touched.
    @MainActor
    private func swipeUpOnTheNavigationBar(_ app: XCUIApplication) {
        let we = app.descendants(matching: .any)["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        let start = we.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120))
        )

        let begin = app.buttons["Begin"]
        if begin.waitForExistence(timeout: 3) {
            begin.tap()
        }
    }

    @MainActor
    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app)
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "choosinghue"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
            "-hasSeenWalkthrough", "YES",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func launchZones() -> XCUIApplication {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app)
        app.launchEnvironment["WE_FIELD"] = "seeded"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launch()
        return app
    }

    /// What a real couple starts with: nothing. Deliberately *not* seeded —
    /// the fictional couple hides every state this app has on day one.
    @MainActor
    private func launchEmpty(
        maximumAccessibility: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(
            app,
            maximumDynamicType: maximumAccessibility,
            reduceMotion: true,
            reduceTransparency: maximumAccessibility
        )
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "ready"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
            "-hasSeenWalkthrough", "YES",
        ]
        app.launch()
        return app
    }
}
