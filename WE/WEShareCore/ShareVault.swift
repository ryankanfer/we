import Darwin
import Foundation
import Security

enum ShareVaultError: Error, LocalizedError {
    case unavailable
    /// The app group container could not be resolved. On device this means the
    /// entitlement is not in the signed profile — the one failure the
    /// simulator cannot reproduce, because it hands back a container regardless.
    case containerUnavailable
    case signedOut
    case invalidPointer
    case invalidDraft
    case immutableDraft
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable: "WE's private Share Sheet space is unavailable."
        case .containerUnavailable:
            "WE's private Share Sheet space is unavailable. (group)"
        case .signedOut: "Open WE and sign in first."
        case .invalidPointer: "WE could not verify which private space is active."
        case .invalidDraft: "This private draft could not be verified."
        case .immutableDraft: "This private draft has already been kept."
        // The status is the whole diagnosis: -34018 is a missing keychain
        // entitlement, -25300 is a group mismatch. Without it a beta report
        // says only "it didn't work".
        case .keychain(let status):
            "WE could not unlock the private Share Sheet space. (\(status))"
        }
    }
}

private struct ShareVaultAccountRecord: Codable {
    let vaultID: UUID
    let keyData: Data
}

private struct ShareKeychainStore {
    let service: String
    let accessGroup: String?

    func read(account: String) throws -> Data? {
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ShareVaultError.keychain(status)
        }
        return data
    }

    func write(_ data: Data, account: String) throws {
        var query = base(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let update = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw ShareVaultError.keychain(update)
        }
        for (key, value) in attributes { query[key] = value }
        let add = SecItemAdd(query as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw ShareVaultError.keychain(add)
        }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(base(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ShareVaultError.keychain(status)
        }
    }

    /// Every account under this service, without needing to know their names.
    ///
    /// A reinstall is the case this exists for. The app group container goes
    /// with the app and the keychain does not, so an account id that was only
    /// ever recorded inside that container is unrecoverable while the key it
    /// named lives on. There is nothing left to enumerate and nothing left to
    /// decrypt — dropping the account clause is the only way to reach it.
    func removeAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ShareVaultError.keychain(status)
        }
    }

    private func base(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

final class ShareVaultController: @unchecked Sendable {
    static let shared = ShareVaultController()

    private let accountKeys = ShareKeychainStore(
        service: "com.ryankanfer.WE.share-vault.accounts",
        accessGroup: nil
    )
    private let activeKey = ShareKeychainStore(
        service: "com.ryankanfer.WE.share-vault.active",
        accessGroup: WEShareConstants.keychainGroup
    )
    private let defaults: UserDefaults?
    let store: ShareVaultStore

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: WEShareConstants.appGroup
        ),
        root: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WEShareConstants.appGroup
        )?.appending(path: "PrivateIntake", directoryHint: .isDirectory)
    ) {
        self.defaults = defaults
        self.store = ShareVaultStore(root: root)
    }

    @discardableResult
    func activate(accountID: String, hueToken: String) throws -> ShareVaultContext {
        guard defaults != nil, store.root != nil else {
            throw ShareVaultError.containerUnavailable
        }

        // Make account switches fail closed. If the process stops between the
        // shared key and pointer writes, the extension sees no active pointer
        // instead of combining the previous vault id with the next key.
        deactivate()

        let record: ShareVaultAccountRecord
        if let data = try accountKeys.read(account: accountID) {
            record = try JSONDecoder().decode(
                ShareVaultAccountRecord.self,
                from: data
            )
        } else {
            record = ShareVaultAccountRecord(
                vaultID: UUID(),
                keyData: ShareCrypto.randomKeyData()
            )
            try accountKeys.write(
                try JSONEncoder().encode(record),
                account: accountID
            )
        }

        let pointer = ShareVaultPointer(
            schemaVersion: WEShareConstants.schemaVersion,
            vaultID: record.vaultID,
            hueToken: hueToken
        )
        try activeKey.write(record.keyData, account: "active")
        defaults?.set(
            try JSONEncoder().encode(pointer),
            forKey: WEShareConstants.pointerKey
        )
        return ShareVaultContext(pointer: pointer, keyData: record.keyData)
    }

    func deactivate() {
        defaults?.removeObject(forKey: WEShareConstants.pointerKey)
        try? activeKey.remove(account: "active")
    }

    func purge(accountID: String) {
        guard let data = try? accountKeys.read(account: accountID),
              let record = try? JSONDecoder().decode(
                  ShareVaultAccountRecord.self,
                  from: data
              )
        else {
            deactivate()
            try? accountKeys.remove(account: accountID)
            return
        }
        if currentPointer()?.vaultID == record.vaultID {
            deactivate()
        }
        store.removeVault(record.vaultID)
        try? accountKeys.remove(account: accountID)
    }

    /// Everything this device holds for the vault, for every account.
    ///
    /// Called once on a fresh install. iOS deletes the app group container
    /// with the app but leaves the keychain standing, so without this the key
    /// and vault id for every account that ever signed in on this device
    /// outlive the encrypted files they were minted for — indefinitely, and
    /// for people who may never sign in again.
    ///
    /// Nothing is lost by it. The sealed drafts those keys opened went with
    /// the container, so a returning account is issued a new vault rather than
    /// a working one, and that is the honest state: their staged drafts are
    /// gone whether or not the key that opened them survived.
    func purgeEveryAccount() {
        deactivate()
        try? accountKeys.removeAll()
        try? activeKey.removeAll()
    }

    func activeContext() throws -> ShareVaultContext {
        guard let pointer = currentPointer() else {
            throw ShareVaultError.signedOut
        }
        guard pointer.schemaVersion == WEShareConstants.schemaVersion,
              let keyData = try activeKey.read(account: "active"),
              keyData.count == 32
        else {
            throw ShareVaultError.invalidPointer
        }
        return ShareVaultContext(pointer: pointer, keyData: keyData)
    }

    private func currentPointer() -> ShareVaultPointer? {
        guard let data = defaults?.data(forKey: WEShareConstants.pointerKey)
        else { return nil }
        return try? JSONDecoder().decode(ShareVaultPointer.self, from: data)
    }
}

