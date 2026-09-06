import Foundation

enum WEDeepLinkDestination: Sendable, Equatable {
    case today
    /// An invitation link. The code arrives already normalised — the router
    /// runs it through `PendingInvitation.normalized`, the same function the
    /// text field uses, so a tapped link and a typed code cannot disagree.
    case join(code: String)
}

enum WEDeepLinkRouter {
    static let didRequestToday = Notification.Name(
        "WEDeepLinkRouter.didRequestToday"
    )

    static func destination(for url: URL) -> WEDeepLinkDestination? {
        guard url.scheme?.lowercased() == "we" else { return nil }
        switch url.host?.lowercased() {
        case "today":
            return .today
        case "join":
            guard let code = joinCode(from: url) else { return nil }
            return .join(code: code)
        default:
            return nil
        }
    }

    /// Accepts both `we://join/CODE` and `we://join?code=CODE`. A link with no
    /// usable code is not a join link — better to fall through than to open the
    /// welcome screen claiming to hold an invitation it does not have.
    private static func joinCode(from url: URL) -> String? {
        let path = url.pathComponents.first { $0 != "/" && !$0.isEmpty }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "code" }?
            .value

        guard let raw = path ?? query else { return nil }
        return PendingInvitation.normalized(raw)
    }

    /// Returns true only when the URL is a product deep link that this router
    /// can fully handle on its own. Authentication callback URLs remain
    /// available to the session's auth handler.
    ///
    /// `.join` deliberately returns false: holding a code mutates
    /// `PendingInvitation`, which is main-actor state owned by `WEApp`. The app
    /// handles that case in `onOpenURL` rather than through a notification the
    /// way `.today` works.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let destination = destination(for: url) else { return false }
        switch destination {
        case .today:
            NotificationCenter.default.post(name: didRequestToday, object: nil)
            return true
        case .join:
            return false
        }
    }
}
