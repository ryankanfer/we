import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var host: SessionHost
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedArchive: RelationshipArchive?
    @State private var showsDelete = false
    @State private var didSaveName = false
    let onReplayPromise: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            WEMark(
                                style: .compact,
                                showsWordmark: true,
                                personalHue: personalHue,
                                partnerHue: partnerHue,
                                accessibilityText: "You and \(partnerName)"
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You and \(partnerName)")
                                    .font(.weHeadline)
                                    .foregroundStyle(Color("WEInk"))
                                Text("A private account inside a shared space.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color("WEFaint"))
                            }
                        }
                        .accessibilityElement(children: .combine)

                        Divider()
                        Text("Only mutual moments cross the boundary. Your private reflections and unshared choices remain yours.")
                            .font(.subheadline)
                            .foregroundStyle(Color("WEFaint"))
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Private and shared")
                }

                Section("Identity") {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                    Button("Save name") {
                        Task {
                            await session.updateProfile(name: name)
                            didSaveName = session.errorMessage == nil
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.canMutate)
                }

                Section("Shared space") {
                    if session.snapshot?.membership != nil {
                        NavigationLink("Appearance") {
                            HueSettingsView(
                                personalName: session.snapshot?.profile.name ?? "You",
                                partnerName: partnerName
                            )
                        }
                    }
                    Button("Replay the Living Confluence Promise") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onReplayPromise() }
                    }
                    if let code = session.snapshot?.couple?.joinCode {
                        ShareLink(item: "Join me in WE with code \(code)") {
                            Label("Share our join code", systemImage: "square.and.arrow.up")
                        }
                    }
                    NavigationLink("How WE notices") {
                        SignalConsentView()
                    }
                    if host.canUseSimulation {
                        NavigationLink("Mode") {
                            ModeSettingsView()
                        }
                    }
                }

                if !session.archives.isEmpty {
                    Section("Shared history") {
                        ForEach(session.archives) { archive in
                            Button {
                                selectedArchive = archive
                            } label: {
                                HStack {
                                    Label("Relationship ended", systemImage: "archivebox")
                                    Spacer()
                                    Text(ArchiveDate.display(archive.endedAt))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Sign out") { Task { await session.signOut(); dismiss() } }
                        .disabled(session.isWorking)
                    Button("Delete account…", role: .destructive) { showsDelete = true }
                        .disabled(session.connectionState != .online || session.isWorking)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Deleting your account ends the live relationship. Your partner keeps only a sanitized read-only archive of shared plans, responsibilities, and completed mutual resolutions.")
                }

                SessionMessageView()
            }
            .scrollContentBackground(.hidden)
            .background(WarmEditorialBackground())
            .tint(Color("WEBurgundy"))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { name = session.snapshot?.profile.name ?? "" }
            .sensoryFeedback(.success, trigger: didSaveName)
            .sheet(item: $selectedArchive) { RelationshipArchiveView(archive: $0) }
            .sheet(isPresented: $showsDelete) { DeleteAccountView() }
        }
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return .partnerDefault
        }
        return WEHue(partner.hue)
    }

    private var partnerName: String {
        guard let user = session.user else { return "your partner" }
        return session.snapshot?.members.first { $0.id != user.id }?.name ?? "your partner"
    }
}

