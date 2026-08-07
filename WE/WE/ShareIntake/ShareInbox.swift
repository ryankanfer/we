import Observation
import SwiftUI
import UIKit

enum WEFeatureFlags {
    static var shareInboxEnabled: Bool {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "WEShareInboxEnabled"
        )
        if let bool = value as? Bool { return bool }
        return (value as? String)?.lowercased() == "yes"
    }
}

@MainActor
@Observable
final class ShareInboxModel {
    private(set) var drafts: [IncomingShareManifest] = []
    private(set) var isLoading = true
    private(set) var message: String?

    private let vault = ShareVaultController.shared

    func load() {
        isLoading = true
        message = nil
        do {
            let context = try vault.activeContext()
            vault.store.expireReady(
                context: context,
                olderThan: Date().addingTimeInterval(-30 * 86_400)
            )
            drafts = try vault.store.readyDrafts(context: context)
            isLoading = false
        } catch {
            drafts = []
            isLoading = false
            message = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class ShareReviewModel {
    let manifest: IncomingShareManifest

    private(set) var revision: AppShareRevision
    private(set) var previewData: [UUID: Data] = [:]
    private(set) var isPublishing = false
    private(set) var publishedItemID: UUID?
    var message: String?

    private let context: ShareVaultContext
    private let vault: ShareVaultController
    private let persistence: ShareReviewPersistence
    private let backend: any SharePublicationBackend
    private var record: PersistedShareReview

    convenience init(manifest: IncomingShareManifest) throws {
        try self.init(
            manifest: manifest,
            vault: ShareVaultController.shared,
            persistence: ShareReviewPersistence(),
            backend: SupabaseSharePublicationBackend()
        )
    }

    init(
        manifest: IncomingShareManifest,
        vault: ShareVaultController,
        persistence: ShareReviewPersistence,
        backend: any SharePublicationBackend
    ) throws {
        let context = try vault.activeContext()
        guard manifest.vaultID == context.pointer.vaultID else {
            throw ShareVaultError.invalidDraft
        }
        self.manifest = manifest
        self.context = context
        self.vault = vault
        self.persistence = persistence
        self.backend = backend

        if let saved = try persistence.load(
            draftID: manifest.id,
            vaultID: manifest.vaultID
        ) {
            record = saved
            revision = saved.revision
        } else {
            let initial = AppShareRevision(
                draftID: manifest.id,
                revision: manifest.revision,
                title: manifest.titleSuggestion,
                body: "",
                category: Self.openingGuess(for: manifest).rawValue,
                includedURLRepresentationIDs: [],
                includedResourceIDs: [],
                updatedAt: Date()
            )
            record = PersistedShareReview(
                schemaVersion: PersistedShareReview.schemaVersion,
                revision: initial,
                frozen: nil,
                session: nil
            )
            revision = initial
            try persistence.save(record, vaultID: manifest.vaultID)
        }
    }

    var textSources: [String] {
        manifest.representations.compactMap(\.text)
    }

    var URLSources: [IncomingShareRepresentation] {
        manifest.representations.filter {
            $0.kind == .url && $0.url != nil
        }
    }

    var imageResources: [IncomingShareResource] {
        manifest.resources.filter { $0.kind == .image }
    }

    var approvedImageResources: [IncomingShareResource] {
        imageResources.filter {
            revision.includedResourceIDs.contains($0.id)
        }
    }

    var category: LifeCategory {
        LifeCategory(rawValue: revision.category)
    }

    var canPublish: Bool {
        !revision.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty && !isPublishing
    }

    var exactSharedFields: [(String, String)] {
        var fields = [
            ("Destination", category.label),
            ("Title", revision.title),
        ]
        if !revision.body.isEmpty {
            fields.append(("Body", revision.body))
        }
        let links = URLSources.filter {
            revision.includedURLRepresentationIDs.contains($0.id)
        }
        for link in links {
            fields.append(("Link", link.url?.absoluteString ?? ""))
        }
        if !revision.includedResourceIDs.isEmpty {
            fields.append(
                (
                    "Photos",
                    "\(revision.includedResourceIDs.count) selected"
                )
            )
        }
        return fields
    }

    func loadPreviews() async {
        var loaded: [UUID: Data] = [:]
        for resource in imageResources {
            if let data = try? vault.store.loadResource(
                resource,
                manifest: manifest,
                context: context
            ) {
                loaded[resource.id] = data
            }
            await Task.yield()
        }
        previewData = loaded
    }

    func setTitle(_ value: String) {
        mutate { $0.title = String(value.prefix(180)) }
    }

    func setBody(_ value: String) {
        mutate { $0.body = String(value.prefix(5_000)) }
    }

    func usePrivateTextInBody() {
        setBody(textSources.joined(separator: "\n\n"))
    }

    func setCategory(_ value: LifeCategory) {
        mutate { $0.category = value.rawValue }
    }

    /// Every category the review sheet can show as selected. The opening guess
    /// is constrained to this list, so the sheet can never open on a category
    /// its own picker does not offer.
    static let reviewCategories: [LifeCategory] =
        LifeCategory.builtIn + [.notes, .talk]

    /// Where a share lands before anybody has said otherwise.
    ///
    /// This used to be the constant `.notes` for everything, which meant an
    /// Amazon product page arrived as a note and was then offered a map. A
    /// guess is not a decision: the review sheet still shows the category, the
    /// couple still changes it with one tap, and nothing publishes until they
    /// do that or accept this.
    ///
    /// A link from a shop settles it outright, ahead of the words. A page
    /// titled "Sony WH-1000XM5 Wireless Headphones" contains no word that says
    /// purchase, and the hostname is the more reliable witness than the title
    /// somebody's product page happened to set.
    static func openingGuess(
        for manifest: IncomingShareManifest
    ) -> LifeCategory {
        let hosts = manifest.representations.compactMap { $0.url?.host }
        if hosts.contains(where: { FieldRetailer.from(host: $0) != nil }) {
            return .buys
        }

        let title = manifest.titleSuggestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !title.isEmpty else { return .notes }

        let guess = FieldClassifier.lifeCategory(
            title,
            categories: LifeCategory.builtIn
        )

        // `lifeCategory` can *invent* a category from the subject of a
        // sentence, which is right for something a person typed and wrong for
        // the title tag of a web page — "Bloomberg" would grow a list called
        // Bloomberg out of one shared article. An opening guess also has to be
        // a category the review sheet can show as selected, and that list is
        // exactly `reviewCategories`. Anything else falls back.
        return Self.reviewCategories.contains(guess) ? guess : .notes
    }

    func setURL(_ id: UUID, included: Bool) {
        mutate {
            if included {
                $0.includedURLRepresentationIDs.insert(id)
            } else {
                $0.includedURLRepresentationIDs.remove(id)
            }
        }
    }

    func setImage(_ id: UUID, included: Bool) {
        mutate {
            if included {
                $0.includedResourceIDs.insert(id)
            } else {
                $0.includedResourceIDs.remove(id)
            }
        }
    }

    func publish() async {
        guard canPublish else {
            message = SharePublicationError.invalidReview.localizedDescription
            return
        }
        isPublishing = true
        message = nil

        do {
            let frozen = try freeze()
            let session: SharePublicationSession
            if let existing = record.session {
                session = existing
            } else {
                session = try await backend.createSession(for: frozen)
                record.session = session
                try persistence.save(record, vaultID: manifest.vaultID)
            }

            let approved = Dictionary(
                uniqueKeysWithValues: frozen.resources.map { ($0.id, $0) }
            )
            guard session.id == frozen.id,
                  session.uploads.count == approved.count,
                  Set(session.uploads.map(\.resourceID))
                    == Set(approved.keys),
                  session.uploads.allSatisfy({ descriptor in
                      guard let expected = approved[descriptor.resourceID]
                      else { return false }
                      let pathParts = descriptor.objectPath.split(
                          separator: "/",
                          omittingEmptySubsequences: false
                      )
                      let expectedFilename =
                          descriptor.resourceID.uuidString.lowercased()
                          + (
                              descriptor.contentType == "image/png"
                                  ? ".png"
                                  : ".jpg"
                          )
                      return descriptor.sha256 == expected.sha256
                          && descriptor.contentType == expected.contentType
                          && descriptor.byteCount == expected.byteCount
                          && pathParts.count == 3
                          && pathParts[1]
                              == Substring(frozen.id.uuidString.lowercased())
                          && pathParts[2] == Substring(expectedFilename)
                          && !pathParts.contains("..")
                  })
            else {
                throw SharePublicationError.privateResourceChanged
            }

            for descriptor in session.uploads {
                guard let resource = manifest.resources.first(where: {
                    $0.id == descriptor.resourceID
                }) else {
                    throw SharePublicationError.privateResourceChanged
                }
                let data = try vault.store.loadResource(
                    resource,
                    manifest: manifest,
                    context: context
                )
                try await backend.upload(data, descriptor: descriptor)
            }

            let itemID = try await backend.finalize(sessionID: session.id)
            vault.store.remove(manifest, context: context)
            persistence.remove(
                draftID: manifest.id,
                vaultID: manifest.vaultID
            )
            publishedItemID = itemID
        } catch {
            message = error.localizedDescription
        }
        isPublishing = false
    }

    func discard() async {
        if let sessionID = record.session?.id ?? record.frozen?.id {
            await backend.retire(sessionID: sessionID)
        }
        vault.store.remove(manifest, context: context)
        persistence.remove(
            draftID: manifest.id,
            vaultID: manifest.vaultID
        )
    }

    private func freeze() throws -> FrozenPublicationSnapshot {
        if let frozen = record.frozen { return frozen }

        let title = revision.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty else {
            throw SharePublicationError.invalidReview
        }
        let body = revision.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let approvedURLs: [FrozenPublicationURL] =
            URLSources.compactMap { representation -> FrozenPublicationURL? in
            guard revision.includedURLRepresentationIDs.contains(
                representation.id
            ), let url = representation.url else { return nil }
            return FrozenPublicationURL(id: representation.id, url: url)
        }
        let resources: [FrozenPublicationResource] =
            imageResources.compactMap {
                resource -> FrozenPublicationResource? in
            guard revision.includedResourceIDs.contains(resource.id) else {
                return nil
            }
            return FrozenPublicationResource(
                id: resource.id,
                sha256: resource.sha256,
                contentType: resource.contentType,
                byteCount: resource.byteCount
            )
        }
        let frozen = FrozenPublicationSnapshot(
            draftID: manifest.id,
            revision: revision.revision,
            title: title,
            body: body,
            category: category.rawValue,
            approvedURLs: approvedURLs,
            resources: resources,
            createdAt: Date()
        )
        record.frozen = frozen
        try persistence.save(record, vaultID: manifest.vaultID)
        return frozen
    }

    private func mutate(
        _ update: (inout MutableShareRevision) -> Void
    ) {
        var mutable = MutableShareRevision(revision)
        update(&mutable)

        if record.frozen != nil {
            let oldSession = record.session?.id ?? record.frozen?.id
            mutable.revision += 1
            record.frozen = nil
            record.session = nil
            if let oldSession {
                Task { await backend.retire(sessionID: oldSession) }
            }
        }

        revision = mutable.value(draftID: manifest.id)
        record.revision = revision
        do {
            try persistence.save(record, vaultID: manifest.vaultID)
        } catch {
            message = "WE couldn't protect this edit. Try again."
        }
    }
}

private struct MutableShareRevision {
    var revision: Int
    var title: String
    var body: String
    var category: String
    var includedURLRepresentationIDs: Set<UUID>
    var includedResourceIDs: Set<UUID>

    init(_ value: AppShareRevision) {
        revision = value.revision
        title = value.title
        body = value.body
        category = value.category
        includedURLRepresentationIDs =
            value.includedURLRepresentationIDs
        includedResourceIDs = value.includedResourceIDs
    }

    func value(draftID: UUID) -> AppShareRevision {
        AppShareRevision(
            draftID: draftID,
            revision: revision,
            title: title,
            body: body,
            category: category,
            includedURLRepresentationIDs:
                includedURLRepresentationIDs,
            includedResourceIDs: includedResourceIDs,
            updatedAt: Date()
        )
    }
}

struct ShareInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FieldStore.self) private var store

    @State private var model = ShareInboxModel()
    @State private var selected: IncomingShareManifest?

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("From elsewhere")
                            .font(FieldType.categoryWord)
                            .foregroundStyle(.fieldInk(.headline))

                        Text(
                            "Private drafts from the Share Sheet. Nothing "
                                + "enters your shared LIFE until you release "
                                + "the exact version together."
                        )
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.55, size: 14.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.bottom, 30)

