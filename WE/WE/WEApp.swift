import SwiftUI

@main
struct WEApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var host: SessionHost
    @AppStorage("hasCrossedThreshold")
    private var hasCrossedThreshold = false
    @State private var isReplayingWalkthrough = false

    init() {
        _host = StateObject(wrappedValue: SessionHost())
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView {
                    isReplayingWalkthrough = true
                }
                .environmentObject(host.session)
                .environmentObject(host)
                .accessibilityHidden(showsWalkthrough)
                .allowsHitTesting(!showsWalkthrough)

                if showsWalkthrough {
                    ThresholdWalkthrough(
                        mode: isReplayingWalkthrough ? .replay : .firstRun
                    ) {
                        hasCrossedThreshold = true
                        isReplayingWalkthrough = false
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .animation(
                .weSettle(duration: 0.45, reduceMotion: reduceMotion),
                value: showsWalkthrough
            )
            .task {
                await host.restore()
            }
            .onOpenURL { url in
                Task { await host.session.handleAuthCallback(url) }
            }
        }
    }

    private var showsWalkthrough: Bool {
        if ProcessInfo.processInfo.environment["WE_SKIP_WALKTHROUGH"] == "1" {
            return false
        }
        return !hasCrossedThreshold || isReplayingWalkthrough
    }
}
