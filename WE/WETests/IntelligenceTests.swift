import Foundation
import Testing
@testable import WE

@MainActor struct IntelligenceTests {
    @Test func dateOnlyRoundTripsAcrossTimeZones() throws {
        for name in ["America/New_York", "Pacific/Auckland", "Asia/Tokyo"] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: name)!
            let date = try #require(WEObjectTiming.day("2026-03-08", calendar: calendar))
            #expect(calendar.component(.day, from: date) == 8)
            #expect(calendar.component(.month, from: date) == 3)
        }
        #expect(WEObjectTiming.day("2026-02-30") == nil)
        #expect(WEObjectTiming.day("03/04") == nil)
        #expect(!WEObjectTiming(precision: .unresolved, unresolvedText: "Friday").isResolved)
    }
    @Test func missingZoneAndReversedTimeAreUnresolved() {
        #expect(!WEObjectTiming(precision: .time, start: Date()).isResolved)
        #expect(!WEObjectTiming(precision: .time, start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 50), timeZoneID: "UTC").isResolved)
    }
    @Test func pendingWriteAndTombstoneSurviveEncryptedRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WEIntelligencePersistence(root: directory)
        let context = ShareVaultContext(pointer: .init(schemaVersion: 1, vaultID: UUID(), hueToken: "sage"), keyData: ShareCrypto.randomKeyData())
        let id = UUID()
        var record = WEArtifactRecord(id: id, content: .init(title: "Private test fragment"))
        record.pending = WEArtifactWrite(expectedVersion: 2, content: record.content)
        var ledger = WEArtifactLedger(); ledger.records[id] = record
        try persistence.save(ledger, context: context)
        let restored = try persistence.load(context: context)
        #expect(restored.records[id]?.pending?.id == record.pending?.id)
        #expect(restored.records[id]?.pending?.expectedVersion == 2)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("Private test fragment"))
        record.deleted = true; record.content = .init(title: "Deleted item"); record.pending = nil
        ledger.records[id] = record; try persistence.save(ledger, context: context)
        #expect(try persistence.load(context: context).records[id]?.deleted == true)
        let wrongKey = ShareVaultContext(pointer: context.pointer, keyData: ShareCrypto.randomKeyData())
        #expect(throws: (any Error).self) { try persistence.load(context: wrongKey) }
    }
    @Test func corruptLedgerIsNotAnEmptyLedger() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = ShareVaultContext(pointer: .init(schemaVersion: 1, vaultID: UUID(), hueToken: "sage"), keyData: ShareCrypto.randomKeyData())
        let persistence = WEIntelligencePersistence(root: directory)
        try persistence.save(.init(), context: context)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: file)
        #expect(throws: (any Error).self) { try persistence.load(context: context) }
        #expect(try Data(contentsOf: file) == Data("broken".utf8))
    }
    @Test func editsAreNotReportedSyncedBeforeAcknowledgment() {
        var record = WEArtifactRecord(id: UUID(), content: .init(title: "Dinner"))
        record.serverVersion = 1; record.syncedContent = record.content
        #expect(record.syncLabel == "Synced privately")
        record.content.title = "Dinner Friday"
        #expect(record.syncLabel == "Saved on this phone")
        record.deleted = true
        #expect(record.syncLabel == "Deletion pending")
    }
    @Test func noFetchForCredentialBearingOrPrivateDestinations() {
        for address in ["127.0.0.1", "10.0.0.1", "172.16.0.1", "169.254.169.254", "192.168.1.2", "100.64.0.1", "0.0.0.0", "224.1.1.1"] {
            #expect(!WEPublicLinkReader.publicIPv4(address))
        }
        #expect(WEPublicLinkReader.publicIPv4("93.184.216.34"))
        for url in ["http://example.com", "https://localhost", "https://example.local", "https://u:p@example.com", "https://example.com/?token=secret", "https://example.com:8443"] {
            #expect(!WEPublicLinkReader.permits(URL(string: url)!))
        }
        #expect(WEPublicLinkReader.permits(URL(string: "https://example.com/restaurant")!))
    }
    @Test func ambiguousCategoriesNeverAutomate() {
        #expect(WELinkCategory.classify("a restaurant") == .restaurants)
        #expect(WELinkCategory.classify("restaurant concert") == nil)
        #expect(WELinkCategory.classify("https://example.com") == nil)
        #expect(WELinkCategory.classify("property listing") == .realEstate)
    }
    @Test func searchExplainsTheActualMatchAndCannotSeeExcludedDocuments() {
        let visible = WESearchDocument(id: .init(kind: .lifeItem, id: "visible"), title: "Friday dinner", text: "Reservation", visibility: .shared)
        let excluded = WESearchDocument(id: .init(kind: .artifact, id: "private"), title: "Private Friday dinner", text: "", visibility: .onlyMe)
        let results = WESemanticSearch.matches("dinner", eligible: [visible])
        #expect(results.count == 1)
        #expect(results.first?.reason == "The title contains ‘dinner’.")
        #expect(!results.contains { $0.id == excluded.id })
        #expect(WESemanticSearch.matches("", eligible: [visible]).isEmpty)
    }
    @Test func originalAndPublishedVersionHaveDistinctVisibility() {
        var content = WEArtifactContent(title: "Reservation")
        #expect(content.visibilityLabel == "Only me")
        content.publishedItemID = UUID().uuidString
        #expect(content.visibilityLabel.contains("Original: Only me"))
        #expect(content.visibilityLabel.contains("Reviewed version: Shared"))
    }
}

