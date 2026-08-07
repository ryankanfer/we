import CryptoKit
import Foundation

struct ShareSealedEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

enum ShareCryptoError: Error, LocalizedError {
    case invalidKey
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .invalidKey: "The private vault key is unavailable."
        case .invalidEnvelope: "This private draft could not be verified."
        }
    }
}

enum ShareCrypto {
    static func randomKeyData() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sealEnvelope(
        _ plaintext: Data,
        keyData: Data,
        authenticatedBy additionalData: Data
    ) throws -> Data {
        let box = try AES.GCM.seal(
            plaintext,
            using: try key(keyData),
            authenticating: additionalData
        )
        let envelope = ShareSealedEnvelope(
            schemaVersion: WEShareConstants.schemaVersion,
            nonce: box.nonce.withUnsafeBytes { Data($0) },
            ciphertext: box.ciphertext,
            tag: box.tag
        )
        return try JSONEncoder().encode(envelope)
    }

    static func openEnvelope(
        _ data: Data,
        keyData: Data,
        authenticatedBy additionalData: Data
    ) throws -> Data {
        let envelope = try JSONDecoder().decode(
            ShareSealedEnvelope.self,
            from: data
        )
        guard envelope.schemaVersion == WEShareConstants.schemaVersion else {
            throw ShareCryptoError.invalidEnvelope
        }
        let nonce = try AES.GCM.Nonce(data: envelope.nonce)
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )
        return try AES.GCM.open(
            box,
            using: try key(keyData),
            authenticating: additionalData
        )
    }

    static func sealResource(
        _ plaintext: Data,
        keyData: Data,
        authenticatedBy additionalData: Data
    ) throws -> Data {
        let box = try AES.GCM.seal(
            plaintext,
            using: try key(keyData),
            authenticating: additionalData
        )
        guard let combined = box.combined else {
            throw ShareCryptoError.invalidEnvelope
        }
        return combined
    }

    static func openResource(
        _ data: Data,
        keyData: Data,
        authenticatedBy additionalData: Data
    ) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(
            box,
            using: try key(keyData),
            authenticating: additionalData
        )
    }

    private static func key(_ data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw ShareCryptoError.invalidKey }
        return SymmetricKey(data: data)
    }
}