struct ShareVaultStore: Sendable {
    let root: URL?

    init(root: URL?) {
        self.root = root
    }

    @discardableResult
    func commit(
        _ draft: IncomingShareDraft,
        context: ShareVaultContext
    ) throws -> URL {
        try validate(draft.manifest, context: context)
        return try withLock {
            guard let root else { throw ShareVaultError.unavailable }
            try prepare(root)
            let vault = vaultURL(context.pointer.vaultID)
            let stagingRoot = vault.appending(
                path: "staging",
                directoryHint: .isDirectory
            )
            let readyRoot = vault.appending(
                path: "ready",
                directoryHint: .isDirectory
            )
            try prepare(stagingRoot)
            try prepare(readyRoot)

            let name = draft.manifest.id.uuidString.lowercased()
            let staging = stagingRoot.appending(
                path: name,
                directoryHint: .isDirectory
            )
            let ready = readyRoot.appending(
                path: name,
                directoryHint: .isDirectory
            )
            guard !FileManager.default.fileExists(atPath: ready.path) else {
                throw ShareVaultError.immutableDraft
            }
            try? FileManager.default.removeItem(at: staging)
            try prepare(staging)
            let resourcesDirectory = staging.appending(
                path: "resources",
                directoryHint: .isDirectory
            )
            try prepare(resourcesDirectory)

            do {
                for resource in draft.manifest.resources {
                    guard let plaintext = draft.resourceData[resource.id],
                          plaintext.count == resource.byteCount,
                          ShareCrypto.sha256(plaintext) == resource.sha256,
                          resource.sealedFilename
                            == "\(resource.id.uuidString.lowercased()).sealed"
                    else { throw ShareVaultError.invalidDraft }

                    let sealed = try ShareCrypto.sealResource(
                        plaintext,
                        keyData: context.keyData,
                        authenticatedBy: resourceAAD(
                            manifest: draft.manifest,
                            resource: resource
                        )
                    )
                    try protectedWrite(
                        sealed,
                        to: resourcesDirectory.appending(
                            path: resource.sealedFilename
                        )
                    )
                }

                let manifestData = try JSONEncoder.share.encode(draft.manifest)
                let envelope = try ShareCrypto.sealEnvelope(
                    manifestData,
                    keyData: context.keyData,
                    authenticatedBy: manifestAAD(draft.manifest)
                )
                try protectedWrite(
                    envelope,
                    to: staging.appending(path: "manifest.json")
                )
                try FileManager.default.moveItem(at: staging, to: ready)
                return ready
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        }
    }

    func readyDrafts(context: ShareVaultContext) throws -> [IncomingShareManifest] {
        try withLock {
            let ready = vaultURL(context.pointer.vaultID).appending(
                path: "ready",
                directoryHint: .isDirectory
            )
            guard FileManager.default.fileExists(atPath: ready.path) else {
                return []
            }
            let directories = try FileManager.default.contentsOfDirectory(
                at: ready,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var manifests: [IncomingShareManifest] = []
            for directory in directories {
                guard let draftID = UUID(uuidString: directory.lastPathComponent)
                else { continue }
                do {
                    manifests.append(
                        try loadManifest(
                            draftID: draftID,
                            context: context
                        )
                    )
                } catch {
                    quarantine(directory, vaultID: context.pointer.vaultID)
                }
            }
            return manifests.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func loadResource(
        _ resource: IncomingShareResource,
        manifest: IncomingShareManifest,
        context: ShareVaultContext
    ) throws -> Data {
        try validate(manifest, context: context)
        return try withLock {
            let url = readyURL(manifest).appending(
                path: "resources/\(resource.sealedFilename)"
            )
            let sealed = try Data(contentsOf: url)
            let plaintext = try ShareCrypto.openResource(
                sealed,
                keyData: context.keyData,
                authenticatedBy: resourceAAD(
                    manifest: manifest,
                    resource: resource
                )
            )
            guard plaintext.count == resource.byteCount,
                  ShareCrypto.sha256(plaintext) == resource.sha256 else {
                throw ShareVaultError.invalidDraft
            }
            return plaintext
        }
    }

    func remove(_ manifest: IncomingShareManifest, context: ShareVaultContext) {
        guard (try? validate(manifest, context: context)) != nil else { return }
        try? withLock {
            try? FileManager.default.removeItem(at: readyURL(manifest))
        }
    }

    func expireReady(
        context: ShareVaultContext,
        olderThan date: Date
    ) {
        guard let manifests = try? readyDrafts(context: context) else { return }
        for manifest in manifests where manifest.createdAt < date {
            remove(manifest, context: context)
        }
    }

    func cleanAbandonedStaging(
        context: ShareVaultContext,
        olderThan date: Date
    ) {
        try? withLock {
            let staging = vaultURL(context.pointer.vaultID).appending(
                path: "staging",
                directoryHint: .isDirectory
            )
            guard let directories = try? FileManager.default
                .contentsOfDirectory(
                    at: staging,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
            else { return }
            for directory in directories {
                let modified = try? directory.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if let modified, modified < date {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }
    }

    func removeVault(_ vaultID: UUID) {
        try? withLock {
            try? FileManager.default.removeItem(at: vaultURL(vaultID))
        }
    }

    private func loadManifest(
        draftID: UUID,
        context: ShareVaultContext
    ) throws -> IncomingShareManifest {
        let placeholder = IncomingShareManifest(
            vaultID: context.pointer.vaultID,
            id: draftID,
            createdAt: .distantPast,
            titleSuggestion: "",
            representations: [],
            resources: [],
            omissions: []
        )
        let data = try Data(
            contentsOf: readyURL(placeholder).appending(path: "manifest.json")
        )
        let plaintext = try ShareCrypto.openEnvelope(
            data,
            keyData: context.keyData,
            authenticatedBy: manifestAAD(placeholder)
        )
        let manifest = try JSONDecoder.share.decode(
            IncomingShareManifest.self,
            from: plaintext
        )
        try validate(manifest, context: context)
        guard manifest.id == draftID else {
            throw ShareVaultError.invalidDraft
        }
        return manifest
    }

    private func validate(
        _ manifest: IncomingShareManifest,
        context: ShareVaultContext
    ) throws {
        let resourceIDs = Set(manifest.resources.map(\.id))
        let representationIDs = Set(manifest.representations.map(\.id))
        let imageReferences = manifest.representations.compactMap {
            $0.kind == .image ? $0.resourceID : nil
        }

        guard manifest.schemaVersion == WEShareConstants.schemaVersion,
              manifest.vaultID == context.pointer.vaultID,
              manifest.revision > 0,
              context.keyData.count == 32,
              manifest.updatedAt >= manifest.createdAt,
              !manifest.representations.isEmpty,
              manifest.titleSuggestion.count <= 80,
              representationIDs.count == manifest.representations.count,
              resourceIDs.count == manifest.resources.count,
              manifest.resources.count <= WEShareConstants.maximumImages,
              imageReferences.count <= WEShareConstants.maximumImages,
              Set(imageReferences) == resourceIDs,
              imageReferences.count == resourceIDs.count,
              manifest.representations.allSatisfy(
                  validRepresentation
              ),
              manifest.resources.allSatisfy({
                  validResource($0)
              })
        else { throw ShareVaultError.invalidDraft }
    }

    private func validRepresentation(
        _ representation: IncomingShareRepresentation
    ) -> Bool {
        switch representation.kind {
        case .text:
            guard let text = representation.text else { return false }
            return !text.isEmpty
                && text.count <= WEShareConstants.maximumTextCharacters
                && representation.url == nil
                && representation.resourceID == nil

        case .url:
            guard let url = representation.url else { return false }
            return IncomingShareParser.canonicalHTTPSURL(url) != nil
                && representation.text == nil
                && representation.resourceID == nil

        case .image:
            return representation.resourceID != nil
                && representation.text == nil
                && representation.url == nil
        }
    }

    private func validResource(_ resource: IncomingShareResource) -> Bool {
        let validHash = resource.sha256.count == 64
            && resource.sha256.unicodeScalars.allSatisfy {
                (48...57).contains($0.value)
                    || (97...102).contains($0.value)
            }
        let validDimensions: Bool
        if let width = resource.pixelWidth,
           let height = resource.pixelHeight {
            validDimensions = width > 0
                && height > 0
                && max(width, height)
                    <= WEShareConstants.maximumOutputDimension
        } else {
            validDimensions = false
        }

        return resource.kind == .image
            && resource.sealedFilename
                == "\(resource.id.uuidString.lowercased()).sealed"
            && ["image/jpeg", "image/png"].contains(resource.contentType)
            && validHash
            && resource.byteCount > 0
            && resource.byteCount <= WEShareConstants.maximumOutputBytes
            && validDimensions
    }

    private func readyURL(_ manifest: IncomingShareManifest) -> URL {
        vaultURL(manifest.vaultID)
            .appending(path: "ready", directoryHint: .isDirectory)
            .appending(
                path: manifest.id.uuidString.lowercased(),
                directoryHint: .isDirectory
            )
    }

    private func vaultURL(_ vaultID: UUID) -> URL {
        root?
            .appending(path: "vaults", directoryHint: .isDirectory)
            .appending(
                path: vaultID.uuidString.lowercased(),
                directoryHint: .isDirectory
            )
            ?? URL(fileURLWithPath: "/dev/null")
    }

    private func manifestAAD(_ manifest: IncomingShareManifest) -> Data {
        Data(
            "manifest|\(manifest.vaultID.uuidString)|\(manifest.id.uuidString)"
                .utf8
        )
    }

    private func resourceAAD(
        manifest: IncomingShareManifest,
        resource: IncomingShareResource
    ) -> Data {
        Data(
            "resource|\(manifest.vaultID.uuidString)|\(manifest.id.uuidString)"
                .appending("|\(resource.id.uuidString)|\(resource.sha256)")
                .utf8
        )
    }

    private func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try? (directory as NSURL).setResourceValue(
            true,
            forKey: .isExcludedFromBackupKey
        )
    }

    private func protectedWrite(_ data: Data, to url: URL) throws {
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    private func quarantine(_ directory: URL, vaultID: UUID) {
        let destination = vaultURL(vaultID)
            .appending(path: "quarantine", directoryHint: .isDirectory)
            .appending(
                path: "\(Date().timeIntervalSince1970)-\(directory.lastPathComponent)",
                directoryHint: .isDirectory
            )
        try? prepare(destination.deletingLastPathComponent())
        try? FileManager.default.moveItem(at: directory, to: destination)
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        guard let root else { throw ShareVaultError.containerUnavailable }
        try prepare(root)
        let lockURL = root.appending(path: ".vault.lock")
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw ShareVaultError.unavailable }
        defer {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw ShareVaultError.unavailable
        }
        return try operation()
    }
}

extension JSONEncoder {
    static var share: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var share: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
