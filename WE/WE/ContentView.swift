import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @EnvironmentObject private var externalSurfaces:
        ExternalSurfaceController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProfile = false
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
            // No bar along the bottom before pairing. It offered "Save · Only
            // me" and "Your saved items" in system chrome on every gate screen
            // — a second way in, before there is a Life to save into. Things
            // shared from elsewhere wait in Life once there is one.
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
                        // DM Sans, like every other label the app puts in a
                        // corner. The filled SF Symbol was the last piece of
                        // iOS chrome on a pre-zone screen.
                        Text("ACCOUNT")
                            .font(FieldType.button)
                            .tracking(FieldTracking.button)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WECanvas.cream.ink)
                    .accessibilityLabel("Open Profile")
                    .accessibilityHint("Account, archives, and privacy")
                    .accessibilityIdentifier("accountButton")
                }
                .padding(.horizontal, FieldMetrics.screenSide)
            }
        }
        // The same Account the app shows once you are paired, before pairing
        // too. Its store holds only the two names; nothing is loaded or
        // written through it here.
        .fullScreenCover(isPresented: $showsProfile) {
            FieldAccountView(onReplayPromise: onReplayPromise)
                .environment(
                    FieldStore(
                        state: session.snapshot?.emptyFieldState
                            ?? .empty(nameA: "You", nameB: "Your partner", now: Date())
                    )
                )
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

private struct PairingView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @State private var joinCode = ""
    @State private var showsJoinCode = false
    @FocusState private var codeFocused: Bool

    /// Two cards, one each way in. Past relationships and Sign out used to
    /// sit under them; both live in Account (top right), where every other
    /// setting is, so this screen asks one question.
    var body: some View {
        FirstRunScreen(
            title: "Your account is ready.",
            subtitle: "Now the person you're making this with.",
            content: {
                VStack(alignment: .leading, spacing: 14) {
                    whatIsHeld

                    FirstRunChoiceCard(
                        symbol: "paperplane",
                        title: "Invite them",
                        detail: "WE makes a code. Send it any way you like.",
                        isWorking: session.isWorking && !showsJoinCode
                    ) {
                        Task { await createSharedSpace() }
                    }
                    .disabled(session.isWorking)
                    .accessibilityLabel("Invite my partner")
                    .accessibilityIdentifier("pairing.createInvitation")

                    FirstRunChoiceCard(
                        symbol: "key",
                        title: "I have their code",
                        detail: "They invited you. Join them."
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) { showsJoinCode.toggle() }
                        codeFocused = showsJoinCode
                    }
                    .accessibilityIdentifier("pairing.showJoinCode")

                    if showsJoinCode {
                        joinCodeEntry
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    SessionMessageView()
                }
            },
            actions: {
                Text("Anything you mark Only me stays yours, even after you pair.")
                    .font(.footnote)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        )
        .onAppear {
            // Reaching this screen with a code still held means redemption
            // failed — a bad code, or offline. Put it back in the field rather
            // than making them find the invitation again.
            if joinCode.isEmpty, let held = pendingInvitation.code {
                joinCode = held
                showsJoinCode = true
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
            FirstRunCard {
                VStack(alignment: .leading, spacing: 11) {
                    Text(saved.title)
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                    FieldReasoning(
                        text: session.privateProposals.count > 1
                            ? "\(session.privateProposals.count) of these, "
                                + "only you can see them. This screen does not "
                                + "load your original notes."
                            : "Protected by your account. This screen does not "
                                + "load your original note.",
                        accent: FieldIdentity.seed.personA.color
                    )
                }
            }
        }
    }

    private var joinCodeEntry: some View {
        FirstRunCard {
            VStack(alignment: .leading, spacing: 16) {
                FieldTextField(
                    label: "The code they sent you",
                    text: $joinCode,
                    autocapitalization: .characters,
                    identifier: "pairing.joinCode"
                )
                .focused($codeFocused)
                // Through `PendingInvitation.normalized` rather than inline:
                // a typed code and a tapped link have to agree.
                .onChange(of: joinCode) { _, value in
                    joinCode = PendingInvitation.normalized(value) ?? ""
                }

                Button("Join") { Task { await joinSharedSpace() } }
                    .buttonStyle(FirstRunPrimaryButtonStyle())
                    .disabled(session.isWorking || joinCode.isEmpty)
                    .accessibilityIdentifier("pairing.join")
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
    @State private var copied = false
    @State private var confirmsWithdrawal = false

    /// Who the invitation is for, in their own name.
    ///
    /// The app never says "your partner" once it has been told, which is why
    /// it asks here rather than waiting for them to arrive: the stillness is
    /// the screen most in need of the name, and it is shown before there is
    /// anybody to ask.
    ///
    /// Kept on this device rather than sent. Naming someone who has not
    /// arrived is a fact about the person doing the inviting, and putting it
    /// on a server before the named person exists would be storing their name
    /// somewhere they never agreed to. It travels no further than this phone.
    @AppStorage("we.invitee.name") private var inviteeName = ""

    /// The name, or nothing. `WEGateCopy` writes the unnamed sentences out in
    /// full rather than assembling them around a placeholder, so what it wants
    /// is the absence rather than a stand in word.
    private var invitee: String? {
        let trimmed = inviteeName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var code: String { session.snapshot?.couple?.joinCode ?? "" }

    private var couple: Couple? { session.snapshot?.couple }

    /// `joinCode` is never nil — the column behind it is `not null` — so the
    /// code alone cannot say whether there is anything live to send. The
    /// expiry is the field that can.
    private var isLive: Bool { couple?.hasLiveInvitation() ?? false }

    var body: some View {
        invitationScreen
    }

    private var closedTitle: String { WEGateCopy.invitationClosedTitle }
    private var closedDetail: String { WEGateCopy.invitationClosedDetail }

    /// Who it is for, the code on a card you could read across a table, and
    /// Share where the thumb is. Copying, a fresh code and withdrawing are
    /// the rare cases; they sit under the card as quiet links.
    private var invitationScreen: some View {
        FirstRunScreen(
            title: isLive ? WEGateCopy.invitationTitle(for: invitee) : closedTitle,
            subtitle: isLive ? WEGateCopy.invitationDetail(for: invitee) : closedDetail,
            content: {
                VStack(alignment: .leading, spacing: 18) {
                    if isLive {
                        FieldTextField(
                            label: WEGateCopy.inviteeNameField,
                            text: $inviteeName,
                            identifier: "waiting.inviteeName"
                        )
                    }

                    codeCard

                    if isLive {
                        HStack(spacing: 18) {
                            copyInvitationButton
                            Spacer(minLength: 0)
                            withdrawal
                        }
                        .sensoryFeedback(.success, trigger: copied)

                        Text("They open it, make their own account, and join you. Nothing is sent until you share it.")
                            .font(.footnote)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SessionMessageView()
                }
            },
            actions: { invitationActions }
        )
    }

    /// Struck through rather than hidden when it is not live: somebody who
    /// sent this an hour ago needs to recognise the string before they can
    /// understand it stopped working.
    private var codeCard: some View {
        FirstRunCard(padding: 24) {
            VStack(spacing: 10) {
                Text(code)
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .tracking(8)
                    .foregroundStyle(.fieldInk(isLive ? .headline : .recessive))
                    .strikethrough(!isLive)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .accessibilityLabel(isLive ? "Join code \(code)" : "Join code \(code), no longer valid")
                window
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// How long the offer stands.
    ///
    /// Stated as a date rather than a countdown. A ticking clock on a screen
    /// about inviting your partner is pressure, and the seven days are there
    /// to stop a code living forever — not to hurry anybody.
    @ViewBuilder
    private var window: some View {
        if let expires = couple?.invitationExpiresAt, isLive {
            Text("Works until \(expires.formatted(.dateTime.month(.wide).day()))")
                .font(.footnote)
                .foregroundStyle(.fieldInk(.reasoning))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("waiting.window")
        }
    }

    @ViewBuilder
    private var invitationActions: some View {
        if isLive {
            sendInvitationButton
        } else {
            Button {
                Task { await session.createInvitation() }
            } label: {
                if session.isWorking {
                    ProgressView().tint(WECanvas.cream.bg)
                } else {
                    Text("Make a new invitation")
                }
            }
            .buttonStyle(FirstRunPrimaryButtonStyle())
            .disabled(session.isWorking)
            .accessibilityIdentifier("waiting.regenerate")
        }
    }

    /// Withdrawing is the answer to "I sent that to the wrong person", and it
    /// has to be reachable at the moment somebody realises it — so it sits on
    /// this screen rather than behind Account.
    @ViewBuilder
    private var withdrawal: some View {
        Button("Withdraw") { confirmsWithdrawal = true }
            .buttonStyle(FirstRunLinkStyle())
            .disabled(session.isWorking)
            .accessibilityLabel("Withdraw this invitation")
            .accessibilityIdentifier("waiting.revoke")
            .confirmationDialog(
                "Withdraw this invitation?",
                isPresented: $confirmsWithdrawal,
                titleVisibility: .visible
            ) {
                Button("Withdraw", role: .destructive) {
                    Task { await session.revokeInvitation() }
                }
            } message: {
                Text("The code stops working straight away, for everyone.")
            }
    }

    // The Field button styles uppercase, so each of these carries its sentence
    // back as an accessibility label — VoiceOver should not be shouting.

    private var sendInvitationButton: some View {
        ShareLink(item: invitationShareMessage) {
            Label("Share invitation", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(FirstRunPrimaryButtonStyle())
        .accessibilityLabel("Share invitation")
        .accessibilityIdentifier("waiting.share")

    }

    private var invitationShareMessage: String {
        couple?.activeInvitation()?.shareMessage
            ?? "Join me in WE with code \(code)"
    }

    private var copyInvitationButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
        } label: {
            Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(FirstRunLinkStyle())
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
