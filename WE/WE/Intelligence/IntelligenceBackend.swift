import Foundation
import Supabase

struct WEArtifactRemote: Decodable, Sendable {
    var id: UUID
    var version: Int
    var manifest: IncomingShareManifest
    var content: WEArtifactContent
}
struct WEArtifactWriteResult: Decodable { var version: Int; var conflict: WEArtifactContent? }

protocol WEIntelligenceSyncBackend: Sendable {
    func list() async throws -> [WEArtifactRemote]
    func tombstones() async throws -> [UUID]
    func upload(_ data: Data, artifact: UUID, resource: IncomingShareResource) async throws
    func download(artifact: UUID, resource: IncomingShareResource) async throws -> Data
    func write(_ pending: WEArtifactWrite, manifest: IncomingShareManifest) async throws -> WEArtifactWriteResult
    func delete(_ id: UUID) async throws
}

struct WEIntelligenceBackend: WEIntelligenceSyncBackend {
    let client: SupabaseClient
    let owner: UUID
    private let authClient: SupabaseClient
    init() async throws {
        guard let client = SupabaseClientProvider.shared.client else { throw SharePublicationError.unavailable }
        guard let configuration = AppEnvironment.current.supabase else { throw SharePublicationError.unavailable }
        let session = try await client.auth.session
        let capturedOwner = session.user.id
        authClient = client; owner = capturedOwner
        // A request may suspend during an account switch. This transport has no
        // session store or refresh timer and can never send the next account’s JWT.
        self.client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey,
            options: .init(auth: .init(autoRefreshToken: false, accessToken: {
                guard try await client.auth.session.user.id == capturedOwner else { throw ShareVaultError.signedOut }
                return session.accessToken
            })))
    }
    func checkAccount() async throws {
        guard try await authClient.auth.session.user.id == owner else { throw ShareVaultError.signedOut }
    }
    func list() async throws -> [WEArtifactRemote] {
        try await checkAccount()
        var result: [WEArtifactRemote] = []
        while true {
            let page: [WEArtifactRemote] = try await client.from("private_artifacts").select()
                .eq("owner_id", value: owner.uuidString).order("id").range(from: result.count, to: result.count + 499).execute().value
            result += page
            if page.count < 500 { return result }
        }
    }
    func tombstones() async throws -> [UUID] {
        struct Row: Decodable { let artifact_id: UUID }
        try await checkAccount()
        var result: [UUID] = []
        while true {
            let page: [Row] = try await client.from("private_artifact_tombstones").select("artifact_id")
                .eq("owner_id", value: owner.uuidString).order("artifact_id").range(from: result.count, to: result.count + 499).execute().value
            result += page.map(\.artifact_id)
            if page.count < 500 { return result }
        }
    }
    func upload(_ data: Data, artifact: UUID, resource: IncomingShareResource) async throws {
        try await checkAccount()
        let path = "\(owner.uuidString.lowercased())/\(artifact.uuidString.lowercased())/\(resource.sha256)"
        // A previous successful upload may have lost its acknowledgment. Verification
        // below, not the upload error, determines whether retry can safely continue.
        do { try await client.storage.from("private-originals").upload(path, data: data,
            options: FileOptions(contentType: "application/octet-stream", upsert: false)) } catch {}
        try await verify(bucket: "private-originals", path: path, sha: resource.sha256, bytes: data.count)
    }
    func download(artifact: UUID, resource: IncomingShareResource) async throws -> Data {
        try await checkAccount()
        let data = try await client.storage.from("private-originals").download(path: "\(owner.uuidString.lowercased())/\(artifact.uuidString.lowercased())/\(resource.sha256)")
        guard data.count == resource.byteCount, ShareCrypto.sha256(data) == resource.sha256 else { throw ShareVaultError.invalidDraft }
        return data
    }
    func verify(bucket: String, path: String, sha: String, bytes: Int) async throws {
        try await checkAccount()
        struct Result: Decodable { let verified: Bool }
        let result: Result = try await client.functions.invoke("intake-resources", options: .init(body: [
            "action": AnyJSON.string("verify"), "bucket": .string(bucket), "path": .string(path),
            "sha256": .string(sha), "bytes": .integer(bytes)
        ]))
        guard result.verified else { throw ShareVaultError.invalidDraft }
    }
    func write(_ pending: WEArtifactWrite, manifest: IncomingShareManifest) async throws -> WEArtifactWriteResult {
        try await checkAccount()
        let manifestJSON = try JSONDecoder().decode(AnyJSON.self, from: JSONEncoder.share.encode(manifest))
        let contentJSON = try JSONDecoder().decode(AnyJSON.self, from: JSONEncoder.share.encode(pending.content))
        return try await client.rpc("intake_write", params: [
            "p_id": AnyJSON.string(manifest.id.uuidString.lowercased()),
            "p_operation": .string(pending.id.uuidString.lowercased()), "p_expected": .integer(pending.expectedVersion),
            "p_manifest": manifestJSON, "p_content": contentJSON
        ]).execute().value
    }
    func delete(_ id: UUID) async throws {
        try await checkAccount()
        struct Result: Decodable { let completed: Bool }
        let result: Result = try await client.functions.invoke("intake-resources", options: .init(body: ["action": "delete", "id": id.uuidString.lowercased()]))
        guard result.completed else { throw SharePublicationError.unavailable }
    }
}
