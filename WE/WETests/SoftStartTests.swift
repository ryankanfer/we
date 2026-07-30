import Foundation
import Testing
@testable import WE

nonisolated private enum SoftStartStubError: Error {
    case unavailable
}

@MainActor
struct SoftStartTests {
    @Test
    func unavailableModelUsesDeterministicLocalFallback() async throws {
        let service = ProposalPreparationService(
            onDeviceTitleGenerator: { _ in nil }
        )

        let first = try await service.prepare(
            note: "I would love a quiet Friday evening."
        )
        let second = try await service.prepare(
            note: "I would love a quiet Friday evening."
        )

        #expect(first.preparationMethod == .deterministicFallback)
        #expect(first.title == "Protect Friday evening")
        #expect(first.title == second.title)
        #expect(first.offeredTopic == second.offeredTopic)
    }

    @Test
    func modelFailureFallsBackWithoutLosingPrivateSource() async throws {
        let service = ProposalPreparationService(
            onDeviceTitleGenerator: { _ in
                throw SoftStartStubError.unavailable
            }
        )
        let note = "There is too much work to carry this week."

        let proposal = try await service.prepare(note: note)

        #expect(proposal.sourceNote == note)
        #expect(proposal.preparationMethod == .deterministicFallback)
        #expect(proposal.title == "Make one thing lighter this week")
    }

    @Test
    func generatedTitleIsShortAndPresentationSafe() async throws {
        let service = ProposalPreparationService(
            onDeviceTitleGenerator: { _ in
                "  “Protect one quiet hour”  \nDo not render this line"
            }
        )

        let proposal = try await service.prepare(note: "A private note")

        #expect(proposal.preparationMethod == .onDeviceModel)
        #expect(proposal.title == "Protect one quiet hour")
        #expect(proposal.title.count <= 60)
    }

    @Test
    func cancellationDoesNotCreateAFallbackProposal() async {
        let service = ProposalPreparationService(
            onDeviceTitleGenerator: { _ in
                try await Task.sleep(for: .seconds(30))
                return nil
            }
        )
        let task = Task {
            try await service.prepare(note: "A thought")
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancellation must not produce a proposal.")
        } catch is CancellationError {
            // Expected: a cancelled model request never falls through to save.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }
    }

    @Test
    func protectedProposalAndAccountIntentSurviveARelaunch()
        async throws
    {
        let fixture = makeStore()
        defer { fixture.removeDirectory() }
        let service = ProposalPreparationService(
            onDeviceTitleGenerator: { _ in nil }
        )
        let coordinator = SoftStartCoordinator(
            store: fixture.store,
            preparationService: service
        )
        coordinator.note = "I would love a quieter Friday."

        await coordinator.prepare()
        #expect(coordinator.stage == .proposal)
        #expect(coordinator.hasProtectedProposal)
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))

        #expect(
            coordinator.prepareAccountHandoff(
                for: .offerApprovedTopic
            )
        )
        #expect(coordinator.pendingClaim?.intent == .offerApprovedTopic)

        let restored = SoftStartCoordinator(
            store: fixture.store,
            preparationService: service
        )
        #expect(restored.stage == .offerPreview)
        #expect(restored.pendingClaim?.intent == .offerApprovedTopic)
        #expect(
            restored.pendingClaim?.proposal.offeredTopic
                == coordinator.proposal?.offeredTopic
        )

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path
        )
#if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey]
            as? FileProtectionType {
            #expect(protection == .complete)
        }
#else
        #expect(
            attributes[.protectionKey] as? FileProtectionType
                == .complete
        )
