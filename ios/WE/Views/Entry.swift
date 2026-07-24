import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject var session: Session
    @State private var signUp = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && (!signUp || !name.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    InterlockMark(overlap: .interlocked, size: 26)
                    Text("WE").font(.serif(18)).tracking(4)
                }
                .padding(.top, 40)

                Text(signUp ? "Make your sign-in." : "Welcome back.")
                    .font(.serif(28)).padding(.top, 24)
                Text(signUp
                     ? "Yours alone. Your partner makes theirs; you meet in one shared space."
                     : "Pick up where the two of you left off.")
                    .font(.system(size: 15)).foregroundColor(Palette.faint).padding(.top, 6)

                VStack(spacing: 12) {
                    if signUp { field("Your name", text: $name) }
                    field("Email", text: $email, keyboard: .emailAddress)
                    field("Password", text: $password, secure: true)
                }
                .padding(.top, 24)

                if let e = session.errorText {
                    Text(e).font(.system(size: 14)).foregroundColor(Palette.burgundy).padding(.top, 12)
                }
                if let i = session.info {
                    Text(i).font(.system(size: 14)).foregroundColor(Palette.sage).padding(.top, 12)
                }

                PrimaryButton(title: session.busy ? "One moment…" : (signUp ? "Create sign-in" : "Sign in"),
                              enabled: canSubmit && !session.busy) {
                    Task {
                        if signUp { await session.signUp(name: name, email: email, password: password) }
                        else { await session.signIn(email: email, password: password) }
                    }
                }
                .padding(.top, 20)

                Button(signUp ? "I already have a sign-in" : "I’m new here") {
                    withAnimation { signUp.toggle() }
                }
                .font(.system(size: 13)).foregroundColor(Palette.faint)
                .frame(maxWidth: .infinity).padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .foregroundColor(Palette.ink)
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            Group {
                if secure { SecureField("", text: text) }
                else { TextField("", text: text).keyboardType(keyboard).textInputAutocapitalization(.never) }
            }
            .autocorrectionDisabled()
            .font(.system(size: 16))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .weCard()
        }
    }
}

struct PairingView: View {
    @EnvironmentObject var session: Session
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    InterlockMark(overlap: .touching, size: 34)
                    Text(session.user.map { "Hi \($0.name)." } ?? "One more step.").font(.serif(28))
                }
                .padding(.top, 44)

                Text("WE lives between two people. Start a shared space and invite your partner, or join the one they already made.")
                    .font(.system(size: 15)).foregroundColor(Palette.faint).padding(.top, 12)

                PrimaryButton(title: session.busy ? "One moment…" : "Start our space", enabled: !session.busy) {
                    Task { await session.createCouple() }
                }
                .padding(.top, 28)

                HStack {
                    line; Text("or").font(.system(size: 12)).foregroundColor(Palette.faint); line
                }.padding(.vertical, 22)

                SectionLabel(text: "Join with a code")
                TextField("6-character code", text: $code)
                    .font(.system(size: 18)).tracking(6).multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(.vertical, 12).weCard().padding(.top, 6)

                Button {
                    Task { await session.joinCouple(code: code) }
                } label: {
                    Text("Join their space").font(.system(size: 16)).foregroundColor(Palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(Capsule().stroke(Palette.ink, lineWidth: 1))
                }
                .opacity(code.count >= 6 && !session.busy ? 1 : 0.4)
                .disabled(code.count < 6 || session.busy)
                .padding(.top, 12)

                if let e = session.errorText {
                    Text(e).font(.system(size: 14)).foregroundColor(Palette.burgundy).padding(.top, 12)
                }

                Button("Sign out") { Task { await session.signOut() } }
                    .font(.system(size: 13)).foregroundColor(Palette.faint)
                    .frame(maxWidth: .infinity).padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .foregroundColor(Palette.ink)
        }
    }

    private var line: some View { Rectangle().fill(Palette.line).frame(height: 1) }
}
