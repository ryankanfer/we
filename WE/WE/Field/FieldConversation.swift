import Foundation

struct FieldChatContext: Codable, Hashable, Identifiable, Sendable {
    var kind: String
    var id: String
}
struct FieldChatMessage: Codable, Hashable, Identifiable, Sendable {
    var id = UUID().uuidString
    var body: String
    var sender: FieldOwner
    var createdAt = Date()
    var context: FieldChatContext?
    var decision = false
    var confirmed = false
    var sourceID: String?
    var valid: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.count <= 4000 }
    var urls: [URL] { FieldConversationLinks.urls(in: body) }
    var firstURL: URL? { urls.first }
    var textWithoutLinks: String { FieldConversationLinks.textWithoutLinks(in: body) }

}
struct FieldChatPreference: Codable, Hashable, Sendable {
    var owner: FieldOwner
    var notices: Bool
    var readAt: Date? = nil
    var notifications: Bool? = nil
}

enum FieldConversationPolicy {
    static func noticesAllowed(_ preferences: [FieldChatPreference]) -> Bool {
        [.a, .b].allSatisfy { owner in preferences.contains { $0.owner == owner && $0.notices } }
    }
    static func evidence(_ messages: [FieldChatMessage]) -> [LifeItem] {
        messages.filter { !$0.decision }.map {
            LifeItem(id: $0.id, title: $0.body, category: .notes, owner: .shared,
                     dueOn: nil, closesAt: nil, clusterID: nil, source: .captured, detail: nil,
                     isTimeCritical: false, isDone: false, sourceURL: $0.firstURL, visibility: .shared)
        }
    }
}

/// URL identity deliberately keeps queries and fragments: either may identify
/// a different resource. Never fetch a pasted URL just to render a preview.
enum FieldConversationLinks {
    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, seen.insert(key(url)).inserted else { return nil }
            return url
        }
    }

    static func key(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
        return parts.string ?? url.absoluteString
    }

    static func textWithoutLinks(in text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return text }
        let result = NSMutableString(string: text)
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if let url = match.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                result.replaceCharacters(in: match.range, with: "")
            }
        }
        return (result as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(_ url: URL) -> String {
        let host = url.host() ?? "Saved link"
        let path = url.path.removingPercentEncoding ?? url.path
        return String((path.isEmpty || path == "/" ? host : host + path).prefix(240))
    }
}
