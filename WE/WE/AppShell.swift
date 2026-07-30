import Combine
import SwiftUI

struct AppShell: View {
    enum Destination: Hashable, CaseIterable {
        case we
        case life
        case ahead

        var title: String {
            switch self {
            case .we: "Today"
            case .life: "Life"
            case .ahead: "Us"
            }
        }

        var surface: VisualEngineCoordinator.Surface {
            switch self {
            case .we: .we
            case .life: .life
            case .ahead: .ahead
            }
        }
    }

    @EnvironmentObject private var session: AppSession
    @Environment(\.visualEngine) private var visualEngine
    @State private var selection: Destination = {
        switch ProcessInfo.processInfo.environment["WE_START_DESTINATION"] {
        case "life": .life
        case "ahead", "us", "thread": .ahead
        default: .we
        }
    }()
    @State private var showsProfile = false
    let onReplayPromise: () -> Void

    var body: some View {
        ZStack {
            NavigationStack {
                WEView { showsProfile = true }
            }
            .zIndex(selection == .we ? 1 : 0)
            .opacity(selection == .we ? 1 : 0)
            .allowsHitTesting(selection == .we)
            .accessibilityHidden(selection != .we)

            NavigationStack {
                LifeView { showsProfile = true }
            }
            .zIndex(selection == .life ? 1 : 0)
            .opacity(selection == .life ? 1 : 0)
            .allowsHitTesting(selection == .life)
            .accessibilityHidden(selection != .life)

            NavigationStack {
                ThreadView(
                    onClose: nil,
                    onProfile: { showsProfile = true }
                )
            }
            .zIndex(selection == .ahead ? 1 : 0)
            .opacity(selection == .ahead ? 1 : 0)
            .allowsHitTesting(selection == .ahead)
            .accessibilityHidden(selection != .ahead)
        }
        .tint(personalHue.controlColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorialTabBar
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                SimulationMarker()
                if session.connectionState != .online {
                    ConnectionBanner()
                }
            }
        }
        .sheet(isPresented: $showsProfile) {
            ProfileView(onReplayPromise: onReplayPromise)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .preferredColorScheme(.dark)
        // All three destinations stay mounted to preserve their navigation
        // and scroll state. The shell is the only place that knows which one
        // is actually visible.
        .onChange(of: selection, initial: true) { _, destination in
            visualEngine?.visibleSurface = destination.surface
        }
        .onChange(of: showsProfile, initial: true) { _, _ in
            syncModalDepth()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WEDeepLinkRouter.didRequestToday
            )
        ) { _ in
            selection = .we
        }
    }

    private func syncModalDepth() {
        visualEngine?.modalDepth = showsProfile ? 1 : 0
    }

    private var editorialTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Destination.allCases, id: \.self) { destination in
                Button {
                    selection = destination
                } label: {
                    VStack(spacing: 6) {
                        Text(destination.title)
                            .font(.subheadline.weight(
                                selection == destination ? .semibold : .regular
                            ))
                            .foregroundStyle(
                                selection == destination
                                    ? personalHue.controlColor
                                    : Color.weInkTertiary
                            )

                        Circle()
                            .fill(personalHue.controlColor)
                            .frame(width: 4, height: 4)
                            .opacity(selection == destination ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selection == destination ? .isSelected : []
                )
                .accessibilityHint("Opens \(destination.title)")
                .accessibilityIdentifier("primaryTab.\(destination.title)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .background {
            LinearGradient(
                colors: [
                    Color.weCanvas.opacity(0.02),
                    Color.weCanvas.opacity(0.68),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }
}
