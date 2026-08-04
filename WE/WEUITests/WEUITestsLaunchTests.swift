//
//  WEUITestsLaunchTests.swift
//  WEUITests
//
//  Created by Ryan Kanfer on 7/24/26.
//

import XCTest

final class WEUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app)
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "ready"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launch()

        XCTAssertTrue(
            app.buttons["field.nav.we"].waitForExistence(timeout: 10)
        )
        keepScreenshot(of: app, named: "golden.field.launch")
    }
}
