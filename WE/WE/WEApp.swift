import SwiftUI

@main
struct WEApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var host: SessionHost
    @State private var visualEngine = VisualEngineCoordinator()
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
            .environment(\.visualEngine, visualEngine)
            .animation(
                .weSettle(duration: 0.45, reduceMotion: reduceMotion),
                value: showsPromise
            )
            // The Promise sits above everything, so it owns the screen while
            // it is up — anything underneath must stop drawing.
            .onChange(of: showsPromise, initial: true) { _, shows in
                visualEngine.visibleSurface = shows ? .promise : .we
            }
            // These live in the environment, not in ProcessInfo, so they have
            // to be pushed down rather than read from the coordinator.
            .onChange(of: reduceMotion, initial: true) { _, _ in
                syncAccessibility()
            }
            .onChange(of: reduceTransparency) { _, _ in
                syncAccessibility()
            }
            .task {
                await host.restore()
            }
            .onOpenURL { url in
                Task { await host.session.handleAuthCallback(url) }
            }
        }
    }

    private func syncAccessibility() {
        visualEngine.setAccessibility(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }

    private var showsPromise: Bool {
        if ProcessInfo.processInfo.environment["WE_SKIP_PROMISE"] == "1" {
            return false
        }
        return !hasSeenPromise || isReplayingPromise
    }
}
