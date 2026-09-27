//
//  WalkthroughUITests.swift
//  WEUITests
//
//  The walkthrough plays once, right after an account is created, and never
//  for someone signing in. These cover when it appears, that every step can
//  be read to the end in both directions, and that it stays reachable at the
//  largest type size.
//

import XCTest

final class WalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: When it plays

    @MainActor
    func testItPlaysAfterCreatingAnAccountAndHandsOffToPairing() throws {
        let app = launch(scenario: "signedout")
        app.buttons["welcome.start"].tap()
        createAccount(app)

        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Sign up should open the walkthrough")
        app.buttons["walkthrough.skip"].tap()

        XCTAssertTrue(
            app.buttons["pairing.createInvitation"].waitForExistence(timeout: 5),
            "Skipping should leave the pairing screen underneath"
        )
    }

    @MainActor
    func testSigningInNeverPlaysIt() throws {
        let app = launch(scenario: "signedout")
        app.buttons["welcome.signIn"].tap()
        let email = app.textFields["account.field.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("ryan@example.com\n")
        app.secureTextFields["account.field.password"].typeText("password\n")

        XCTAssertTrue(app.staticTexts["Your account is ready."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["walkthrough.next"].exists)
    }

    @MainActor
    func testTheWelcomeScreenNoLongerOffersIt() throws {
        let app = launch(scenario: "signedout")
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["welcome.walkthrough"].exists)
        XCTAssertFalse(app.buttons["walkthrough.next"].exists)
    }

    // MARK: Reading it through

    @MainActor
    func testEveryStepCanBeReadToTheEnd() throws {
        let app = launch(scenario: "ready", pending: true)
        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))

        // Hello, then Three buttons. + opens the real card.
        next.tap()
        let plus = app.buttons["walkthrough.plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        next.tap()

        // Say it: Next waits for send.
        let send = app.buttons["walkthrough.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "Next should wait until the sentence is sent")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 6)
        send.tap()
        XCTAssertTrue(app.otherElements["walkthrough.savedItem"].waitForExistence(timeout: 5)
            || app.staticTexts["walkthrough.savedItem"].exists)
        next.tap()

        // Shared or yours.
        let onlyMe = app.buttons["walkthrough.visibility.private"]
        XCTAssertTrue(onlyMe.waitForExistence(timeout: 5))
        onlyMe.tap()
        XCTAssertTrue(onlyMe.isSelected)
        next.tap()

        // Three promises, lit one at a time, then the handoff.
        next.tap(); next.tap(); next.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertFalse(
            app.buttons["walkthrough.skip"].waitForExistence(timeout: 2),
            "The last button should hand the screen back"
        )
    }

    @MainActor
    func testBackReturnsThroughEveryStep() throws {
        let app = launch(scenario: "ready", pending: true)
        let next = app.buttons["walkthrough.next"]
        let back = app.buttons["walkthrough.back"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(back.exists, "The first screen has nowhere to go back to")

        next.tap(); next.tap()
        XCTAssertTrue(app.buttons["walkthrough.send"].waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["walkthrough.plus"].waitForExistence(timeout: 5))
        back.tap()
        XCTAssertFalse(back.waitForExistence(timeout: 2))
        app.buttons["walkthrough.skip"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
    }

    // MARK: Reachable

    @MainActor
    func testHelloPassesTheAuditAtAccessibilityTextSize() throws {
        let app = launch(scenario: "ready", pending: true, accessibilityTextSize: true)
        XCTAssertTrue(app.buttons["walkthrough.next"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .textClipped, .trait]
        )
    }

    @MainActor
    func testThreeButtonsPassesTheAuditAtAccessibilityTextSize() throws {
        let app = launch(scenario: "ready", pending: true, accessibilityTextSize: true)
        let next = app.buttons["walkthrough.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        keepScreenshot(of: app, named: "walkthrough.three-buttons.accessibility5")
        XCTAssertTrue(next.isHittable)
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .textClipped]
        )
    }

    // MARK: -

    /// `pending` stands in for an account that was just created: it is the
    /// flag `AppSession.signUp` writes, supplied in the argument domain.
    @MainActor
    private func launch(
        scenario: String,
        pending: Bool = false,
        accessibilityTextSize: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = scenario
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
            "-hasSeenWalkthrough", "NO",
        ]
        if pending {
            app.launchArguments += ["-walkthroughPendingAfterSignUp", "YES"]
        }
        if accessibilityTextSize {
            app.launchEnvironment["WE_TEST_DYNAMIC_TYPE"] = "accessibility5"
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        }
        app.launch()
        return app
    }

    @MainActor
    private func createAccount(_ app: XCUIApplication) {
        let name = app.textFields["account.field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ry\n")
        let email = app.textFields["account.field.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        email.tap()
        email.typeText("ry@example.com\n")
        let password = app.secureTextFields["account.field.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 3))
        password.tap()
        password.typeText("together2026\n")
    }
}
