import SwiftUI

@main
struct WEApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var host: SessionHost
    @StateObject private var softStart: SoftStartCoordinator
    @StateObject private var externalSurfaces: ExternalSurfaceController
    @State private var visualEngine = VisualEngineCoordinator()
    @AppStorage("hasSeenLivingConfluencePromise")
    private var hasSeenPromise = false
    @State private var isReplayingPromise = false

    init() {
        _host = StateObject(wrappedValue: SessionHost())
        _softStart = StateObject(wrappedValue: SoftStartCoordinator())
        _externalSurfaces = StateObject(
            wrappedValue: ExternalSurfaceController()
        )
    }

    var body: some Scene {
        WindowGroup {
            // The zones are the app. `liveApp` now only carries the states
            // that come *before* a couple exists — sign in, verification,
            // password recovery, pairing — because those are not zones and
            // never were. The moment a relationship is ready, FieldRoot owns
            // the screen.
            switch FieldEntry.Mode.current {
            // Both dev modes get a preview-backed session. The zones
            // themselves never touch it, but the account surface does, and an
            // `@EnvironmentObject` that is merely absent traps at runtime —
            // so the mode that exists to exercise every screen has to be able
            // to open that one too.
            case .gallery:
                FieldGallery()
                    .environmentObject(previewSession)
            case .seeded:
                FieldZoneShell()
                    .environmentObject(previewSession)
            case .live:
                if let snapshot = host.session.snapshot,
                   isReady(host.session.state) {
                    FieldRoot(snapshot: snapshot)
                        .environmentObject(host.session)
                        .environmentObject(host)
                        .environmentObject(externalSurfaces)
                        .task { await host.restore() }
                        .onOpenURL { url in
                            if !WEDeepLinkRouter.handle(url) {
                                Task {
                                    await host.session.handleAuthCallback(url)
                                }
                            }
                        }
                } else {
                    liveApp
                }
            }
        }
    }

    /// Only built when a dev mode asks for it — `WE_FIELD` is unset in every
    /// shipping run, so this never reaches a user.
    private var previewSession: AppSession {
        AppSession(repository: PreviewRepository())
    }

    private var liveApp: some View {
        ZStack {
            ContentView {
                isReplayingPromise = true
            }
            .environmentObject(host.session)
            .environmentObject(host)
            .environmentObject(softStart)
            .environmentObject(externalSurfaces)
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
            if !WEDeepLinkRouter.handle(url) {
                Task { await host.session.handleAuthCallback(url) }
            }
        }
    }

    /// Only `.ready` hands the screen to the zones. Pairing, hue choice, and
    /// waiting for a partner still belong to the old flow — they are setup,
    /// not the product, and 6f will replace them.
    private func isReady(_ state: AppSession.State) -> Bool {
        if case .ready = state { return true }
        return false
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
        if isReplayingPromise {
            return true
        }
        guard !hasSeenPromise else { return false }
        switch host.session.state {
        case .needsCouple, .waitingForPartner, .choosingHue, .ready:
            return true
        case .loading, .unconfigured, .signedOut, .verificationPending,
                .resettingPassword, .failed:
            return false
        }
    }
}
