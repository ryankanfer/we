//
//  SignUpDemoUITests.swift
//  WEUITests
//
//  Two paced walkthroughs of the first run, one per side, for recording a
//  demo — not assertions about behaviour, which live in `WEUITests`.
//
//  Skipped unless the runner is given WE_DEMO=1:
//
//      TEST_RUNNER_WE_DEMO=1 xcodebuild test ... -only-testing:WEUITests/SignUpDemoUITests
//
//  Both run against the preview repository, so no real account is created.
//

import XCTest

final class SignUpDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WE_DEMO"] == "1",
            "demo walkthroughs run only when recording"
        )
        continueAfterFailure = false
    }

    /// Ryan starts WE: Begin, an account, then the invitation for Dylan.
    @MainActor
    func testInviter() throws {
        let app = launch()
        beat(3)

        press(app.buttons["welcome.start"])
        beat(1.5)
        fill(app, name: "Ryan", email: "ryan@example.com")

        XCTAssertTrue(app.buttons["pairing.createInvitation"].waitForExistence(timeout: 8))
        beat(3)
        press(app.buttons["pairing.createInvitation"])

        XCTAssertTrue(app.buttons["waiting.share"].waitForExistence(timeout: 8))
        beat(3)
        let invitee = app.textFields["waiting.inviteeName"]
        if invitee.waitForExistence(timeout: 3) {
            invitee.tap()
            invitee.typeText("Dylan\n")
        }
        beat(4)
        app.swipeUp()
        beat(4)
    }

    /// Dylan was sent a code: "Someone invited me", the code, who is
    /// waiting, an account, the Promise, and Today.
    @MainActor
    func testInvited() throws {
        let app = launch(skipsPromise: false)
        beat(3)

        press(app.buttons["welcome.join"])
        beat(1.5)
        let code = app.textFields.firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 4))
        code.tap()
        code.typeText("WEDEMO")
        beat(1)
        app.buttons["welcome.joinCode.continue"].firstMatch.tap()
        beat(3)
        // The line now names who is waiting; continuing opens account creation.
        let proceed = app.buttons["welcome.joinCode.continue"].firstMatch
        if proceed.waitForExistence(timeout: 3) { proceed.tap() }

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 6))
        beat(1.5)
        fill(app, name: "Dylan", email: "dylan@example.com")

        // The Promise is performed live on both phones at arrival; it needs
        // the server's ceremony record, which the preview does not have.
        XCTAssertTrue(app.buttons["Add something"].waitForExistence(timeout: 12))
        beat(5)
    }

    // MARK: -

    @MainActor
    private func launch(skipsPromise: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "signedout"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = skipsPromise ? "1" : "0"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchArguments += [
            "-we.invitation.sent", "NO",
            "-we.invitee.name", "",
            "-hasSeenWalkthrough", "YES",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func fill(_ app: XCUIApplication, name: String, email: String) {
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        nameField.tap()
        // Return moves to the next field, the way a person would go.
        nameField.typeText(name + "\n")
        beat(0.6)
        app.textFields["Email"].typeText(email + "\n")
        beat(0.6)
        app.secureTextFields["Password"].typeText("together2026")
        beat(1.2)
        // Go on the keyboard creates the account.
        app.secureTextFields["Password"].typeText("\n")
        // iOS offers to save the password; a demo says not now.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let button = [app.buttons["Not Now"], springboard.buttons["Not Now"]]
                .first(where: \.exists) {
                beat(1)
                button.tap()
                break
            }
            beat(0.4)
        }
    }

    /// Taps once the element can take it; the welcome screen settles in.
    @MainActor
    private func press(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        let deadline = Date().addingTimeInterval(8)
        while !element.isHittable, Date() < deadline { beat(0.3) }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
