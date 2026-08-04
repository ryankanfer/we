//
//  FieldGateScaffold.swift
//  WE
//
//  The screens before a couple exists, drawn in the app's own language.
//
//  Sign in, verification, recovery, pairing — none of these are zones, so they
//  do not get `FieldZoneScaffold`, which carries a zone label and a nav bar's
//  worth of bottom padding. They get this instead: the same background, the
//  same ambient, the same margins, the same dark.
//
//  Until this existed the gates were still drawn in DesignSystem.swift's cream
//  — the collapse in `WESplashView` landed on a deep green mark and handed over
//  to a light screen, which reads as two applications. See the header of
//  FieldTokens.swift: "Both exist side by side only while the zones are
//  migrated; Field* is the destination."
//
//  There is nobody to be yet, so the ambient and every tint here come from
//  `FieldIdentity.seed` — the brand pair — for the same reason `WEApp` passes
//  no identity to the splash before a snapshot loads.
//

import SwiftUI

struct FieldGateScaffold<Content: View>: View {
    /// The mono label above the headline. Optional: the loading gate has
    /// nothing to say and should not invent a heading to fill the space.
    var label: String?
    /// Centred vertically rather than pinned to the top. The gates are short
    /// and a headline hanging under the status bar reads as a page that failed
    /// to load the rest of itself.
    var centred = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            FieldAmbient(
                identity: .seed,
                hour: Calendar.gregorianUS.component(.hour, from: Date())
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let label {
                        FieldLabel(label)
                            .padding(.bottom, 24)
                    }

                    content
                }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
                .frame(
                    minHeight: centred ? FieldMetrics.referenceDevice.height : 0,
                    alignment: centred ? .center : .top
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - A gate's headline

/// The serif statement and its supporting line. Every gate opens with one, and
/// they are the same two sizes on all of them.
struct FieldGateHeadline: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - A gate's text field
//
// A hairline under the text, never a rounded border. `.roundedBorder` is
// UIKit's grey capsule and the only place it appeared in the app was here.

struct FieldTextField: View {
    let label: String
    @Binding var text: String
    /// `nil` for a plain field; otherwise a `SecureField`.
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var identifier: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FieldLabel(
                label,
                font: FieldType.subLabel,
                tracking: FieldTracking.subLabel,
                color: .fieldInk(.monoLabelQuiet),
                isHeader: false
            )

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .font(FieldType.captureInput)
            .foregroundStyle(.fieldInk(.headline))
            .tint(FieldIdentity.seed.personA.color)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .focused($isFocused)
            .accessibilityLabel(label)
            // Applied only when there is one. An empty identifier is not the
            // absence of an identifier — it is a query that matches nothing,
            // which is worse than the default the platform would have given.
            .modifier(FieldOptionalIdentifier(identifier))

            Rectangle()
                .fill(
                    isFocused
                        ? FieldIdentity.seed.personA.color.opacity(0.7)
                        : FieldRule.row
                )
                .frame(height: 1)
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

struct FieldOptionalIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

#Preview("Gate") {
    FieldGateScaffold(label: "Account") {
        VStack(alignment: .leading, spacing: 30) {
            FieldGateHeadline(
                title: "Welcome back.",
                subtitle: "Return to your shared space."
            )

            FieldTextField(
                label: "Email",
                text: .constant("ryan@example.com"),
                contentType: .emailAddress,
                keyboard: .emailAddress,
                autocapitalization: .never
            )

            Button("Sign in") {}
                .buttonStyle(FieldFilledButtonStyle())
        }
    }
}
