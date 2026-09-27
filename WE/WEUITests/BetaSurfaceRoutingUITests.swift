import XCTest

final class BetaSurfaceRoutingUITests: XCTestCase {
    @MainActor
    func testAcceptedSurfacesOpenFromLiveRootWithoutGalleryOrSeed() throws {
        try verifyAccountSurfaces(large: false)
    }

    @MainActor
    func testAccountSurfacesAtLargestTextSize() throws {
        try verifyAccountSurfaces(large: true)
    }

    @MainActor
    private func verifyAccountSurfaces(large: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app, maximumDynamicType: large, reduceMotion: true)
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
        ]
        app.launchEnvironment["WE_FIELD"] = "live"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "empty"
        app.launchEnvironment["WE_SHARED_JOURNEYS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += ["-hasSeenLivingConfluencePromise", "YES", "-hasSeenWalkthrough", "YES"]
        app.launch()
        let account = app.buttons["field.openAccount"]
        XCTAssertTrue(account.waitForExistence(timeout: 15))
        account.tap()
        XCTAssertFalse(app.staticTexts["Your colours"].exists)
        XCTAssertTrue(app.buttons["field.account.done"].isHittable)
        capture(app, name: large ? "account-large" : "account")
        for (route, destination) in [
            ("presence", "field.presence"),
            ("moment", "field.moment"),
            ("deferral", "field.deferral"),
            ("corrections", "field.us.corrections"),
            ("seasons", "field.seasons.empty")
        ] {
            let button = app.buttons["field.account." + route]
            for _ in 0..<20 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable, "Missing real account route: " + route)
            button.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: destination).firstMatch.waitForExistence(timeout: 5), route)
            let done = app.buttons["field.account.surface.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            if route == "moment" {
                let earlier = app.buttons["field.moment.earlier"]
                for _ in 0..<12 where !earlier.isHittable { app.swipeUp() }
                XCTAssertTrue(earlier.isHittable)
                XCTAssertTrue(app.buttons["field.moment.later"].isHittable)
            }
            capture(app, name: route + (large ? "-large" : ""))
            XCTAssertTrue(done.isHittable)
            done.tap()
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
