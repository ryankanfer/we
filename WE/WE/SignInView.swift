import SwiftUI

struct SignInView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: String { rawValue }
    }

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showsReset = false
    @State private var submitting = false
    @FocusState private var focus: WEAccountFocus?

    init(initialMode: Mode = .signIn) { _mode = State(initialValue: initialMode) }
    private var busy: Bool { submitting || session.isWorking }
    private var valid: Bool {
        mode == .signIn
            ? WEAccountInput.validSignIn(email: email, password: password)
            : WEAccountInput.validCreation(name: name, email: email, password: password, confirmation: confirmation)
    }

    var body: some View {
        WEAccountSurface(
            title: mode == .signIn ? "Welcome back." : "A little space for you two.",
            subtitle: mode == .signIn ? "Your shared life, right where you left it." : "Start with your own account. You can invite your partner or join them next.",
            closeLabel: "Close sign in", onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 28) {
                fields.disabled(busy)
                WEAccountFeedback()
                VStack(spacing: 12) {
                    WEAccountPrimaryButton(
                        title: mode.rawValue,
                        workingTitle: mode == .signIn ? "Signing in…" : "Creating your account…",
                        isWorking: busy, enabled: valid, identifier: "accountSubmitButton", action: submit
                    )
                    if mode == .signIn {
                        Button("Forgot password?") {
                            focus = nil
                            session.clearMessages()
                            showsReset = true
                        }
                        .font(.system(.subheadline)).frame(minHeight: 44)
                        .buttonStyle(.plain).disabled(busy)
                        .accessibilityIdentifier("account.forgotPassword")
                    } else {
                        Text("We may ask you to verify your email before you pair.")
                            .font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                FieldRuleLine(color: FieldRule.row)
                modeSwitch.disabled(busy)
            }
        }
        .sheet(isPresented: $showsReset) { PasswordResetView(email: $email) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil; WEAccountInput.dismissKeyboard() }
            }
        }
        .onChange(of: mode) { _, _ in session.clearMessages() }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 24) {
            if mode == .create {
                WEAccountTextField(label: "Your name", placeholder: "What should we call you?", text: $name,
                    field: .name, focus: $focus, contentType: .name, capitalization: .words,
                    onSubmit: { focus = .email })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
            }
            WEAccountTextField(label: "Email", placeholder: "you@example.com", text: $email,
                field: .email, focus: $focus, contentType: .emailAddress, keyboard: .emailAddress,
                problem: WEAccountInput.validEmail(email) ? nil : "Enter your email address, including the @.",
                onSubmit: { focus = .password })
            WEAccountTextField(label: "Password", placeholder: mode == .signIn ? "Your password" : "Choose a password", text: $password,
                field: .password, focus: $focus, secure: true,
                contentType: disablesCredentialPrompts ? nil : (mode == .signIn ? .password : .newPassword),
                submitLabel: mode == .signIn ? .go : .next,
                hint: mode == .create ? "At least 8 characters." : nil,
                problem: mode == .create && !password.isEmpty && password.count < 8 ? "Use at least 8 characters." : nil,
                onSubmit: { if mode == .signIn { submit() } else { focus = .confirmation } })
                .id(mode)
            if mode == .create {
                WEAccountTextField(label: "Confirm password", placeholder: "Once more", text: $confirmation,
                    field: .confirmation, focus: $focus, secure: true,
                    contentType: disablesCredentialPrompts ? nil : .newPassword, submitLabel: .go,
                    problem: password == confirmation ? nil : "These passwords don’t match yet.", onSubmit: submit)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
    }

    private var modeSwitch: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { modePrompt; modeButton }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) { modePrompt; modeButton }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var modePrompt: some View {
        Text(mode == .signIn ? "New to WE?" : "Already have an account?")
            .font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
    }
    private var modeButton: some View {
        Button(mode == .signIn ? "Create an account" : "Sign in") {
            focus = nil
            WEAccountInput.dismissKeyboard()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                mode = mode == .signIn ? .create : .signIn
            }
        }
        .font(.system(.subheadline, weight: .medium)).frame(minHeight: 44)
        .buttonStyle(.plain)
        .accessibilityIdentifier(mode == .signIn ? "account.mode.create" : "account.mode.signIn")
    }
    private var disablesCredentialPrompts: Bool {
        ProcessInfo.processInfo.environment["WE_DISABLE_CREDENTIAL_PROMPTS"] == "1"
    }
    private func submit() {
        guard valid, !busy else { return }
        let submittedMode = mode
        let submittedEmail = WEAccountInput.email(email)
        let submittedPassword = password
        let submittedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        submitting = true
        focus = nil
        WEAccountInput.dismissKeyboard()
        Task {
            defer { submitting = false }
            if submittedMode == .signIn {
                await session.signIn(email: submittedEmail, password: submittedPassword)
            } else {
                await session.signUp(name: submittedName, email: submittedEmail, password: submittedPassword)
            }
        }
    }
}

