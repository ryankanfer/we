//
//  FieldAccountView.swift
//  WE
//
//  Account, privacy and response preferences, reached from each main zone.
//

import SwiftUI

@MainActor
struct FieldAccountView: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var walkthrough: WalkthroughPresenter
    @EnvironmentObject private var externalSurfaces: ExternalSurfaceController
    @Environment(\.dismiss) private var dismiss

    /// Shown only where there is a Promise to replay from.
    var onReplayPromise: (() -> Void)? = nil

    @State private var surface: FieldAccountSurface?
    @State private var showsDelete = false
    @State private var showsRecovery = false
    @State private var showsFeedback = false
    @State private var showsPrivacyPolicy = false
    @State private var copiedInvitationCode = false
    @State private var name = ""
    @State private var didSaveName = false
    @State private var selectedArchive: RelationshipArchive?
    @State private var selectedProposal: SavedPrivateProposal?

    var body: some View {
        ZStack {
            WECanvas.cream.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    yourName
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    if canInvitePartner {
                        partnerConnection
                            .padding(.bottom, FieldMetrics.sectionGapLoose)
                    }

                    noticing
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    responseSettings
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    privacy
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    outsideWE
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    if !session.archives.isEmpty || !session.privateProposals.isEmpty {
                        records
                            .padding(.bottom, FieldMetrics.sectionGapLoose)
                    }

                    understanding
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    if WEFeatureFlags.shareInboxEnabled {
                        Button("Needs attention") { showsRecovery = true }
                            .frame(minHeight: 44).padding(.bottom, FieldMetrics.sectionGapLoose)
                    }
                    trouble
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    leaving
                }
                .padding(.top, 20)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.light)
        .foregroundStyle(.fieldInk(.headline))
        .tint(store.identity.personA.color(on: .cream))
        .accessibilityIdentifier("field.account")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                FieldLabel("Account")
                Spacer()
                closeButton
            }
            .padding(.leading, FieldMetrics.screenSide)
            .background(WECanvas.cream.bg)
        }
        .environment(\.weCanvas, WECanvas.cream)
        .fullScreenCover(isPresented: $showsDelete) {
            FieldDeleteAccountView()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showsFeedback) {
            WEFeedbackView(
                accountID: session.user?.id,
                email: session.user?.email
            )
        }
        .fullScreenCover(isPresented: $showsPrivacyPolicy) {
            NavigationStack {
                WEPrivacyPolicyView(showsCloseButton: true)
            }
            .preferredColorScheme(.light)
            .environment(\.weCanvas, WECanvas.cream)
        }
        .sheet(isPresented: $showsRecovery) { WERecoveryCenter().environment(store) }
        .sheet(item: $surface) { selection in
            FieldAccountSurfaceView(surface: selection).environment(store)
        }
        .sheet(item: $selectedArchive) { RelationshipArchiveView(archive: $0) }
        .sheet(item: $selectedProposal) { proposal in
            NavigationStack { SavedPrivateProposalView(proposal: proposal) }
        }
        .onAppear { if name.isEmpty { name = session.snapshot?.profile.name ?? "" } }
        .onChange(of: liveInvitation?.code) { _, _ in
            copiedInvitationCode = false
        }
    }

    private var responseSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
            FieldLabel("How WE responds")
                .padding(.top, 20)
                .padding(.bottom, 18)
            ForEach(FieldAccountSurface.allCases) { selection in
                Button { surface = selection } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selection.rawValue)
                                .font(FieldType.listItem)
                                .foregroundStyle(.fieldInk(.headline))
                            Text(selection.summary)
                                .font(FieldType.body)
                                .foregroundStyle(.fieldInk(.metadataProse))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.fieldInk(.recessive))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("field.account." + selection.accessibilityID)
                FieldRuleLine(color: FieldRule.row)
            }
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .textCase(nil)
                .foregroundStyle(.fieldInk(.recessive))
                .padding(18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.account.done")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Just this person until there is a partner: "Ryan and Your
            // partner" names somebody who does not exist yet.
            Text(
                (session.snapshot?.members.count ?? 2) < 2
                    ? store.identity.name(for: store.speaker)
                    : store.identity.name(for: .shared)
            )
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Partner connection

    private var canInvitePartner: Bool {
        session.snapshot?.canInvitePartner ?? false
    }

    private var liveInvitation: PartnerInvitation? {
        session.snapshot?.couple?.activeInvitation()
    }

    private var partnerConnection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            Text("Invite your partner").font(FieldType.weLifeSection)
                .padding(.top, 20)
                .padding(.bottom, 6)

            if let invitation = liveInvitation {
                liveInvitationContent(invitation)
            } else {
                createInvitationContent
            }
        }
        .accessibilityIdentifier("field.account.invitation")
    }

    private func liveInvitationContent(
        _ invitation: PartnerInvitation
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Share this link or code with your partner. The invitation "
                    + "itself contains no private writing or answers."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)

            Text(invitation.code)
                .font(FieldType.metric)
                .tracking(4)
                .foregroundStyle(.fieldInk(.headline))
                .textSelection(.enabled)
                .accessibilityLabel("Join code \(invitation.code)")

            Text(
                "Works until "
                    + invitation.expiresAt.formatted(
                        .dateTime.month(.wide).day()
                    )
                    + "."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.metadataProse))
            .fixedSize(horizontal: false, vertical: true)

            ShareLink(item: invitation.shareMessage) {
                Text("Share invitation")
            }
            .buttonStyle(FieldFilledButtonStyle())
            .accessibilityIdentifier("field.account.invitation.share")

            Button(copiedInvitationCode ? "Copied" : "Copy code") {
                UIPasteboard.general.string = invitation.code
                copiedInvitationCode = true
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .accessibilityIdentifier("field.account.invitation.copy")

            Text("They’ll open the link, create their own account, and join you here. Your private writing stays yours.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))

            DisclosureGroup("Manage invitation") {
                VStack(alignment: .leading, spacing: 14) {
            Button("Replace this invitation") {
                Task { await session.createInvitation() }
            }
            .buttonStyle(FieldQuietButtonStyle())
            .disabled(session.isWorking || !session.canMutate)
            .accessibilityIdentifier("field.account.invitation.replace")

            Text("Replacing it stops the current link and code immediately.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fixedSize(horizontal: false, vertical: true)

            Button("Withdraw this invitation") {
                Task { await session.revokeInvitation() }
            }
            .buttonStyle(FieldQuietButtonStyle())
            .disabled(session.isWorking || !session.canMutate)
            .accessibilityIdentifier("field.account.invitation.revoke")
                }
                .padding(.top, 14)
            }
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.headline))
        }
    }

    private var createInvitationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "When you are ready, make a private invitation for your "
                    + "partner. It expires after seven days."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)

            Button("Create invitation") {
                Task { await session.createInvitation() }
            }
            .buttonStyle(FieldFilledButtonStyle())
            .disabled(session.isWorking || !session.canMutate)
            .accessibilityIdentifier("field.account.invitation.create")
        }
    }

    // MARK: What the app is allowed to notice

    private var noticing: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel(WEGateCopy.interruptions)
                .padding(.top, 20)
                .padding(.bottom, 6)

            Text(
                "Choose which shared signals WE can notice. Private writing "
                    + "is never used to shape a response."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)

            ForEach(SignalKind.allCases, id: \.self) { signal in
                if signal.isPermanentlyDisabled {
                    Label {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Private writing stays private")
                                .font(FieldType.listItem)
                                .foregroundStyle(.fieldInk(.legend))
                            Text("Never used to shape WE’s responses. Always off.")
                                .font(FieldType.body)
                                .foregroundStyle(.fieldInk(.metadataProse))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "lock")
                            .foregroundStyle(.fieldInk(.metadataProse))
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("field.account.signal.\(signal.rawValue)")
                } else {
                    signalToggle(signal)
                }
            }

            FieldSessionMessage()
        }
    }

    private func signalToggle(_ signal: SignalKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { isEnabled(signal) },
                set: { value in
                    Task { await session.setSignalConsent(signal, enabled: value) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(signal.title)
                    .font(FieldType.listItem)
                    .foregroundStyle(.fieldInk(.legend))

                Text(signal.detail)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.5, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(store.identity.personA.color(on: .cream))
        .disabled(signal.isPermanentlyDisabled || !session.canMutate)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
        .accessibilityIdentifier("field.account.signal.\(signal.rawValue)")
    }

    /// Private reflection can never be enabled, regardless of stored consent.
    private func isEnabled(_ signal: SignalKind) -> Bool {
        guard !signal.isPermanentlyDisabled else { return false }
        return session.v2State.signalConsents.first {
            $0.profileID == session.user?.id && $0.signal == signal
        }?.isEnabled ?? true
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Privacy and data")
                .padding(.top, 20)
                .padding(.bottom, 18)

            Button("Read the privacy policy") {
                showsPrivacyPolicy = true
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .accessibilityIdentifier("field.account.privacyPolicy")

            Text(
                "It names what WE stores, which services process it, how "
                    + "OpenAI is used, and how to delete your account."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.metadataProse))
            .fieldLineHeight(1.5, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
        }
    }

    // MARK: Your name

    private var yourName: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Your name")
                .padding(.top, 20)
                .padding(.bottom, 18)

            HStack(spacing: 12) {
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .font(FieldType.body)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(WECanvas.cream.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: name) { _, _ in didSaveName = false }
                    .accessibilityIdentifier("field.account.name")
                Button(didSaveName ? "Saved" : "Save") {
                    Task {
                        await session.updateProfile(name: name)
                        didSaveName = session.errorMessage == nil
                    }
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || name == session.snapshot?.profile.name
                        || !session.canMutate
                )
            }
        }
    }

    // MARK: Outside WE

    private var outsideWE: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Outside WE")
                .padding(.top, 20)
                .padding(.bottom, 18)

            Toggle(
                "Show approved shared wording",
                isOn: Binding(
                    get: { externalSurfaces.specificWordingOptedIn },
                    set: { externalSurfaces.setSpecificWordingOptIn($0) }
                )
            )
            .font(FieldType.body)
            .frame(minHeight: 44)

            Text(
                "Lock Screen, widgets, StandBy and Live Activities say "
                    + "something generic unless this is on. Answers, names, "
                    + "invitation details and read receipts never appear there."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.metadataProse))
            .fieldLineHeight(1.5, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
    }

    // MARK: What you can look back on

    private var records: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Looking back")
                .padding(.top, 20)
                .padding(.bottom, 10)

            ForEach(session.privateProposals) { proposal in
                Button { selectedProposal = proposal } label: {
                    HStack {
                        Label(proposal.title, systemImage: "lock")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.fieldInk(.reasoning))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Only you can open this")
            }
            ForEach(session.archives) { archive in
                Button { selectedArchive = archive } label: {
                    HStack {
                        Label("Relationship ended", systemImage: "archivebox")
                        Spacer()
                        Text(ArchiveDate.display(archive.endedAt)).foregroundStyle(.fieldInk(.reasoning))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(FieldType.body)
    }

    // MARK: Understanding

    /// The way back to the explanation, months after the one time it played.
    ///
    /// It lives here rather than on a zone because it is not part of using the
    /// app — nobody needs it twice in a week. Dismissing it and then wanting
    /// it back is a real thing that happens, though, and an explanation you
    /// cannot find again may as well not exist.
    private var understanding: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("How it works")
                .padding(.top, 20)
                .padding(.bottom, 18)

            Button("See how WE works") {
                // Dismissed first: this surface is a full-screen cover, and
                // the walkthrough is presented at the scene root above it.
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    walkthrough.replay()
                }
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .accessibilityIdentifier("field.account.walkthrough")
            .padding(.bottom, 14)

            if let onReplayPromise {
                Button(WEGateCopy.replayPromise) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onReplayPromise() }
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .padding(.bottom, 14)
            }

            Text("Try a fictional example: put down a thought, correct its date, and find it in Life. Nothing from the example is saved to your account.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fieldLineHeight(1.5, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: When it breaks

    /// Above Leaving, and deliberately so: a beta tester who cannot make the
    /// app work will find the way out on their own. The way to say *why* is
    /// the thing that has to be easier to reach than the door.
    private var trouble: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Help and feedback")
                .padding(.top, 20)
                .padding(.bottom, 18)

            Button("Send feedback") { showsFeedback = true }
                .buttonStyle(FieldOutlinedButtonStyle())
                .accessibilityIdentifier("field.account.feedback")
                .padding(.bottom, 14)

            Text("You'll see everything that gets sent before it goes. "
                 + "Nothing either of you has written is in it.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fieldLineHeight(1.5, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
            Link("Get support online", destination: WEPrivacyPolicyView.publicURL)
                .font(FieldType.body)
                .frame(minHeight: 44)
                .padding(.top, 14)
                .accessibilityIdentifier("field.account.support")
        }
    }

    // MARK: Leaving

    private var leaving: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Leaving")
                .padding(.top, 20)
                .padding(.bottom, 18)

            Button("Sign out") {
                // The cancel that used to be here is inside `signOut` now,
                // with the rest of the purge contract. It was correct on this
                // one button and missing from the two in `ContentView`, which
                // is the argument for it not living on a button at all.
                Task { await session.signOut() }
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(session.isWorking)
            .accessibilityIdentifier("field.account.signOut")
            .padding(.bottom, 14)

            Button("Delete account") {
                showsDelete = true
            }
            .buttonStyle(FieldQuietButtonStyle())
            .accessibilityIdentifier("field.account.delete")

            FieldSessionMessage()
        }
    }
}

