import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @EnvironmentObject private var externalSurfaces:
        ExternalSurfaceController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProfile = false
    @State private var showsPartnerArrival = false
    var onReplayPromise: () -> Void = {}

    var body: some View {
        ZStack {
            Group {
                switch session.state {
                case .loading:
                    loadingView
                case .unconfigured:
                    BackendStateView(
                        title: "Connect WE to Supabase.",
                        message: "Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY to the WE scheme, or set WE_REPOSITORY to preview."
                    )
                case .signedOut:
                    signedOutView
                case .verificationPending(let email):
                    VerificationPendingView(email: email)
                case .resettingPassword:
                    NewPasswordView()
                case .needsCouple:
                    PairingView()
                case .waitingForPartner:
                    PartnerWaitingView()
                case .choosingHue:
                    hueOnboarding
                case .ready:
                    // Unreachable: `WEApp` hands `.ready` to `FieldRoot`
                    // before ContentView is ever built. The zones are the
                    // app; what is left here is only what comes before a
                    // couple exists. Held rather than empty, so a state
                    // change racing the handover never flashes.
                    loadingView
                case .failed(let message):
                    BackendStateView(
                        title: "WE could not load.",
                        message: message,
                        retry: { Task { await session.retry() } },
                        signOut: { Task { await session.signOut() } }
                    )
                }
            }
            .accessibilityHidden(showsPartnerArrival)
            .allowsHitTesting(!showsPartnerArrival)

            if showsPartnerArrival {
                PartnerArrivalCeremony {
                    showsPartnerArrival = false
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(
            .weSettle(duration: 0.35, reduceMotion: reduceMotion),
            value: session.state
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsAuthenticatedProfileButton {
                HStack {
                    Spacer()
                    Button {
                        showsProfile = true
                    } label: {
                        // Mono, like every other label the app puts in a
                        // corner. The filled SF Symbol was the last piece of
                        // iOS chrome on a pre-zone screen.
                        Text("ACCOUNT")
                            .font(FieldType.button)
                            .tracking(FieldTracking.button)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityLabel("Open Profile")
                    .accessibilityHint("Account, archives, and privacy")
                    .accessibilityIdentifier("accountButton")
                }
                .padding(.horizontal, FieldMetrics.screenSide)
            }
        }
        .sheet(isPresented: $showsProfile) {
            ProfileView(onReplayPromise: onReplayPromise)
        }
        .onChange(of: session.state) { oldState, newState in
            if oldState == .waitingForPartner, newState == .ready {
                showsPartnerArrival = true
            }
        }
        .task(id: externalSurfaceSyncKey) {
            await syncExternalSurfaces()
        }
        .task(id: pendingInvitationKey) {
            await redeemPendingInvitationIfNeeded()
        }
    }

    private var showsAuthenticatedProfileButton: Bool {
        switch session.state {
        // `.choosingHue` is 6f, which is full-bleed and drawn in the zones'
        // language. The old light chrome sat on top of it as a band across
        // the header, and there is nothing behind this button that onboarding
        // needs — the account lives on the WE mark once the zones open.
        case .needsCouple, .waitingForPartner:
            true
        default:
            false
        }
    }

    private var externalSurfaceSyncKey: String {
        let sync = session.snapshot?.syncedAt.timeIntervalSince1970 ?? 0
        return "\(session.user?.id ?? "signed-out"):\(sync):\(session.state)"
    }

    private var pendingInvitationKey: String {
        let code = pendingInvitation.code ?? "none"
        let coupleID = session.snapshot?.membership?.coupleID ?? "solo"
        return "\(session.user?.id ?? "signed-out"):\(code):\(coupleID):\(session.state)"
    }

    /// A code collected on the welcome screen is spent here, at the first
    /// moment there is a session to spend it on.
    ///
    /// Only at `.needsCouple`. Earlier there is no account; later there is
    /// already a shared space, and silently moving someone out of one and into
    /// another on the strength of an old held code would be the worst thing
    /// this function could do. A failure leaves the code held on purpose —
    /// `PairingView` shows it back in an editable field with the error.
    private func redeemPendingInvitationIfNeeded() async {
        guard session.state == .needsCouple,
              let code = pendingInvitation.code else {
            return
        }
        await session.joinCouple(code: code)
        if session.errorMessage == nil {
            pendingInvitation.clear()
        }
    }

    private func syncExternalSurfaces() async {
        if session.state == .signedOut {
            externalSurfaces.clear()
            return
        }
        guard session.state == .ready,
              let snapshot = session.snapshot else {
            return
        }

        if let direction = snapshot.insights
            .first(where: {
                $0.sharedDirection != nil
                    && $0.consent?.resolutionType == nil
            })?
            .sharedDirection
        {
            let wording = ExplicitlyPermittedSharedWording(
                sharedDirection: direction
            )
            _ = try? await externalSurfaces
                .publishAndEnsureLiveActivity(
                    state: .roomAvailable,
                    expiresAt: Date().addingTimeInterval(2 * 60 * 60),
                    approvedSharedWording: wording
                )
            return
        }

        if snapshot.insights.contains(where: {
            $0.consent?.resolutionType != nil
        }) {
            externalSurfaces.publish(
                state: .resolved,
                expiresAt: Date().addingTimeInterval(60 * 60)
            )
        } else {
            externalSurfaces.publish(
                state: .quiet,
                expiresAt: Date().addingTimeInterval(60 * 60)
            )
        }
    }

    private var signedOutView: some View {
        WelcomeView()
    }

    /// The mark is the wait state, and there is no spinner — the same decision
    /// `WESplashView` makes, and the reason the handover from the collapse to
    /// this screen is invisible.
    private var loadingView: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()
            FieldIntelligenceMark(
                identity: .seed,
                diameter: 22,
                ringDiameter: 70
            )
        }
        .preferredColorScheme(.dark)
        .accessibilityElement()
        .accessibilityLabel("Loading your WE space")
    }

    /// 6f. The last screen before the zones, and the first one drawn in their
    /// language — colour, three questions, and a calendar.
    ///
    /// `FieldSwatch` supersedes `MemberHue` in the UI, but `couple_members.hue`
    /// is still a database column, so finishing writes both: the swatch through
    /// `FieldStore`, and the nearest legacy hue through the session. See
    /// CUTOVER.md — that column goes when something migrates it.
    private var hueOnboarding: some View {
        FieldOnboardingRoot { swatch in
            Task { await session.updateHue(swatch.memberHue) }
        }
    }

    private var partnerName: String {
        guard let snapshot = session.snapshot,
              let user = session.user else { return "your partner" }
        return snapshot.members.first { $0.id != user.id }?.name ?? "your partner"
    }

    private var partnerHue: WEHue {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(
                where: { $0.id != user.id }
              ) else {
            return .partnerDefault
        }
        return WEHue(partner.hue)
    }
}

private struct PartnerArrivalCeremony: View {
    @EnvironmentObject private var session: AppSession
    let onComplete: () -> Void

    var body: some View {
        FieldGateScaffold(label: "Ours") {
            VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
                // The blend, once, on the one screen that is literally about
                // two people becoming reachable to each other. This is exactly
                // what the handoff reserves it for.
                Rectangle()
                    .fill(FieldIdentity.seed.blend())
                    .frame(height: 1)
                    .accessibilityLabel(
                        "Two private sides with a shared clearing between them"
                    )

                FieldGateHeadline(
                    title: "A shared space opened.",
                    subtitle: "You and \(session.partnerName) remain "
                        + "yourselves. What you both choose can now have a "
                        + "place between you."
                )

                Button("Begin together", action: onComplete)
                    .buttonStyle(FieldFilledButtonStyle())
                    .accessibilityIdentifier("arrival.begin")
            }
        }
    }
}