@MainActor private final class IntelligenceMemoryBackend: WEIntelligenceSyncBackend, @unchecked Sendable {
    enum Failure: Error { case offline }
    var online = true
    var loseAcknowledgment = false
    var rows: [UUID: WEArtifactRemote] = [:]
    var removed: Set<UUID> = []
    var receipts: [UUID: Int] = [:]
    var committedWrites = 0
    func list() throws -> [WEArtifactRemote] { if !online { throw Failure.offline }; return Array(rows.values) }
    func tombstones() throws -> [UUID] { if !online { throw Failure.offline }; return Array(removed) }
    func upload(_ data: Data, artifact: UUID, resource: IncomingShareResource) throws {}
    func download(artifact: UUID, resource: IncomingShareResource) throws -> Data { throw Failure.offline }
    func write(_ pending: WEArtifactWrite, manifest: IncomingShareManifest) throws -> WEArtifactWriteResult {
        if !online || removed.contains(manifest.id) { throw Failure.offline }
        if let version = receipts[pending.id] { return .init(version: version) }
        let version = rows[manifest.id]?.version ?? 0
        if version != pending.expectedVersion { return .init(version: version, conflict: rows[manifest.id]?.content) }
        rows[manifest.id] = .init(id: manifest.id, version: version + 1, manifest: manifest, content: pending.content)
        receipts[pending.id] = version + 1; committedWrites += 1
        if loseAcknowledgment { loseAcknowledgment = false; throw Failure.offline }
        return .init(version: version + 1)
    }
    func delete(_ id: UUID) throws { if !online { throw Failure.offline }; removed.insert(id); rows[id] = nil }
}

