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
            lights: .near,
            hero: {
                // The icon, small, as the mark. The two big lights are the
                // background; they arrive from the splash already drawn
                // together. The old bloom had a fixed frame wider than a
                // phone, which pushed the whole column off both edges.
                WelcomeMark()
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// The app icon's two lights at mark size: burgundy and sage, overlapping.
private struct WelcomeMark: View {
    @Environment(\.weCanvas) private var canvas

    var body: some View {
        ZStack {
            light(FieldSwatch.burgundy).offset(x: -16)
            light(FieldSwatch.sage).offset(x: 16)
        }
        .frame(width: 120, height: 88)
        .blendMode(canvas.isDark ? .screen : .multiply)
        .accessibilityHidden(true)
    }

    private func light(_ swatch: FieldSwatch) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [swatch.color(on: canvas).opacity(0.9), swatch.color(on: canvas).opacity(0)],
                center: .center, startRadius: 0, endRadius: 44
            ))
            .frame(width: 88, height: 88)
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environmentObject(PendingInvitation())
        .environmentObject(AppSession(repository: PreviewRepository()))
}
