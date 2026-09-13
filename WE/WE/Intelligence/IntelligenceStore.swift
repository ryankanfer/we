import Foundation
import Observation

@MainActor @Observable
final class WEIntelligenceStore {
    static let shared = WEIntelligenceStore()
    private(set) var ledger = WEArtifactLedger()
    private(set) var manifests: [IncomingShareManifest] = []
    private(set) var message: String?
    private(set) var syncing = false
    private(set) var context: ShareVaultContext?
    private let persistence: WEIntelligencePersistence
    private let vault: ShareVaultController
    private let backendFactory: (@MainActor () async throws -> any WEIntelligenceSyncBackend)?
    init(vault: ShareVaultController = .shared, persistence: WEIntelligencePersistence = .init(),
         backendFactory: (@MainActor () async throws -> any WEIntelligenceSyncBackend)? = nil) {
        self.vault = vault; self.persistence = persistence; self.backendFactory = backendFactory
    }
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var records: [WEArtifactRecord] {
        ledger.records.values.filter { !$0.deleted }.sorted { $0.content.title.localizedStandardCompare($1.content.title) == .orderedAscending }
    }
    var deletedSharedIDs: Set<String> {
        Set(ledger.records.values.filter(\.deleted).compactMap(\.deletedPublishedItemID).map { $0.lowercased() })
    }
    var issues: [WEArtifactRecord] {
        ledger.records.values.filter { $0.failure != nil || $0.remoteConflict != nil || ($0.deleted && !$0.deletionConfirmed) || $0.content.job?.state == .failed }
    }
    func reload() {
        do {
            let active = try vault.activeContext()
            if context?.pointer.vaultID != active.pointer.vaultID { reset() }
            let disk = try persistence.load(context: active)
            context = active; ledger = disk
            manifests = try vault.store.readyDrafts(context: active)
            var changed = false
            for manifest in manifests where ledger.records[manifest.id] == nil {
                var content = WEArtifactContent(title: manifest.titleSuggestion)
                if let review = try ShareReviewPersistence().load(draftID: manifest.id, vaultID: active.pointer.vaultID) {
                    content.title = review.revision.title
                    content.body = review.revision.body
                    content.category = review.revision.category
                }
                content.processingConsent = ledger.localUnderstandingForNewItems == true
                content.linkCategory = WELinkCategory.classify(manifest.representations.compactMap { $0.text ?? $0.url?.absoluteString }.joined(separator: " "))
                ledger.records[manifest.id] = WEArtifactRecord(id: manifest.id, content: content)
                changed = true
            }
            for id in Array(ledger.records.keys) {
                if ledger.records[id]?.content.job?.state == .processing && tasks[id] == nil {
                    ledger.records[id]?.content.job?.state = .failed
                    ledger.records[id]?.content.job?.failure = "Understanding was interrupted. Retry or edit manually."
                    changed = true
                }
            }
            if changed { try persistence.save(ledger, context: active) }
            message = nil
            for record in records where record.content.job == nil && record.content.processingConsent {
                if let category = record.content.linkCategory, ledger.trustedCategories.contains(category),
                   let manifest = manifests.first(where: { $0.id == record.id }),
                   manifest.representations.compactMap(\.url).contains(where: WEPublicLinkReader.permitsAutomatic) {
                    understand(record.id, fetchLink: true, automatic: true)
                } else if manifests.first(where: { $0.id == record.id })?.representations.contains(where: { $0.text != nil || $0.kind == .image }) == true {
                    understand(record.id)
                }
            }
        } catch { reset(); message = "Private items could not be opened. Unlock this phone and retry. Saved files have not been replaced." }
    }
    func reset() {
        WESemanticSearch.invalidate()
        for task in tasks.values { task.cancel() }; tasks.removeAll()
        ledger = WEArtifactLedger(); manifests = []; context = nil; message = nil
        WEPlanNavigation.shared.pendingID = nil
    }
    private func validContext() throws -> ShareVaultContext {
        let active = try vault.activeContext()
        guard active.pointer.vaultID == context?.pointer.vaultID else { throw ShareVaultError.signedOut }
        return active
    }
    private func commit(_ next: WEArtifactLedger) throws {
        try persistence.save(next, context: validContext()); ledger = next
    }
    func edit(_ id: UUID, _ edit: (inout WEArtifactContent) -> Void) {
        guard var record = ledger.records[id], !record.deleted else { return }
        let before = record.content
        edit(&record.content); record.content.revision += 1; record.failure = nil
        let invalidatesJob = before.authorizationID != record.content.authorizationID
            || before.processingConsent != record.content.processingConsent
            || before.title != record.content.title || before.body != record.content.body
            || before.place != record.content.place || before.timing != record.content.timing
            || before.linkCategory != record.content.linkCategory
        if invalidatesJob && record.content.job?.state == .processing {
            record.content.job?.state = .failed
            record.content.job?.failure = "Details or permissions changed. Review and retry understanding."
        }
        var next = ledger; next.records[id] = record
        do {
            try commit(next)
            if invalidatesJob { tasks.removeValue(forKey: id)?.cancel() }
        } catch { message = "This edit was not saved. Please retry." }
    }
    @discardableResult func capture(_ candidates: [IncomingShareCandidate]) throws -> UUID {
        if context == nil { reload() }
        let active = try validContext()
        let draft = try IncomingShareParser.parse(candidates, vaultID: active.pointer.vaultID)
        try vault.store.commit(draft, context: active)
        reload()
        return draft.manifest.id
    }
    func deleteEverywhere(_ id: UUID) async {
        guard var record = ledger.records[id] else { return }
        record.deletedPublishedItemID = record.content.publishedItemID ?? record.deletedPublishedItemID
        record.deleted = true; record.pending = nil; record.syncedContent = nil; record.remoteConflict = nil; record.failure = nil
        record.content = WEArtifactContent(title: "Deleted item")
        var next = ledger; next.records[id] = record
        for childID in Array(next.records.keys) where next.records[childID]?.content.connectedPrivatePlanID == id {
            next.records[childID]?.content.connectedPrivatePlanID = nil
            next.records[childID]?.content.revision += 1
        }
        do {
            try commit(next) // Tombstone before files, processing, or network changes.
            WESemanticSearch.invalidate()
            tasks.removeValue(forKey: id)?.cancel()
            if let manifest = manifests.first(where: { $0.id == id }), let context {
                try vault.store.removePreserved(manifest, context: context)
                try ShareReviewPersistence().removeVerified(draftID: id, vaultID: context.pointer.vaultID)
            }
            manifests.removeAll { $0.id == id }
            await synchronize()
        } catch {
            message = ledger.records[id]?.deleted == true ? "Deletion is queued; local cleanup needs retry." : "Deletion could not be saved. Your item is still here."
        }
    }
    func recordFailure(_ id: UUID, message: String) {
        guard ledger.records[id]?.deleted == false else { return }
        var next = ledger; next.records[id]?.failure = message
        do { try commit(next) } catch { self.message = "Recovery status could not be saved. Your original remains preserved." }
    }
    func resolveConflict(_ id: UUID, keepLocal: Bool) {
        guard var record = ledger.records[id], let remote = record.remoteConflict, let version = record.conflictVersion else { return }
        if !keepLocal { record.content = remote }
        record.serverVersion = version; record.syncedContent = remote; record.remoteConflict = nil; record.conflictVersion = nil; record.pending = nil
        record.failure = nil
        var next = ledger; next.records[id] = record
        do { try commit(next) } catch { message = "Conflict choice was not saved." }
    }
    func synchronize() async {
        guard !syncing, let startContext = context else { return }
        if backendFactory == nil && WEIntelligenceCapabilities.isPreview { return }
        syncing = true; defer { syncing = false }
        let scope = startContext.pointer.vaultID
        do {
            let backend: any WEIntelligenceSyncBackend
            if let backendFactory { backend = try await backendFactory() } else { backend = try await WEIntelligenceBackend() }
            let deleted = try await backend.tombstones()
            guard try validContext().pointer.vaultID == scope else { return }
            if !deleted.isEmpty { WESemanticSearch.invalidate() }
            for id in deleted {
                if let manifest = manifests.first(where: { $0.id == id }) { try vault.store.removePreserved(manifest, context: startContext) }
                try ShareReviewPersistence().removeVerified(draftID: id, vaultID: scope)
                tasks.removeValue(forKey: id)?.cancel()
                var next = ledger
                var tombstone = WEArtifactRecord(id: id, content: WEArtifactContent(title: "Deleted item"))
                tombstone.deletedPublishedItemID = ledger.records[id]?.content.publishedItemID ?? ledger.records[id]?.deletedPublishedItemID
                tombstone.deleted = true; tombstone.deletionConfirmed = ledger.records[id]?.deletionConfirmed ?? false
                next.records[id] = tombstone; try commit(next)
                manifests.removeAll { $0.id == id }
            }
            for remote in try await backend.list() {
                guard try validContext().pointer.vaultID == scope else { return }
                if ledger.records[remote.id]?.deleted == true { continue }
                if var local = ledger.records[remote.id], remote.version > local.serverVersion, local.pending == nil {
                    if local.syncedContent == local.content {
                        local.content = remote.content; local.syncedContent = remote.content; local.serverVersion = remote.version
                    } else { local.remoteConflict = remote.content; local.conflictVersion = remote.version }
                    var next = ledger; next.records[remote.id] = local; try commit(next)
                }
                if !manifests.contains(where: { $0.id == remote.id }) {
                    var resources: [UUID: Data] = [:]
                    for resource in remote.manifest.resources {
                        resources[resource.id] = try await backend.download(artifact: remote.id, resource: resource)
                    }
                    guard try validContext().pointer.vaultID == scope else { return }
                    let old = remote.manifest
                    let manifest = IncomingShareManifest(vaultID: scope, id: old.id, revision: old.revision,
                        createdAt: old.createdAt, updatedAt: old.updatedAt, titleSuggestion: old.titleSuggestion,
                        representations: old.representations, resources: old.resources, omissions: old.omissions)
                    try vault.store.commit(IncomingShareDraft(manifest: manifest, resourceData: resources), context: startContext)
                    manifests.append(manifest)
                    var next = ledger
                    var record = WEArtifactRecord(id: remote.id, content: remote.content); record.serverVersion = remote.version; record.syncedContent = remote.content
                    next.records[remote.id] = record; try commit(next)
                }
            }
            for id in Array(ledger.records.keys) {
                guard try validContext().pointer.vaultID == scope else { return }
                guard var record = ledger.records[id], !record.deletionConfirmed, record.remoteConflict == nil else { continue }
                do {
                    if record.deleted {
                        if let manifest = manifests.first(where: { $0.id == id }) { try vault.store.removePreserved(manifest, context: startContext) }
                        try ShareReviewPersistence().removeVerified(draftID: id, vaultID: scope)
                        manifests.removeAll { $0.id == id }
                        try await backend.delete(id)
                        guard try validContext().pointer.vaultID == scope else { return }
                        record.deletionConfirmed = true; record.failure = nil
                        var next = ledger; next.records[id] = record; try commit(next)
                        continue
                    }
                    guard let manifest = manifests.first(where: { $0.id == id }) else { continue }
                    if record.pending == nil && record.syncedContent == record.content { continue }
                    if record.pending == nil {
                        record.pending = WEArtifactWrite(expectedVersion: record.serverVersion, content: record.content)
                        var next = ledger; next.records[id] = record; try commit(next)
                    }
                    let pending = record.pending!
                    for resource in manifest.resources {
                        let bytes = try vault.store.loadResource(resource, manifest: manifest, context: startContext)
                        try await backend.upload(bytes, artifact: id, resource: resource)
                    }
                    guard try validContext().pointer.vaultID == scope, ledger.records[id]?.deleted == false else { continue }
                    let result = try await backend.write(pending, manifest: manifest)
                    guard try validContext().pointer.vaultID == scope, var latest = ledger.records[id], !latest.deleted else { continue }
                    latest.serverVersion = result.version; latest.failure = nil
                    if let conflict = result.conflict { latest.remoteConflict = conflict; latest.conflictVersion = result.version }
                    else {
                        latest.syncedContent = pending.content
                        latest.pending = latest.content == pending.content ? nil : WEArtifactWrite(expectedVersion: result.version, content: latest.content)
                    }
                    var next = ledger; next.records[id] = latest; try commit(next)
                } catch {
                    guard try validContext().pointer.vaultID == scope else { return }
                    var next = ledger; next.records[id]?.failure = "Could not sync. Your saved work remains on this phone."
                    try commit(next)
                }
            }
        } catch { message = "Sync is unavailable. Saved items remain on this phone." }
    }
    func setLocalUnderstandingDefault(_ enabled: Bool) {
        var next = ledger; next.localUnderstandingForNewItems = enabled
        do { try commit(next) } catch { message = "Permission change was not saved." }
    }
    func ruleEligible(_ category: WELinkCategory) -> Bool {
        Set(records.filter { $0.content.linkCategory == category }.flatMap { $0.content.explicitLinkGrants }).count >= 3
    }
    func setRule(_ category: WELinkCategory, enabled: Bool) {
        guard !enabled || ruleEligible(category) || ledger.trustedCategories.contains(category) else {
            message = "Understand three different \(category.label) links before enabling this rule."
            return
        }
        var next = ledger
        if enabled { next.trustedCategories.insert(category) } else { next.trustedCategories.remove(category) }
        do {
            try commit(next)
            if !enabled {
                for record in records where record.content.linkCategory == category && record.content.automaticFetchReason != nil {
                    tasks.removeValue(forKey: record.id)?.cancel()
                    edit(record.id) { $0.authorizationID = UUID(); $0.job = nil }
                }
            }
        } catch { message = "Permission change was not saved." }
    }
}

