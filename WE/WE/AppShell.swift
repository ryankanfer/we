import SwiftUI

struct AppShell: View {
    enum Destination: Hashable {
        case we
        case life
        case ahead
    }

    @EnvironmentObject private var session: AppSession
    @State private var selection: Destination = .we
    @State private var showsProfile = false
    let onReplayPromise: () -> Void

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                WEView { showsProfile = true }
            }
            .tabItem { Label("WE", systemImage: "person.2.fill") }
            .tag(Destination.we)

            NavigationStack {
                LifeView { showsProfile = true }
            }
            .tabItem { Label("Life", systemImage: "house.fill") }
            .tag(Destination.life)

            NavigationStack {
                AheadView { showsProfile = true }
            }
            .tabItem { Label("Ahead", systemImage: "arrow.forward.circle.fill") }
            .tag(Destination.ahead)
        }
        .tint(Color("WEBurgundy"))
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.connectionState != .online {
                ConnectionBanner()
            }
        }
        .sheet(isPresented: $showsProfile) {
            ProfileView(onReplayPromise: onReplayPromise)
        }
    }
}
