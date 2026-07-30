import Foundation

/// The only result that can cross from two owner-only answers into shared UI.
///
/// Its copy is prepared from public insight context. It never contains or
/// varies with either person's answer, note, or answer equality.
nonisolated struct SharedDirection: Codable, Hashable, Sendable {
    let insightID: String
    let key: String
    let eyebrow: String
    let title: String
    let message: String
    let symbol: String
    let createdAt: String?
}
