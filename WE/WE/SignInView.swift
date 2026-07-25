import SwiftUI

struct SignInView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: String { rawValue }
    }

    @EnvironmentObject private var session: AppSession
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showsReset = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color("WEBackground").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 26) {
                        WEMark(style: .compact)
                        VStack(spacing: 8) {
                            Text(mode == .signIn ? "Welcome back." : "Begin on your side.")
                                .font(.weLargeTitle)
                            Text(mode == .signIn ? "Return to your shared space." : "Your private account comes before the shared space.")
                                .font(.weBody)
                                .foregroundStyle(Color("WEFaint"))
                                .multilineTextAlignment(.center)
                        }

                        Picker("Account action", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 14) {
                            if mode == .create {
                                TextField("Your name", text: $name)
                                    .textContentType(.name)
                            }
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                            SecureField("Password", text: $password)
                                .textContentType(
                                    disablesCredentialPrompts
                                        ? .oneTimeCode
                                        : (mode == .create
                                            ? .newPassword
                                            : .password)
                                )
                            if mode == .create {
                                SecureField("Confirm password", text: $confirmation)
                                    .textContentType(
                                        disablesCredentialPrompts
                                            ? .oneTimeCode
                                            : .newPassword
                                    )
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        SessionMessageView()

                        Button { submit() } label: {
                            if session.isWorking { ProgressView().tint(.white) }
                            else { Text(mode.rawValue) }
                        }
                        .buttonStyle(WEPrimaryButtonStyle())
                        .disabled(!isValid || session.isWorking)
                        .accessibilityIdentifier("accountSubmitButton")

                        if mode == .signIn {
                            Button("Forgot password?") { showsReset = true }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color("WEBurgundy"))
                                .frame(minHeight: 44)
                        } else {
                            Text("Use at least 8 characters. You may need to verify your email before pairing.")
                                .font(.footnote)
                                .foregroundStyle(Color("WEFaint"))
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                }
            }
            .sheet(isPresented: $showsReset) { PasswordResetView(email: $email) }
            .onChange(of: mode) { _, _ in session.clearMessages() }
        }
    }

    private var isValid: Bool {
        let basic = email.contains("@") && password.count >= 8
        return mode == .signIn ? basic : basic && !name.trimmingCharacters(in: .whitespaces).isEmpty && password == confirmation
    }

    private var disablesCredentialPrompts: Bool {
        ProcessInfo.processInfo.environment[
            "WE_DISABLE_CREDENTIAL_PROMPTS"
        ] == "1"
    }

    private func submit() {
        Task {
            if mode == .signIn {
                await session.signIn(email: email, password: password)
            } else {
                await session.signUp(name: name, email: email, password: password)
            }
        }
    }
}

private struct PasswordResetView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Reset password") {
                    Text("WE will send a secure reset link. Your shared data will not be changed.")
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                SessionMessageView()
                Button("Send reset link") {
                    Task { await session.sendPasswordReset(email: email) }
                }
                .disabled(!email.contains("@") || session.isWorking)
            }
            .navigationTitle("Password reset")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct NewPasswordView: View {
    @EnvironmentObject private var session: AppSession
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color("WEBackground").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        WEMark(style: .compact)
                        Text("Choose a new password.")
                            .font(.weLargeTitle)
                            .multilineTextAlignment(.center)
                        Text(
                            "Your recovery link is confirmed. Set at least "
                                + "8 characters to return to WE."
                        )
                        .font(.weBody)
                        .foregroundStyle(Color("WEFaint"))
                        .multilineTextAlignment(.center)

                        SecureField("New password", text: $password)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                        SecureField(
                            "Confirm new password",
                            text: $confirmation
                        )
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)

                        SessionMessageView()

                        Button {
                            Task {
                                await session.completePasswordRecovery(
                                    password
                                )
                            }
                        } label: {
                            if session.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Update password")
                            }
                        }
                        .buttonStyle(WEPrimaryButtonStyle())
                        .disabled(
                            password.count < 8
                                || password != confirmation
                                || session.isWorking
                        )
                        .accessibilityIdentifier("updatePasswordButton")
                    }
                    .padding(28)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Password recovery")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SessionMessageView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if let error = session.errorMessage {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
        } else if let notice = session.noticeMessage {
            Label(notice, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(Color("WEFaint"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
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
            Text(title).font(.weTitle)
            Text(message)
                .font(.weBody)
                .foregroundStyle(Color("WEFaint"))
                .multilineTextAlignment(.center)
            if let retry { Button("Continue", action: retry).buttonStyle(.borderedProminent).tint(Color("WEBurgundy")) }
            if let signOut { Button("Sign out", action: signOut).buttonStyle(.bordered) }
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("WEBackground"))
    }
}
