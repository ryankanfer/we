import Foundation
import FoundationModels
import Combine

nonisolated enum ProposalPreparationMethod: String, Codable, Sendable {
    case onDeviceModel
    case deterministicFallback
}

nonisolated enum SoftStartAccountIntent: String, Codable, Sendable {
    case keepPrivateProposal
    case offerApprovedTopic
}

nonisolated struct OfferedTopic: Codable, Hashable, Sendable {
    let title: String
    let question: String
    let options: [String]
}

nonisolated struct PrivateProposal: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceNote: String
    let title: String
    let offeredTopic: OfferedTopic
    let preparationMethod: ProposalPreparationMethod
    let createdAt: Date
    let accountIntent: SoftStartAccountIntent?

    init(
        id: UUID,
        sourceNote: String,
        title: String,
        offeredTopic: OfferedTopic,
        preparationMethod: ProposalPreparationMethod,
        createdAt: Date,
        accountIntent: SoftStartAccountIntent? = nil
    ) {
        self.id = id
        self.sourceNote = sourceNote
        self.title = title
        self.offeredTopic = offeredTopic
        self.preparationMethod = preparationMethod
        self.createdAt = createdAt
        self.accountIntent = accountIntent
    }

    func settingAccountIntent(
        _ accountIntent: SoftStartAccountIntent?
    ) -> PrivateProposal {
        PrivateProposal(
            id: id,
            sourceNote: sourceNote,
            title: title,
            offeredTopic: offeredTopic,
            preparationMethod: preparationMethod,
            createdAt: createdAt,
            accountIntent: accountIntent
        )
    }
}

/// The owner-only projection of a proposal after it has been claimed by an
/// account. The private source note is deliberately absent so routine reads
/// cannot bring raw Soft Start input back into app state.
nonisolated struct SavedPrivateProposal: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let offeredTopic: OfferedTopic
    let preparationMethod: ProposalPreparationMethod
    let preparedAt: String

    init(
        id: String,
        title: String,
        offeredTopic: OfferedTopic,
        preparationMethod: ProposalPreparationMethod,
        preparedAt: String
    ) {
        self.id = id
        self.title = title
        self.offeredTopic = offeredTopic
        self.preparationMethod = preparationMethod
        self.preparedAt = preparedAt
    }

    init(serverID: String, proposal: PrivateProposal) {
        self.init(
            id: serverID,
            title: proposal.title,
            offeredTopic: proposal.offeredTopic,
            preparationMethod: proposal.preparationMethod,
            preparedAt: ISO8601DateFormatter().string(
                from: proposal.createdAt
            )
        )
    }
}

nonisolated struct SoftStartClaim: Hashable, Sendable {
    let proposal: PrivateProposal
    let intent: SoftStartAccountIntent
}

nonisolated struct SoftStartClaimReceipt: Codable, Hashable, Sendable {
    let serverID: String
    let intent: SoftStartAccountIntent
}

