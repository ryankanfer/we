import XCTest

@MainActor
final class WEAccountSurfaceUITests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app, maximumDynamicType: large, reduceMotion: large)
        if !large { app.launchEnvironment["WE_QA_DISABLE_ANIMATIONS"] = "0" }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "signedout"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchArguments += ["-hasSeenLivingConfluencePromise", "YES", "-hasSeenWalkthrough", "YES"]
        app.launch()
        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 15))
        if !signIn.isHittable { app.swipeUp() }
        signIn.tap()
        XCTAssertTrue(app.staticTexts["Welcome back."].waitForExistence(timeout: 5))
        return app
    }

    func testSignInRevealAndSubmit() {
        let app = launch()
        keepScreenshot(of: app, named: "sign-in")
        XCTAssertFalse(app.buttons["accountSubmitButton"].isEnabled)
        let email = app.textFields["account.field.email"]
        email.tap(); email.typeText("alex@example.com")
        email.typeText("\n")
        app.secureTextFields["account.field.password"].typeText("password")
        app.buttons["account.password.visibility"].tap()
        XCTAssertEqual(app.textFields["account.field.password"].value as? String, "password")
        app.buttons["account.password.visibility"].tap()
        XCTAssertTrue(app.secureTextFields["account.field.password"].exists)
        keepScreenshot(of: app, named: "sign-in-keyboard")
        app.secureTextFields["account.field.password"].typeText("\n")
        XCTAssertTrue(app.staticTexts["Your account is ready."].waitForExistence(timeout: 10))
    }

    func testCreationAndReset() {
        let app = launch()
        app.buttons["account.mode.create"].tap()
        XCTAssertTrue(app.textFields["account.field.name"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "create-account")
        app.swipeUp()
        app.buttons["account.mode.signIn"].tap()
        app.buttons["account.forgotPassword"].tap()
        XCTAssertTrue(app.staticTexts["We'll send a link."].waitForExistence(timeout: 5))
        let email = app.textFields.matching(identifier: "account.field.email").allElementsBoundByIndex.last!
        email.tap(); email.typeText("alex@example.com\n")
        XCTAssertTrue(app.staticTexts["Check your email."].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "password-reset")
        app.buttons["account.reset.back"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["account.field.email"].value as? String, "alex@example.com")
    }

    func testLargestTypeCanReachActionsAndClose() {
        let app = launch(large: true)
        keepScreenshot(of: app, named: "sign-in-accessibility")
        let create = app.buttons["account.mode.create"]
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        let close = app.buttons["account.close"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["welcome.signIn"].waitForExistence(timeout: 5))
    }
}
