//
//  SignInView.swift
//  WE
//
//  The account gates, in the app's own language.
//
//  Everything here is drawn on `FieldGateScaffold` — the same deep green, the
//  same two families, the same hairlines as the zones behind it. It used to be
//  cream, and the collapse in `WESplashView` handed a deep green mark to a
//  light screen.
//
//  The identifiers are a contract with WEUITests and are load-bearing:
//  `accountSubmitButton` and `updatePasswordButton` are how the suite signs in
//  at all.
//

import SwiftUI

struct SignInView: View {
    /// Internal rather than private so `WelcomeView` can open this straight
    /// into account creation. The default stays `.signIn` — "Welcome back." is
    /// what the suite asserts on when the view is built with no argument.
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: String { rawValue }

        /// The chip, which is mono and uppercase like every other label in the
        /// app. The raw value stays sentence case because it is also the
        /// submit button's title.
        var chip: String {
            self == .signIn ? "SIGN IN" : "CREATE ACCOUNT"
        }
    }

    @EnvironmentObject private var session: AppSession
    @State private var mode: Mode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showsReset = false

    init(initialMode: Mode = .signIn) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        FieldGateScaffold(label: "Account") {
            VStack(alignment: .leading, spacing: 30) {
                FieldGateHeadline(
                    title: mode == .signIn
                        ? "Welcome back."
                        : "Begin on your side.",
                    subtitle: mode == .signIn
                        ? "Return to your shared space."
                        : "Your private account comes before the shared space."
                )

                // Two chips rather than a segmented control. A segmented
                // control is UIKit chrome, and there is none anywhere else in
                // the app.
                HStack(spacing: 8) {
                    ForEach(Mode.allCases) { option in
                        FieldChip(
                            option.chip,
                            isSelected: mode == option
                        ) {
                            mode = option
                        }
                        .accessibilityLabel(option.rawValue)
                        .accessibilityIdentifier(
                            "account.mode.\(option == .signIn ? "signIn" : "create")"
                        )
                    }
                }

                fields

                SessionMessageView()

                VStack(alignment: .leading, spacing: 16) {
                    Button { submit() } label: {
                        if session.isWorking {
                            ProgressView().tint(FieldPalette.bg)
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                    .buttonStyle(FieldFilledButtonStyle())
                    .disabled(!isValid || session.isWorking)
                    .accessibilityIdentifier("accountSubmitButton")

                    if mode == .signIn {
                        // Every Field button style uppercases its label, so
                        // the accessibility label is set back to the sentence
                        // — VoiceOver should not be shouting, and the UI suite
                        // addresses this one by name.
                        Button("Forgot password?") { showsReset = true }
                            .buttonStyle(FieldQuietButtonStyle())
                            .accessibilityLabel("Forgot password?")
                            .accessibilityIdentifier("account.forgotPassword")
                    } else {
                        Text(
                            "At least 8 characters. You may need to verify "
                                + "your email before you can pair."
                        )
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fieldLineHeight(1.62, size: 13)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .sheet(isPresented: $showsReset) { PasswordResetView(email: $email) }
        .onChange(of: mode) { _, _ in session.clearMessages() }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 24) {
            if mode == .create {
                FieldTextField(
                    label: "Your name",
                    text: $name,
                    contentType: .name,
                    autocapitalization: .words
                )
            }

            FieldTextField(
                label: "Email",
                text: $email,
                contentType: .emailAddress,
                keyboard: .emailAddress,
                autocapitalization: .never
            )

            FieldTextField(
                label: "Password",
                text: $password,
                isSecure: true,
                contentType: disablesCredentialPrompts
                    ? .oneTimeCode
                    : (mode == .create ? .newPassword : .password),
                autocapitalization: .never
            )

            if mode == .create {
                FieldTextField(
                    label: "Confirm password",
                    text: $confirmation,
                    isSecure: true,
                    contentType: disablesCredentialPrompts
                        ? .oneTimeCode
                        : .newPassword,
                    autocapitalization: .never
                )
            }
        }
    }

    private var isValid: Bool {
        let basic = email.contains("@") && password.count >= 8
        return mode == .signIn
            ? basic
            : basic
                && !name.trimmingCharacters(in: .whitespaces).isEmpty
                && password == confirmation
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
                await session.signUp(
                    name: name,
                    email: email,
                    password: password
                )
            }
        }
    }
}

/// Reached from "Forgot password?". A plain stack, not a `Form` — a grouped
/// inset list cannot be made to look like this app, and there are two controls
/// on it.
private struct PasswordResetView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String

    var body: some View {
        ZStack {
            FieldGateScaffold(label: "Password reset") {
                VStack(alignment: .leading, spacing: 30) {
                    FieldGateHeadline(
                        title: "We'll send a link.",
                        subtitle: "Your shared data will not be changed."
                    )

                    FieldTextField(
                        label: "Email",
                        text: $email,
                        contentType: .emailAddress,
                        keyboard: .emailAddress,
                        autocapitalization: .never
                    )

                    SessionMessageView()

                    Button("Send reset link") {
                        Task { await session.sendPasswordReset(email: email) }
                    }
                    .buttonStyle(FieldFilledButtonStyle())
                    .disabled(!email.contains("@") || session.isWorking)
                    .accessibilityIdentifier("sendResetLinkButton")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Text("DONE ✕")
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    .foregroundStyle(.fieldInk(.legend))
                    .padding(FieldMetrics.screenSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
    }
}

struct NewPasswordView: View {
    @EnvironmentObject private var session: AppSession
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        FieldGateScaffold(label: "Password recovery") {
            VStack(alignment: .leading, spacing: 30) {
                FieldGateHeadline(
                    title: "Choose a new password.",
                    subtitle: "Your recovery link is confirmed. At least "
                        + "8 characters, and you're back."
                )

                VStack(alignment: .leading, spacing: 24) {
                    FieldTextField(
                        label: "New password",
                        text: $password,
                        isSecure: true,
                        contentType: .newPassword,
                        autocapitalization: .never
                    )

                    FieldTextField(
                        label: "Confirm new password",
                        text: $confirmation,
                        isSecure: true,
                        contentType: .newPassword,
                        autocapitalization: .never
                    )
                }

                SessionMessageView()

                Button {
                    Task { await session.completePasswordRecovery(password) }
                } label: {
                    if session.isWorking {
                        ProgressView().tint(FieldPalette.bg)
                    } else {
                        Text("Update password")
                    }
                }
                .buttonStyle(FieldFilledButtonStyle())
                .disabled(
                    password.count < 8
                        || password != confirmation
                        || session.isWorking
                )
                .accessibilityIdentifier("updatePasswordButton")
            }
        }
    }
}

/// An error or a notice from the session, in the ink ramp rather than in red.
///
/// The one exception is a real failure, which carries Rust — a person colour
/// used here because the app has no error palette and inventing one for a
/// single line would be a sixth semantic colour nothing else uses.
struct SessionMessageView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if let error = session.errorMessage {
            Text(error)
                .font(FieldType.reasoning)
                .foregroundStyle(FieldSwatch.rust.color)
                .fieldLineHeight(1.62, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
        } else if let notice = session.noticeMessage {
            Text(notice)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.metadataProse))
                .fieldLineHeight(1.62, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// The gate for a backend that is missing, or a load that failed. Both are
/// states the app can be honest about without dressing them up.
struct BackendStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?
    var signOut: (() -> Void)?

    var body: some View {
        FieldGateScaffold {
            VStack(alignment: .leading, spacing: 30) {
                FieldGateHeadline(title: title, subtitle: message)

                HStack(spacing: 12) {
                    if let retry {
                        Button("Continue", action: retry)
                            .buttonStyle(FieldFilledButtonStyle())
                    }
                    if let signOut {
                        Button("Sign out", action: signOut)
                            .buttonStyle(FieldOutlinedButtonStyle())
                    }
                }
            }
        }
    }
}

#Preview("Sign in") {
    SignInView()
        .environmentObject(AppSession(repository: PreviewRepository()))
}