                        content
                    }
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.top, 24)
                    .padding(.bottom, 70)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { model.load() }
        .sheet(item: $selected, onDismiss: model.load) { manifest in
            ShareReviewView(manifest: manifest) {
                await store.retryLoad()
            }
            .environment(store)
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private var header: some View {
        HStack {
            FieldLabel("Private intake")
            Spacer(minLength: 12)
            Button("DONE ✕") { dismiss() }
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.legend))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, FieldMetrics.screenSide)
        .frame(minHeight: 56)
        .background(FieldPalette.bgElevated.opacity(0.98))
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .tint(.fieldInk(.headline))
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityLabel("Opening private drafts")
        } else if let message = model.message {
            FieldReasoning(text: message, accent: store.identity.personA.color)
        } else if model.drafts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                FieldRuleLine()
                Text("Nothing waiting.")
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.headline))
                    .padding(.top, 18)
                Text("Use “Send to WE” from another app to keep something here.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(model.drafts) { draft in
                Button {
                    selected = draft
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRuleLine(color: FieldRule.row)

                        Text(draft.titleSuggestion)
                            .font(FieldType.listItemLarge)
                            .foregroundStyle(.fieldInk(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)

                        HStack {
                            Text(draft.summary.uppercased())
                            Spacer(minLength: 10)
                            Text(
                                draft.createdAt.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                ).uppercased()
                            )
                        }
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.dateCount))
                        .padding(.bottom, 14)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens exact private review")
            }
        }
    }
}

