import SwiftUI

struct SignInView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: String { rawValue }
    }

    /// One question per screen. Big enough to read at arm's length, and
    /// never more than one thing to get right at a time.
    private enum Question: Hashable {
        case name, email, password
    }

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pendingInvitation: PendingInvitation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode
    @State private var question: Question
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showsReset = false
    @State private var submitting = false
    @State private var revealed = false
    @FocusState private var focus: WEAccountFocus?

    init(initialMode: Mode = .signIn) {
        _mode = State(initialValue: initialMode)
        _question = State(initialValue: initialMode == .create ? .name : .email)
    }

    private var busy: Bool { submitting || session.isWorking }

    private var questions: [Question] {
        mode == .create ? [.name, .email, .password] : [.email, .password]
    }

    private var isLast: Bool { question == questions.last }

    private var answerIsValid: Bool {
        switch question {
        case .name: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .email: WEAccountInput.validEmail(email)
        case .password: mode == .create ? password.count >= 8 : !password.isEmpty
        }
    }

    var body: some View {
        ZStack {
            WECanvas.surface.bg.ignoresSafeArea()
            WELights(identity: .seed, pose: .apart)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("WE")
                        .font(FieldType.mark)
                        .tracking(FieldTracking.mark * 1.4)
                        .accessibilityHidden(true)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .regular))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("account.close")
                }
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(kicker.uppercased())
                            .font(FieldType.mark)
                            .tracking(2.6)
                            .foregroundStyle(.fieldInk(.label))
                            .padding(.top, 28)
                            .padding(.bottom, 12)

                        WEWordReveal(text: prompt, font: FieldType.hero(44), tracking: -0.8)
                            .accessibilityAddTraits(.isHeader)
                            .id(prompt)

                        if let line = promptLine {
                            Text(line)
                                .font(FieldType.hero(18))
                                .foregroundStyle(.fieldInk(.reasoning))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 12)
                                .weArrival(delay: 0.3)
                        }

                        field
                            .padding(.top, 30)
                            .id(question)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 18)))

                        WEAccountFeedback()
                            .padding(.top, 14)
                    }
                    .frame(maxWidth: 440, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 12) {
                    WEAccountPrimaryButton(
                        title: isLast ? mode.rawValue : "Continue",
                        workingTitle: mode == .signIn ? "Signing in\u{2026}" : "Creating your account\u{2026}",
                        isWorking: busy,
                        enabled: answerIsValid,
                        identifier: "accountSubmitButton",
                        action: advance
                    )
                    footerLinks
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, FirstRunMetrics.side)
        }
        .foregroundStyle(.fieldInk(.headline))
        .environment(\.weCanvas, .surface)
        .preferredColorScheme(WETheme.shared.colorScheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.9), value: question)
        .sheet(isPresented: $showsReset) { PasswordResetView(email: $email) }
        .onAppear { focus = focusTarget(question) }
        .onChange(of: question) { _, next in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focus = focusTarget(next) }
        }
        .onChange(of: mode) { _, _ in session.clearMessages() }
        .sensoryFeedback(.selection, trigger: question)
    }

    // MARK: The words

    private var kicker: String {
        switch mode {
        case .signIn: return question == .password ? WEAccountInput.email(email) : "Sign in"
        case .create:
            let index = (questions.firstIndex(of: question) ?? 0) + 1
            return "\(index) of \(questions.count)"
        }
    }

    private var inviter: String? {
        pendingInvitation.code == nil ? nil : pendingInvitation.inviterName
    }

    private var prompt: String {
        switch (mode, question) {
        case (.signIn, .email): "Welcome back."
        case (.signIn, _): "And your password."
        case (.create, .name): inviter.map { "What should \($0) call you?" } ?? "First, you. What\u{2019}s your name?"
        case (.create, .email): "Your email."
        case (.create, .password): "Pick a password."
        }
    }

    private var promptLine: String? {
        switch (mode, question) {
        case (.signIn, .email): "Today and Life are right where you left them."
        case (.create, .name): WEGateCopy.createDetail(joining: inviter)
        case (.create, .password): "You\u{2019}ll get one email to confirm it\u{2019}s you."
        default: nil
        }
    }

    // MARK: The field

    @ViewBuilder
    private var field: some View {
        switch question {
        case .name:
            answer(label: "Your name", placeholder: "First name", text: $name, target: .name,
                   contentType: .givenName, capitalization: .words)
        case .email:
            answer(label: "Email", placeholder: "you@example.com", text: $email, target: .email,
                   contentType: .emailAddress, keyboard: .emailAddress,
                   problem: !email.isEmpty && !WEAccountInput.validEmail(email) ? "Include the @ and the part after it." : nil)
        case .password:
            answer(label: "Password", placeholder: mode == .create ? "8 or more characters" : "Your password",
                   text: $password, target: .password,
                   contentType: disablesCredentialPrompts ? nil : (mode == .signIn ? .password : .newPassword),
                   secure: true,
                   problem: mode == .create && !password.isEmpty && password.count < 8 ? "A little longer: at least 8 characters." : nil)
        }
    }

    private func answer(
        label: String,
        placeholder: String,
        text: Binding<String>,
        target: WEAccountFocus,
        contentType: UITextContentType?,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .never,
        secure: Bool = false,
        problem: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(FieldType.mark)
                    .tracking(1.8)
                    .foregroundStyle(.fieldInk(.label))
                HStack(spacing: 8) {
                    Group {
                        if secure && !revealed {
                            SecureField(placeholder, text: text)
                        } else {
                            TextField(placeholder, text: text)
                        }
                    }
                    .font(FieldType.hero(24))
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .privacySensitive(secure)
                    .focused($focus, equals: target)
                    .submitLabel(isLast ? .go : .next)
                    .onSubmit(advance)
                    .tint(FieldIdentity.seed.personA.color(on: .surface))
                    .frame(minHeight: 40)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("account.field.\(target.rawValue)")

                    if secure {
                        Button {
                            focus = nil
                            revealed.toggle()
                            DispatchQueue.main.async { focus = target }
                        } label: {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .font(.system(size: 17))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .accessibilityLabel(revealed ? "Hide password" : "Show password")
                        .accessibilityIdentifier("account.password.visibility")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .weGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if let problem {
                Text(problem)
                    .font(.system(.footnote))
                    .foregroundStyle(FieldSwatch.rust.color(on: .surface))
                    .padding(.leading, 6)
                    .accessibilityIdentifier("account.\(target.rawValue).hint")
            }
        }
    }

    // MARK: Links under the button

    @ViewBuilder
    private var footerLinks: some View {
        let first = question == questions.first
        HStack(spacing: 16) {
            if !first {
                Button("Back") { step(-1) }
                    .accessibilityIdentifier("account.back")
            }
            if mode == .signIn {
                Button("Forgot password?") {
                    focus = nil
                    session.clearMessages()
                    showsReset = true
                }
                .accessibilityIdentifier("account.forgotPassword")
            }
            if first {
                if mode == .signIn {
                    Button("New here? Create an account") { switchMode(.create) }
                        .accessibilityIdentifier("account.mode.create")
                } else {
                    Button("Have an account? Sign in") { switchMode(.signIn) }
                        .accessibilityIdentifier("account.mode.signIn")
                }
            }
        }
        .font(.system(.subheadline, weight: .medium))
        .foregroundStyle(.fieldInk(.reasoning))
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .disabled(busy)
    }

    // MARK: Moving

    private func focusTarget(_ question: Question) -> WEAccountFocus {
        switch question {
        case .name: .name
        case .email: .email
        case .password: .password
        }
    }

    private func step(_ delta: Int) {
        guard let index = questions.firstIndex(of: question) else { return }
        let next = index + delta
        guard questions.indices.contains(next) else { return }
        session.clearMessages()
        question = questions[next]
    }

    private func switchMode(_ next: Mode) {
        focus = nil
        mode = next
        question = next == .create ? .name : .email
    }

    private func advance() {
        guard answerIsValid, !busy else { return }
        if isLast { submit() } else { step(1) }
    }

    private var disablesCredentialPrompts: Bool {
        ProcessInfo.processInfo.environment["WE_DISABLE_CREDENTIAL_PROMPTS"] == "1"
    }

    private func submit() {
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
            subtitle: sentEmail == nil ? "A secure way back in." : "If there’s an account for this address, a reset link is on its way.",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 28) {
                if let sentEmail {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Reset link requested", systemImage: "checkmark.circle")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(FieldSwatch.sage.color(on: .surface))
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
                    Text("Everything in Today and Life stays as it is.")
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
        .environmentObject(PendingInvitation())
}
