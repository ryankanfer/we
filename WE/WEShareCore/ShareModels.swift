import Foundation

enum WEShareConstants {
    static let appGroup = "group.com.ryankanfer.WE.private-intake"

    /// The keychain access group must carry the App ID prefix that the
    /// entitlement was actually signed with. That prefix is *usually* the team
    /// id, but it is not guaranteed to be — a transferred or legacy App ID can
    /// carry a different one, and it changes outright if the app ever moves
    /// to another developer account. Hardcoding it means a signing change
    /// makes every share fail with a keychain error, and the simulator cannot
    /// catch it because it does not enforce access groups.
    ///
    /// Read it from the bundle that was signed. The literal stays as a
    /// fallback so a missing key degrades to today's known-good value rather
    /// than an unusable group.
    static let keychainGroup: String = {
        let prefix = Bundle.main.object(
            forInfoDictionaryKey: "AppIdentifierPrefix"
        ) as? String
        guard let prefix, !prefix.isEmpty, !prefix.hasPrefix("$(") else {
            return "2F28BDAM56.com.ryankanfer.WE.share-vault"
        }
        return "\(prefix)com.ryankanfer.WE.share-vault"
    }()
    static let pointerKey = "we.share.active-vault.v1"
    static let schemaVersion = 1
    static let maximumImages = 5
    static let maximumSourceBytes = 64 * 1_024 * 1_024
    static let maximumOutputBytes = 8 * 1_024 * 1_024
    static let maximumOutputDimension = 2_400
    static let maximumTextCharacters = 20_000
}

enum IncomingShareKind: String, Codable, Hashable, Sendable {
    case text
    case url
    case image
}

struct IncomingShareOmission: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let label: String
    let reason: String

    init(id: UUID = UUID(), label: String, reason: String) {
        self.id = id
        self.label = label
        self.reason = reason
    }
}

struct IncomingShareResource: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let kind: IncomingShareKind
    let sealedFilename: String
    let contentType: String
    let sha256: String
    let byteCount: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
}

struct IncomingShareRepresentation: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let kind: IncomingShareKind
    let text: String?
    let url: URL?
    let resourceID: UUID?

    init(
        id: UUID = UUID(),
        kind: IncomingShareKind,
        text: String? = nil,
        url: URL? = nil,
        resourceID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.url = url
        self.resourceID = resourceID
    }
}

struct IncomingShareManifest: Codable, Hashable, Sendable, Identifiable {
    let schemaVersion: Int
    let vaultID: UUID
    let id: UUID
    let revision: Int
    let createdAt: Date
    let updatedAt: Date
    let titleSuggestion: String
    let representations: [IncomingShareRepresentation]
    let resources: [IncomingShareResource]
    let omissions: [IncomingShareOmission]

    init(
        schemaVersion: Int = WEShareConstants.schemaVersion,
        vaultID: UUID,
        id: UUID = UUID(),
        revision: Int = 1,
        createdAt: Date,
        updatedAt: Date? = nil,
        titleSuggestion: String,
        representations: [IncomingShareRepresentation],
        resources: [IncomingShareResource],
        omissions: [IncomingShareOmission]
    ) {
        self.schemaVersion = schemaVersion
        self.vaultID = vaultID
        self.id = id
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.titleSuggestion = titleSuggestion
        self.representations = representations
        self.resources = resources
        self.omissions = omissions
    }

    var imageCount: Int {
        representations.count { $0.kind == .image }
    }

    var summary: String {
        var pieces: [String] = []
        let textCount = representations.count { $0.kind == .text }
        let urlCount = representations.count { $0.kind == .url }
        if textCount > 0 { pieces.append(textCount == 1 ? "text" : "\(textCount) texts") }
        if urlCount > 0 { pieces.append(urlCount == 1 ? "link" : "\(urlCount) links") }
        if imageCount > 0 {
            pieces.append(imageCount == 1 ? "photo" : "\(imageCount) photos")
        }
        return pieces.isEmpty ? "nothing supported" : pieces.joined(separator: ", ")
    }
}

struct IncomingShareDraft: Sendable {
    let manifest: IncomingShareManifest
    let resourceData: [UUID: Data]
}

enum IncomingShareCandidate: Sendable {
    case text(String, label: String)
    case webURL(URL, label: String)
    case image(NormalizedShareImage, label: String)
    case omitted(IncomingShareOmission)
}

struct NormalizedShareImage: Hashable, Sendable {
    let data: Data
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let sha256: String
}

struct ShareVaultPointer: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let vaultID: UUID
    let hueToken: String
}

struct ShareVaultContext: Sendable {
    let pointer: ShareVaultPointer
    let keyData: Data
}

struct AppShareRevision: Codable, Hashable, Sendable {
    let draftID: UUID
    let revision: Int
    let title: String
    let body: String
    let category: String
    let includedURLRepresentationIDs: Set<UUID>
    let includedResourceIDs: Set<UUID>
    let updatedAt: Date
}

struct FrozenPublicationURL: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let url: URL
}

struct FrozenPublicationResource: Codable, Hashable, Sendable {
    let id: UUID
    let sha256: String
    let contentType: String
    let byteCount: Int
}

struct FrozenPublicationSnapshot: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let draftID: UUID
    let revision: Int
    let title: String
    let body: String
    let category: String
    let approvedURLs: [FrozenPublicationURL]
    let resources: [FrozenPublicationResource]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        draftID: UUID,
        revision: Int,
        title: String,
        body: String,
        category: String,
        approvedURLs: [FrozenPublicationURL],
        resources: [FrozenPublicationResource],
        createdAt: Date
    ) {
        self.id = id
        self.draftID = draftID
        self.revision = revision
        self.title = title
        self.body = body
        self.category = category
        self.approvedURLs = approvedURLs
        self.resources = resources
        self.createdAt = createdAt
    }
}