#endif
    }

    @Test
    func leavingApprovedPreviewRevokesPendingAccountIntent()
        async throws
    {
        let fixture = makeStore()
        defer { fixture.removeDirectory() }
        let coordinator = SoftStartCoordinator(
            store: fixture.store,
            preparationService: ProposalPreparationService(
                onDeviceTitleGenerator: { _ in nil }
            )
        )
        coordinator.note = "Keep Friday open."
        await coordinator.prepare()
        #expect(coordinator.showOfferPreview())
        #expect(
            coordinator.prepareAccountHandoff(
                for: .offerApprovedTopic
            )
        )

        #expect(coordinator.showProposal())

        #expect(coordinator.pendingClaim == nil)
        #expect(try fixture.store.load()?.accountIntent == nil)
    }

    @Test
    func approvedOfferContainsNoVerbatimPrivateNote() async throws {
        let uniquePrivateText = "Dylan and the saffron envelope"
        let service = ProposalPreparationService(
            onDeviceTitleGenerator: { _ in nil }
        )

        let proposal = try await service.prepare(note: uniquePrivateText)
        let offeredText = [
            proposal.offeredTopic.title,
            proposal.offeredTopic.question,
            proposal.offeredTopic.options.joined(separator: " "),
        ]
        .joined(separator: " ")
        .lowercased()

        #expect(!offeredText.contains("dylan"))
        #expect(!offeredText.contains("saffron"))
        #expect(!offeredText.contains("envelope"))
    }

    @Test
    func successfulPrivateClaimDeletesRawLocalState()
        async
    {
        let fixture = makeStore()
        defer { fixture.removeDirectory() }
        let coordinator = SoftStartCoordinator(
            store: fixture.store,
            preparationService: ProposalPreparationService(
                onDeviceTitleGenerator: { _ in nil }
            )
        )
        coordinator.note = "A quieter weekend."
        await coordinator.prepare()
        #expect(
            coordinator.prepareAccountHandoff(
                for: .keepPrivateProposal
            )
        )

        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(coordinator.pendingClaim != nil)

        #expect(
            coordinator.markClaimed(
                serverID: "server-private-1",
                intent: .keepPrivateProposal
            )
        )

        #expect(coordinator.pendingClaim == nil)
        #expect(coordinator.pendingOfferProposalID == nil)
        #expect(coordinator.proposal == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.store.receiptFileURL.path
            )
        )
        #expect(coordinator.stage == .capture)
    }

    @Test
    func claimedOfferKeepsOnlySafeReceiptUntilPublished() async throws {
        let fixture = makeStore()
        defer { fixture.removeDirectory() }
        let privateText = "Dylan and the saffron envelope"
        let coordinator = SoftStartCoordinator(
            store: fixture.store,
            preparationService: ProposalPreparationService(
                onDeviceTitleGenerator: { _ in nil }
            )
        )
        coordinator.note = privateText
        await coordinator.prepare()
        #expect(coordinator.showOfferPreview())
        #expect(
            coordinator.prepareAccountHandoff(
                for: .offerApprovedTopic
            )
        )

        #expect(
            coordinator.markClaimed(
                serverID: "server-offer-7",
                intent: .offerApprovedTopic
            )
        )

        #expect(coordinator.proposal == nil)
        #expect(coordinator.note.isEmpty)
        #expect(coordinator.pendingClaim == nil)
        #expect(coordinator.pendingOfferProposalID == "server-offer-7")
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.store.receiptFileURL.path
            )
        )

        let receiptBytes = try Data(
            contentsOf: fixture.store.receiptFileURL
        )
        let receiptText = String(decoding: receiptBytes, as: UTF8.self)
        #expect(!receiptText.lowercased().contains("dylan"))
        #expect(!receiptText.lowercased().contains("saffron"))
        #expect(!receiptText.lowercased().contains("envelope"))

        let restored = SoftStartCoordinator(
            store: fixture.store,
            preparationService: ProposalPreparationService(
                onDeviceTitleGenerator: { _ in nil }
            )
        )
        #expect(restored.proposal == nil)
        #expect(restored.note.isEmpty)
        #expect(restored.pendingOfferProposalID == "server-offer-7")

        #expect(restored.markOfferPublished())
        #expect(restored.pendingOfferProposalID == nil)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.store.receiptFileURL.path
            )
        )
    }

    @Test
    func relaunchFinishesReceiptFirstRawDeletion() throws {
        let fixture = makeStore()
        defer { fixture.removeDirectory() }
        let proposal = PrivateProposal(
            id: UUID(),
            sourceNote: "Raw note that must be removed",
            title: "Make a little room for this",
            offeredTopic: ProposalPreparationService.offeredTopic(
                for: "Raw note that must be removed"
            ),
            preparationMethod: .deterministicFallback,
            createdAt: Date(),
            accountIntent: .offerApprovedTopic
        )
        try fixture.store.save(proposal)
        try fixture.store.saveReceipt(
            SoftStartClaimReceipt(
                serverID: "server-recovered-3",
                intent: .offerApprovedTopic
            )
        )

        let restored = SoftStartCoordinator(
            store: fixture.store,
            preparationService: ProposalPreparationService(
                onDeviceTitleGenerator: { _ in nil }
            )
        )

        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(restored.proposal == nil)
        #expect(restored.note.isEmpty)
        #expect(
            restored.pendingOfferProposalID == "server-recovered-3"
        )
    }

    private func makeStore() -> StoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "we-soft-start-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        let fileURL = directory.appendingPathComponent(
            "private-proposal.json"
        )
        return StoreFixture(
            directory: directory,
            fileURL: fileURL,
            store: ProtectedProposalStore(fileURL: fileURL)
        )
    }
}

private struct StoreFixture {
    let directory: URL
    let fileURL: URL
    let store: ProtectedProposalStore

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }
}
