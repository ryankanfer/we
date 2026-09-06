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
//  Not built on `FieldGateScaffold`. The scaffold centres its content, caps it
//  at 440pt, and owns the background — and the bloom has to run full-bleed to
//  the top edge. The scaffold's *components* are all reused; only its frame is
//  not. Every sheet this screen opens goes back to the scaffold.
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
        ZStack(alignment: .top) {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WelcomeBloom()
                        .padding(.bottom, FieldMetrics.sectionGapTight)

                    VStack(
                        alignment: .leading,
                        spacing: FieldMetrics.sectionGap
                    ) {
                        introduction
                        start
                        invitation
                        returning
                    }
                    .padding(.horizontal, FieldMetrics.screenSide)
                }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, FieldMetrics.sectionGapLoose)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
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

    /// One question, and nothing above it.
    ///
    /// What stood here was a tracked "WELCOME TO WE" eyebrow over a headline
    /// naming the category and a subtitle explaining the category again. Three
    /// pieces of furniture to say one thing, and none of them about the person
    /// the reader has in mind.
    private var introduction: some View {
        FieldGateHeadline(title: WEGateCopy.welcome)
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The width goes on the *label*: every Field button style pads and
            // then backs its label, so stretching the button leaves the fill
            // hugging the text.
            Button {
                destination = .createAccount
            } label: {
                Text(WEGateCopy.begin).frame(maxWidth: .infinity)
            }
            .buttonStyle(FieldFilledButtonStyle())
            .accessibilityIdentifier("welcome.start")
        }
    }

    /// One door, whether or not a code is already held.
    ///
    /// It used to split: a held code turned the button into "Join with
    /// WEDEMO" and routed straight to account creation, skipping the only
    /// screen that tells this person who is waiting for them. Both routes now
    /// go through that screen, which is where a held code belongs anyway.
    private var invitation: some View {
        Button {
            destination = .joinWithCode
        } label: {
            Text(WEGateCopy.invited).frame(maxWidth: .infinity)
        }
        .buttonStyle(FieldOutlinedButtonStyle())
        .accessibilityIdentifier("welcome.join")
    }

    private var returning: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Built the way `ContentView`'s account button is, rather than on
            // `FieldQuietButtonStyle`: that style pads without a background,
            // and an unbacked pad is not hit-testable, so the only tappable
            // part is the glyphs. A door on the first screen needs 44pt.
            Button {
                destination = .signIn
            } label: {
                Text(WEGateCopy.signIn)
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    // The underline is drawn to the text, not to the tap
                    // target — `.underline()` on an uppercased, tracked label
                    // label sits too low and runs past the last letter.
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(FieldRule.row)
                            .frame(height: 1)
                            .offset(y: 4)
                            .allowsHitTesting(false)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.fieldInk(.label))
            .accessibilityLabel("Sign in")
            .accessibilityIdentifier("welcome.signIn")
        }
    }

}

#Preview("Welcome") {
    WelcomeView()
        .environmentObject(PendingInvitation())
        .environmentObject(AppSession(repository: PreviewRepository()))
}
