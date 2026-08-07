import Foundation
import Supabase

struct SharePublicationUpload: Codable, Hashable, Sendable, Identifiable {
    let resourceID: UUID
    let objectPath: String
    let sha256: String
    let contentType: String
    let byteCount: Int

    var id: UUID { resourceID }

    enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case objectPath = "object_path"
        case sha256
        case contentType = "content_type"
        case byteCount = "byte_count"
    }
}

struct SharePublicationSession: Codable, Hashable, Sendable {
    let id: UUID
    let uploads: [SharePublicationUpload]
}

private struct SharePublicationResult: Decodable {
    let lifeItemID: UUID

    enum CodingKeys: String, CodingKey {
        case lifeItemID = "life_item_id"
    }
}

protocol SharePublicationBackend: Sendable {
    func createSession(
        for snapshot: FrozenPublicationSnapshot
    ) async throws -> SharePublicationSession
    func upload(
        _ data: Data,
        descriptor: SharePublicationUpload
    ) async throws
    func finalize(sessionID: UUID) async throws -> UUID
    func retire(sessionID: UUID) async
}

final class SupabaseSharePublicationBackend:
    SharePublicationBackend,
    @unchecked Sendable
{
    private let client: SupabaseClient?
    private let bucket = "life-resources"

    init(client: SupabaseClient? = SupabaseClientProvider.shared.client) {
        self.client = client
    }

    func createSession(
        for snapshot: FrozenPublicationSnapshot
    ) async throws -> SharePublicationSession {
        guard let client else { throw SharePublicationError.unavailable }

        let urls: [AnyJSON] = snapshot.approvedURLs.map {
            .object([
                "id": .string($0.id.uuidString.lowercased()),
                "url": .string($0.url.absoluteString),
            ])
        }
        let resources: [AnyJSON] = snapshot.resources.map {
            .object([
                "id": .string($0.id.uuidString.lowercased()),
                "sha256": .string($0.sha256),
                "content_type": .string($0.contentType),
                "byte_count": .integer($0.byteCount),
            ])
        }
        let params: [String: AnyJSON] = [
            "p_snapshot": .string(snapshot.id.uuidString.lowercased()),
            "p_draft": .string(snapshot.draftID.uuidString.lowercased()),
            "p_revision": .integer(snapshot.revision),
            "p_title": .string(snapshot.title),
            "p_body": .string(snapshot.body),
            "p_category": .string(snapshot.category),
            "p_urls": .array(urls),
            "p_resources": .array(resources),
        ]

        return try await client
            .rpc("share_create_publication_session", params: params)
            .execute()
            .value
    }

    func upload(
        _ data: Data,
        descriptor: SharePublicationUpload
    ) async throws {
        guard let client else { throw SharePublicationError.unavailable }
        guard data.count == descriptor.byteCount,
              ShareCrypto.sha256(data) == descriptor.sha256 else {
            throw SharePublicationError.privateResourceChanged
        }

        _ = try await client.storage
            .from(bucket)
            .upload(
                descriptor.objectPath,
                data: data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: descriptor.contentType,
                    upsert: true,
                    metadata: [
                        "sha256": .string(descriptor.sha256),
                        "resource_id": .string(
                            descriptor.resourceID.uuidString.lowercased()
                        ),
                    ]
                )
            )
    }

    func finalize(sessionID: UUID) async throws -> UUID {
        guard let client else { throw SharePublicationError.unavailable }
        let result: SharePublicationResult = try await client
            .rpc(
                "share_finalize_publication",
                params: ["p_session": sessionID.uuidString.lowercased()]
            )
            .execute()
            .value
        return result.lifeItemID
    }

    func retire(sessionID: UUID) async {
        guard let client else { return }
        _ = try? await client
            .rpc(
                "share_retire_publication_session",
                params: ["p_session": sessionID.uuidString.lowercased()]
            )
            .execute()
    }
}

enum SharePublicationError: Error, LocalizedError {
    case unavailable
    case privateResourceChanged
    case invalidReview

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "WE can't reach the shared space right now. Your private draft is safe."
        case .privateResourceChanged:
            "A private photo no longer matches the reviewed copy. Nothing was shared."
        case .invalidReview:
            "Review the shared title and destination before releasing this."
        }
    }
}
