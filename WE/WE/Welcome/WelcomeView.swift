//
//  WelcomeView.swift
//  WE
//
//  The first screen, and the only one a person sees before they have an
//  account.
//
//  What was here before was `SoftStartView` — a four-stage funnel that asked
//  for a private note and prepared a proposal on device before mentioning an
//  account at all. It delivered something real, but it answered a question
//  nobody had asked yet. This answers the one they did: what is this, and which
//  door is mine. Three doors, named: start one, join one, return to one.
//
//  Built on `FirstRunScreen`, like every screen before pairing: the bloom and
//  the question scroll, and the three doors stay pinned where the thumb is.
//

import SwiftUI

struct WelcomeView: View {
    private enum Destination: String, Identifiable {
        case createAccount
        case signIn
        case joinWithCode
        var id: String { rawValue }
    }

    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @EnvironmentObject private var walkthrough: WalkthroughPresenter
    @State private var destination: Destination?

    /// Whether the held code has already been offered on this launch.
    ///
    /// A `we://join/CODE` link opens this screen with a code already in hand,
    /// and somebody who tapped an invitation should not have to pick a door to
    /// be told who sent it. So the invited person's screen presents itself —
    /// once. Doing it every time the welcome screen appears would put somebody
    /// who dismissed it in order to sign in straight back where they were.
    @State private var hasOfferedHeldInvitation = false

    var body: some View {
        FirstRunScreen(
            title: WEGateCopy.welcome,
            subtitle: WEGateCopy.welcomeLine,
            hero: {
                ZStack(alignment: .topTrailing) {
                    WelcomeBloom(diameter: 280)
                        .padding(.top, 12)
                    // The explanation, offered rather than played at them.
                    Button("How it works") { walkthrough.replay() }
                        .buttonStyle(FirstRunLinkStyle())
                        .accessibilityIdentifier("welcome.walkthrough")
                }
            },
            actions: {
                Button(WEGateCopy.begin) { destination = .createAccount }
                    .buttonStyle(FirstRunPrimaryButtonStyle())
                    .accessibilityIdentifier("welcome.start")
                // One door, whether or not a code is already held: both go
                // through the screen that says who is waiting.
                Button(WEGateCopy.invited) { destination = .joinWithCode }
                    .buttonStyle(FirstRunSecondaryButtonStyle())
                    .accessibilityIdentifier("welcome.join")
                FirstRunPromptLink(
                    prompt: "Already have an account?",
                    link: WEGateCopy.signIn,
                    identifier: "welcome.signIn"
                ) { destination = .signIn }
            }
        )
        .task(id: pendingInvitation.code) {
            guard pendingInvitation.code != nil, !hasOfferedHeldInvitation
            else { return }
            hasOfferedHeldInvitation = true
            destination = .joinWithCode
        }
        .sheet(item: $destination) { destination in
            switch destination {
            case .createAccount:
                SignInView(initialMode: .create)
            case .signIn:
                SignInView()
            case .joinWithCode:
                WEInvitationArrival(
                    onContinue: {
                        // Swapping the item rather than dismissing and
                        // presenting again — the code is held by now, and a
                        // dismiss/present race would flash the welcome screen
                        // in between.
                        self.destination = .createAccount
                    },
                    onDecline: { self.destination = nil }
                )
            }
        }
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environmentObject(PendingInvitation())
        .environmentObject(AppSession(repository: PreviewRepository()))
}