private struct PasswordResetView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String
    @State private var sentEmail: String?
    @State private var submitting = false
    @FocusState private var focus: WEAccountFocus?
    private var busy: Bool { submitting || session.isWorking }

    var body: some View {
        WEAccountSurface(
            title: sentEmail == nil ? "We'll send a link." : "Check your email.",
            subtitle: sentEmail == nil ? "A secure way back into your shared space." : "If there’s an account for this address, a reset link is on its way.",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 28) {
                if let sentEmail {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Reset link requested", systemImage: "checkmark.circle")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(FieldSwatch.sage.color(on: .cream))
                        Text(sentEmail).font(.system(.body)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("account.reset.sent")
                    WEAccountPrimaryButton(title: "Back to sign in", workingTitle: "", isWorking: false,
                        enabled: true, identifier: "account.reset.back", action: { dismiss() })
                    Button("Use a different email") { self.sentEmail = nil; session.clearMessages(); focus = .email }
                        .font(.system(.subheadline)).frame(minHeight: 44).buttonStyle(.plain)
                } else {
                    WEAccountTextField(label: "Email", placeholder: "you@example.com", text: $email,
                        field: .email, focus: $focus, contentType: .emailAddress, keyboard: .emailAddress,
                        submitLabel: .send, problem: WEAccountInput.validEmail(email) ? nil : "Enter your email address, including the @.",
                        onSubmit: send)
                        .disabled(busy)
                    WEAccountFeedback()
                    WEAccountPrimaryButton(title: "Send reset link", workingTitle: "Sending your link…", isWorking: busy,
                        enabled: WEAccountInput.validEmail(email), identifier: "sendResetLinkButton", action: send)
                    Text("Your plans and conversations stay as they are.")
                        .font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func send() {
        guard WEAccountInput.validEmail(email), !busy else { return }
        let address = WEAccountInput.email(email)
        focus = nil
        WEAccountInput.dismissKeyboard()
        submitting = true
        Task {
            defer { submitting = false }
            await session.sendPasswordReset(email: address)
            if session.errorMessage == nil { sentEmail = address }
        }
    }
}

struct NewPasswordView: View {
    @EnvironmentObject private var session: AppSession
    @State private var password = ""
    @State private var confirmation = ""
    @State private var submitting = false
    @FocusState private var focus: WEAccountFocus?
    private var busy: Bool { submitting || session.isWorking }

    var body: some View {
        WEAccountSurface(title: "Choose a new password.", subtitle: "Your recovery link is confirmed. Let’s get you back in.") {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 24) {
                    WEAccountTextField(label: "New password", placeholder: "Choose a password", text: $password,
                        field: .password, focus: $focus, secure: true, contentType: .newPassword,
                        hint: "At least 8 characters.",
                        problem: !password.isEmpty && password.count < 8 ? "Use at least 8 characters." : nil,
                        onSubmit: { focus = .confirmation })
                    WEAccountTextField(label: "Confirm new password", placeholder: "Once more", text: $confirmation,
                        field: .confirmation, focus: $focus, secure: true, contentType: .newPassword, submitLabel: .go,
                        problem: password == confirmation ? nil : "These passwords don’t match yet.", onSubmit: submit)
                }.disabled(busy)
                WEAccountFeedback()
                WEAccountPrimaryButton(title: "Update password", workingTitle: "Updating your password…", isWorking: busy,
                    enabled: WEAccountInput.validPassword(password, confirmation: confirmation), identifier: "updatePasswordButton", action: submit)
            }
        }
    }
    private func submit() {
        guard WEAccountInput.validPassword(password, confirmation: confirmation), !busy else { return }
        let value = password
        submitting = true
        focus = nil
        WEAccountInput.dismissKeyboard()
        Task {
            defer { submitting = false }
            await session.completePasswordRecovery(value)
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
