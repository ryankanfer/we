import SwiftUI

/// The account surfaces share Life’s paper, the editorial type and the WE
/// lens. Content scrolls independently of the close control and keyboard.
struct WEAccountSurface<Content: View>: View {
    let title: String
    let subtitle: String
    var closeLabel = "Done"
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                WELens(diameter: 44, foreground: WECanvas.cream.ink)
                    .scaleEffect(arrived || reduceMotion ? 1 : 0.92)
                Text("WE").font(.system(.subheadline, weight: .medium)).tracking(2)
                    .accessibilityLabel("WE")
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .regular))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(closeLabel)
                    .accessibilityIdentifier("account.close")
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(FieldType.hero)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle).font(.system(.body))
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .modifier(WEAccountArrival(visible: arrived, delay: 0))

                    content
                        .modifier(WEAccountArrival(visible: arrived, delay: 0.08))
                }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(WECanvas.cream.bg.ignoresSafeArea())
        .foregroundStyle(.fieldInk(.headline))
        .environment(\.weCanvas, .cream).preferredColorScheme(.light)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { arrived = true }
        }
    }
}

private struct WEAccountArrival: ViewModifier {
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(delay), value: visible)
    }
}

enum WEAccountFocus: String { case name, email, password, confirmation }

struct WEAccountTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let field: WEAccountFocus
    var focus: FocusState<WEAccountFocus?>.Binding
    var secure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var hint: String?
    var problem: String?
    var onSubmit: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var revealed = false
    @State private var hasEdited = false

    private var isFocused: Bool { focus.wrappedValue == field }
    private var visibleProblem: String? { hasEdited ? problem : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.fieldInk(.reasoning))
            HStack(spacing: 8) {
                Group {
                    if secure && !revealed { SecureField(placeholder, text: $text) }
                    else { TextField(placeholder, text: $text) }
                }
                .font(.system(.title3))
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .privacySensitive(secure)
                .focused(focus, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .tint(FieldIdentity.seed.personA.color(on: .cream))
                .frame(minHeight: 44)
                .accessibilityLabel(label)
                .accessibilityIdentifier("account.field.\(field.rawValue)")

                if secure {
                    Button {
                        // The secure and revealed controls have distinct UIKit
                        // responders. Restore focus after SwiftUI swaps them.
                        focus.wrappedValue = nil
                        revealed.toggle()
                        DispatchQueue.main.async { focus.wrappedValue = field }
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 19)).frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .accessibilityLabel((revealed ? "Hide " : "Show ") + label.lowercased())
                    .accessibilityIdentifier("account.\(field.rawValue).visibility")
                }
            }
            Rectangle().fill(FieldRule.row.color(on: .cream)).frame(height: 1)
                .overlay {
                    Rectangle().fill(FieldIdentity.seed.personA.color(on: .cream))
                        .frame(height: 2).opacity(isFocused ? 1 : 0)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFocused)

            if let message = visibleProblem ?? hint {
                Text(message).font(.system(.footnote))
                    .foregroundStyle(visibleProblem != nil ? FieldSwatch.rust.color(on: .cream) : WECanvas.cream.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account.\(field.rawValue).hint")
            }
        }
        .onChange(of: focus.wrappedValue) { previous, current in
            if previous == field && current != field && !text.isEmpty { hasEdited = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealed = false }
        }
    }
}

struct WEAccountPrimaryButton: View {
    let title: String
    let workingTitle: String
    let isWorking: Bool
    let enabled: Bool
    let identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isWorking { ProgressView().tint(WECanvas.cream.bg) }
                Text(isWorking ? workingTitle : title)
                    .fixedSize(horizontal: false, vertical: true)
                if !isWorking { Image(systemName: "arrow.right").font(.system(size: 18)) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(WEAccountButtonStyle())
        .disabled(!enabled || isWorking)
        .accessibilityIdentifier(identifier)
    }
}

private struct WEAccountButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, weight: .medium))
            .foregroundStyle(WECanvas.cream.bg)
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(WECanvas.cream.ink, in: RoundedRectangle(cornerRadius: 16))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct WEAccountFeedback: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if let message = session.errorMessage ?? session.noticeMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: session.errorMessage == nil ? "info.circle" : "exclamationmark.circle")
                    .font(.system(size: 18)).padding(.top, 2)
                Text(message).font(.system(.subheadline)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account.feedback")
            .onAppear {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
            .onChange(of: message) { _, value in
                UIAccessibility.post(notification: .announcement, argument: value)
            }
        }
    }
}

enum WEAccountInput {
    static func email(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func validEmail(_ value: String) -> Bool {
        let value = email(value)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
            && !value.contains(where: \.isWhitespace)
    }
    static func validSignIn(email: String, password: String) -> Bool {
        validEmail(email) && !password.isEmpty
    }
    static func validCreation(name: String, email: String, password: String, confirmation: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validEmail(email) && validPassword(password, confirmation: confirmation)
    }
    static func validPassword(_ password: String, confirmation: String) -> Bool {
        password.count >= 8 && password == confirmation
    }
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
