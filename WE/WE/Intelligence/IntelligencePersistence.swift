import Foundation

/// One encrypted transaction contains accepted edits, durable work, and deletion tombstones.
/// The account vault supplies identity and encryption; never use the widget app group.
struct WEIntelligencePersistence {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WE/Intelligence", directoryHint: .isDirectory)
    }
    func load(context: ShareVaultContext) throws -> WEArtifactLedger {
        let url = file(context)
        guard FileManager.default.fileExists(atPath: url.path) else { return WEArtifactLedger() }
        let sealed = try Data(contentsOf: url)
        let data = try ShareCrypto.openEnvelope(sealed, keyData: context.keyData, authenticatedBy: aad(context))
        let ledger = try JSONDecoder.share.decode(WEArtifactLedger.self, from: data)
        guard ledger.version == 1 else { throw ShareVaultError.invalidDraft }
        return ledger
    }
    func save(_ ledger: WEArtifactLedger, context: ShareVaultContext) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var rootURL = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try rootURL.setResourceValues(values)
        let data = try JSONEncoder.share.encode(ledger)
        let sealed = try ShareCrypto.sealEnvelope(data, keyData: context.keyData, authenticatedBy: aad(context))
        let url = file(context)
        try sealed.write(to: url, options: [.atomic, .completeFileProtection])
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize(); try handle.close()
    }
    func remove(vaultID: UUID) throws {
        let url = root.appending(path: vaultID.uuidString + ".sealed")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(_ context: ShareVaultContext) -> URL {
        root.appending(path: context.pointer.vaultID.uuidString + ".sealed")
    }
    private func aad(_ context: ShareVaultContext) -> Data {
        Data("intelligence|\(context.pointer.vaultID.uuidString)|1".utf8)
    }
}
