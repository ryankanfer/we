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
            if arrivalHappened(from: oldState, to: newState) {
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

    /// Whether the space just became two people, from either side of it.
    ///
    /// Both people see the arrival, which the single `.waitingForPartner ->
    /// .ready` edge never managed: that one fires only for the person who did
    /// the inviting, so the person who redeemed the code walked into a colour
    /// picker without the app ever acknowledging that they had arrived
    /// somewhere. Redemption moves them out of `.needsCouple`, which is the
    /// same event seen from the other phone.
    ///
    /// `.waitingForPartner -> .choosingHue` is the inviter's real route, not
    /// `-> .ready`: `create_couple` leaves `hue_chosen_at` null, so the person
    /// who opened the space still has a colour to choose when the second
    /// person lands. The old hook watched the one transition the inviter
    /// usually does not take.
    ///
    /// This is an edge, and edges are exactly what the *ceremony* refuses to
    /// be driven by — see `WECeremonyHost`. The difference is what is at
    /// stake: a missed arrival costs three words, and a missed ceremony would
    /// leave a promise unperformed. The Joining is driven by persisted state
    /// precisely so it survives everything this cannot.
    private func arrivalHappened(
        from oldState: AppSession.State,
        to newState: AppSession.State
    ) -> Bool {
        let wasAlone = oldState == .needsCouple
            || oldState == .waitingForPartner
        let isTogether = newState == .choosingHue || newState == .ready
        // And there are actually two people. A partner who joins and deletes
        // their account while this phone is offline would otherwise arrive and
        // depart in one snapshot, and the app would announce somebody who is
        // already gone.
        return wasAlone
            && isTogether
            && session.snapshot?.members.count == 2
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

/// The other person, arriving.
///
/// Three words on both phones at the same instant, and the first surface in
/// the product to carry both hues. What stood here was a paragraph — "A shared
/// space opened. You and Dylan remain yourselves. What you both choose can now
/// have a place between you." — which explains the arrival to somebody who is
/// looking straight at it, and explaining a moment is how you lose it.
///
/// The sentence is always about the *other* person. Neither phone announces
/// its owner to its owner, so both people read the same three words and
/// neither reads their own name.
///
/// **No haptic here.** WE has exactly one, at the instant a ceremony beat
/// lands on both phones, and it fires correctly already. A second one in
/// onboarding would spend the only piece of physical vocabulary the product
/// has on the smaller of two moments.
private struct PartnerArrivalCeremony: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var typeSize
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            WECanvas.ground.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                WEDisplayText(
                    WEGateCopy.arrival(of: session.partnerName),
                    role: .hero
                )

                Spacer(minLength: 0)

                WEEditorialAction(WEGateCopy.begin, action: onComplete)
                    .accessibilityIdentifier("arrival.begin")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FieldMetrics.usSide)
            .padding(.bottom, FieldMetrics.screenBottom(at: typeSize))

            // Shared, and for the first time truthfully so: until this instant
            // there was one person in the space.
            WEColourField(state: .shared, identity: identity, height: 168)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.weCanvas, .ground)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("we.arrival")
    }

    /// Both people, in the Field vocabulary. The bridge from
    /// `couple_members.hue` is the same one `HueSelectionView` uses; see
    /// CUTOVER.md for why two vocabularies still exist.
    private var identity: FieldIdentity {
        let members = session.snapshot?.members ?? []
        let mine = members.first { $0.id == session.user?.id }
        let theirs = members.first { $0.id != session.user?.id }
        return FieldIdentity(
            personA: mine.map { FieldSwatch(nearest: WEHue($0.hue)) }
                ?? FieldIdentity.seed.personA,
            personB: theirs.map { FieldSwatch(nearest: WEHue($0.hue)) }
                ?? FieldIdentity.seed.personB,
            nameA: mine?.name ?? FieldIdentity.seed.nameA,
            nameB: theirs?.name ?? session.partnerName
        )
    }
}

