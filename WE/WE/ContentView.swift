import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var softStart: SoftStartCoordinator
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
                    AppShell(onReplayPromise: onReplayPromise)
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
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color("WEInk"))
                    .accessibilityLabel("Open Profile")
                    .accessibilityHint("Account, archives, and privacy")
                    .accessibilityIdentifier("accountButton")
                }
                .padding(.horizontal, 16)
                .background(Color("WEBackground"))
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
        .task(id: softStartClaimKey) {
            await claimSoftStartIfNeeded()
        }
    }

    private var showsAuthenticatedProfileButton: Bool {
        switch session.state {
        case .needsCouple, .waitingForPartner, .choosingHue:
            true
        default:
            false
        }
    }

    private var externalSurfaceSyncKey: String {
        let sync = session.snapshot?.syncedAt.timeIntervalSince1970 ?? 0
        return "\(session.user?.id ?? "signed-out"):\(sync):\(session.state)"
    }

    private var softStartClaimKey: String {
        let proposalID = softStart.pendingClaim?.proposal.id.uuidString
            ?? "none"
        let offerID = softStart.pendingOfferProposalID ?? "none"
        let coupleID = session.snapshot?.membership?.coupleID ?? "solo"
        return "\(session.user?.id ?? "signed-out"):\(proposalID):\(offerID):\(coupleID)"
    }

    private func claimSoftStartIfNeeded() async {
        guard session.user != nil else { return }

        if let pendingOfferID = softStart.pendingOfferProposalID,
           session.snapshot?.membership != nil {
            if await session.offerPrivateProposal(id: pendingOfferID) {
                _ = softStart.markOfferPublished()
            }
            return
        }

        guard
              let claim = softStart.pendingClaim,
              let serverID = await session.claimPrivateProposal(
                  claim.proposal
              ) else {
            return
        }
        let marked = softStart.markClaimed(
            serverID: serverID,
            intent: claim.intent
        )
        if marked,
           claim.intent == .offerApprovedTopic,
           session.snapshot?.membership != nil,
           await session.offerPrivateProposal(id: serverID) {
            _ = softStart.markOfferPublished()
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

    @ViewBuilder
    private var signedOutView: some View {
        if ProcessInfo.processInfo.environment["WE_SKIP_SOFT_START"] == "1" {
            SignInView()
        } else {
            SoftStartView()
        }
    }

    private var loadingView: some View {
        ZStack {
            Color("WEBackground").ignoresSafeArea()
            VStack(spacing: 16) {
                WEMark(style: .compact)
                ProgressView()
                    .accessibilityLabel("Loading your WE space")
            }
        }
    }

    private var hueOnboarding: some View {
        HueOnboardingView(
            personalName: session.snapshot?.profile.name ?? "You",
            partnerName: partnerName,
            partnerHue: partnerHue,
            isWorking: session.isWorking,
            errorMessage: session.errorMessage
        ) { hue in
            Task { await session.updateHue(hue.memberHue) }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            WEJourneyBackdrop(state: .shared)

            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 18) {
                        Spacer(minLength: 12)

                        WEContinuityLine(state: .shared)
                            .frame(
                                height: dynamicTypeSize.isAccessibilitySize
                                    ? 112
                                    : 180
                            )
                            .accessibilityLabel(
                                "Two private sides with a shared clearing between them"
                            )

                        Text("OURS")
                            .font(.weCaption)
                            .tracking(1.8)
                            .foregroundStyle(
                                Color.weCharcoal.opacity(0.76)
                            )
                        Text("A shared space opened.")
                            .font(.weLargeTitle)
                            .foregroundStyle(Color.weCharcoal)
                            .multilineTextAlignment(.center)
                        Text("You and \(session.partnerName) remain yourselves. What you both choose can now have a place between you.")
                            .font(.weBody)
                            .foregroundStyle(
                                Color.weCharcoal.opacity(0.76)
                            )
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)

                        Spacer(minLength: 12)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: viewport.size.height
                    )
                    .padding(.horizontal, 28)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Begin together", action: onComplete)
                .buttonStyle(WEJourneyPrimaryButtonStyle(state: .shared))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.wePearl.opacity(0.96))
        }
        .preferredColorScheme(.light)
    }
}