private struct DeleteAccountView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var asksFinalConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Your private reflections, unrevealed responses, pending requests, and dismissals will be deleted. They are never placed in your partner’s archive.")
                }
                Section("Confirm your identity") {
                    SecureField("Current password", text: $password)
                        .textContentType(
                            disablesCredentialPrompts
                                ? .oneTimeCode
                                : .password
                        )
                    TextField("Type DELETE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                SessionMessageView()
                Section {
                    Button("Delete my account", role: .destructive) { asksFinalConfirmation = true }
                        .disabled(password.isEmpty || confirmation != "DELETE" || !session.canMutate)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog(
                "Delete your account and end this relationship?",
                isPresented: $asksFinalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete permanently", role: .destructive) {
                    Task { await session.deleteAccount(password: password) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("There is no recovery for your account or private data.")
            }
            .onChange(of: session.state) { _, state in
                if state == .signedOut { dismiss() }
            }
        }
    }

    private var disablesCredentialPrompts: Bool {
        ProcessInfo.processInfo.environment[
            "WE_DISABLE_CREDENTIAL_PROMPTS"
        ] == "1"
    }
}

struct RelationshipArchiveView: View {
    let archive: RelationshipArchive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Read-only", systemImage: "lock.fill")
                    Text("This archive contains only things that were genuinely shared. Private and unrevealed material was excluded.")
                        .foregroundStyle(.secondary)
                }
                if !archive.snapshot.plans.isEmpty {
                    Section("Plans") {
                        ForEach(archive.snapshot.plans) { item in
                            ArchiveRow(title: item.title, detail: item.note)
                        }
                    }
                }
                if !archive.snapshot.responsibilities.isEmpty {
                    Section("Responsibilities") {
                        ForEach(archive.snapshot.responsibilities) { item in
                            ArchiveRow(title: item.title, detail: item.ownership.title)
                        }
                    }
                }
                if !archive.snapshot.resolutions.isEmpty {
                    Section("Mutual resolutions") {
                        ForEach(archive.snapshot.resolutions) { item in
                            ArchiveRow(title: item.title, detail: item.resolutionChoice ?? item.resolutionType.label)
                        }
                    }
                }
                if !archive.snapshot.anchors.isEmpty {
                    Section("Anchors") {
                        ForEach(archive.snapshot.anchors) { anchor in
                            ArchiveRow(
                                title: anchor.title,
                                detail: anchor.note
                            )
                        }
                    }
                }
                if !archive.snapshot.events.isEmpty {
                    Section("Thread") {
                        ForEach(archive.snapshot.events) { event in
                            ArchiveRow(
                                title: event.title,
                                detail: event.type.title
                            )
                        }
                    }
                }
                if !archive.snapshot.seasons.isEmpty {
                    Section("Seasons") {
                        ForEach(archive.snapshot.seasons) { season in
                            ArchiveRow(
                                title: season.title,
                                detail: season.summary
                            )
                        }
                    }
                }
                if !archive.snapshot.handoffs.isEmpty {
                    Section("Handoffs") {
                        ForEach(archive.snapshot.handoffs) { handoff in
                            ArchiveRow(
                                title: responsibilityTitle(
                                    handoff.responsibilityID
                                ),
                                detail: handoff.status.rawValue.capitalized
                            )
                        }
                    }
                }
                if !archive.snapshot.approaches.isEmpty {
                    Section("Opened approaches") {
                        ForEach(archive.snapshot.approaches) { approach in
                            ArchiveRow(
                                title: planTitle(approach.planID),
                                detail: approach.approach.title
                            )
                        }
                    }
                }
                if isEmpty {
                    ContentUnavailableView("Nothing was archived", systemImage: "archivebox", description: Text("There were no completed shared records to retain."))
                }
            }
            .navigationTitle("Relationship archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var isEmpty: Bool {
        archive.snapshot.plans.isEmpty
            && archive.snapshot.responsibilities.isEmpty
            && archive.snapshot.resolutions.isEmpty
            && archive.snapshot.anchors.isEmpty
            && archive.snapshot.events.isEmpty
            && archive.snapshot.seasons.isEmpty
            && archive.snapshot.handoffs.isEmpty
            && archive.snapshot.approaches.isEmpty
    }

    private func responsibilityTitle(_ id: String) -> String {
        archive.snapshot.responsibilities.first {
            $0.id == id
        }?.title ?? "Shared care"
    }

    private func planTitle(_ id: String) -> String {
        archive.snapshot.plans.first {
            $0.id == id
        }?.title ?? "Shared plan"
    }
}

private struct ArchiveRow: View {
    let title: String
    let detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let detail, !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

private enum ArchiveDate {
    static func display(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "Past" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension ResolutionType {
    var label: String {
        switch self { case .settled: "Settled"; case .released: "Released"; case .leftOpen: "Left open" }
    }
}

#Preview {
    ProfileView(onReplayPromise: {})
        .environmentObject(AppSession(repository: PreviewRepository()))
        .environmentObject(
            SessionHost(
                environment: AppEnvironment(
                    repositoryMode: .preview,
                    supabase: nil,
                    previewScenario: .ready,
                    previewDeletionPassword: nil
                )
            )
        )
}
