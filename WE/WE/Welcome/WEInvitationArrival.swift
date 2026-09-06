//
//  WEInvitationArrival.swift
//  WE
//
//  The invited person's first screen.
//
//  Dylan's first screen cannot be Ryan's first screen. Ryan arrived through
//  curiosity and was asked a question — what is this, which door is mine.
//  Dylan arrived because he is wanted, and the difference between being
//  summoned and being chosen is entirely a matter of what the first sentence
//  does:
//
//      Ryan is waiting.
//
//  One line, Ryan's hue in the field behind it, and only then the practical
//  step. **Code entry happens after that sentence, never before it.** The
//  screen this replaced opened with "Enter the code." over a form, which is
//  the register of a parcel locker.
//
//  WHERE THE NAME COMES FROM
//
//  `invitation_greeting`, the one read in the app that runs without a session,
//  because the person reading this line does not have one yet. It answers with
//  a name and a hue for a live invitation and with nothing at all otherwise —
//  a withdrawn, spent, expired or invented code are indistinguishable here on
//  purpose. Redemption tells those four apart, later, for somebody who has
//  actually committed to spending one.
//
//  WHEN THERE IS NO NAME
//
//  The line still tells rather than asks. Somebody arriving on this screen has
//  said they were invited; that is true whether or not the network has
//  answered yet, and "Someone is waiting for you" is the honest version of it.
//  What must never appear is an error about an invitation the reader did not
//  make: no "that code is not valid", no "expired", no retry counter.
//
//  This screen never joins anything. Joining needs a session, and the person
//  here usually has no account at all — the code is held on the device and
//  spent by `ContentView` on the far side of account creation.
//

import SwiftUI

struct WEInvitationArrival: View {
    /// Called once the code is held, so `WelcomeView` can swap the sheet to
    /// account creation rather than dismissing back to itself.
    var onContinue: () -> Void

    /// Called when this person says no. The sheet closes and there is nothing
    /// else: no confirmation, no second ask, and nothing that treats the
    /// answer as an objection to be handled.
    var onDecline: () -> Void = {}

    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var code = ""
    @State private var greeting: InvitationGreeting?
    @FocusState private var isFocused: Bool

    private var normalizedCode: String? {
        PendingInvitation.normalized(code)
    }

    /// The code this screen is speaking about: one already held from a
    /// `we://join/CODE` link, or the one being typed.
    private var liveCode: String? {
        pendingInvitation.code ?? normalizedCode
    }

    /// Whether the practical step is still "tell us the code".
    ///
    /// A held code has already been through this, so somebody arriving by link
    /// never meets the field at all: they read the sentence and continue.
    private var asksForCode: Bool {
        pendingInvitation.code == nil && greeting == nil
    }

    private var line: String {
        guard let greeting else { return WEGateCopy.waitingUnnamed }
        return WEGateCopy.waiting(for: greeting.name)
    }

    /// The waiting person's own hue, once it is known.
    ///
    /// One hue, not two. The other field is this person's, and they have not
    /// chosen a colour yet — drawing a second one would be the app inventing
    /// them before they exist.
    private var identity: FieldIdentity {
        guard let greeting else { return .seed }
        return FieldIdentity(
            personA: FieldSwatch(nearest: WEHue(greeting.hue)),
            personB: FieldIdentity.seed.personB,
            nameA: greeting.name,
            nameB: FieldIdentity.seed.nameB
        )
    }

    var body: some View {
        ZStack {
            WECanvas.ground.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                WEDisplayText(line, role: .hero)
                    .accessibilityIdentifier("welcome.invitation.line")

                Spacer(minLength: 0)

                if asksForCode {
                    codeEntry
                } else {
                    // No second explanation. The next screen is an account,
                    // and saying so twice would be the app hedging the one
                    // sentence it just made.
                    VStack(alignment: .leading, spacing: 20) {
                        WEEditorialAction(WEGateCopy.begin, action: hold)
                            .accessibilityIdentifier("welcome.joinCode.continue")

                        // Saying no, in the same typeface and at the same
                        // size as saying yes. A ceremony that can only end in
                        // yes is a sales funnel, and a decline hidden behind a
                        // gesture or drawn three shades quieter is the same
                        // funnel being coy about it.
                        WEEditorialAction(WEGateCopy.decline, action: decline)
                            .accessibilityIdentifier("welcome.invitation.decline")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FieldMetrics.usSide)
            .padding(.bottom, FieldMetrics.screenBottom(at: typeSize))

            WEColourField(state: .mine(.a), identity: identity, height: 168)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeInOut(duration: 0.45), value: greeting)
        .environment(\.weCanvas, .ground)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        // A code held from a link is asked about immediately, so the sentence
        // is already the person's name by the time the screen settles.
        .task(id: pendingInvitation.code) {
            guard greeting == nil else { return }
            await lookUp(pendingInvitation.code)
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 22) {
            FieldTextField(
                label: WEGateCopy.codeField,
                text: $code,
                autocapitalization: .characters,
                identifier: "welcome.joinCode"
            )
            .focused($isFocused)
            .onChange(of: code) { _, value in
                // Normalising as they type, so what is on screen is exactly
                // what will be held. Only written when it actually differs:
                // assigning back on every keystroke re-enters the field
                // mid-edit and drops characters already queued, which with
                // the keyboard set to `.characters` was most of them.
                let normalized = PendingInvitation.normalized(value) ?? ""
                if normalized != value { code = normalized }
            }

            WEEditorialAction(WEGateCopy.useCode) {
                Task { await lookUp(normalizedCode) }
            }
            .disabled(normalizedCode == nil)
            .accessibilityIdentifier("welcome.joinCode.continue")
        }
        .onAppear { isFocused = true }
    }

    /// Asks who is waiting, and holds the code either way.
    ///
    /// Either way, deliberately. A code that answers nothing is still the code
    /// this person was given: the network may be down, and redemption is the
    /// place that knows the difference. Holding it here means they never have
    /// to find the invitation again.
    private func lookUp(_ candidate: String?) async {
        guard let candidate else { return }
        isFocused = false
        greeting = await session.invitationGreeting(for: candidate)
        pendingInvitation.hold(candidate)
    }

    /// Closes the invitation, forgets the code, and leaves.
    ///
    /// The revocation is deliberately not waited on. Whether the network is
    /// there or not, this person has answered, and holding them on the screen
    /// while the app talks to a server about their answer would make saying no
    /// into a transaction. The write is idempotent, and the code is gone from
    /// this device either way.
    private func decline() {
        guard let liveCode else {
            onDecline()
            return
        }
        Task { await session.declineInvitation(code: liveCode) }
        pendingInvitation.clear()
        onDecline()
    }

    private func hold() {
        if let liveCode { pendingInvitation.hold(liveCode) }
        onContinue()
    }
}

#Preview("Invited, by name") {
    WEInvitationArrival(onContinue: {})
        .environmentObject(PendingInvitation())
        .environmentObject(AppSession(repository: PreviewRepository()))
}