private struct PairingView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var softStart: SoftStartCoordinator
    @State private var joinCode = ""
    @State private var selectedArchive: RelationshipArchive?

    var body: some View {
        NavigationStack {
            ZStack {
                WEJourneyBackdrop(state: .privateState)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("YOUR SIDE")
                                .font(.weCaption)
                                .tracking(1.8)
                                .foregroundStyle(Color.wePearl.opacity(0.7))
                            Spacer()
                            Label("Private", systemImage: "lock.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.wePearl.opacity(0.7))
                        }

                        Text("Your side is ready.")
                            .font(.weLargeTitle)
                            .foregroundStyle(Color.wePearl)
                        Text("You can keep what you began here. Invite your partner only when a shared space would be useful.")
                            .font(.weBody)
                            .foregroundStyle(Color.wePearl.opacity(0.72))

                        if let proposal = softStart.proposal {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PREPARED FOR YOU")
                                    .font(.weCaption)
                                    .tracking(1.5)
                                    .foregroundStyle(Color.wePearl.opacity(0.6))
                                Text(proposal.title)
                                    .font(.weTitle)
                                    .foregroundStyle(Color.wePearl)
                                Label(
                                    "Prepared on this iPhone from your note",
                                    systemImage: "iphone.gen3"
                                )
                                .font(.footnote)
                                .foregroundStyle(Color.wePearl.opacity(0.64))
                                WEContinuityLine(state: .privateState)
                                    .frame(height: 46)
                            }
                            .padding(18)
                            .background(
                                Color.white.opacity(0.07),
                                in: RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .stroke(Color.weChampagne.opacity(0.34))
                            }
                        } else if softStart.pendingOfferProposalID == nil,
                                  let saved = session.privateProposals.first {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(
                                    "SAVED ON YOUR SIDE",
                                    systemImage: "lock.fill"
                                )
                                .font(.weCaption)
                                .tracking(1.4)
                                .foregroundStyle(Color.wePearl.opacity(0.64))
                                Text(saved.title)
                                    .font(.weTitle)
                                    .foregroundStyle(Color.wePearl)
                                Text(
                                    "Protected by your account. This view does not load your original note."
                                )
                                .font(.footnote)
                                .foregroundStyle(Color.wePearl.opacity(0.64))
                                if session.privateProposals.count > 1 {
                                    Text(
                                        "\(session.privateProposals.count) proposals are kept on your side."
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(
                                        Color.wePearl.opacity(0.64)
                                    )
                                }
                            }
                            .padding(18)
                            .background(
                                Color.white.opacity(0.07),
                                in: RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .stroke(Color.weChampagne.opacity(0.34))
                            }
                        } else if softStart.pendingOfferProposalID != nil {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(
                                    "APPROVED OFFER READY",
                                    systemImage: "checkmark.shield"
                                )
                                .font(.weCaption)
                                .tracking(1.4)
                                .foregroundStyle(Color.wePearl.opacity(0.64))
                                Text(
                                    "Your exact preview is protected. The original note has been removed from this iPhone and will not cross."
                                )
                                .font(.weBody)
                                .foregroundStyle(Color.wePearl)
                            }
                            .padding(18)
                            .background(
                                Color.white.opacity(0.07),
                                in: RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                        }

                        Text("WHEN YOU ARE READY")
                            .font(.weCaption)
                            .tracking(1.8)
                            .foregroundStyle(Color.wePearl.opacity(0.58))
                            .padding(.top, 8)
                        Text("Create an invitation. Your note and private proposal do not travel with it.")
                            .font(.weBody)
                            .foregroundStyle(Color.wePearl.opacity(0.68))

                        Button {
                            Task { await createSharedSpace() }
                        } label: {
                            Label {
                                workingLabel("Create an invitation")
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(
                            WEJourneyPrimaryButtonStyle(state: .privateState)
                        )
                        .disabled(session.isWorking)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("HAVE A JOIN CODE?")
                                .font(.weCaption)
                                .tracking(1.5)
                                .foregroundStyle(Color.wePearl.opacity(0.64))
                            HStack(spacing: 10) {
                                TextField("JOIN CODE", text: $joinCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 50)
                                    .background(
                                        .white.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(.white.opacity(0.14))
                                    }
                                    .foregroundStyle(.white)
                                    .accessibilityLabel("Partner join code")
                                    .onChange(of: joinCode) { _, value in
                                        joinCode = String(
                                            value.uppercased()
                                                .filter {
                                                    $0.isLetter || $0.isNumber
                                                }
                                                .prefix(16)
                                        )
                                    }
                                Button("Join") {
                                    Task { await joinSharedSpace() }
                                }
                                .buttonStyle(.bordered)
                                .tint(.wePearl)
                                .frame(minHeight: 44)
                                .disabled(session.isWorking || joinCode.isEmpty)
                            }
                        }

                        SessionMessageView()

                        if !session.archives.isEmpty {
                            Divider().overlay(Color.wePearl.opacity(0.12))
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Past relationships")
                                    .font(.weHeadline)
                                    .foregroundStyle(.white)
                                ForEach(session.archives) { archive in
                                    Button {
                                        selectedArchive = archive
                                    } label: {
                                        Label("View read-only archive", systemImage: "archivebox")
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button("Sign out") { Task { await session.signOut() } }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.wePearl.opacity(0.54))
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: 430)
                    .padding(.horizontal, 26)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
            }
            .preferredColorScheme(.dark)
            .sheet(item: $selectedArchive) { RelationshipArchiveView(archive: $0) }
        }
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        if session.isWorking {
            ProgressView().tint(Color.wePrivateInk)
        } else {
            Text(title)
        }
    }

    private func createSharedSpace() async {
        let pendingOfferID = softStart.pendingOfferProposalID
        await session.createCouple()
        guard session.errorMessage == nil,
              let pendingOfferID else {
            return
        }
        if await session.offerPrivateProposal(id: pendingOfferID) {
            _ = softStart.markOfferPublished()
        }
    }

    private func joinSharedSpace() async {
        let pendingOfferID = softStart.pendingOfferProposalID
        await session.joinCouple(code: joinCode)
        guard session.errorMessage == nil,
              let pendingOfferID else {
            return
        }
        if await session.offerPrivateProposal(id: pendingOfferID) {
            _ = softStart.markOfferPublished()
        }
    }
}

