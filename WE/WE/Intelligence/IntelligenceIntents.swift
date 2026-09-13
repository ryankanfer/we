import Observation

import AppIntents
import Foundation

struct WEPrivateCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Save privately in WE"
    static var description = IntentDescription("Save text or a link as Only Me. Understanding and sharing happen separately inside WE.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Text or HTTPS link") var text: String
    @MainActor func perform() async throws -> some IntentResult {
        guard WEFeatureFlags.shareInboxEnabled else { throw SharePublicationError.unavailable }
        let store = WEIntelligenceStore.shared; store.reload()
        let candidate: IncomingShareCandidate
        if let url = URL(string: text), IncomingShareParser.canonicalHTTPSURL(url) != nil { candidate = .webURL(url, label: "Link") }
        else { candidate = .text(text, label: "Thought") }
        try store.capture([candidate])
        return .result()
    }
}
struct WEOpenPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "Open a WE plan"
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Plan ID") var planID: String
    @MainActor func perform() async throws -> some IntentResult {
        _ = try ShareVaultController.shared.activeContext()
        guard UUID(uuidString: planID) != nil else { throw SharePublicationError.invalidReview }
        WEPlanNavigation.shared.pendingID = planID
        return .result()
    }
}
@MainActor @Observable final class WEPlanNavigation {
    static let shared = WEPlanNavigation()
    var pendingID: String?
}
