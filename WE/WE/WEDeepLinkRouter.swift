import Foundation

enum WEDeepLinkDestination: Sendable {
    case today
}

enum WEDeepLinkRouter {
    static let didRequestToday = Notification.Name(
        "WEDeepLinkRouter.didRequestToday"
    )

    static func destination(for url: URL) -> WEDeepLinkDestination? {
        guard url.scheme?.lowercased() == "we" else { return nil }
        if url.host?.lowercased() == "today" {
            return .today
        }
        return nil
    }

    /// Returns true only when the URL is a product deep link. Authentication
    /// callback URLs remain available to the session's auth handler.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let destination = destination(for: url) else { return false }
        switch destination {
        case .today:
            NotificationCenter.default.post(name: didRequestToday, object: nil)
        }
        return true
    }
}
