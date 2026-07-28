import SwiftUI

@main
struct WEApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var host: SessionHost
    @AppStorage("hasSeenLivingConfluencePromise")
    private var hasSeenPromise = false
    @State private var isReplayingPromise = false

    init() {
        _host = StateObject(wrappedValue: SessionHost())
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView {
                    isReplayingPromise = true
                }
                .environmentObject(host.session)
                .environmentObject(host)
                .accessibilityHidden(showsPromise)
                .allowsHitTesting(!showsPromise)

                if showsPromise {
                    LivingConfluencePromise {
                        hasSeenPromise = true
                        isReplayingPromise = false
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .animation(
                .weSettle(duration: 0.45, reduceMotion: reduceMotion),
                value: showsPromise
            )
            .task {
                await host.restore()
            }
            .onOpenURL { url in
                Task { await host.session.handleAuthCallback(url) }
            }
        }
    }

    private var showsPromise: Bool {
        if ProcessInfo.processInfo.environment["WE_SKIP_PROMISE"] == "1" {
            return false
        }
        return !hasSeenPromise || isReplayingPromise
    }
}
