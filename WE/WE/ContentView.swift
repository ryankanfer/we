import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProfile = false
    var onReplayPromise: () -> Void = {}

    var body: some View {
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
                SignInView()
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
    }

    private var showsAuthenticatedProfileButton: Bool {
        switch session.state {
        case .needsCouple, .waitingForPartner, .choosingHue:
            true
        default:
            false
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

private struct PairingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var joinCode = ""
    @State private var selectedArchive: RelationshipArchive?

    var body: some View {
        NavigationStack {
            ZStack {
                Color("WEBackground").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        WEMark(style: .compact)
                        Text("Make this space yours.")
                            .font(.weLargeTitle)
                            .foregroundStyle(Color("WEInk"))
                        Text("Create a shared space, or enter the code your partner sent you.")
                            .font(.weBody)
                            .foregroundStyle(Color("WEFaint"))

                        Button {
                            Task { await session.createCouple() }
                        } label: {
                            workingLabel("Create our space")
                        }
                        .buttonStyle(WEPrimaryButtonStyle())
                        .disabled(session.isWorking)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("JOIN A SPACE")
                                .font(.weCaption)
                                .tracking(1.2)
                                .foregroundStyle(Color("WEFaint"))
                            HStack(spacing: 10) {
                                TextField("JOIN CODE", text: $joinCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
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
                                    Task { await session.joinCouple(code: joinCode) }
                                }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .disabled(session.isWorking || joinCode.isEmpty)
                            }
                        }

                        SessionMessageView()

                        if !session.archives.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Past relationships")
                                    .font(.weHeadline)
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
                            .foregroundStyle(Color("WEFaint"))
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: 520)
                    .padding(28)
                }
            }
            .sheet(item: $selectedArchive) { RelationshipArchiveView(archive: $0) }
        }
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        if session.isWorking { ProgressView().tint(.white) } else { Text(title) }
    }
}

private struct PartnerWaitingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var copied = false

    private var code: String { session.snapshot?.couple?.joinCode ?? "" }

    var body: some View {
        ZStack {
            Color("WEBackground").ignoresSafeArea()
            VStack(spacing: 24) {
                WEMark(
                    style: .display,
                    joined: false,
                    accessibilityText: "WE mark, waiting for your partner"
                )
                Text("Your side is ready.")
                    .font(.weLargeTitle)
                Text("Invite your partner. WE will open automatically when they arrive.")
                    .font(.weBody)
                    .foregroundStyle(Color("WEFaint"))
                    .multilineTextAlignment(.center)

                Text(code)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .tracking(3)
                    .textSelection(.enabled)
                    .accessibilityLabel("Join code \(code)")

                HStack(spacing: 12) {
                    ShareLink(item: "Join me in WE with code \(code)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("WEBurgundy"))

                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .sensoryFeedback(.success, trigger: copied)

                ProgressView("Waiting for your partner")
                    .controlSize(.small)
                    .foregroundStyle(Color("WEFaint"))

                SessionMessageView()
                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color("WEFaint"))
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: 440)
            .padding(28)
        }
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
    ContentView().environmentObject(AppSession(repository: PreviewRepository()))
}