@MainActor struct IntelligenceSyncTests {
    private func fixture() throws -> (ShareVaultController, WEIntelligencePersistence, URL, String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "intelligence-\(UUID().uuidString)")
        let namespace = "we-test-\(UUID().uuidString)"
        let vault = ShareVaultController(defaults: UserDefaults(suiteName: namespace), root: root.appending(path: "vault"), keychainNamespace: namespace)
        try vault.activate(accountID: "fixture", hueToken: "sage")
        return (vault, WEIntelligencePersistence(root: root.appending(path: "ledger")), root, namespace)
    }
    @Test func lostAcknowledgmentAndRelaunchDoNotDuplicate() async throws {
        let (vault, persistence, root, namespace) = try fixture()
        defer { vault.purgeEveryAccount(); UserDefaults().removePersistentDomain(forName: namespace); try? FileManager.default.removeItem(at: root) }
        let backend = IntelligenceMemoryBackend(); backend.loseAcknowledgment = true
        let first = WEIntelligenceStore(vault: vault, persistence: persistence, backendFactory: { backend })
        first.reload()
        let id = try first.capture([.text("Dinner Friday", label: "Thought")])
        await first.synchronize()
        #expect(backend.committedWrites == 1)
        #expect(first.ledger.records[id]?.pending != nil)
        let restarted = WEIntelligenceStore(vault: vault, persistence: persistence, backendFactory: { backend })
        restarted.reload(); await restarted.synchronize()
        #expect(backend.committedWrites == 1)
        #expect(restarted.ledger.records[id]?.syncLabel == "Synced privately")
        #expect(restarted.manifests.contains { $0.id == id })
    }
    @Test func concurrentEditRequiresRecoverableChoice() async throws {
        let (vault, persistence, root, namespace) = try fixture()
        defer { vault.purgeEveryAccount(); UserDefaults().removePersistentDomain(forName: namespace); try? FileManager.default.removeItem(at: root) }
        let backend = IntelligenceMemoryBackend()
        let store = WEIntelligenceStore(vault: vault, persistence: persistence, backendFactory: { backend })
        store.reload(); let id = try store.capture([.text("Dinner", label: "Thought")]); await store.synchronize()
        backend.rows[id]?.version += 1; backend.rows[id]?.content.title = "Dinner from another phone"
        store.edit(id) { $0.title = "My correction" }; await store.synchronize()
        #expect(store.ledger.records[id]?.remoteConflict?.title == "Dinner from another phone")
        #expect(store.ledger.records[id]?.content.title == "My correction")
        store.resolveConflict(id, keepLocal: true); await store.synchronize()
        #expect(backend.rows[id]?.content.title == "My correction")
        #expect(backend.rows[id]?.version == 3)
    }
    @Test func offlineDeletionSurvivesRestartAndPreventsResurrection() async throws {
        let (vault, persistence, root, namespace) = try fixture()
        defer { vault.purgeEveryAccount(); UserDefaults().removePersistentDomain(forName: namespace); try? FileManager.default.removeItem(at: root) }
        let backend = IntelligenceMemoryBackend()
        let store = WEIntelligenceStore(vault: vault, persistence: persistence, backendFactory: { backend })
        store.reload(); let id = try store.capture([.text("Delete all copies", label: "Thought")]); await store.synchronize()
        backend.online = false; await store.deleteEverywhere(id)
        #expect(store.records.isEmpty)
        #expect(store.ledger.records[id]?.syncedContent == nil)
        #expect(store.ledger.records[id]?.pending == nil)
        #expect(store.issues.contains { $0.id == id })
        let restarted = WEIntelligenceStore(vault: vault, persistence: persistence, backendFactory: { backend })
        restarted.reload(); backend.online = true; await restarted.synchronize()
        #expect(backend.rows[id] == nil)
        #expect(backend.removed.contains(id))
        #expect(restarted.records.isEmpty)
        #expect(restarted.ledger.records[id]?.deletionConfirmed == true)
    }
    @Test func categoryRuleNeedsDistinctGrantsAndDeliberateActivation() throws {
        let (vault, persistence, root, namespace) = try fixture()
        defer { vault.purgeEveryAccount(); UserDefaults().removePersistentDomain(forName: namespace); try? FileManager.default.removeItem(at: root) }
        let store = WEIntelligenceStore(vault: vault, persistence: persistence)
        store.reload()
        store.setRule(.restaurants, enabled: true)
        #expect(!store.ledger.trustedCategories.contains(.restaurants))
        for index in 1...3 {
            let id = try store.capture([.text("Restaurant \(index)", label: "Link")])
            store.edit(id) { $0.linkCategory = .restaurants; $0.explicitLinkGrants = ["https://example.com/restaurant/\(index)"] }
            #expect(store.ruleEligible(.restaurants) == (index == 3))
            #expect(!store.ledger.trustedCategories.contains(.restaurants))
        }
        store.setRule(.restaurants, enabled: true)
        #expect(store.ledger.trustedCategories.contains(.restaurants))
        store.setRule(.restaurants, enabled: false)
        #expect(!store.ledger.trustedCategories.contains(.restaurants))
        #expect(!WEPublicLinkReader.permitsAutomatic(URL(string: "https://example.com/restaurant?reservation=abc")!))
        #expect(WEPublicLinkReader.permitsAutomatic(URL(string: "https://example.com/restaurant")!))
    }
    @Test func deletingPrivatePlanDetachesButPreservesItsChildren() async throws {
        let (vault, persistence, root, namespace) = try fixture()
        defer { vault.purgeEveryAccount(); UserDefaults().removePersistentDomain(forName: namespace); try? FileManager.default.removeItem(at: root) }
        let backend = IntelligenceMemoryBackend()
        let store = WEIntelligenceStore(vault: vault, persistence: persistence, backendFactory: { backend })
        store.reload()
        let parent = try store.capture([.text("Trip", label: "Plan")])
        let child = try store.capture([.text("Independent reservation", label: "Saved")])
        store.edit(child) { $0.connectedPrivatePlanID = parent }
        await store.deleteEverywhere(parent)
        #expect(store.records.count == 1)
        #expect(store.ledger.records[child]?.content.connectedPrivatePlanID == nil)
        #expect(store.manifests.contains { $0.id == child })
    }
    @Test func accountSwitchCannotReadPreviousLedger() throws {
        let (vault, persistence, root, namespace) = try fixture()
        defer { vault.purgeEveryAccount(); UserDefaults().removePersistentDomain(forName: namespace); try? FileManager.default.removeItem(at: root) }
        let store = WEIntelligenceStore(vault: vault, persistence: persistence)
        store.reload(); try store.capture([.text("First account only", label: "Thought")])
        try vault.activate(accountID: "second-account", hueToken: "sage")
        store.reload(); #expect(store.records.isEmpty)
        try vault.activate(accountID: "fixture", hueToken: "sage")
        store.reload(); #expect(store.records.count == 1)
    }
}

