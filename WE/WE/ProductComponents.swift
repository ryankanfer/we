import SwiftUI

struct ProductHeader: View {
    let eyebrow: String
    let title: String
    let profileName: String
    let onProfile: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.weMeta)
                    .tracking(1.4)
                    .foregroundStyle(Color("WEFaint"))
                Text(title)
                    .font(.weLargeTitle)
                    .foregroundStyle(Color("WEInk"))
            }
            Spacer(minLength: 8)
            Button(action: onProfile) {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color("WEBurgundy"), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Profile")
            .accessibilityHint("Account, appearance, archives, and privacy")
            .accessibilityIdentifier("profileButton")
        }
    }

    private var initials: String {
        let parts = profileName.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "ME" : value.uppercased()
    }
}

struct WarmEditorialBackground: View {
    @EnvironmentObject private var session: AppSession

    /// Life and Ahead share the WE canvas exactly — same base, same two
    /// washes, same confluence. Previously this and `WEAtmosphere` were
    /// different compositions, so moving between tabs read as moving between
    /// products rather than around one home.
    var body: some View {
        ZStack {
            Color.weCanvas

            RadialGradient(
                colors: [personalHue.atmosphereColor.opacity(0.22), .clear],
                center: .init(x: 0.12, y: -0.10),
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [partnerHue.atmosphereColor.opacity(0.16), .clear],
                center: .init(x: 0.92, y: 0.10),
                startRadius: 0,
                endRadius: 580
            )

            WEConfluenceForm(
                personalHue: personalHue,
                partnerHue: partnerHue,
                connection: session.presenceMode == .together ? 1 : 0.72
            )
            .opacity(0.34)
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        relationshipPartnerHue(session)
    }
}

struct EditorialEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color("WEBurgundy"))
                .accessibilityHidden(true)
            Text(title).font(.weTitle)
            Text(message)
                .font(.weSubheadline)
                .foregroundStyle(Color("WEFaint"))
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(WESecondaryButtonStyle(tintColor: Color("WEBurgundy")))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }
}

struct ConnectionBanner: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.connectionState == .reconnecting ? "arrow.triangle.2.circlepath" : "wifi.slash")
            Text(message)
                .font(.footnote.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 38)
        .background(.thinMaterial)
        .foregroundStyle(Color("WEInk"))
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if session.connectionState == .reconnecting { return "Reconnecting…" }
        guard let cachedAt = session.cachedAt else { return "Offline · changes are paused" }
        return "Offline · last synced \(cachedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// The answering surface.
///
/// This replaces two separate radio lists — one in `SharedMomentPage`, one in
/// `InsightDetailView` — that each drew every option as an identically
/// weighted rounded rect with a `circle` / `checkmark.circle.fill` on the
/// right. Five equally loud plates read as a form to fill in rather than a
/// question being asked.
///
/// Unanswered options are hairline-separated serif lines with no container at
/// all. Only the chosen one takes a surface, lifting onto a plate in the
/// person's own hue. Quiet by default, one clear moment of commitment.
struct WEAnswerOptions: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let options: [String]
    let hue: WEHue
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                row(option, showsRule: showsRule(after: index))
            }
        }
    }

    private func row(_ option: String, showsRule: Bool) -> some View {
        let isSelected = selection == option

        return Button {
            withAnimation(.weSettle(duration: 0.3, reduceMotion: reduceMotion)) {
                selection = option
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                // A gutter mark rather than a control. Nothing to "tick" —
                // the line itself is the answer.
                Circle()
                    .fill(isSelected ? Color.white : .clear)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle().stroke(
                            isSelected ? .clear : Color.weHairline,
                            lineWidth: 1
                        )
                    }
                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.85 }

                Text(option)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(isSelected ? Color.weInk : Color.weInkTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, isSelected ? 16 : 2)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        // `color` would fail AA on the five light hues —
                        // pearl lands at 2.51:1. `atmosphereColor` deepens
                        // those, and holds every hue above 6.2:1.
                        .fill(hue.atmosphereColor.opacity(0.65))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.42), lineWidth: 1)
                        }
                        .shadow(
                            color: hue.atmosphereColor.opacity(0.5),
                            radius: 13,
                            y: 6
                        )
                }
            }
            .overlay(alignment: .bottom) {
                if showsRule {
                    Rectangle()
                        .fill(Color.weHairline)
                        .frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WEPressableCardStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// No rule beneath the last row, and none touching a lifted plate.
    private func showsRule(after index: Int) -> Bool {
        guard index < options.count - 1 else { return false }
        return selection != options[index] && selection != options[index + 1]
    }
}

struct ProductSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.weCaption)
                .tracking(1.35)
                .foregroundStyle(Color("WEFaint"))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Color("WEFaint"))
            }
        }
    }
}
