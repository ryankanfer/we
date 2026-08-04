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

    /// A code can already be held before this screen is ever tapped — a
    /// `we://join/CODE` link opens straight here. When it is, the invitation
    /// section stops asking and starts confirming.
    private var heldCode: String? { pendingInvitation.code }

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
                        privacy
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
        .sheet(item: $destination) { destination in
            switch destination {
            case .createAccount:
                SignInView(initialMode: .create)
            case .signIn:
                SignInView()
            case .joinWithCode:
                JoinWithCodeView {
                    // Swapping the item rather than dismissing and presenting
                    // again — the code is held by now, and a dismiss/present
                    // race would flash the welcome screen in between.
                    self.destination = .createAccount
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.sectionGapTight) {
            brandLabel("Welcome to ")

            FieldGateHeadline(
                title: "A shared space for\nwhat matters between you.",
                subtitle: "What you both choose can have a place here."
            )
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The width goes on the *label*: every Field button style pads and
            // then backs its label, so stretching the button leaves the fill
            // hugging the text.
            Button {
                destination = .createAccount
            } label: {
                brandText("Start a ", trailing: " space")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FieldFilledButtonStyle())
            .accessibilityIdentifier("welcome.start")

            Text("Begin here. Invite the other person when you're ready.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fieldLineHeight(1.5, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(
                heldCode == nil ? "Have an invitation?" : "Your invitation"
            )

            if let heldCode {
                Button {
                    destination = .createAccount
                } label: {
                    Text("Join with \(heldCode)").frame(maxWidth: .infinity)
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .accessibilityLabel("Join with code \(heldCode)")
                .accessibilityIdentifier("welcome.join")
            } else {
                Button {
                    destination = .joinWithCode
                } label: {
                    Text("Join with a code").frame(maxWidth: .infinity)
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .accessibilityIdentifier("welcome.join")
            }
        }
    }

    private var returning: some View {
        VStack(alignment: .leading, spacing: 2) {
            brandLabel("Already use ", trailing: "?")

            // Built the way `ContentView`'s account button is, rather than on
            // `FieldQuietButtonStyle`: that style pads without a background,
            // and an unbacked pad is not hit-testable, so the only tappable
            // part is the glyphs. A door on the first screen needs 44pt.
            Button {
                destination = .signIn
            } label: {
                Text("SIGN IN")
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    // The underline is drawn to the text, not to the tap
                    // target — `.underline()` on an uppercased, tracked mono
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
            .foregroundStyle(.fieldInk(.monoLabel))
            .accessibilityLabel("Sign in")
            .accessibilityIdentifier("welcome.signIn")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(FieldSwatch.clay.color.opacity(0.7))
                .frame(width: 56, height: 1)
                .accessibilityHidden(true)

            Text("Private reflection stays private.")
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.6, size: 13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, FieldMetrics.sectionGapTight)
    }

    /// WE is the one word on this page that is not interface copy. Giving the
    /// wordmark a stronger weight keeps it legible inside the airy tracked
    /// labels without making every door louder.
    private func brandText(
        _ leading: String,
        trailing: String = ""
    ) -> Text {
        Text(
            "\(leading)\(Text("WE").fontWeight(.bold))\(trailing)"
        )
    }

    private func brandLabel(
        _ leading: String,
        trailing: String = ""
    ) -> some View {
        brandText(leading.uppercased(), trailing: trailing.uppercased())
            .font(FieldType.sectionLabel)
            .tracking(FieldTracking.sectionLabel)
            .foregroundStyle(.fieldInk(.monoLabel))
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environmentObject(PendingInvitation())
        .environmentObject(AppSession(repository: PreviewRepository()))
}