private struct PartnerWaitingView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copied = false

    private var code: String { session.snapshot?.couple?.joinCode ?? "" }

    var body: some View {
        ZStack {
            WEJourneyBackdrop(state: .offered)

            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("INVITATION READY", systemImage: "lock.open")
                            .font(.weCaption)
                            .tracking(1.8)
                            .foregroundStyle(
                                Color.weCharcoal.opacity(0.76)
                            )

                        Spacer(minLength: 20)

                        WEContinuityLine(state: .offered)
                            .frame(
                                height: dynamicTypeSize.isAccessibilitySize
                                    ? 64
                                    : 92
                            )
                            .padding(.bottom, 24)

                        Text("The invitation is at\nthe threshold.")
                            .font(.weLargeTitle)
                            .foregroundStyle(Color.weCharcoal)
                        Text("Send the code when you are ready. It contains no note, proposal, answer, or private context.")
                            .font(.weBody)
                            .foregroundStyle(
                                Color.weCharcoal.opacity(0.76)
                            )
                            .padding(.top, 14)

                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                "WHAT CROSSES",
                                systemImage: "checkmark.shield"
                            )
                            .font(.weCaption)
                            .tracking(1.4)
                            .foregroundStyle(
                                Color.weCharcoal.opacity(0.76)
                            )
                            Text(
                                "An invitation to create a WE space. Nothing else."
                            )
                            .font(.weHeadline)
                            .foregroundStyle(Color.weCharcoal)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.white.opacity(0.54),
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.weChampagne.opacity(0.46))
                        }
                        .padding(.top, 22)

                        Text(code)
                            .font(
                                .system(
                                    .title2,
                                    design: .monospaced,
                                    weight: .semibold
                                )
                            )
                            .tracking(3)
                            .foregroundStyle(Color.weCharcoal)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                            .textSelection(.enabled)
                            .accessibilityLabel("Join code \(code)")

                        invitationActions
                            .padding(.top, 12)
                            .sensoryFeedback(.success, trigger: copied)

                        Text("WE will stay still until they choose.")
                            .font(.footnote)
                            .foregroundStyle(
                                Color.weCharcoal.opacity(0.76)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)

                        SessionMessageView()
                        Button("Sign out") {
                            Task { await session.signOut() }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            Color.weCharcoal.opacity(0.76)
                        )
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(
                        maxWidth: 440,
                        minHeight: max(0, viewport.size.height - 50),
                        alignment: .topLeading
                    )
                    .padding(.horizontal, 26)
                    .padding(.top, 24)
                    .padding(.bottom, 26)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var invitationActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
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

    private var sendInvitationButton: some View {
        ShareLink(item: "Join me in WE with code \(code)") {
            Label(
                "Send the invitation",
                systemImage: "square.and.arrow.up"
            )
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(WEJourneyPrimaryButtonStyle(state: .shared))
    }

    private var copyInvitationButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
        } label: {
            Label(
                copied ? "Copied" : "Copy",
                systemImage: copied ? "checkmark" : "doc.on.doc"
            )
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.bordered)
        .tint(.weCharcoal)
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
        .environmentObject(SoftStartCoordinator())
        .environmentObject(ExternalSurfaceController())
}
