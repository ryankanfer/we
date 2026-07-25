import SwiftUI

@main
struct WEApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var session: AppSession
    @AppStorage("hasSeenLivingConfluencePromise")
    private var hasSeenPromise = false
    @State private var isReplayingPromise = false

    init() {
        let environment = AppEnvironment.current
        let isOfflinePreview = environment.repositoryMode == .preview
            && environment.previewScenario == .offline
        _session = StateObject(
            wrappedValue: AppSession(
                repository: RepositoryFactory.make(environment: environment),
                connectivity: ConnectivityMonitor(
                    startImmediately: !isOfflinePreview,
                    initiallyOnline: !isOfflinePreview
                )
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView {
                    isReplayingPromise = true
                }
                .environmentObject(session)
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
                await session.restoreIfNeeded()
            }
            .onOpenURL { url in
                Task { await session.handleAuthCallback(url) }
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