private struct ShareReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FieldStore.self) private var store

    let didPublish: @MainActor () async -> Void

    @State private var model: ShareReviewModel?
    @State private var setupMessage: String?
    @State private var showReleaseConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showFullSource = false

    private let manifest: IncomingShareManifest

    init(
        manifest: IncomingShareManifest,
        didPublish: @escaping @MainActor () async -> Void
    ) {
        self.manifest = manifest
        self.didPublish = didPublish
    }

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            if let model {
                review(model)
            } else if let setupMessage {
                VStack(spacing: 16) {
                    Text("This private draft couldn't be opened.")
                        .font(FieldType.cardTitle)
                        .foregroundStyle(.fieldInk(.headline))
                    Text(setupMessage)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.reasoning))
                    Button("Close") { dismiss() }
                        .buttonStyle(FieldOutlinedButtonStyle())
                }
                .padding(FieldMetrics.screenSide)
            } else {
                ProgressView().tint(.fieldInk(.headline))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard model == nil else { return }
            do {
                let newModel = try ShareReviewModel(manifest: manifest)
                model = newModel
                await newModel.loadPreviews()
            } catch {
                setupMessage = error.localizedDescription
            }
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private func review(_ model: ShareReviewModel) -> some View {
        VStack(spacing: 0) {
            reviewHeader(model)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    privateSource(model)
                    sharedDraft(model)
                    resources(model)
                    exactReview(model)

                    if let message = model.message {
                        FieldReasoning(
                            text: message,
                            accent: store.identity.personA.color
                        )
                    }

                    if model.publishedItemID != nil {
                        FieldReasoning(
                            text: "Released to LIFE. The private draft is gone.",
                            accent: store.identity.personA.color
                        )
                    }
                }
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)

            actionBar(model)
        }
        .confirmationDialog(
            "Release exactly this to \(model.category.label)?",
            isPresented: $showReleaseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Release to \(model.category.label)") {
                Task {
                    await model.publish()
                    if model.publishedItemID != nil {
                        await didPublish()
                    }
                }
            }
            Button("Keep private", role: .cancel) {}
        } message: {
            Text("Only the fields listed under Exact shared version will cross.")
        }
        .confirmationDialog(
            "Discard this private draft?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard draft", role: .destructive) {
                Task {
                    await model.discard()
                    dismiss()
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This removes the private draft and cannot be undone.")
        }
    }

    private func reviewHeader(_ model: ShareReviewModel) -> some View {
        HStack {
            Button("BACK ‹") { dismiss() }
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.legend))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

            Spacer(minLength: 12)

            Button("DISCARD") { showDiscardConfirmation = true }
                .font(FieldType.subLabel)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.recessive))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .disabled(model.isPublishing)
        }
        .padding(.horizontal, FieldMetrics.screenSide)
        .frame(minHeight: 56)
        .background(FieldPalette.bgElevated.opacity(0.98))
    }

    private func privateSource(_ model: ShareReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel("Private source")

            Text("Only you can see this. It is not the shared version.")
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))

            ForEach(Array(model.textSources.enumerated()), id: \.offset) {
                _, source in
                Text(
                    showFullSource
                        ? source
                        : String(source.prefix(700))
                )
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.quietListItem))
                .fixedSize(horizontal: false, vertical: true)
            }

            if model.textSources.contains(where: { $0.count > 700 }) {
                Button(showFullSource ? "Show less" : "Show all private text") {
                    showFullSource.toggle()
                }
                .buttonStyle(FieldQuietButtonStyle())
            }

            if !model.textSources.isEmpty {
                Button("Use this in the shared body") {
                    model.usePrivateTextInBody()
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .accessibilityHint(
                    "Copies the private text into the editable shared body."
                )
            }

            ForEach(manifest.omissions) { omission in
                Text("Left out: \(omission.label) — \(omission.reason)")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sharedDraft(_ model: ShareReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldRuleLine()
            FieldLabel("Shared proposal")

            TextField(
                "Shared title",
                text: Binding(
                    get: { model.revision.title },
                    set: model.setTitle
                ),
                axis: .vertical
            )
            .font(FieldType.cardTitle)
            .foregroundStyle(.fieldInk(.headline))
            .lineLimit(1...4)
            .padding(12)
            .background(
                FieldPalette.ink.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            TextField(
                "Optional shared body",
                text: Binding(
                    get: { model.revision.body },
                    set: model.setBody
                ),
                axis: .vertical
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.headline))
            .lineLimit(3...10)
            .padding(12)
            .background(
                FieldPalette.ink.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            Menu {
                ForEach(reviewCategories) { category in
                    Button(category.word) { model.setCategory(category) }
                }
            } label: {
                HStack {
                    Text("DESTINATION")
                    Spacer()
                    Text(model.category.label)
                }
                .font(FieldType.subLabel)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.legend))
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
        }
    }

    private func resources(_ model: ShareReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.URLSources.isEmpty || !model.imageResources.isEmpty {
                FieldRuleLine()
                FieldLabel("Optional resources")
                Text("Every link and photo begins private.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
            }

            ForEach(model.URLSources) { representation in
                if let url = representation.url {
                    Toggle(
                        isOn: Binding(
                            get: {
                                model.revision
                                    .includedURLRepresentationIDs
                                    .contains(representation.id)
                            },
                            set: {
                                model.setURL(
                                    representation.id,
                                    included: $0
                                )
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.host ?? "Secure link")
                                .font(FieldType.body)
                                .foregroundStyle(.fieldInk(.headline))
                            Text(url.absoluteString)
                                .font(FieldType.reasoning)
                                .foregroundStyle(.fieldInk(.reasoning))
                                .lineLimit(3)
                        }
                    }
                    .tint(store.identity.personA.color)
                }
            }

            ForEach(model.imageResources) { resource in
                Toggle(
                    isOn: Binding(
                        get: {
                            model.revision.includedResourceIDs.contains(
                                resource.id
                            )
                        },
                        set: {
                            model.setImage(resource.id, included: $0)
                        }
                    )
                ) {
                    HStack(spacing: 12) {
                        if let data = model.previewData[resource.id],
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 8,
                                        style: .continuous
                                    )
                                )
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Share this photo")
                                .font(FieldType.body)
                                .foregroundStyle(.fieldInk(.headline))
                            Text(
                                "\(resource.pixelWidth ?? 0) × "
                                    + "\(resource.pixelHeight ?? 0)"
                            )
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.reasoning))
                        }
                    }
                }
                .tint(store.identity.personA.color)
            }
        }
    }

    private func exactReview(_ model: ShareReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            FieldRuleLine()
            FieldLabel("Exact shared version")

            ForEach(
                Array(model.exactSharedFields.enumerated()),
                id: \.offset
            ) { _, field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.0.uppercased())
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.headerMeta))
                    Text(field.1)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.headline))
                        .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(
                Array(model.approvedImageResources.enumerated()),
                id: \.element.id
            ) { index, resource in
                VStack(alignment: .leading, spacing: 7) {
                    Text("PHOTO \(index + 1)")
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.headerMeta))

                    if let data = model.previewData[resource.id],
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                            .accessibilityLabel(
                                "Selected photo \(index + 1)"
                            )
                    }
                }
            }
        }
        .accessibilityIdentifier("share.review.exact")
    }

    @ViewBuilder
    private func actionBar(_ model: ShareReviewModel) -> some View {
        if model.publishedItemID != nil {
            Button("Done") { dismiss() }
                .buttonStyle(FieldFilledButtonStyle())
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.vertical, 12)
        } else if model.isPublishing {
            ProgressView()
                .tint(.fieldInk(.headline))
                .frame(minHeight: 72)
                .accessibilityLabel("Releasing the reviewed version")
        } else {
            Button("Release to LIFE") {
                showReleaseConfirmation = true
            }
            .buttonStyle(FieldFilledButtonStyle())
            .disabled(!model.canPublish)
            .padding(.horizontal, FieldMetrics.screenSide)
            .padding(.vertical, 12)
            .accessibilityHint(
                "Shows a final confirmation before anything is shared."
            )
            .accessibilityIdentifier("share.review.release")
        }
    }

    private var reviewCategories: [LifeCategory] {
        ShareReviewModel.reviewCategories
    }
}