private struct PairingView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @State private var joinCode = ""
    @State private var selectedArchive: RelationshipArchive?

    var body: some View {
        FieldGateScaffold(label: "Your side", centred: false) {
            VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
                FieldGateHeadline(
                    title: "Your side is ready.",
                    subtitle: "You can keep what you began here. Invite your "
                        + "partner only when a shared space would be useful."
                )

                whatIsHeld

                invitation

                joinCodeEntry

                SessionMessageView()

                archives

                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(FieldQuietButtonStyle())
            }
        }
        .sheet(item: $selectedArchive) { RelationshipArchiveView(archive: $0) }
        .onAppear {
            // Reaching this screen with a code still held means redemption
            // failed — a bad code, or offline. Put it back in the field rather
            // than making them find the invitation again.
            if joinCode.isEmpty, let held = pendingInvitation.code {
                joinCode = held
            }
        }
    }

    /// What this account is already holding, if anything.
    ///
    /// This used to have three branches, two of which described artifacts of
    /// the pre-account funnel that no longer exists. What is left reads the
    /// server: proposals claimed before the funnel was retired are still real,
    /// still owned, and still worth naming on the screen where someone decides
    /// whether to open a shared space.
    @ViewBuilder
    private var whatIsHeld: some View {
        if let saved = session.privateProposals.first {
            FieldCard(accent: FieldIdentity.seed.personA.color) {
                VStack(alignment: .leading, spacing: 11) {
                    FieldLabel("Saved on your side")
                    Text(saved.title)
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                    FieldReasoning(
                        text: session.privateProposals.count > 1
                            ? "\(session.privateProposals.count) are kept on "
                                + "your side. This screen does not load your "
                                + "original notes."
                            : "Protected by your account. This screen does not "
                                + "load your original note.",
                        accent: FieldIdentity.seed.personA.color
                    )
                }
            }
        }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldRuleLine()

            FieldLabel("When you are ready")
                .padding(.top, 4)

            Text(
                "Create an invitation. Your note and private proposal do not "
                    + "travel with it."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await createSharedSpace() }
            } label: {
                if session.isWorking {
                    ProgressView().tint(FieldPalette.bg)
                } else {
                    Text("Create an invitation")
                }
            }
            .buttonStyle(FieldFilledButtonStyle())
            .disabled(session.isWorking)
            .accessibilityLabel("Create an invitation")
            .accessibilityIdentifier("pairing.createInvitation")
        }
    }

    private var joinCodeEntry: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldTextField(
                label: "Have a join code?",
                text: $joinCode,
                autocapitalization: .characters,
                identifier: "pairing.joinCode"
            )
            .onChange(of: joinCode) { _, value in
                joinCode = String(
                    value.uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                        .prefix(16)
                )
            }

            Button("Join") { Task { await joinSharedSpace() } }
                .buttonStyle(FieldOutlinedButtonStyle())
                .disabled(session.isWorking || joinCode.isEmpty)
        }
    }

    @ViewBuilder
    private var archives: some View {
        if !session.archives.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                FieldRuleLine()

                FieldLabel("Past relationships")
                    .padding(.top, 4)

                ForEach(session.archives) { archive in
                    Button {
                        selectedArchive = archive
                    } label: {
                        Text("View read-only archive")
                            .font(FieldType.listItem)
                            .foregroundStyle(.fieldInk(.quietListItem))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 44,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func createSharedSpace() async {
        await session.createCouple()
        if session.errorMessage == nil {
            // Choosing to start a space instead of joining one settles the
            // question the held code was waiting on.
            pendingInvitation.clear()
        }
    }

    private func joinSharedSpace() async {
        await session.joinCouple(code: joinCode)
        if session.errorMessage == nil {
            pendingInvitation.clear()
        }
    }
}

private struct PartnerWaitingView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copied = false

    private var code: String { session.snapshot?.couple?.joinCode ?? "" }

    var body: some View {
        FieldGateScaffold(label: "Invitation ready") {
            VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
                FieldGateHeadline(
                    title: "The invitation is at\nthe threshold.",
                    subtitle: "Send the code when you are ready. It contains "
                        + "no note, proposal, answer, or private context."
                )

                // The code itself, in the app's mono at a size you can read
                // across a table. Selectable, because somebody will want to
                // copy it by hand rather than share it.
                VStack(alignment: .leading, spacing: 14) {
                    FieldRuleLine()

                    Text(code)
                        .font(FieldType.metric)
                        .tracking(4)
                        .foregroundStyle(.fieldInk(.headline))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .textSelection(.enabled)
                        .accessibilityLabel("Join code \(code)")

                    FieldRuleLine()
                }

                FieldReasoning(
                    text: "What crosses is an invitation to create a WE space. "
                        + "Nothing else.",
                    accent: FieldIdentity.seed.personB.color
                )

                invitationActions
                    .sensoryFeedback(.success, trigger: copied)

                Text("WE will stay still until they choose.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fixedSize(horizontal: false, vertical: true)

                SessionMessageView()

                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(FieldQuietButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var invitationActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                sendInvitationButton
                copyInvitationButton
            }
        } else {
            HStack(spacing: 12) {
                sendInvitationButton
                copyInvitationButton
            }
        }
    }

    // The Field button styles uppercase, so each of these carries its sentence
    // back as an accessibility label — VoiceOver should not be shouting.

    private var sendInvitationButton: some View {
        ShareLink(item: "Join me in WE with code \(code)") {
            Text("Send the invitation")
        }
        .buttonStyle(FieldFilledButtonStyle())
        .accessibilityLabel("Send the invitation")
        .accessibilityIdentifier("waiting.share")
    }

    private var copyInvitationButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
        } label: {
            Text(copied ? "Copied" : "Copy")
        }
        .buttonStyle(FieldOutlinedButtonStyle())
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .accessibilityIdentifier("waiting.copy")
    }
}

private struct VerificationPendingView: View {
    @EnvironmentObject private var session: AppSession
    let email: String

    var body: some View {
        BackendStateView(
            title: "Check your email.",
            message: "We sent a verification link to \(email). Open it, then return here to sign in.",
            retry: { session.returnToSignIn(message: "After verifying, sign in below.") }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSession(repository: PreviewRepository()))
        .environmentObject(PendingInvitation())
        .environmentObject(ExternalSurfaceController())
        .environmentObject(WalkthroughPresenter())
}
