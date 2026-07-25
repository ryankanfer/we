//
//  WEUITestsLaunchTests.swift
//  WEUITests
//
//  Created by Ryan Kanfer on 7/24/26.
//

import XCTest

final class WEUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "ready"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "WE Native Product"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