extension WEIntelligenceStore {
    func understand(_ id: UUID, fetchLink: Bool = false, automatic: Bool = false) {
        guard WEIntelligenceCapabilities.enrichmentEnabled else { return }
        if automatic && !WEIntelligenceCapabilities.automaticLinksEnabled { return }
        guard let record = ledger.records[id], !record.deleted, record.content.processingConsent,
              let manifest = manifests.first(where: { $0.id == id }), let context else { return }
        if automatic {
            guard let category = record.content.linkCategory, ledger.trustedCategories.contains(category) else { return }
        }
        tasks[id]?.cancel()
        let authorization = record.content.authorizationID
        let revision = record.content.revision + 1
        edit(id) {
            $0.job = WEProcessingJob(sourceRevision: revision, state: .processing, authorizationID: authorization)
            $0.automaticFetchReason = automatic ? "Understood automatically under your \($0.linkCategory?.label ?? "") rule." : nil
        }
        guard ledger.records[id]?.content.job?.sourceRevision == revision else { return }
        let scope = context.pointer.vaultID
        tasks[id] = Task {
            defer {
                if (try? validContext().pointer.vaultID) == scope,
                   ledger.records[id]?.content.job?.sourceRevision == revision {
                    tasks[id] = nil
                    if ledger.records[id]?.content.job?.state == .processing {
                        edit(id) { $0.job?.state = .failed; $0.job?.failure = "Saved details changed. Review and retry understanding." }
                    }
                }
            }
            do {
                var source = manifest.representations.compactMap(\.text).joined(separator: "\n")
                var granted: [String] = []
                if fetchLink {
                    for url in manifest.representations.compactMap(\.url) {
                        if automatic && !WEPublicLinkReader.permitsAutomatic(url) { throw WEPublicLinkReader.Failure.unsafeURL }
                        source += "\n" + (try await WEPublicLinkReader.read(url))
                        granted.append(url.absoluteString)
                    }
                }
                let images = try manifest.resources.map { resource in
                    (resource.id, try vault.store.loadResource(resource, manifest: manifest, context: context))
                }
                let output = try await WEUnderstanding.extract(text: source, images: images)
                try Task.checkCancellation()
                guard try validContext().pointer.vaultID == scope,
                      let current = ledger.records[id], !current.deleted,
                      current.content.revision == revision,
                      current.content.authorizationID == authorization,
                      current.content.processingConsent else { return }
                edit(id) {
                    $0.evidence = output.evidence; $0.suggestions = output.suggestions
                    $0.job?.state = .completed; $0.job?.failure = nil
                    if !automatic { $0.explicitLinkGrants.formUnion(granted) }
                }
            } catch {
                guard (try? validContext().pointer.vaultID) == scope,
                      ledger.records[id]?.content.authorizationID == authorization,
                      ledger.records[id]?.content.revision == revision else { return }
                edit(id) { $0.job?.state = .failed; $0.job?.failure = "Understanding did not finish. Your original is safe; retry or edit manually." }
            }
        }
    }
    func accept(_ suggestion: WEUnderstandingSuggestion, for id: UUID) {
        edit(id) { content in
            switch suggestion.field {
            case .title: content.title = suggestion.value
            case .place: content.place = suggestion.value
            case .category: content.category = suggestion.value
            case .timing: content.timing = WEObjectTiming(precision: .day, startDay: suggestion.value)
            }
            if let index = content.suggestions.firstIndex(where: { $0.id == suggestion.id }) { content.suggestions[index].accepted = true }
        }
    }
}
