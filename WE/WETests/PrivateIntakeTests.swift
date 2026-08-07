import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import WE

@MainActor
private final class SharePublicationBackendStub:
    SharePublicationBackend,
    @unchecked Sendable
{
    private enum StubError: Error, LocalizedError {
        case finalizeFailed

        var errorDescription: String? {
            "The simulated final response was lost."
        }
    }

    var snapshots: [FrozenPublicationSnapshot] = []
    var retired: [UUID] = []
    var finalizeShouldFail = true
    private let publishedItemID = UUID()

    func createSession(
        for snapshot: FrozenPublicationSnapshot
    ) async throws -> SharePublicationSession {
        snapshots.append(snapshot)
        return SharePublicationSession(id: snapshot.id, uploads: [])
    }

    func upload(
        _ data: Data,
        descriptor: SharePublicationUpload
    ) async throws {}

    func finalize(sessionID: UUID) async throws -> UUID {
        if finalizeShouldFail { throw StubError.finalizeFailed }
        return publishedItemID
    }

    func retire(sessionID: UUID) async {
        retired.append(sessionID)
    }
}

@MainActor
struct PrivateIntakeTests {
    /// The per-category table, before anything is known about the item.
    /// `FieldLookupPolicy.choices(for:)` is what narrows this, and
    /// `FieldLookupPolicyTests` covers the narrowing.
    @Test
    func lookupCatalogueIsCategorySpecificAndExact() throws {
        #expect(
            FieldLookupPolicy.catalogue(for: .care).map(\.label)
                == ["FIND CARE", "APPOINTMENT", "SUPPLIES", "UNDERSTAND"]
        )
        #expect(
            FieldLookupPolicy.catalogue(for: .food).map(\.label)
                == ["COOK", "SHOP", "ORDER", "GO SOMEWHERE"]
        )
        #expect(
            FieldLookupPolicy.catalogue(for: .trips).map(\.label)
                == ["GET THERE", "STAY", "DO", "RESEARCH"]
        )
        #expect(
            FieldLookupPolicy.catalogue(for: .watchlist).map(\.label)
                == ["WATCH", "READ", "LISTEN", "LEARN"]
        )
        #expect(
            FieldLookupPolicy.catalogue(for: .buys).map(\.label)
                == ["BUY ONLINE", "NEARBY", "COMPARE", "SECONDHAND"]
        )
        #expect(
            FieldLookupPolicy.catalogue(for: .money).map(\.label)
                == ["PAY", "CONTACT PROVIDER", "UNDERSTAND", "COMPARE CAREFULLY"]
        )
        #expect(
            FieldLookupPolicy.catalogue(for: .home).map(\.label)
                == ["DIY", "PROFESSIONAL HELP", "BUY A PART", "NEARBY"]
        )
        // The generic set, reached by anything grown or ungrouped. Previously
        // untested, and the branch the Amazon complaint actually landed on.
        #expect(
            FieldLookupPolicy.catalogue(for: .notes).map(\.label)
                == ["INFORMATION", "PLACE", "PRODUCT", "PERSON OR SERVICE"]
        )

        let choice = try #require(
            FieldLookupPolicy.catalogue(for: .money)
                .first { $0.id == "money.contact" }
        )
        let request = FieldLookupRequest(
            choice: choice,
            title: "   Electric   bill   "
        )
        let disclosure = FieldLookupPolicy.disclosure(
            for: request,
            clarification: "  customer service  "
        )
        #expect(disclosure.destination == "DuckDuckGo")
        #expect(
            disclosure.fields == ["LIFE title", "lookup clarification"]
        )
        #expect(
            disclosure.query
                == "Electric bill customer service official contact"
        )
        #expect(!disclosure.query.contains("partner"))
    }

    // MARK: Where a share lands

    private func manifest(
        title: String,
        urls: [String] = []
    ) -> IncomingShareManifest {
        IncomingShareManifest(
            vaultID: UUID(),
            createdAt: Date(),
            titleSuggestion: title,
            representations: urls.compactMap { string in
                URL(string: string).map {
                    IncomingShareRepresentation(kind: .url, url: $0)
                }
            } + [IncomingShareRepresentation(kind: .text, text: title)],
            resources: [],
            omissions: []
        )
    }

    /// The complaint, at the layer it starts on. Every share used to land in
    /// Notes, which is how an Amazon product page ended up being offered a map.
    ///
    /// A link from a shop settles it ahead of the words, because a product
    /// page's title says nothing about buying and its hostname says everything.
    @Test
    func aSharedShopLinkOpensOnBuys() {
        #expect(
            ShareReviewModel.openingGuess(
                for: manifest(
                    title: "Sony WH-1000XM5 Wireless Headphones",
                    urls: ["https://www.amazon.com/dp/B09XS7JWHH"]
                )
            ) == .buys
        )
        #expect(
            ShareReviewModel.openingGuess(
                for: manifest(
                    title: "Cordless drill",
                    urls: ["https://www.homedepot.com/p/12345"]
                )
            ) == .buys
        )
    }

    /// A hostname that merely contains a shop's name is not that shop.
    @Test
    func aLookalikeHostDoesNotOpenOnBuys() {
        #expect(
            ShareReviewModel.openingGuess(
                for: manifest(
                    title: "A long read",
                    urls: ["https://fakeamazon.com/dp/1"]
                )
            ) != .buys
        )
    }

    /// A guess is still only a guess, and it has to be one the review sheet
    /// can show as selected. `lifeCategory` will happily invent a category
    /// from the subject of a sentence, which is right for something a person
    /// typed and wrong for the title tag of a web page.
    @Test
    func anOpeningGuessIsAlwaysACategoryTheSheetCanShow() {
        for title in [
            "Bloomberg",
            "Some Startup Raises A Series B",
            "",
            "   ",
            "Miso's teeth",
            "Renter's insurance",
        ] {
            let guess = ShareReviewModel.openingGuess(
                for: manifest(title: title)
            )
            #expect(
                ShareReviewModel.reviewCategories.contains(guess),
                "\(title) opened on \(guess.rawValue)"
            )
        }
    }

    /// Nothing to go on is still Notes. The old behaviour, kept for the case
    /// it was actually right for.
    @Test
    func aShareWithNothingToGoOnStillOpensOnNotes() {
        #expect(
            ShareReviewModel.openingGuess(for: manifest(title: "")) == .notes
        )
    }

    @Test
    func parserNormalisesDeduplicatesAndRejectsUnsafeLinks() throws {
        let vaultID = UUID()
        let duplicate = URL(string: "https://Example.COM/place#menu")!
        let draft = try IncomingShareParser.parse(
            [
                .webURL(duplicate, label: "Safari"),
                .webURL(duplicate, label: "Mail"),
                .webURL(
                    URL(string: "http://example.com/private")!,
                    label: "Insecure link"
                ),
                .text("  Dinner   Saturday\r\n", label: "Text"),
                .text("Dinner   Saturday", label: "Duplicate text"),
            ],
            vaultID: vaultID,
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(draft.manifest.vaultID == vaultID)
        #expect(
            draft.manifest.representations.count { $0.kind == .url } == 1
        )
        #expect(
            draft.manifest.representations.compactMap(\.url).first?
                .absoluteString == "https://example.com/place"
        )
        #expect(
            draft.manifest.representations.count { $0.kind == .text } == 1
        )
        #expect(draft.manifest.omissions.count == 3)
    }

    @Test
    func parserCapsPhotosAndUsesContentHashes() throws {
        let bytes = Data("normalized-photo".utf8)
        let image = NormalizedShareImage(
            data: bytes,
            contentType: "image/jpeg",
            pixelWidth: 1200,
            pixelHeight: 800,
            sha256: ShareCrypto.sha256(bytes)
        )
        let candidates = (0..<7).map {
            IncomingShareCandidate.image(image, label: "Photo \($0 + 1)")
        }
        let draft = try IncomingShareParser.parse(
            candidates,
            vaultID: UUID()
        )

        // Identical image content is one resource; the rest are explicit
        // duplicate omissions rather than silent copies.
        #expect(draft.manifest.imageCount == 1)
        #expect(draft.manifest.resources.count == 1)
        #expect(draft.manifest.omissions.count == 6)
    }

    @Test
    func vaultIsAccountIsolatedAndReadyDraftsAreImmutable() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShareVaultStore(root: root)
        let vaultA = UUID()
        let vaultB = UUID()
        let contextA = ShareVaultContext(
            pointer: ShareVaultPointer(
                schemaVersion: WEShareConstants.schemaVersion,
                vaultID: vaultA,
                hueToken: "burgundy"
            ),
            keyData: ShareCrypto.randomKeyData()
        )
        let contextB = ShareVaultContext(
            pointer: ShareVaultPointer(
                schemaVersion: WEShareConstants.schemaVersion,
                vaultID: vaultB,
                hueToken: "sage"
            ),
            keyData: ShareCrypto.randomKeyData()
        )
        let draft = try IncomingShareParser.parse(
            [.text("A private note", label: "Text")],
            vaultID: vaultA
        )

        try store.commit(draft, context: contextA)
        #expect(try store.readyDrafts(context: contextA).count == 1)
        #expect(try store.readyDrafts(context: contextB).isEmpty)
        #expect(throws: ShareVaultError.self) {
            try store.commit(draft, context: contextA)
        }
    }

    @Test
    func vaultRejectsCrossVaultManifests() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-attack-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let context = ShareVaultContext(
            pointer: ShareVaultPointer(
                schemaVersion: WEShareConstants.schemaVersion,
                vaultID: UUID(),
                hueToken: "burgundy"
            ),
            keyData: ShareCrypto.randomKeyData()
        )
        let otherDraft = try IncomingShareParser.parse(
            [.text("Wrong account", label: "Text")],
            vaultID: UUID()
        )
        #expect(throws: ShareVaultError.self) {
            try ShareVaultStore(root: root).commit(
                otherDraft,
                context: context
            )
        }
    }

    @Test
    func activeVaultHidesOnSignOutAndRestoresForTheSameAccount() throws {
        let suite = "we-private-intake-\(UUID().uuidString)"
        let account = "test-account-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-lifecycle-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = ShareVaultController(
            defaults: defaults,
            root: root
        )
        defer {
            controller.purge(accountID: account)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        let first = try controller.activate(
            accountID: account,
            hueToken: "burgundy"
        )
        controller.deactivate()
        #expect(throws: ShareVaultError.self) {
            try controller.activeContext()
        }

        let restored = try controller.activate(
            accountID: account,
            hueToken: "sage"
        )
        #expect(restored.pointer.vaultID == first.pointer.vaultID)

        controller.purge(accountID: account)
        let replacement = try controller.activate(
            accountID: account,
            hueToken: "sage"
        )
        #expect(replacement.pointer.vaultID != first.pointer.vaultID)
    }

    /// Reinstall, as iOS actually performs it: the app group container goes
    /// with the app, and the keychain does not.
    ///
    /// The container is what held the sealed drafts and the pointer naming the
    /// active vault, so it is modelled by dropping the suite and the root. The
    /// keychain is modelled by leaving it entirely alone — the same controller
    /// process keeps talking to the same real keychain across the boundary,
    /// which is precisely the asymmetry under test.
    @Test
    func freshInstallLeavesNoVaultMaterialForAnyAccount() throws {
        let suite = "we-reinstall-\(UUID().uuidString)"
        let first = "test-account-\(UUID().uuidString)"
        let second = "test-account-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-reinstall-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let defaults = try #require(UserDefaults(suiteName: suite))
        let before = ShareVaultController(defaults: defaults, root: root)
        defer {
            before.purgeEveryAccount()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        // Two accounts have signed in on this phone. Only the second is still
        // active, but both left a key behind.
        let firstVault = try before.activate(
            accountID: first,
            hueToken: "burgundy"
        )
        let secondVault = try before.activate(
            accountID: second,
            hueToken: "sage"
        )
        #expect(firstVault.pointer.vaultID != secondVault.pointer.vaultID)

        // The app is deleted. The container goes; the keychain stays.
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)

        let reinstalledSuite = "we-reinstall-\(UUID().uuidString)"
        let reinstalledRoot = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-reinstall-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let reinstalledDefaults = try #require(
            UserDefaults(suiteName: reinstalledSuite)
        )
        let after = ShareVaultController(
            defaults: reinstalledDefaults,
            root: reinstalledRoot
        )
        defer {
            after.purgeEveryAccount()
            reinstalledDefaults.removePersistentDomain(
                forName: reinstalledSuite
            )
            try? FileManager.default.removeItem(at: reinstalledRoot)
        }

        // Nothing is active before anybody signs in, container or no container.
        #expect(throws: ShareVaultError.self) {
            try after.activeContext()
        }

        // What `clearCredentialsIfFreshlyInstalled` now does on first run.
        after.purgeEveryAccount()

        // Both accounts are issued new vaults, which is the assertion that the
        // surviving keys are genuinely gone rather than merely unreachable.
        let firstAgain = try after.activate(
            accountID: first,
            hueToken: "burgundy"
        )
        let secondAgain = try after.activate(
            accountID: second,
            hueToken: "sage"
        )
        #expect(firstAgain.pointer.vaultID != firstVault.pointer.vaultID)
        #expect(secondAgain.pointer.vaultID != secondVault.pointer.vaultID)
    }

    /// The reinstall above must not be reachable by ordinary sign-out. Staged
    /// drafts are the person's own and survive signing out and back in — that
    /// is what `activeVaultHidesOnSignOutAndRestoresForTheSameAccount` fixes
    /// in place, and this is the same claim stated from the other side, so
    /// that a future `purgeEveryAccount()` added to the sign-out path fails
    /// loudly here rather than quietly discarding somebody's drafts.
    @Test
    func signOutKeepsTheVaultThatReinstallDestroys() throws {
        let suite = "we-signout-vs-reinstall-\(UUID().uuidString)"
        let account = "test-account-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-signout-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = ShareVaultController(defaults: defaults, root: root)
        defer {
            controller.purgeEveryAccount()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        let original = try controller.activate(
            accountID: account,
            hueToken: "burgundy"
        )

        controller.deactivate()
        let afterSignIn = try controller.activate(
            accountID: account,
            hueToken: "burgundy"
        )
        #expect(afterSignIn.pointer.vaultID == original.pointer.vaultID)

        controller.purgeEveryAccount()
        let afterReinstall = try controller.activate(
            accountID: account,
            hueToken: "burgundy"
        )
        #expect(afterReinstall.pointer.vaultID != original.pointer.vaultID)
    }

    @Test
    func vaultIgnoresInterruptedStagingAndExpiresOnSchedule() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-expiry-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let vaultID = UUID()
        let context = ShareVaultContext(
            pointer: ShareVaultPointer(
                schemaVersion: WEShareConstants.schemaVersion,
                vaultID: vaultID,
                hueToken: "burgundy"
            ),
            keyData: ShareCrypto.randomKeyData()
        )
        let store = ShareVaultStore(root: root)
        let old = Date().addingTimeInterval(-31 * 86_400)
        let draft = try IncomingShareParser.parse(
            [.text("Old private note", label: "Text")],
            vaultID: vaultID,
            now: old
        )
        try store.commit(draft, context: context)

        let abandoned = root
            .appending(path: "vaults/\(vaultID.uuidString.lowercased())")
            .appending(path: "staging/\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(
            at: abandoned,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: abandoned.path
        )

        // Only immutable ready directories enumerate as drafts.
        #expect(try store.readyDrafts(context: context).count == 1)
        store.cleanAbandonedStaging(
            context: context,
            olderThan: Date().addingTimeInterval(-86_400)
        )
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))

        store.expireReady(
            context: context,
            olderThan: Date().addingTimeInterval(-30 * 86_400)
        )
        #expect(try store.readyDrafts(context: context).isEmpty)
    }

    @Test
    func vaultRejectsUnreferencedResources() throws {
        let bytes = Data("normalized-photo".utf8)
        let resourceID = UUID()
        let vaultID = UUID()
        let manifest = IncomingShareManifest(
            vaultID: vaultID,
            createdAt: Date(),
            titleSuggestion: "Private note",
            representations: [
                .init(kind: .text, text: "Private note"),
            ],
            resources: [
                IncomingShareResource(
                    id: resourceID,
                    kind: .image,
                    sealedFilename:
                        "\(resourceID.uuidString.lowercased()).sealed",
                    contentType: "image/jpeg",
                    sha256: ShareCrypto.sha256(bytes),
                    byteCount: bytes.count,
                    pixelWidth: 20,
                    pixelHeight: 20
                ),
            ],
            omissions: []
        )
        let draft = IncomingShareDraft(
            manifest: manifest,
            resourceData: [resourceID: bytes]
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-vault-invalid-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let context = ShareVaultContext(
            pointer: ShareVaultPointer(
                schemaVersion: WEShareConstants.schemaVersion,
                vaultID: vaultID,
                hueToken: "burgundy"
            ),
            keyData: ShareCrypto.randomKeyData()
        )

        #expect(throws: ShareVaultError.self) {
            try ShareVaultStore(root: root).commit(
                draft,
                context: context
            )
        }
    }

    @Test
    func reviewFreezesARevisionAndDeletesOnlyAfterConfirmation() async throws {
        let suite = "we-review-\(UUID().uuidString)"
        let account = "review-account-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(
            path: "we-review-vault-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let reviews = FileManager.default.temporaryDirectory.appending(
            path: "we-review-records-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let defaults = try #require(UserDefaults(suiteName: suite))
        let vault = ShareVaultController(defaults: defaults, root: root)
        let context = try vault.activate(
            accountID: account,
            hueToken: "burgundy"
        )
        defer {
            vault.purge(accountID: account)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: reviews)
        }

        let draft = try IncomingShareParser.parse(
            [.text("A private reservation note", label: "Text")],
            vaultID: context.pointer.vaultID
        )
        try vault.store.commit(draft, context: context)

        let persistence = ShareReviewPersistence(root: reviews)
        let backend = SharePublicationBackendStub()
        let model = try ShareReviewModel(
            manifest: draft.manifest,
            vault: vault,
            persistence: persistence,
            backend: backend
        )

        #expect(model.revision.body.isEmpty)
        #expect(model.revision.includedURLRepresentationIDs.isEmpty)
        #expect(model.revision.includedResourceIDs.isEmpty)

        model.setTitle("Reviewed reservation")
        await model.publish()

        #expect(model.publishedItemID == nil)
        #expect(try vault.store.readyDrafts(context: context).count == 1)
        let failed = try #require(
            try persistence.load(
                draftID: draft.manifest.id,
                vaultID: context.pointer.vaultID
            )
        )
        let firstFrozen = try #require(failed.frozen)
        #expect(failed.session?.id == firstFrozen.id)
        #expect(firstFrozen.revision == 1)

        model.setTitle("Reviewed reservation, corrected")
        #expect(model.revision.revision == 2)
        let edited = try #require(
            try persistence.load(
                draftID: draft.manifest.id,
                vaultID: context.pointer.vaultID
            )
        )
        #expect(edited.frozen == nil)
        #expect(edited.session == nil)

        for _ in 0..<20 where backend.retired.isEmpty {
            await Task.yield()
        }
        #expect(backend.retired == [firstFrozen.id])

        backend.finalizeShouldFail = false
        await model.publish()

        #expect(model.publishedItemID != nil)
        #expect(backend.snapshots.map(\.revision) == [1, 2])
        #expect(try vault.store.readyDrafts(context: context).isEmpty)
        #expect(
            try persistence.load(
                draftID: draft.manifest.id,
                vaultID: context.pointer.vaultID
            ) == nil
        )
    }

    @Test
    func imageNormalizationDownsamplesAndStripsMetadata() throws {
        let input = FileManager.default.temporaryDirectory.appending(
            path: "we-source-\(UUID().uuidString).png"
        )
        defer { try? FileManager.default.removeItem(at: input) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 3_000,
                height: 1_500,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.setFillColor(
            CGColor(
                red: 0.42,
                green: 0.09,
                blue: 0.15,
                alpha: 1
            )
        )
        context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 1_500))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                input as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 40.7,
                    kCGImagePropertyGPSLongitude: -74.0,
                ]
            ] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))

        let normalized = try ShareImageNormalizer().normalize(fileAt: input)
        #expect(max(normalized.pixelWidth, normalized.pixelHeight) <= 2_400)
        #expect(normalized.data.count <= WEShareConstants.maximumOutputBytes)
        #expect(normalized.contentType == UTType.jpeg.identifier)
        #expect(normalized.sha256 == ShareCrypto.sha256(normalized.data))

        let outputSource = try #require(
            CGImageSourceCreateWithData(normalized.data as CFData, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(
                outputSource,
                0,
                nil
            ) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyExifDictionary] == nil)
        #expect(properties[kCGImagePropertyIPTCDictionary] == nil)
    }
}
