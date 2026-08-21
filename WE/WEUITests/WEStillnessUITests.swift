import XCTest

/// The stillness, on a device.
///
/// The screen is the product's thesis in one frame, so it is captured rather
/// than described. Someone who has never seen the app should be able to look
/// at this and say what WE believes without reading a word of explanation.
final class WEStillnessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTheStillnessIsOneLineAndAWayOut() throws {
        let app = launchGallery()

        stillnessRow(app).tap()

        let stillness = app.descendants(matching: .any)
            .matching(identifier: "we.stillness")
            .firstMatch
        XCTAssertTrue(stillness.waitForExistence(timeout: 8))

        keepScreenshot(of: app, named: "golden.we.stillness")

        // One line. Not a heading over a body, not a line and a hint, not a
        // line and a card. If a second sentence ever appears here, the screen
        // has started explaining itself.
        XCTAssertTrue(
            app.staticTexts["WE is still until Dylan arrives."]
                .waitForExistence(timeout: 4)
        )

        // Nothing accumulating. These are the words a helpful future commit
        // would reach for, and none of them belongs on this screen.
        for forbidden in ["Still waiting", "Waiting", "Resend", "Remind",
                          "Invite again", "Check again"] {
            XCTAssertFalse(
                app.staticTexts[forbidden].exists,
                "the stillness must not say \(forbidden)"
            )
        }

        // A way out that does not ask to be looked at, but is reachable.
        XCTAssertTrue(app.buttons["we.stillness.withdraw"].exists)
    }

    /// Reduce Motion must not leave a static screen looking broken, and
    /// Reduce Transparency must not leave it looking like a bar chart.
    @MainActor
    func testTheStillnessHoldsUnderReducedMotionAndTransparency() throws {
        let app = launchGallery(reducedEverything: true)

        stillnessRow(app).tap()

        let stillness = app.descendants(matching: .any)
            .matching(identifier: "we.stillness")
            .firstMatch
        XCTAssertTrue(stillness.waitForExistence(timeout: 8))
        keepScreenshot(of: app, named: "golden.we.stillness.reduced")

        XCTAssertTrue(
            app.staticTexts["WE is still until Dylan arrives."].exists
        )
    }

    /// The gallery rows carry identifiers of their own, so the row has to be
    /// found by the words on it rather than by name.
    @MainActor
    private func stillnessRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "stillness"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        return row
    }

    @MainActor
    private func launchGallery(
        reducedEverything: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(
            app,
            reduceMotion: reducedEverything,
            reduceTransparency: reducedEverything
        )
        app.launchEnvironment["WE_FIELD"] = "gallery"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchArguments += [
            "-hasSeenLivingConfluencePromise", "YES",
            "-hasSeenWalkthrough", "YES",
        ]
        app.launch()
        return app
    }
}
