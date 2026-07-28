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
                Color.weCinematicInk.ignoresSafeArea()
                WEConfluenceForm(
                    personalHue: .burgundy,
                    partnerHue: .sage,
                    connection: 0.08
                )
                .opacity(0.38)
                .blur(radius: 18)
                .ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.weCinematicInk.opacity(0.58),
                        Color.weCinematicInk.opacity(0.32),
                        Color.weCinematicInk.opacity(0.97),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("06 · THE OTHER HALF")
                            .font(.weCaption)
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.58))

                        missingField
                            .padding(.vertical, 42)

                        Text("Half the field is missing.")
                            .font(.weLargeTitle)
                            .foregroundStyle(.white)
                        Text("Create your shared side, then send the invitation. When your partner chooses their color, the field completes.")
                            .font(.weBody)
                            .foregroundStyle(.white.opacity(0.64))
                            .padding(.top, 12)

                        Button {
                            Task { await session.createCouple() }
                        } label: {
                            Label {
                                workingLabel("Create and send the invitation")
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(
                            WEHue.burgundy.controlColor,
                            in: RoundedRectangle(cornerRadius: 17)
                        )
                        .disabled(session.isWorking)
                        .padding(.top, 24)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("OPEN AN INVITATION")
                                .font(.weCaption)
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.44))
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
                                    Task { await session.joinCouple(code: joinCode) }
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .frame(minHeight: 44)
                                .disabled(session.isWorking || joinCode.isEmpty)
                            }
                        }
                        .padding(.top, 28)

                        SessionMessageView()

                        if !session.archives.isEmpty {
                            Divider().overlay(.white.opacity(0.12))
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
                            .foregroundStyle(.white.opacity(0.46))
                            .frame(minHeight: 44)
                            .padding(.top, 12)
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

    private var missingField: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.weCinematicInk.opacity(0.62))
            WEConfluenceForm(
                personalHue: .burgundy,
                partnerHue: .sage,
                connection: 0.02
            )
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    Color.clear
                }
            }
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 3) {
                Text((session.snapshot?.profile.name ?? "YOUR SIDE").uppercased())
                    .font(.weCaption)
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                Text("is waiting for you.")
                    .font(.weHeadline)
                    .foregroundStyle(.white)
            }
            .padding(18)
        }
        .frame(height: 206)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.14))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Half of the shared field is waiting")
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
            Color.weCinematicInk.ignoresSafeArea()
            WEConfluenceForm(
                personalHue: personalHue,
                partnerHue: .sage,
                connection: 0.05
            )
            .opacity(0.48)
            .blur(radius: 20)
            .ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.weCinematicInk.opacity(0.52),
                    Color.weCinematicInk.opacity(0.34),
                    Color.weCinematicInk.opacity(0.98),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Label("YOUR SIDE IS READY", systemImage: "circle.fill")
                    .font(.weCaption)
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.58))
                    .symbolRenderingMode(.monochrome)
                    .tint(personalHue.color)

                Spacer()

                Text("WE is holding one thing\nfor your partner.")
                    .font(.weLargeTitle)
                    .foregroundStyle(.white)
                Text("You can start using your side now. Anything you write stays yours. WE will not show, summarise, or read it.")
                    .font(.weBody)
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 10) {
                    Label("HELD ON YOUR SIDE", systemImage: "lock.fill")
                        .font(.weCaption)
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("A private reflection, and one moment waiting for both of you.")
                        .font(.weTitle)
                        .foregroundStyle(.white)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.weCinematicInk.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.13))
                }
                .padding(.top, 22)

                Text(code)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .textSelection(.enabled)
                    .accessibilityLabel("Join code \(code)")

                HStack(spacing: 12) {
                    ShareLink(item: "Join me in WE with code \(code)") {
                        Label("Send the invitation", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(personalHue.controlColor)

                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(minHeight: 54)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.top, 12)
                .sensoryFeedback(.success, trigger: copied)

                ProgressView("Waiting for your partner")
                    .controlSize(.small)
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                SessionMessageView()
                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.46))
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 26)
        }
        .preferredColorScheme(.dark)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
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
