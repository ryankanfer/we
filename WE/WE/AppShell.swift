import SwiftUI

struct AppShell: View {
    enum Destination: Hashable, CaseIterable {
        case we
        case life
        case ahead

        var title: String {
            switch self {
            case .we: "WE"
            case .life: "Life"
            case .ahead: "Ahead"
            }
        }

        var systemImage: String {
            switch self {
            case .we: "sparkles"
            case .life: "hands.and.sparkles"
            case .ahead: "arrow.forward.circle"
            }
        }
    }

    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Destination = .we
    @State private var showsProfile = false
    let onReplayPromise: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selection {
                case .we:
                    NavigationStack {
                        WEView { showsProfile = true }
                    }
                case .life:
                    NavigationStack {
                        LifeView { showsProfile = true }
                    }
                case .ahead:
                    NavigationStack {
                        AheadView { showsProfile = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.connectionState != .online {
                ConnectionBanner()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingTabBar
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        }
        .sheet(isPresented: $showsProfile) {
            ProfileView(onReplayPromise: onReplayPromise)
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 6) {
            ForEach(Destination.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.weSettle(duration: 0.35, reduceMotion: reduceMotion)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .bold))

                        if selection == tab {
                            Text(tab.title)
                                .font(.subheadline.weight(.bold))
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .foregroundStyle(selection == tab ? .white : Color("WEInk").opacity(0.6))
                    .padding(.horizontal, selection == tab ? 18 : 14)
                    .padding(.vertical, 10)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(personalHue.controlColor)
                                .shadow(color: personalHue.color.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(
            .ultraThinMaterial,
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }
}
