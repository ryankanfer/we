//
//  FieldAccountView.swift
//  WE
//
//  The account surface, reached by long-pressing the WE mark.
//
//  The handoff specifies eleven screens and none of them is settings — every
//  surface it draws is the product. So this is new, and it is deliberately
//  the smallest thing that is honest: who you are, what the app is allowed to
//  notice, and how to leave. Anything else belongs in a zone.
//
//  It carries no navigation chrome of its own beyond a close action, because
//  the handoff forbids a tab bar and this is not an exception to that.
//

import SwiftUI

@MainActor
struct FieldAccountView: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var showsDelete = false

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    identity
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    noticing
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    leaving
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.account")
        .overlay(alignment: .topTrailing) { closeButton }
        .fullScreenCover(isPresented: $showsDelete) {
            FieldDeleteAccountView()
                .environmentObject(session)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .textCase(.uppercase)
                .foregroundStyle(.fieldInk(.recessive))
                .padding(18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.account.done")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldLabel("Account")

            Text(store.identity.name(for: .shared))
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Your colours")
                .padding(.top, 20)
                .padding(.bottom, 6)

            Text(
                "Anything of \(store.identity.nameA)'s is one colour, anything "
                    + "of \(store.identity.nameB)'s is the other, and anything "
                    + "you share is both."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)

            FieldSwatchRow(owner: .a, identity: store.identity) { swatch in
                store.choose(swatch, for: .a)
            }
            .padding(.bottom, FieldMetrics.sectionGap)

            FieldSwatchRow(owner: .b, identity: store.identity) { swatch in
                store.choose(swatch, for: .b)
            }
        }
    }

    // MARK: What the app is allowed to notice

    private var noticing: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("How WE notices")
                .padding(.top, 20)
                .padding(.bottom, 6)

            Text(
                "I only read what you both allow. Private reflection is "
                    + "outside the intelligence entirely, and stays that way."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)

            ForEach(SignalKind.allCases, id: \.self) { signal in
                signalToggle(signal)
            }
        }
    }

    private func signalToggle(_ signal: SignalKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { isEnabled(signal) },
                set: { value in
                    Task { await session.setSignalConsent(signal, enabled: value) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(signal.title)
                    .font(FieldType.listItem)
                    .foregroundStyle(.fieldInk(.legend))

                Text(signal.detail)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.5, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(store.identity.personA.color)
        .disabled(signal.isPermanentlyDisabled || !session.canMutate)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
        .accessibilityIdentifier("field.account.signal.\(signal.rawValue)")
    }

    /// Permanently-disabled signals read as off regardless of what is stored —
    /// private reflection is never an input, and the control says so by being
    /// off and untouchable rather than by a caveat underneath it.
    private func isEnabled(_ signal: SignalKind) -> Bool {
        guard !signal.isPermanentlyDisabled else { return false }
        return session.v2State.signalConsents.first {
            $0.profileID == session.user?.id && $0.signal == signal
        }?.isEnabled ?? true
    }

    // MARK: Leaving

    private var leaving: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Leaving")
                .padding(.top, 20)
                .padding(.bottom, 18)

            Button("Sign out") {
                // Nothing should be waiting for someone who has left.
                FieldMomentDelivery.cancel()
                Task { await session.signOut() }
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(session.isWorking)
            .accessibilityIdentifier("field.account.signOut")
            .padding(.bottom, 14)

            Button("Delete account") {
                showsDelete = true
            }
            .buttonStyle(FieldQuietButtonStyle())
            .accessibilityIdentifier("field.account.delete")

            FieldSessionMessage()
        }
    }
}

/// Whatever the session last failed at, in the app's own voice. Italic,
/// because the app is speaking rather than labelling.
@MainActor
private struct FieldSessionMessage: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if let message = session.errorMessage {
            Text(message)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }
}

// MARK: - Deletion
//
// Two steps, and neither is decorative. Apple requires account deletion to be
// reachable in-app; the product requires it to be hard to do by accident,
// because it ends a relationship's record and not just a login.

@MainActor
struct FieldDeleteAccountView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmation = ""
    @State private var asksFinalConfirmation = false

    private var canDelete: Bool {
        !password.isEmpty && confirmation == "DELETE" && session.canMutate
    }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    warning
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    fields
                        .padding(.bottom, FieldMetrics.sectionGap)

                    actions
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.account.delete.screen")
        .confirmationDialog(
            "Delete your account and end this relationship?",
            isPresented: $asksFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                Task { await session.deleteAccount(password: password) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There is no recovery for your account or private data.")
        }
        .onChange(of: session.state) { _, state in
            if state == .signedOut { dismiss() }
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Delete account")
                .padding(.bottom, 18)

            Text("This cannot be undone.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            Text(
                "Your private reflections, answers, approaches, and dismissals "
                    + "go with it. They were never in your partner's archive "
                    + "and they will not be left there now."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Delete my account") {
                asksFinalConfirmation = true
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.4)
            .accessibilityIdentifier("field.account.delete.confirm")
            .padding(.bottom, 14)

            Button("Not yet") { dismiss() }
                .buttonStyle(FieldQuietButtonStyle())
                .accessibilityIdentifier("field.account.delete.decline")

            FieldSessionMessage()
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            SecureField("Current password", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("field.account.delete.password")

            TextField("Type DELETE", text: $confirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("field.account.delete.confirmation")
        }
        .font(FieldType.listItem)
        .foregroundStyle(.fieldInk(.headline))
        .textFieldStyle(.plain)
        .padding(16)
        .background(
            FieldPalette.ink.opacity(0.06),
            in: RoundedRectangle(
                cornerRadius: FieldMetrics.cardRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: FieldMetrics.cardRadius,
                style: .continuous
            )
            .stroke(FieldRule.primary, lineWidth: 1)
        }
    }
}
