import XCTest

enum WEUITestLaunchSupport {
    /// Wednesday 13 August 2025, the fixed date used by the committed Field
    /// fixture. Noon UTC keeps the calendar day stable in every CI timezone.
    static let frozenNow = "2025-08-13T12:00:00Z"

    @MainActor
    static func configure(
        _ app: XCUIApplication,
        maximumDynamicType: Bool = false,
        reduceMotion: Bool = true,
        reduceTransparency: Bool? = nil
    ) {
        XCUIDevice.shared.orientation = .portrait

        let matrixReduceTransparency = bool(
            ProcessInfo.processInfo.environment[
                "WE_QA_REDUCE_TRANSPARENCY"
            ]
        )
        let effectiveReduceTransparency =
            reduceTransparency ?? matrixReduceTransparency ?? false

        app.launchEnvironment["WE_QA_FIXED_NOW"] = frozenNow
        app.launchEnvironment["WE_QA_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["WE_TEST_REDUCE_MOTION"] =
            reduceMotion ? "1" : "0"
        app.launchEnvironment["WE_TEST_REDUCE_TRANSPARENCY"] =
            effectiveReduceTransparency ? "1" : "0"
        // SwiftUI's accessibility values are read-only Environment keys.
        // XCTest's launch defaults are therefore the authoritative way to
        // select these variants for the target process.
        app.launchArguments += [
            "-UIAccessibilityReduceMotionEnabled",
            reduceMotion ? "YES" : "NO",
            "-UIAccessibilityReduceTransparencyEnabled",
            effectiveReduceTransparency ? "YES" : "NO",
        ]
        let requestedDynamicType = maximumDynamicType
            ? "accessibility5"
            : ProcessInfo.processInfo.environment["WE_QA_DYNAMIC_TYPE"]
        if let requestedDynamicType, !requestedDynamicType.isEmpty {
            // Matrix-level values live in the UI-test runner. XCUIApplication
            // does not promise to inherit that process environment, so copy
            // the requested category into every launched app explicitly.
            app.launchEnvironment["WE_QA_DYNAMIC_TYPE"] =
                requestedDynamicType
        }
    }

    private static func bool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes": true
        case "0", "false", "no": false
        default: nil
        }
    }
}

extension XCTestCase {
    @MainActor
    func keepScreenshot(
        of app: XCUIApplication,
        named name: String
    ) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name.lowercased().hasSuffix(".png")
            ? name
            : "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
