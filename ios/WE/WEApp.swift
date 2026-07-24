import SwiftUI

@main
struct WEApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(Palette.ink)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: Session
    @State private var splashDone = false
    @AppStorage("we-intro-seen") private var introSeen = false

    private var showSplash: Bool { !splashDone || session.status == .loading }

    var body: some View {
        ZStack {
            Palette.cream.ignoresSafeArea()

            if showSplash {
                SplashView(onDone: { splashDone = true })
            } else {
                switch session.status {
                case .loading:
                    SplashView(onDone: {})
                case .signedOut:
                    if introSeen { AuthView() } else { OnboardingView(onDone: { introSeen = true }) }
                case .needsCouple:
                    PairingView()
                case .ready:
                    MainTabView()
                }
            }
        }
        .task { await session.start() }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
        }
    }
}
