import SwiftUI

@main
struct WEApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var host: SessionHost
    @StateObject private var pendingInvitation: PendingInvitation
    @StateObject private var externalSurfaces: ExternalSurfaceController
    @StateObject private var previewSession: AppSession
    /// At the scene's root, not inside `liveApp`. Both branches of `content`
    /// have to reach it — the pre-couple screens open it by themselves, and
    /// the account surface inside the zones can ask for it again.
    @StateObject private var walkthrough = WalkthroughPresenter()
    @State private var visualEngine = VisualEngineCoordinator()
    private let testConfiguration = AppTestConfiguration.current
    @State private var isReplayingPromise = false

    init() {
        _host = StateObject(wrappedValue: SessionHost())
        _pendingInvitation = StateObject(wrappedValue: PendingInvitation())
        _externalSurfaces = StateObject(
            wrappedValue: ExternalSurfaceController()
        )
        _previewSession = StateObject(
            wrappedValue: AppSession(
                repository: PreviewRepository(
                    scenario: AppEnvironment.current.previewScenario
                )
            )
        )

        // In `init` rather than a `.task`, because the payloads worth having
        // describe a launch that did not get as far as a view. MetricKit
        // holds subscribers weakly, hence the singleton; `start()` also
        // sweeps `pastDiagnosticPayloads`, so a crash from earlier in the
        // week is picked up rather than lost to the once-a-day cadence.
        WEDiagnostics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                content
                    .accessibilityHidden(walkthrough.isPresented)
                    .allowsHitTesting(!walkthrough.isPresented)

                // Under the splash and over everything else. The collapse is
                // an arrival and has to finish before anything explains
                // itself; the walkthrough is the first thing after it.
                if walkthrough.isPresented {
                    WalkthroughView { walkthrough.finish() }
                        .transition(.opacity)
                        .zIndex(20)
                }

                // Above everything, and only on an arrival that has earned
                // it. `showsSplash` starts true and is never set again, so a
                // warm resume from background can never replay it — the
                // process starting is the whole signal.
                if showsSplash {
                    WESplashView(
                        identity: host.session.snapshot.map(fieldIdentity),
                        isWaiting: { host.session.state == .loading }
                    ) {
                        splashLastPlayed = Date().timeIntervalSince1970
                        withAnimation(.easeInOut(duration: 0.40)) {
                            showsSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .environmentObject(walkthrough)
            .environment(
                \.dynamicTypeSize,
                testConfiguration.dynamicTypeSize ?? dynamicTypeSize
            )
            // Considered whenever the session settles, not once on appear: at
            // launch the state is `.loading`, and "signed out" is a conclusion
            // the session reaches a moment later. `consider` is idempotent, so
            // a state that republishes cannot reopen what was dismissed.
            .onChange(of: host.session.state, initial: true) { _, state in
                guard !showsSplash else { return }
                walkthrough.consider(isSignedOut: state == .signedOut)
            }
            .onChange(of: showsSplash) { _, shows in
                guard !shows else { return }
                walkthrough.consider(
                    isSignedOut: host.session.state == .signedOut
                )
            }
            .animation(
                .weSettle(duration: 0.40, reduceMotion: effectiveReduceMotion),
                value: walkthrough.isPresented
            )
            .transaction { transaction in
                guard testConfiguration.disablesAnimations else { return }
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
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
                    .task { await previewSession.restoreIfNeeded() }
            case .seeded:
                FieldZoneShell()
                    .environmentObject(previewSession)
                    .task { await previewSession.restoreIfNeeded() }
            case .demo:
                FieldZoneShell(store: FieldStore(state: .demo))
                    .environmentObject(previewSession)
                    .task { await previewSession.restoreIfNeeded() }
            case .live:
                if let snapshot = host.session.snapshot,
                   isReady(host.session.state) {
                    FieldRoot(snapshot: snapshot)
                        .environmentObject(host.session)
                        .environmentObject(host)
                        .environmentObject(externalSurfaces)
                        .task { await host.restore() }
                        .onOpenURL { open($0) }
                } else {
                    liveApp
                }
            }
    }

    // MARK: The collapse

    @AppStorage(WESplashGate.lastPlayedKey) private var splashLastPlayed = 0.0

    /// Decided once, when the process starts. `@State` is doing real work
    /// here: it makes "cold start only" true for free, because a warm resume
    /// does not rebuild this.
    @State private var showsSplash = WESplashGate.shouldPlay(
        lastPlayed: UserDefaults.standard.object(
            forKey: WESplashGate.lastPlayedKey
        ).flatMap { $0 as? Double }.map(Date.init(timeIntervalSince1970:)),
        // Never in the dev modes: waiting 1.4s to review a screen is friction
        // with nothing on the other side of it.
        now: Date()
    ) && FieldEntry.Mode.current == .live

    /// The couple's own two colours, for the cross-tint. Before a couple
    /// exists there is nobody to be, and the collapse stays brand throughout.
    private func fieldIdentity(_ snapshot: RelationshipSnapshot) -> FieldIdentity {
        snapshot.emptyFieldState.identity
    }

    private var liveApp: some View {
        ZStack {
            ContentView {
                isReplayingPromise = true
            }
            .environmentObject(host.session)
            .environmentObject(host)
            .environmentObject(pendingInvitation)
            .environmentObject(externalSurfaces)
            .accessibilityHidden(showsPromise)
            .allowsHitTesting(!showsPromise)

            if showsPromise {
                // Only ever the replay from Account. `showsPromise` is
                // `isReplayingPromise` and nothing else — the Promise stopped
                // owning any launch state when the walkthrough became the
                // sole first-run explanation, and it is now performed at
                // arrival rather than after account creation, because the
                // most important moment in the product cannot be one somebody
                // completes alone.
                //
                // A replay waits on nobody, so it is handed a ceremony that
                // is already complete and simply reads the beats through.
                LivingConfluencePromise(
                    isReplay: true,
                    ceremony: .constant(
                        WECeremonyState(
                            mine: Set(WEBeat.allCases),
                            kept: Set(WEBeat.allCases)
                        )
                    ),
                    onComplete: { isReplayingPromise = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .environment(\.visualEngine, visualEngine)
        .animation(
            .weSettle(duration: 0.45, reduceMotion: effectiveReduceMotion),
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
        .onOpenURL { open($0) }
    }

    /// One entry point for every incoming URL, in three layers: an invitation
    /// is held here because the code is main-actor state this scene owns; any
    /// other product deep link goes to the router; anything left is an auth
    /// callback.
    private func open(_ url: URL) {
        if case .join(let code)? = WEDeepLinkRouter.destination(for: url) {
            pendingInvitation.hold(code)
            return
        }
        if !WEDeepLinkRouter.handle(url) {
            Task { await host.session.handleAuthCallback(url) }
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
            reduceMotion: effectiveReduceMotion,
            reduceTransparency: effectiveReduceTransparency
        )
    }

    private var effectiveReduceMotion: Bool {
        testConfiguration.disablesAnimations
            || (testConfiguration.reduceMotion ?? reduceMotion)
    }

    private var effectiveReduceTransparency: Bool {
        testConfiguration.reduceTransparency ?? reduceTransparency
    }

    private var showsPromise: Bool {
        if ProcessInfo.processInfo.environment["WE_SKIP_PROMISE"] == "1" {
            return false
        }
        // This is preserved as an intentional re-read from Account. It no
        // longer owns any launch state: the current walkthrough is the sole
        // first-run explanation, and returning people land where their
        // session actually is.
        return isReplayingPromise
    }
}
