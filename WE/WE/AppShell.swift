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
            case .we: "person.2.fill"
            case .life: "house.fill"
            case .ahead: "arrow.forward.circle.fill"
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
    @EnvironmentObject private var host: SessionHost
    @Environment(\.visualEngine) private var visualEngine
    @State private var selection: Destination = {
        switch ProcessInfo.processInfo.environment["WE_START_DESTINATION"] {
        case "life": .life
        case "ahead": .ahead
        default: .we
        }
    }()
    @State private var showsProfile = false
    @State private var showsThread =
        ProcessInfo.processInfo.environment[
            "WE_START_DESTINATION"
        ] == "thread"
    let onReplayPromise: () -> Void

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                WEView { showsProfile = true }
            }
            .tabItem {
                Label(
                    Destination.we.title,
                    systemImage: Destination.we.systemImage
                )
            }
            .tag(Destination.we)

            NavigationStack {
                LifeView { showsProfile = true }
            }
            .tabItem {
                Label(
                    Destination.life.title,
                    systemImage: Destination.life.systemImage
                )
            }
            .tag(Destination.life)

            if session.hasUnlockedAhead {
                NavigationStack {
                    AheadView { showsProfile = true }
                }
                .tabItem {
                    Label(
                        Destination.ahead.title,
                        systemImage: Destination.ahead.systemImage
                    )
                }
                .tag(Destination.ahead)
            }

        }
        .tint(personalHue.controlColor)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.regularMaterial, for: .tabBar)
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
        .fullScreenCover(isPresented: $showsThread) {
            NavigationStack {
                ThreadView { showsThread = false }
            }
            .preferredColorScheme(.dark)
        }
        .overlay(alignment: .top) {
            if session.hasUnlockedThread {
                ThreadPullHandle { showsThread = true }
                    .padding(.top, host.mode == .simulation ? 34 : 4)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .preferredColorScheme(.dark)
        // A tab that is not selected keeps its view tree alive and never
        // receives onDisappear, so no destination can work out on its own
        // that it is off screen. The shell is the only place that knows.
        .onChange(of: selection, initial: true) { _, destination in
            visualEngine?.visibleSurface = destination.surface
        }
        .onChange(of: showsProfile, initial: true) { _, _ in
            syncModalDepth()
        }
        .onChange(of: showsThread) { _, _ in
            syncModalDepth()
        }
    }

    private func syncModalDepth() {
        visualEngine?.modalDepth =
            (showsProfile ? 1 : 0) + (showsThread ? 1 : 0)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }
}
