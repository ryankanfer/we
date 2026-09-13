import XCTest

final class FieldConversationLinkUITests: XCTestCase {
    @MainActor
    func testLinksTravelFromConversationToLifeAndBack() throws {
        try exerciseLinks(largeText: false)
    }

    @MainActor
    func testLinkComposerAtLargestAccessibilityTextSize() throws {
        try exerciseLinks(largeText: true)
    }

    @MainActor
    private func exerciseLinks(largeText: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        WEUITestLaunchSupport.configure(app, maximumDynamicType: largeText, reduceMotion: true)
        app.launchEnvironment["WE_FIELD"] = "live"
        app.launchEnvironment["WE_REPOSITORY"] = "preview"
        app.launchEnvironment["WE_PREVIEW_SCENARIO"] = "empty"
        app.launchEnvironment["WE_SHARED_JOURNEYS"] = "1"
        app.launchEnvironment["WE_SKIP_PROMISE"] = "1"
        app.launchEnvironment["WE_SKIP_WALKTHROUGH"] = "1"
        app.launchEnvironment["WE_DISABLE_CREDENTIAL_PROMPTS"] = "1"
        app.launchArguments += ["-hasSeenLivingConfluencePromise", "YES", "-hasSeenWalkthrough", "YES"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        }
        app.launch()
        let chat = app.buttons["Chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.tap()
        let input = app.descendants(matching: .any).matching(identifier: "field.chat.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("A weekend away? https://example.com/stay https://example.org/garden")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "field.chat.linkPreview").firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["field.chat.done"].isHittable, "Keep navigation visible above a multiline draft and keyboard")
        XCTAssertGreaterThanOrEqual(app.buttons["field.chat.done"].frame.minY, app.frame.minY, "The header must remain inside the visible screen")
        capture(largeText ? "Accessible link composer" : "Links ready to send", app: app)
        app.buttons["field.chat.send"].tap()
        let saved = app.buttons.matching(identifier: "field.chat.savedLink")
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.count, 2)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let done = app.buttons["field.chat.done"]
            return !app.keyboards.firstMatch.exists && done.frame.minY >= 0 && done.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        capture(largeText ? "Accessible saved links" : "Links saved in conversation", app: app)
        if largeText { return }
        saved.firstMatch.tap()
        let discuss = app.buttons["Discuss this together"]
        for _ in 0..<6 where !discuss.isHittable { app.swipeUp() }
        XCTAssertTrue(discuss.isHittable)
        discuss.tap()
        XCTAssertTrue(app.buttons["field.chat.showAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A weekend away?"].exists)
        capture("Life conversation return path", app: app)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