nonisolated struct ProtectedProposalStore: Sendable {
    enum StoreError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "WE could not protect this note on this iPhone."
        }
    }

    let fileURL: URL
    let receiptFileURL: URL

    init(fileURL: URL? = nil, receiptFileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            self.receiptFileURL = receiptFileURL
                ?? fileURL.deletingLastPathComponent()
                    .appendingPathComponent("claim-receipt.json")
            return
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let directory = (base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("SoftStart", isDirectory: true)
        self.fileURL = directory
            .appendingPathComponent("private-proposal.json")
        self.receiptFileURL = receiptFileURL
            ?? directory.appendingPathComponent("claim-receipt.json")
    }

    func load() throws -> PrivateProposal? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder.weProposal.decode(
            PrivateProposal.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ proposal: PrivateProposal) throws {
        try writeProtected(proposal, to: fileURL)
    }

    func loadReceipt() throws -> SoftStartClaimReceipt? {
        guard FileManager.default.fileExists(
            atPath: receiptFileURL.path
        ) else {
            return nil
        }
        return try JSONDecoder.weProposal.decode(
            SoftStartClaimReceipt.self,
            from: Data(contentsOf: receiptFileURL)
        )
    }

    func saveReceipt(_ receipt: SoftStartClaimReceipt) throws {
        try writeProtected(receipt, to: receiptFileURL)
    }

    func removeReceipt() throws {
        try removeFile(at: receiptFileURL)
    }

    func remove() throws {
        try removeFile(at: fileURL)
    }

    private func writeProtected<Value: Encodable>(
        _ value: Value,
        to destination: URL
    ) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(directoryValues)

        let data = try JSONEncoder.weProposal.encode(value)
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtection]
        )
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path
            )
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var protectedFile = destination
            try protectedFile.setResourceValues(fileValues)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func removeFile(at destination: URL) throws {
        guard FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            return
        }
        try FileManager.default.removeItem(at: destination)

        let directory = destination.deletingLastPathComponent()
        let remainingItems = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        if remainingItems.isEmpty {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

nonisolated struct ProposalPreparationService: Sendable {
    typealias OnDeviceTitleGenerator =
        @Sendable (_ privateNote: String) async throws -> String?

    private let onDeviceTitleGenerator: OnDeviceTitleGenerator

    init(
        onDeviceTitleGenerator: @escaping OnDeviceTitleGenerator =
            ProposalPreparationService.generateOnDeviceTitle
    ) {
        self.onDeviceTitleGenerator = onDeviceTitleGenerator
    }

    func prepare(note: String) async throws -> PrivateProposal {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let offeredTopic = Self.offeredTopic(for: trimmed)

        do {
            if let generated = try await onDeviceTitleGenerator(trimmed),
               let title = Self.sanitizedTitle(generated) {
                return PrivateProposal(
                    id: UUID(),
                    sourceNote: trimmed,
                    title: title,
                    offeredTopic: offeredTopic,
                    preparationMethod: .onDeviceModel,
                    createdAt: Date()
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The private note never leaves the device. A predictable local
            // transformation is the complete fallback path.
        }

        try Task.checkCancellation()
        return PrivateProposal(
            id: UUID(),
            sourceNote: trimmed,
            title: Self.fallbackTitle(for: trimmed),
            offeredTopic: offeredTopic,
            preparationMethod: .deterministicFallback,
            createdAt: Date()
        )
    }

    private static func generateOnDeviceTitle(
        for note: String
    ) async throws -> String? {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            Turn a private relationship note into one concrete, reversible \
            proposal the writer can keep for themselves. Do not diagnose, \
            judge, mention a partner, or quote the note. Return only a short \
            imperative phrase under 60 characters.
            """
        )
        let response = try await session.respond(
            to: note,
            options: GenerationOptions(
                sampling: .greedy,
                maximumResponseTokens: 24
            )
        )
        return response.content
    }

    static func fallbackTitle(for note: String) -> String {
        let value = note.lowercased()
        if value.contains("friday") || value.contains("evening") {
            return "Protect Friday evening"
        }
        if value.contains("weekend") || value.contains("rest") {
            return "Keep part of the weekend open"
        }
        if value.contains("grocer") || value.contains("chore")
            || value.contains("work") || value.contains("load") {
            return "Make one thing lighter this week"
        }
        if value.contains("talk") || value.contains("discuss") {
            return "Choose a calm time to talk"
        }
        return "Make a little room for this"
    }

    static func offeredTopic(for note: String) -> OfferedTopic {
        let value = note.lowercased()
        if value.contains("friday") || value.contains("evening") {
            return OfferedTopic(
                title: "A quieter Friday",
                question: "How should Friday feel?",
                options: ["Quiet", "Open", "Social"]
            )
        }
        if value.contains("weekend") || value.contains("rest") {
            return OfferedTopic(
                title: "A weekend with room",
                question: "What should this weekend hold?",
                options: ["Rest", "Something new", "Keep it open"]
            )
        }
        if value.contains("grocer") || value.contains("chore")
            || value.contains("work") || value.contains("load") {
            return OfferedTopic(
                title: "A lighter week",
                question: "What would make this week lighter?",
                options: ["One less thing", "Do one thing together", "Decide later"]
            )
        }
        return OfferedTopic(
            title: "A little more room",
            question: "What would feel useful right now?",
            options: ["More quiet", "A simple plan", "Room to decide later"]
        )
    }

    private static func sanitizedTitle(_ content: String) -> String? {
        let first = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(
                charactersIn: "\"'“”•-* "
            ))
        guard let first, !first.isEmpty else { return nil }
        return String(first.prefix(60))
    }
}

@MainActor
final class SoftStartCoordinator: ObservableObject {
    enum Stage: Equatable {
        case capture
        case preparing
        case proposal
        case offerPreview
    }

    @Published var note = ""
    @Published private(set) var proposal: PrivateProposal?
    @Published private(set) var claimReceipt: SoftStartClaimReceipt?
    @Published private(set) var stage: Stage = .capture
    @Published private(set) var errorMessage: String?

    private let store: ProtectedProposalStore
    private let preparationService: ProposalPreparationService

    init(
        store: ProtectedProposalStore = ProtectedProposalStore(),
        preparationService: ProposalPreparationService =
            ProposalPreparationService()
    ) {
        self.store = store
        self.preparationService = preparationService
        claimReceipt = try? store.loadReceipt()

        if claimReceipt != nil {
            do {
                // Receipt-first claiming means a terminated process can leave
                // the old source file behind. A receipt proves the server has
                // the owner-only record, so finish deleting raw local input.
                try store.remove()
                if claimReceipt?.intent == .keepPrivateProposal {
                    try store.removeReceipt()
                    claimReceipt = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if let restored = try? store.load() {
            proposal = restored
            note = restored.sourceNote
            stage = restored.accountIntent == .offerApprovedTopic
                ? .offerPreview
                : .proposal
        }
    }

    var hasProtectedProposal: Bool { proposal != nil }

    var pendingClaim: SoftStartClaim? {
        guard let proposal, let intent = proposal.accountIntent else {
            return nil
        }
        return SoftStartClaim(proposal: proposal, intent: intent)
    }

    var pendingOfferProposalID: String? {
        guard claimReceipt?.intent == .offerApprovedTopic else {
            return nil
        }
        return claimReceipt?.serverID
    }

    func prepare() async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, stage != .preparing else { return }
        guard claimReceipt == nil else {
            errorMessage =
                "Your approved offer is still waiting to be published."
            return
        }
        errorMessage = nil
        stage = .preparing
        do {
            let prepared = try await preparationService.prepare(note: trimmed)
            try Task.checkCancellation()
            try store.save(prepared)
            proposal = prepared
            note = prepared.sourceNote
            stage = .proposal
        } catch is CancellationError {
            stage = .capture
        } catch {
            errorMessage = error.localizedDescription
            stage = .capture
        }
    }

    @discardableResult
    func showOfferPreview() -> Bool {
        guard proposal != nil else { return false }
        guard updateAccountIntent(nil) else { return false }
        stage = .offerPreview
        return true
    }

    @discardableResult
    func showProposal() -> Bool {
        guard proposal != nil else { return false }
        guard updateAccountIntent(nil) else { return false }
        stage = .proposal
        return true
    }

    @discardableResult
    func prepareAccountHandoff(
        for intent: SoftStartAccountIntent
    ) -> Bool {
        updateAccountIntent(intent)
    }

    private func updateAccountIntent(
        _ intent: SoftStartAccountIntent?
    ) -> Bool {
        guard let proposal else { return false }
        guard proposal.accountIntent != intent else {
            errorMessage = nil
            return true
        }
        let updated = proposal.settingAccountIntent(intent)
        do {
            try store.save(updated)
            self.proposal = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func clear() -> Bool {
        do {
            try store.remove()
            proposal = nil
            note = ""
            errorMessage = nil
            stage = .capture
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func markClaimed(
        serverID: String,
        intent: SoftStartAccountIntent
    ) -> Bool {
        let normalizedID = serverID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedID.isEmpty else { return false }
        guard proposal?.accountIntent == intent else { return false }

        let receipt = SoftStartClaimReceipt(
            serverID: normalizedID,
            intent: intent
        )
        do {
            // Persist the safe continuation before deleting the only record
            // that contains the private source note.
            try store.saveReceipt(receipt)
            claimReceipt = receipt
            proposal = nil
            note = ""
            stage = .capture
            try store.remove()
            if intent == .keepPrivateProposal {
                try store.removeReceipt()
                claimReceipt = nil
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func markOfferPublished() -> Bool {
        guard claimReceipt?.intent == .offerApprovedTopic else {
            return false
        }
        do {
            try store.removeReceipt()
            claimReceipt = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

nonisolated private extension JSONEncoder {
    static var weProposal: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

nonisolated private extension JSONDecoder {
    static var weProposal: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