/// Whatever the session last failed at, in the app's own voice. Italic,
/// because the app is speaking rather than labelling.
@MainActor
private struct FieldSessionMessage: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if let message = session.errorMessage {
            Text(message)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }
}

// MARK: - Deletion
//
// Two steps, and neither is decorative. Apple requires account deletion to be
// reachable in-app; the product requires it to be hard to do by accident,
// because it ends a relationship's record and not just a login.

@MainActor
struct FieldDeleteAccountView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmation = ""
    @State private var asksFinalConfirmation = false

    private var canDelete: Bool {
        !password.isEmpty && confirmation == "DELETE" && session.canMutate
    }

    var body: some View {
        ZStack {
            WECanvas.cream.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    warning
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    fields
                        .padding(.bottom, FieldMetrics.sectionGap)

                    actions
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.light)
        .environment(\.weCanvas, WECanvas.cream)
        .accessibilityIdentifier("field.account.delete.screen")
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
            // Not "there is no recovery". Same backup domain, same unproven
            // claim, and this screen was saying the stronger version of it.
            //
            // `YoursCopy.deletionAssurance` carries the reasoning: Supabase
            // keeps its root key outside the database so a restore can bring
            // data back, which is excellent disaster recovery and the exact
            // opposite of what deletion here needs. Until deletion routes
            // through a key WE destroys and can prove it destroyed, this is
            // the strongest true sentence available, and the two surfaces
            // must not disagree about it.
            Text("Unrecoverable within 24 hours.")
        }
        .onChange(of: session.state) { _, state in
            if state == .signedOut { dismiss() }
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Delete account")
                .padding(.bottom, 18)

            Text("This cannot be undone.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            Text(
                "Your private reflections, answers, approaches, and dismissals "
                    + "go with it. They were never in your partner's archive "
                    + "and they will not be left there now."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Delete my account") {
                asksFinalConfirmation = true
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.4)
            .accessibilityIdentifier("field.account.delete.confirm")
            .padding(.bottom, 14)

            Button("Not yet") { dismiss() }
                .buttonStyle(FieldQuietButtonStyle())
                .accessibilityIdentifier("field.account.delete.decline")

            FieldSessionMessage()
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            SecureField("Current password", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("field.account.delete.password")

            TextField("Type DELETE", text: $confirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("field.account.delete.confirmation")
        }
        .font(FieldType.listItem)
        .foregroundStyle(.fieldInk(.headline))
        .textFieldStyle(.plain)
        .padding(16)
        .background(
            FieldPalette.ink.opacity(0.06),
            in: RoundedRectangle(
                cornerRadius: FieldMetrics.cardRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: FieldMetrics.cardRadius,
                style: .continuous
            )
            .stroke(FieldRule.primary, lineWidth: 1)
        }
    }
}
