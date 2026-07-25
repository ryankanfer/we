import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: AppSession

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Color("WEBackground")
                .ignoresSafeArea()

            VStack(spacing: 28) {
                WEMark(style: .compact)

                VStack(spacing: 8) {
                    Text("Welcome back.")
                        .font(.weLargeTitle)

                    Text("Return to your shared space.")
                        .font(.weBody)
                        .foregroundStyle(Color("WEFaint"))
                }

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                .textFieldStyle(.roundedBorder)

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        await session.signIn(
                            email: email,
                            password: password
                        )
                    }
                } label: {
                    if session.isWorking {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("WEBurgundy"))
                .disabled(
                    session.isWorking
                        || email.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || password.isEmpty
                )
            }
            .padding(28)
            .frame(maxWidth: 440)
        }
    }
}

struct BackendStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?
    var signOut: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            WEMark(style: .compact)

            Text(title)
                .font(.weTitle)

            Text(message)
                .font(.weBody)
                .foregroundStyle(Color("WEFaint"))
                .multilineTextAlignment(.center)

            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("WEBurgundy"))
            }

            if let signOut {
                Button("Sign out", action: signOut)
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("WEBackground"))
    }
}