@MainActor struct IntelligenceOriginalTests {
    @Test func originalChunksPreserveBytesAndRejectTampering() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = ShareVaultContext(pointer: .init(schemaVersion: 1, vaultID: UUID(), hueToken: "sage"), keyData: ShareCrypto.randomKeyData())
        let bytes = Data(repeating: 19, count: 2_100_000)
        let image = NormalizedShareImage(data: bytes, contentType: "image/png", pixelWidth: 5000, pixelHeight: 4000, sha256: ShareCrypto.sha256(bytes), isOriginal: true)
        let draft = try IncomingShareParser.parse([.image(image, label: "Original")], vaultID: context.pointer.vaultID)
        let vault = ShareVaultStore(root: root)
        let directory = try vault.commit(draft, context: context)
        let resource = try #require(draft.manifest.resources.first)
        #expect(try vault.loadResource(resource, manifest: draft.manifest, context: context) == bytes)
        let path = directory.appending(path: "resources/\(resource.sealedFilename)")
        var encrypted = try Data(contentsOf: path); encrypted[100] ^= 1; try encrypted.write(to: path)
        #expect(throws: (any Error).self) { try vault.loadResource(resource, manifest: draft.manifest, context: context) }
    }
}

@MainActor struct IntelligenceTimeProjectionTests {
    @Test func dateOnlyDeadlineIsNotOverdueDuringItsDay() throws {
        let now = try #require(WEObjectTiming.day("2026-09-13")).addingTimeInterval(12 * 3_600)
        let due = WEObjectTiming(precision: .day, kind: .deadline, startDay: "2026-09-13")
        #expect(WETimeRelevance.reason(for: due, now: now) == "You accepted this date for today.")
        #expect(WETimeRelevance.reason(for: due, now: now.addingTimeInterval(86_400))?.contains("has passed") == true)
    }
    @Test func multiDayTripIsRelevantOnIntermediateDays() throws {
        let timing = WEObjectTiming(precision: .day, startDay: "2026-11-01", endDay: "2026-11-04")
        let now = try #require(WEObjectTiming.day("2026-11-03"))
        #expect(WETimeRelevance.reason(for: timing, now: now) == "Today falls within the dates you accepted.")
        #expect(timing.includes(now))
        #expect(!timing.includes(try #require(WEObjectTiming.day("2026-11-05"))))
    }
}
