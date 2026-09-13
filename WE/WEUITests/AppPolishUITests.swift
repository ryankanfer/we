import XCTest

final class AppPolishUITests: XCTestCase {
    @MainActor private func launch(large: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app, maximumDynamicType: large, reduceMotion: true, reduceTransparency: true)
        app.launchEnvironment["WE_FIELD"] = "seeded"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["field.nav.life"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor func testMainSurfacesAndExits() {
        let app = launch(large: false)
        keepScreenshot(of: app, named: "polish.today")
        app.buttons["field.nav.life"].tap()
        keepScreenshot(of: app, named: "polish.life")
        app.buttons["field.life.calendar"].tap()
        XCTAssertTrue(app.buttons["field.calendar.done"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "polish.calendar")
        app.buttons["field.openChat"].tap()
        XCTAssertTrue(app.buttons["field.chat.done"].waitForExistence(timeout: 5))
        app.buttons["field.chat.done"].tap()
        XCTAssertTrue(app.buttons["field.calendar.done"].waitForExistence(timeout: 5))
        app.buttons["field.calendar.done"].tap()
        app.buttons["field.life.search"].tap()
        XCTAssertTrue(app.textFields["field.search.field"].waitForExistence(timeout: 5))
        app.textFields["field.search.field"].typeText("Japan")
        keepScreenshot(of: app, named: "polish.search")
        app.buttons["field.openChat"].tap()
        XCTAssertTrue(app.buttons["field.chat.done"].waitForExistence(timeout: 5))
        app.buttons["field.chat.done"].tap()
        XCTAssertTrue(app.textFields["field.search.field"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["field.search.field"].value as? String, "Japan")
        app.buttons["field.search.done"].tap()
        app.buttons["field.nav.us"].tap()
        XCTAssertTrue(app.buttons["field.us.goals"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "polish.us")
        app.buttons["field.openAccount"].tap()
        XCTAssertTrue(app.buttons["field.account.done"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "polish.account")
        app.buttons["field.account.done"].tap()
        app.buttons["field.nav.we"].tap()
        app.buttons["field.openYours"].tap()
        let begin = app.buttons["yours.teaching.begin"]
        if begin.waitForExistence(timeout: 2) { begin.tap() }
        XCTAssertTrue(app.buttons["yours.close"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "polish.yours")
        app.buttons["yours.close"].tap()
    }
    @MainActor func testLargestTextNavigationAndAccountExit() {
        let app = launch(large: true)
        for zone in ["life", "us", "we"] {
            let button = app.buttons["field.nav.\(zone)"]
            XCTAssertTrue(button.isHittable); button.tap()
            if zone == "us" {
                for concept in app.buttons.allElementsBoundByIndex where concept.identifier.hasPrefix("field.us.concept.") {
                    XCTAssertLessThanOrEqual(concept.frame.maxX, app.frame.maxX + 1)
                    XCTAssertGreaterThanOrEqual(concept.frame.minX, app.frame.minX - 1)
                }
            }
            keepScreenshot(of: app, named: "polish.\(zone).accessibility5")
        }
        app.buttons["field.nav.life"].tap()
        app.buttons["field.life.calendar"].tap()
        XCTAssertTrue(app.buttons["field.calendar.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["field.calendar.done"].isHittable)
        keepScreenshot(of: app, named: "polish.calendar.accessibility5")
        app.buttons["field.calendar.done"].tap()
        app.buttons["field.openAccount"].tap()
        XCTAssertTrue(app.buttons["field.account.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["field.account.done"].isHittable)
        app.buttons["field.account.done"].tap()
    }
}
