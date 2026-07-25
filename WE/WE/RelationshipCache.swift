import Foundation

nonisolated struct CachedRelationship: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let snapshot: RelationshipSnapshot
    let savedAt: Date
}

protocol RelationshipCache {
    func load(userID: String) async throws -> CachedRelationship?
    func save(_ snapshot: RelationshipSnapshot, userID: String) async throws
    func remove(userID: String) async throws
}

actor FileRelationshipCache: RelationshipCache {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("WE/RelationshipCache", isDirectory: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(userID: String) throws -> CachedRelationship? {
        let url = fileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let cached = try decoder.decode(
            CachedRelationship.self,
            from: Data(contentsOf: url)
        )
        guard cached.version == CachedRelationship.currentVersion else {
            try FileManager.default.removeItem(at: url)
            return nil
        }
        return cached
    }

    func save(_ snapshot: RelationshipSnapshot, userID: String) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let data = try encoder.encode(
            CachedRelationship(
                version: CachedRelationship.currentVersion,
                snapshot: snapshot,
                savedAt: Date()
            )
        )
        let url = fileURL(userID: userID)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func remove(userID: String) throws {
        let url = fileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(userID: String) -> URL {
        let safeID = userID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent("\(safeID).json")
    }
}

actor InMemoryRelationshipCache: RelationshipCache {
    private var values: [String: CachedRelationship] = [:]

    func load(userID: String) throws -> CachedRelationship? {
        values[userID]
    }

    func save(_ snapshot: RelationshipSnapshot, userID: String) throws {
        values[userID] = CachedRelationship(
            version: CachedRelationship.currentVersion,
            snapshot: snapshot,
            savedAt: Date()
        )
    }

    func remove(userID: String) throws {
        values[userID] = nil
    }
}
