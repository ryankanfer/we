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

    /// The single most valuable test in Stage 4.
    ///
    /// "Miso's teeth" is a sentence about a cat, filed under Care with a day
    /// on it. The app has nothing to open for it, nothing to search, and no
    /// business breaking it into steps — so the item sheet must show no help
    /// block at all. Not an empty one, not a disabled one: none.
    ///
    /// If this ever fails, the app has started having opinions about a
    /// couple's list, and every other test in this feature stops mattering.
    @MainActor
    func testAPlainItemOffersNothingUnsolicited() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let care = app.buttons["field.life.care"]
        XCTAssertTrue(waitForHittable(care))
        care.tap()

        openRow(app, titled: "Miso's teeth")

        // The sheet is up — asserted on a control that is always there.
        XCTAssertTrue(
            app.buttons["field.item.remove"].waitForExistence(timeout: 4)
        )
        for identifier in Self.helpIdentifiers {
            XCTAssertFalse(
                app.descendants(matching: .any)
                    .matching(identifier: identifier)
                    .firstMatch
                    .exists,
                "a plain item grew \(identifier)"
            )
        }
    }

    /// Every affordance the help block can put on screen. Named here so the
    /// absence test above cannot quietly stop covering a new one.
    private static let helpIdentifiers = [
        "field.item.help.web",
        "field.item.help.shop",
        "field.item.help.maps",
        "field.item.help.plan",
        "field.item.help.calendar",
        "field.item.help.ask",
    ]

    /// A row carries `field.room.row` as an identifier and wraps an inner
    /// button with the same label, so asking for the title alone is ambiguous
    /// — ask for both. And `BEGINSWITH` rather than equality: a row in the
    /// pressing band combines its reason into the label ("Air filter. This was
    /// down for Sunday…"), while a quiet row is the title alone.
    @MainActor
    private func openRow(_ app: XCUIApplication, titled title: String) {
        let row = app.buttons
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label BEGINSWITH %@",
                    "field.room.row",
                    title
                )
            )
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "no row for \(title)")
        row.tap()
    }

    /// The other half of the gate: where there *is* something to open, it is
    /// one button, and it names where it goes before it is tapped.
    @MainActor
    func testSomethingBuyableOffersOneNamedDestination() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let home = app.buttons["field.life.home"]
        XCTAssertTrue(waitForHittable(home))
        home.tap()

        openRow(app, titled: "Air filter")

        XCTAssertTrue(
            app.buttons["field.item.remove"].waitForExistence(timeout: 6),
            "the item sheet did not open"
        )

        let shop = app.buttons["field.item.help.shop"]
        XCTAssertTrue(
            shop.waitForExistence(timeout: 6),
            "no shop button. Tree:\n\(app.debugDescription)"
        )

        // The sheet must still be up. Two `.sheet` modifiers on one view used
        // to close it the instant this block appeared, and the only visible
        // symptom was the item sheet vanishing.
        XCTAssertTrue(app.buttons["field.item.remove"].exists)
        XCTAssertEqual(shop.label, "FIND AN AIR FILTER")

        // No size on the item, so the app says so rather than searching badly.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "field.item.help.ask")
                .firstMatch
                .exists
        )

        // Picking the shop is the actual question, so it is asked. Nothing is
        // preselected and nothing is recommended.
        shop.tap()
        let aShop = app.buttons["field.item.shop.target"]
        XCTAssertTrue(aShop.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["field.item.shop.amazon"].exists)
    }

    /// The pull-to-search gesture lives on the same screen as the category
    /// buttons. A tap must not start it, and it must still work.
    ///
    /// This test predates the gesture it now names: the pull used to open the
    /// calendar, and the collision it guards against is a property of the
    /// screen rather than of whichever surface is behind the drag.
    @MainActor
    func testTappingACategoryDoesNotOpenSearch() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let food = app.buttons["field.life.food"]
        XCTAssertTrue(waitForHittable(food))
        food.tap()

        // If the pull gesture had fired instead, search would be up and this
        // row would not be.
        XCTAssertTrue(
            app.buttons["Send the grocery list"]
                .waitForExistence(timeout: 6),
            "a tap should open the room, not search"
        )
        XCTAssertFalse(app.otherElements["field.search"].exists)
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

    /// The month, from the visible control on Life. It replaced the Reminders
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
            "the calendar control on Life should open the month"
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

    // MARK: Tap again to go deeper
    //
    // One sentence, twice: a nav target that is already showing has nothing
    // left to do as navigation, so a second tap opens the room behind it. The
    // three tests below pin the three halves that can each break alone — the
    // first tap still navigating, the second tap opening, and the second tap
    // *not* opening when something is in the way.

    /// LIFE while Life is showing opens the month.
    @MainActor
    func testTappingLifeWhileOnLifeOpensTheCalendar() throws {
        let app = launchZones()
        let life = app.buttons["field.nav.life"]
        XCTAssertTrue(life.waitForExistence(timeout: 8))

        // First tap navigates, and must not open anything.
        life.tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))
        XCTAssertFalse(
            app.otherElements["field.calendar"].exists,
            "the first tap on LIFE opened the calendar instead of Life"
        )

        // Second tap opens the room behind it.
        life.tap()
        XCTAssertTrue(
            app.otherElements["field.calendar"].waitForExistence(timeout: 4),
            "a second tap on LIFE should open the month"
        )
    }

    /// The mark returns home from anywhere, and opens Yours only once it is
    /// already home. Both halves, because a change that made it open the room
    /// unconditionally would strand somebody on Life.
    @MainActor
    func testTheMarkReturnsHomeFirstAndOpensYoursSecond() throws {
        let app = launchZones()
        let we = app.descendants(matching: .any)["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        app.buttons["field.nav.life"].tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))

        // From Life the mark is the way home, and nothing else.
        we.tap()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 4))
        XCTAssertFalse(
            app.textViews["yours.compose"].exists,
            "the mark opened the private space on the way home"
        )

        // From home it opens the room.
        we.tap()
        let begin = app.buttons["Begin"]
        if begin.waitForExistence(timeout: 3) { begin.tap() }
        XCTAssertTrue(
            app.textViews["yours.compose"].waitForExistence(timeout: 5),
            "a second tap on the mark should open the private space"
        )
    }

    /// With something over Life, the mark means *close this*. Otherwise
    /// dismissing the calendar would drop somebody into the private space,
    /// which is the one place an accidental arrival is least welcome.
    @MainActor
    func testTheMarkClosesTheCalendarRatherThanOpeningYours() throws {
        let app = launchZones()
        let we = app.descendants(matching: .any)["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        app.buttons["field.nav.life"].tap()
        XCTAssertTrue(app.staticTexts["LIFE"].waitForExistence(timeout: 4))
        let affordance = app.buttons["field.life.calendar"]
        XCTAssertTrue(affordance.waitForExistence(timeout: 4))
        affordance.tap()
        XCTAssertTrue(
            app.otherElements["field.calendar"].waitForExistence(timeout: 4)
        )

        // The bar is hidden while the calendar is up, so this is the tap a
        // person makes immediately after closing it — the first one the bar
        // can receive. It has to mean Today, not Yours.
        app.buttons["Done"].tap()
        XCTAssertTrue(we.waitForExistence(timeout: 4))
        we.tap()

        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 4))
        XCTAssertFalse(
            app.textViews["yours.compose"].exists,
            "closing the calendar and pressing the mark opened the private space"
        )
    }

    // MARK: Search

    /// Search finds anything, wherever it was filed. It is the only route in
    /// the app that does not require remembering where something went.
    ///
    /// Driven from the visible control rather than the pull. The pull is an
    /// accelerator and is deliberately *not* covered here: XCUITest cannot
    /// synthesize it — the scroll view claims the drag, and a synthesized
    /// press-and-drag never presents the recogniser with the 90pt it wants.
    /// The calendar's identical gesture was never covered either, for the
    /// same reason, which is part of why both rooms now have a control.
    ///
    /// So this asserts the route everybody has, and the non-interference test
    /// above asserts that the pull does not fire on a tap. What is untested is
    /// only whether the pull fires when it should, and the cost of that being
    /// wrong is an accelerator that does nothing — not a room nobody can open.
    @MainActor
    func testSearchOpensAndFindsSomething() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let control = app.buttons["field.life.search"]
        XCTAssertTrue(waitForHittable(control))
        control.tap()

        XCTAssertTrue(
            app.otherElements["field.search"].waitForExistence(timeout: 4),
            "the search control on Life should open search"
        )

        // Typed at the application, not at the field.
        //
        // The field takes focus the moment the surface appears — arriving here
        // and wanting to type are the same act, and nobody pulls this down to
        // look at it — so there is a first responder already and no tap is
        // needed. That is also the only way to reach it: this field does not
        // surface by identifier or as a `textFields` match, unlike the capture
        // field on Today, and asserting on a query that does not resolve would
        // test the query rather than the screen.
        //
        // So this covers the auto-focus too. If focus ever stops landing here,
        // the characters go nowhere and this fails — which is the right
        // failure, because a search field that has to be tapped first is a
        // search field with an extra step.
        app.typeText("grocery")

        XCTAssertTrue(
            app.buttons["field.search.row"].firstMatch
                .waitForExistence(timeout: 4),
            "search found nothing it was seeded with"
        )

        // By identifier, not by label: the keyboard is up, and its own "done"
        // key matches `buttons["Done"]` just as well as this one does.
        app.descendants(matching: .any)["field.search.done"].tap()
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

    // MARK: - Getting rid of a group
    //
    // Run against the empty couple rather than the seeded one, and not for
    // convenience: the fictional couple has something in all seven built-ins,
    // and putting a group away is refused while anything is in it. A real
    // couple's first launch is the only state where every word on Life is a
    // heading over nothing, which is exactly when somebody would want to set
    // one down.

    /// The whole of the built-in half, in one pass: away, off Life, named at
    /// the foot of it, and back.
    @MainActor
    func testAnEmptyBuiltInGroupCanBePutAwayAndBroughtBack() throws {
        let app = launchEmpty()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let care = app.buttons["field.life.care"]
        XCTAssertTrue(waitForHittable(care))
        care.tap()

        let menu = roomMenu(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()

        let putAway = app.buttons["Put away"].firstMatch
        XCTAssertTrue(putAway.waitForExistence(timeout: 4))
        putAway.tap()

        // The room closes with it. Staying would leave the couple looking at
        // a page for something no longer on Life.
        XCTAssertTrue(care.waitForNonExistence(timeout: 6), "Care stayed on Life")

        // Nothing is ever simply gone.
        let row = app.buttons["field.life.putAway"]
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        XCTAssertEqual(row.label, "1 group put away")
        row.tap()

        let bringBack = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Bring"))
            .firstMatch
        XCTAssertTrue(bringBack.waitForExistence(timeout: 4))
        bringBack.tap()

        XCTAssertTrue(
            app.buttons["field.life.care"].waitForExistence(timeout: 6),
            "Care did not come back"
        )
        XCTAssertTrue(row.waitForNonExistence(timeout: 4))
    }

    /// A container never sets its contents down with it. Care has five things
    /// in it for the seeded couple, so the control is there and refuses.
    @MainActor
    func testAGroupWithThingsInItCannotBePutAway() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let care = app.buttons["field.life.care"]
        XCTAssertTrue(waitForHittable(care))
        care.tap()

        let menu = roomMenu(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()

        let putAway = app.buttons["Put away"].firstMatch
        XCTAssertTrue(putAway.waitForExistence(timeout: 4))
        XCTAssertFalse(
            putAway.isEnabled,
            "a group with things in it offered to hide them along with itself"
        )
    }

    /// The other half: emptying a group in one gesture.
    ///
    /// Run against Care because the fictional couple has no grown category, so
    /// there is nothing on Life whose *word* can be watched disappearing —
    /// that part is `FieldGroupTests.movingAGroupDissolvesIt`, where a grown
    /// group can be arranged. What is driven here is the gesture: menu, sheet,
    /// destination, and a room that is genuinely empty afterwards rather than
    /// a sheet that dismissed without doing anything.
    @MainActor
    func testMovingEverythingOutOfAGroupEmptiesIt() throws {
        let app = launchZones()
        XCTAssertTrue(
            app.buttons["field.nav.life"].waitForExistence(timeout: 8)
        )
        app.buttons["field.nav.life"].tap()
        settleOnLife(app)

        let care = app.buttons["field.life.care"]
        XCTAssertTrue(waitForHittable(care))
        care.tap()

        XCTAssertTrue(
            app.buttons.matching(identifier: "field.room.row").firstMatch
                .waitForExistence(timeout: 6)
        )

        let menu = roomMenu(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()

        let moveAll = app.buttons["Move everything to…"].firstMatch
        XCTAssertTrue(moveAll.waitForExistence(timeout: 4))
        moveAll.tap()

        // The sheet names what it is about to move before anybody commits to
        // it. Matched on the sentence rather than the identifier, for the
        // reason `roomMenu` gives about identifiers on a sheet's root.
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "in Care")
                )
                .firstMatch
                .waitForExistence(timeout: 4),
            "the sheet must name what it is about to move"
        )

        let destination = app.buttons
            .matching(identifier: "field.correction.option")
            .firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 4))
        destination.tap()

        // A real state, said plainly — and the proof that everything moved
        // rather than the sheet simply closing. Matched on the sentence, for
        // the reason `roomMenu` gives about identifiers in this room.
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    NSPredicate(
                        format: "label CONTAINS[c] %@", "Nothing in care"
                    )
                )
                .firstMatch
                .waitForExistence(timeout: 6),
            "the room still had something in it after moving everything out"
        )
        XCTAssertFalse(
            app.buttons.matching(identifier: "field.room.row").firstMatch
                .exists,
            "a row survived a move of everything"
        )
    }

    /// The `•••` in a room's header.
    ///
    /// Addressed by label, not by identifier, and not by choice: the room
    /// carries `field.room.<category>` on its root, and SwiftUI propagates
    /// that down over the identifier on every control in the header — the
    /// `•••` and Done both report `field.room.care` in the tree. It is the
    /// same quirk `testACategoryOpensItsRoomAndCloses` names when it says the
    /// close button does not surface by identifier, and it is why Done is
    /// tapped by label there too.
    ///
    /// The label is real accessibility text rather than a test hook, so this
    /// is not a weaker assertion — a `•••` that stopped announcing itself as
    /// "More" would be a bug worth failing on.
    @MainActor
    private func roomMenu(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["More"].firstMatch
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
    // The way in is a tap on the WE mark while Today is already showing, and
    // there is no control for it. That is the point: §2 wants the room
    // wordless, and a permanent button in the chrome is the loudest possible
    // way to describe somewhere private. What the bar carries instead is a
    // hint, once.
    //
    // It was an upward drag on the bar until it turned out that a gesture with
    // no feedback and a 40pt threshold is indistinguishable, to the person
    // attempting it, from a room that is not there.

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
    func testTappingTheMarkFromTodayOpensOntoWritingAndAQuietEmptyState() {
        let app = launchZones()
        openYours(app)

        XCTAssertTrue(
            app.textViews["yours.compose"].waitForExistence(timeout: 5),
            "the tap did not open the space"
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
        openYours(app)

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

    /// The way in: a tap on the WE mark while Today is already showing.
    ///
    /// It used to be an upward drag on the bar, which asked for 40pt of travel
    /// in a direction nothing else moved and resolved only on release — so a
    /// failed attempt and no attempt looked the same, and the test had to
    /// simulate it by coordinate because `app.swipeUp()` dragged the zone's
    /// scroll view instead.
    ///
    /// A cold launch lands on Today (`activeZone` defaults to `.we`), so one
    /// tap is the whole gesture. Every caller here launches fresh; a caller
    /// that had navigated away first would need two.
    ///
    /// Also clears the first-entry teaching sheet. It is `interactiveDismiss`
    /// disabled and covers the room, so without this every assertion about
    /// what the room does is really an assertion about a sheet sitting on top
    /// of it — the element is found, and nothing on it can be touched.
    @MainActor
    private func openYours(_ app: XCUIApplication) {
        let we = app.descendants(matching: .any)["field.nav.we"]
        XCTAssertTrue(we.waitForExistence(timeout: 8))

        we.tap()

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
