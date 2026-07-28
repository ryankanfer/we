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
    }

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var host: SessionHost
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
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }
}
