import Foundation

/// The only result that can cross from two owner-only answers into shared UI.
/// Exact answers and notes are never copied into this value.
nonisolated struct SharedDirection: Codable, Hashable, Sendable {
    let insightID: String
    let key: String
    let eyebrow: String
    let title: String
    let message: String
    let symbol: String
    let createdAt: String?
    var summary: String? = nil
    var rationale: String? = nil
    var proposedActions: [ProposedJourneyAction] = []
    var synthesisVersion: String = "legacy"
    var expiresAt: String? = nil
    var status: SharedDirectionStatus = .proposed

    var displaySummary: String { summary ?? title }
    var displayRationale: String { rationale ?? message }
}
