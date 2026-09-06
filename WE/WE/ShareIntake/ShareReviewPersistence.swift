import Foundation

struct PersistedShareReview: Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    var revision: AppShareRevision
    var frozen: FrozenPublicationSnapshot?
    var session: SharePublicationSession?
}

struct ShareReviewPersistence: Sendable {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(
            path: "WE/PrivateIntakeReviews",
            directoryHint: .isDirectory
        )
    }

    func load(
        draftID: UUID,
        vaultID: UUID
    ) throws -> PersistedShareReview? {
        let url = fileURL(draftID: draftID, vaultID: vaultID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let value = try JSONDecoder.share.decode(
            PersistedShareReview.self,
            from: Data(contentsOf: url)
        )
        guard value.schemaVersion == PersistedShareReview.schemaVersion,
              value.revision.draftID == draftID else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return value
    }

    func save(
        _ value: PersistedShareReview,
        vaultID: UUID
    ) throws {
        let directory = vaultDirectory(vaultID)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)

        let data = try JSONEncoder.share.encode(value)
        try data.write(
            to: fileURL(
                draftID: value.revision.draftID,
                vaultID: vaultID
            ),
            options: [.atomic, .completeFileProtection]
        )
    }

    func remove(draftID: UUID, vaultID: UUID) {
        try? FileManager.default.removeItem(
            at: fileURL(draftID: draftID, vaultID: vaultID)
        )
    }

    private func fileURL(draftID: UUID, vaultID: UUID) -> URL {
        vaultDirectory(vaultID).appending(
            path: "\(draftID.uuidString.lowercased()).json"
        )
    }

    private func vaultDirectory(_ vaultID: UUID) -> URL {
        root.appending(
            path: vaultID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
    }
}
