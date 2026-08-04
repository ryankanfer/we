//
//  WalkthroughUITests.swift
//  WEUITests
//
//  The walkthrough is the one surface whose whole job is to be read, so the
//  thing worth testing is that it can be: that it opens by itself exactly
//  once, that every journey draws its beats and can be stepped through to the
//  end, and that every step keeps a way out.
//
//  `WalkthroughTests` in the unit target already proves the three rules fire
//  and fire on the right subjects. These tests deliberately do not re-assert
//  that. They assert the parts only a running app can answer — presentation,
//  reachability, and whether the last button actually finishes.
//

import XCTest

final class WalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: When it plays

    /// The gate's whole claim, end to end: a first run gets it, and the run
    /// after that does not.
    @MainActor
    func testItPlaysOnceOnAFirstRunAndNotAgain() throws {
        let app = launchIntoWalkthrough()
        XCTAssertTrue(
            app.buttons["walkthrough.journey.movement"]
                .waitForExistence(timeout: 5)
        )

        app.buttons["walkthrough.notNow"].tap()
        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 4),
            "Dismissing the walkthrough should leave the welcome screen"
        )

        // Relaunched without the harness override, and with `hasSeen` now
        // written by the app itself rather than by a launch argument.
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
            second.buttons["walkthrough.journey.movement"].exists,
            "The chooser should not be up on a second run"
        )
    }

    // MARK: The journeys

    @MainActor
    func testEveryJourneyCanBeReadToItsEnd() throws {
        for journey in ["movement", "context", "memory"] {
            let app = launchIntoWalkthrough()
            let door = app.buttons["walkthrough.journey.\(journey)"]
            XCTAssertTrue(
                door.waitForExistence(timeout: 5),
                "\(journey) should be offered on the chooser"
            )
            door.tap()

            // Every journey is two beats. Stepping through them must never
            // dead-end: each one offers either another step or a way out.
            for step in 0..<2 {
                let next = app.buttons["walkthrough.next"]
                let done = app.buttons["walkthrough.done"]
                XCTAssertTrue(
                    next.waitForExistence(timeout: 3) || done.exists,
                    "\(journey) step \(step) offered no way forward"
                )
                // Skip is on every step, not just the first.
                XCTAssertTrue(
                    app.buttons["walkthrough.skip"].exists,
                    "\(journey) step \(step) had no way out"
                )
                if next.exists { next.tap() } else { done.tap() }
            }

            app.terminate()
        }
    }

    /// The last journey's last button ends the walkthrough rather than
    /// offering a fourth thing that does not exist.
    @MainActor
    func testTheLastJourneyFinishes() throws {
        let app = launchIntoWalkthrough()
        let door = app.buttons["walkthrough.journey.memory"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()

        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()

        let done = app.buttons["walkthrough.done"]
        XCTAssertTrue(
            done.waitForExistence(timeout: 3),
            "The last step of the last journey should say Done"
        )
        done.tap()

        XCTAssertTrue(
            app.buttons["welcome.start"].waitForExistence(timeout: 4),
            "Finishing should hand the screen back"
        )
    }

    /// Journey one chains to journey two by name. This is what makes reading
    /// all three in a row possible without returning to the chooser.
    @MainActor
    func testAJourneyOffersTheNextOneByName() throws {
        let app = launchIntoWalkthrough()
        let door = app.buttons["walkthrough.journey.movement"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()

        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()

        let chain = app.buttons["walkthrough.next"]
        XCTAssertTrue(chain.waitForExistence(timeout: 3))
        XCTAssertEqual(chain.label, "Next: Ryan's dad")
        chain.tap()

        // Landed in the occasion journey, and back at its first beat rather
        // than carrying the previous journey's last step across.
        XCTAssertTrue(
            app.staticTexts["FILED APART"]
                .waitForExistence(timeout: 3)
        )
    }

    // MARK: Reachable

    @MainActor
    func testTheWalkthroughIsUsableAtAccessibilityTextSizeAndPassesAudit()
        throws
    {
        let app = launchIntoWalkthrough(accessibilityTextSize: true)
        XCTAssertTrue(
            app.buttons["walkthrough.journey.movement"]
                .waitForExistence(timeout: 5)
        )

        // At AX5 the chooser scrolls; the third door is the one that would be
        // stranded below the fold.
        let last = app.buttons["walkthrough.journey.memory"]
        for _ in 0..<8 where !last.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(last.isHittable, "The third journey should be reachable")

        try app.performAccessibilityAudit(
            for: [
                .hitRegion,
                .sufficientElementDescription,
                .textClipped,
                .trait,
            ]
        )
    }

    /// The stage inside a journey is the dense part — a card, a question, two
    /// tinted answers — and it is the part most likely to clip at AX5.
    @MainActor
    func testAJourneyPassesTheAuditAtAccessibilityTextSize() throws {
        let app = launchIntoWalkthrough(accessibilityTextSize: true)
        let door = app.buttons["walkthrough.journey.context"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()

        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 4))
        // The second beat carries the question and both answers.
        next.tap()

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
