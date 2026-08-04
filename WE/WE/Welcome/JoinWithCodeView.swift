//
//  JoinWithCodeView.swift
//  WE
//
//  Taking the code before there is anywhere to spend it.
//
//  `joinCouple(code:)` needs a session, and the person holding an invitation
//  usually has no account at all — so this screen does not join anything. It
//  takes the code, hands it to `PendingInvitation`, and moves on to account
//  creation. `ContentView` redeems it on the far side, once a session exists.
//
//  Which means: no network call here, no failure state here. A wrong code fails
//  later, in `PairingView`, where the field is still on screen to correct.
//

import SwiftUI

struct JoinWithCodeView: View {
    /// Called once the code is held. `WelcomeView` swaps the sheet to account
    /// creation rather than dismissing back to itself.
    var onContinue: () -> Void

    @State private var code = ""
    @FocusState private var isFocused: Bool

    private var normalizedCode: String? {
        PendingInvitation.normalized(code)
    }

    @EnvironmentObject private var pendingInvitation: PendingInvitation

    var body: some View {
        FieldGateScaffold(label: "Invitation") {
            VStack(alignment: .leading, spacing: 30) {
                FieldGateHeadline(
                    title: "Enter the code.",
                    subtitle: "The person who invited you has a code to share. You'll make your own account next — the shared space opens once you're both in it."
                )

                FieldTextField(
                    label: "Join code",
                    text: $code,
                    autocapitalization: .characters,
                    identifier: "welcome.joinCode"
                )
                .focused($isFocused)
                .onChange(of: code) { _, value in
                    // Normalising as they type, so what is on screen is exactly
                    // what will be held. Same shape as `PairingView`'s field,
                    // and now the same code path.
                    //
                    // Only written when it actually differs. Assigning back on
                    // every keystroke re-enters the field mid-edit and drops
                    // characters that are already queued — which, with the
                    // keyboard set to `.characters`, was most of them.
                    let normalized = PendingInvitation.normalized(value) ?? ""
                    if normalized != value {
                        code = normalized
                    }
                }

                Button {
                    guard let normalizedCode else { return }
                    pendingInvitation.hold(normalizedCode)
                    onContinue()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(FieldFilledButtonStyle())
                .disabled(normalizedCode == nil)
                .accessibilityIdentifier("welcome.joinCode.continue")
            }
        }
        .onAppear { isFocused = true }
    }
}

#Preview("Join with a code") {
    JoinWithCodeView(onContinue: {})
        .environmentObject(PendingInvitation())
}