private struct PairingView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @State private var joinCode = ""
    @State private var selectedArchive: RelationshipArchive?

    var body: some View {
        FieldGateScaffold(centred: false) {
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
            // Through `PendingInvitation.normalized` rather than inline. This
            // was the second definition of a join code's shape that
            // `InvitationTests.normalisingStripsCaseAndPunctuationAndCaps`
            // exists to stop growing back — a typed code and a tapped link
            // have to agree, and they cannot if two places decide separately.
            .onChange(of: joinCode) { _, value in
                joinCode = PendingInvitation.normalized(value) ?? ""
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

    /// Whether the invitation has left this phone.
    ///
    /// The distinction the screen turns on. Before it, there is something to
    /// do; after it, there is nothing to do, and the app says so by going
    /// still rather than by continuing to display the thing already done.
    @AppStorage("we.invitation.sent") private var invitationSent = false

    private var name: String {
        invitee ?? "they"
    }

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
        if invitationSent, isLive {
            stillness
        } else {
            invitationScreen
        }
    }

    /// Nothing to do, so nothing to tap.
    ///
    /// The code was sent. Leaving it on screen with a share button beside it
    /// would be the app asking to be checked on, and checking on it is the
    /// behaviour the whole position is trying not to produce.
    private var stillness: some View {
        WEStillness(
            line: WEGateCopy.stillness(for: name == "they" ? nil : name),
            identity: FieldIdentity.seed,
            withdrawal: WEGateCopy.withdraw,
            onWithdraw: {
                invitationSent = false
                Task { await session.revokeInvitation() }
            }
        )
    }

    /// Two different endings, and only one of them is this person's doing.
    ///
    /// Withdrawing sets `invitationSent` back to false, so an invitation that
    /// is no longer live while it is still marked as sent ended some other
    /// way: it was declined, or it ran out. Those two are deliberately the
    /// same sentence. Telling somebody they were turned down, as against
    /// simply told the invitation is closed, is a fact they can do nothing
    /// with and would be handed on the app's initiative.
    private var closedTitle: String {
        invitationSent
            ? WEGateCopy.invitationClosedTitle
            : WEGateCopy.invitationWithdrawnTitle
    }

    private var closedDetail: String {
        invitationSent
            ? WEGateCopy.invitationClosedDetail
            : WEGateCopy.invitationWithdrawnDetail
    }

    private var invitationScreen: some View {
        FieldGateScaffold {
            VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
                FieldGateHeadline(
                    // "The invitation is at the threshold" is the register of
                    // the specification document that produced it. The word
                    // "threshold" survives fine as internal geometry naming
                    // and does not belong in a sentence anybody reads.
                    title: isLive
                        ? WEGateCopy.invitationTitle(for: invitee)
                        : closedTitle,
                    subtitle: isLive
                        ? WEGateCopy.invitationDetail(for: invitee)
                        : closedDetail
                )

                if isLive {
                    FieldTextField(
                        label: WEGateCopy.inviteeNameField,
                        text: $inviteeName,
                        identifier: "waiting.inviteeName"
                    )
                }

                // The code itself, in the app's label face at a size you can read
                // across a table. Selectable, because somebody will want to
                // copy it by hand rather than share it.
                VStack(alignment: .leading, spacing: 14) {
                    FieldRuleLine()

                    // Struck through rather than hidden when it is not live.
                    // Somebody who sent this code to their partner an hour
                    // ago needs to recognise the string they are looking at
                    // before they can understand that it stopped working.
                    Text(code)
                        .font(FieldType.metric)
                        .tracking(4)
                        .foregroundStyle(
                            .fieldInk(isLive ? .headline : .recessive)
                        )
                        .strikethrough(!isLive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .textSelection(.enabled)
                        .accessibilityLabel(
                            isLive
                                ? "Join code \(code)"
                                : "Join code \(code), no longer valid"
                        )

                    FieldRuleLine()
                }

                window

                invitationActions
                    .sensoryFeedback(.success, trigger: copied)

                withdrawal

                SessionMessageView()

                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(FieldQuietButtonStyle())
            }
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
            Text("This code works until \(expires.formatted(.dateTime.month(.wide).day())).")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("waiting.window")
        }
    }

    @ViewBuilder
    private var invitationActions: some View {
        if isLive {
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
        } else {
            Button {
                Task { await session.createInvitation() }
            } label: {
                if session.isWorking {
                    ProgressView().tint(FieldPalette.bg)
                } else {
                    Text("Make a new invitation")
                }
            }
            .buttonStyle(FieldFilledButtonStyle())
            .disabled(session.isWorking)
            .accessibilityLabel("Make a new invitation")
            .accessibilityIdentifier("waiting.regenerate")
        }
    }

    /// Withdrawing is the answer to "I sent that to the wrong person", and it
    /// has to be reachable at the moment somebody realises it — so it sits on
    /// this screen rather than behind Account.
    @ViewBuilder
    private var withdrawal: some View {
        if isLive {
            VStack(alignment: .leading, spacing: 10) {
                FieldRuleLine()

                Button("Withdraw this invitation") {
                    Task { await session.revokeInvitation() }
                }
                .buttonStyle(FieldQuietButtonStyle())
                .disabled(session.isWorking)
                .accessibilityIdentifier("waiting.revoke")
                .padding(.top, 4)

                Text("The code stops working straight away, for everyone.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // The Field button styles uppercase, so each of these carries its sentence
    // back as an accessibility label — VoiceOver should not be shouting.

    private var sendInvitationButton: some View {
        ShareLink(item: invitationShareMessage) {
            Text("Send the invitation")
        }
        .buttonStyle(FieldFilledButtonStyle())
        .accessibilityLabel("Send the invitation")
        .accessibilityIdentifier("waiting.share")
        // Sharing is the last thing there is to do, so the app goes still
        // once it is done. Optimistic on purpose: whether the message was
        // actually sent is between two people and their messaging app, and
        // WE having an opinion about it would mean watching for an answer.
        .simultaneousGesture(TapGesture().onEnded { invitationSent = true })
    }

    private var invitationShareMessage: String {
        couple?.activeInvitation()?.shareMessage
            ?? "Join me in WE with code \(code)"
    }

    private var copyInvitationButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            invitationSent = true
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
