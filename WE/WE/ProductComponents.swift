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
                    .font(.weCaption)
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

    var body: some View {
        ZStack {
            Color.weCinematicInk
            LinearGradient(
                colors: [
                    personalHue.atmosphereColor.opacity(0.14),
                    .clear,
                    partnerHue.atmosphereColor.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            WEConfluenceForm(
                personalHue: personalHue,
                partnerHue: partnerHue,
                connection: session.presenceMode == .together ? 1 : 0.72
            )
            .opacity(0.12)
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
                .font(.weBody)
                .foregroundStyle(Color("WEFaint"))
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(Color("WEBurgundy"))
                    .frame(minHeight: 44)
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
