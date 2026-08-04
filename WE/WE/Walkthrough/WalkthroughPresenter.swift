//
//  WalkthroughPresenter.swift
//  WE
//
//  When the walkthrough plays, and who can ask for it again.
//
//  Two things, deliberately apart. `WalkthroughGate` is the decision and is
//  pure — the same reasoning `WESplashGate` gets, and for the same reason:
//  a gate that opens at the wrong moment looks like nothing at all, which is
//  exactly the kind of thing that regresses unnoticed. `WalkthroughPresenter`
//  is the state, and it exists at the scene's root so that both branches of
//  `WEApp.content` can reach it — the pre-couple screens *and* the zones.
//  That is what makes "See how WE works" work from the account surface
//  without threading a closure through three view layers.
//
//  It plays once. There is no day-boundary rule like the splash's, because
//  this is not a ceremony — it is an explanation, and an explanation you have
//  already read is an obstacle.
//

import Combine
import Foundation
import SwiftUI

enum WalkthroughGate {
    /// Persisted across launches. `UserDefaults` is removed when the app is
    /// deleted, so a reinstall correctly gets its first run again.
    static let hasSeenKey = "hasSeenWalkthrough"

    /// The harness's way out, mirroring `WE_SKIP_PROMISE`. Every UI test that
    /// is not about the walkthrough launches with this set, because six of
    /// them wait on the welcome screen's first button and a full-screen
    /// explanation in front of it would fail all six for the wrong reason.
    static let skipKey = "WE_SKIP_WALKTHROUGH"

    static var isSkipped: Bool {
        ProcessInfo.processInfo.environment[skipKey] == "1"
    }

    /// Whether the walkthrough should open by itself.
    ///
    /// Signed out and only signed out. Someone mid-verification or mid-pairing
    /// has already decided to be here, and covering their screen to explain
    /// what they are already doing is the app talking over them. Someone with
    /// a couple can still reach it from the account surface, which is the
    /// difference between offering and insisting.
    ///
    /// - Parameters:
    ///   - hasSeen: whether it has played before on this install.
    ///   - isSignedOut: whether the session has settled on signed out.
    ///   - isSkipped: the harness override.
    static func shouldPresent(
        hasSeen: Bool,
        isSignedOut: Bool,
        isSkipped: Bool = WalkthroughGate.isSkipped
    ) -> Bool {
        guard !isSkipped else { return false }
        guard !hasSeen else { return false }
        return isSignedOut
    }
}

@MainActor
final class WalkthroughPresenter: ObservableObject {
    @Published private(set) var isPresented = false

    /// Not `@AppStorage`: that is a `View` property wrapper, and this has to
    /// be readable from a model that outlives any particular view. The key is
    /// the same one the harness sets with `-hasSeenWalkthrough`, so a launch
    /// argument and a real run agree about what "seen" means.
    private(set) var hasSeen: Bool {
        get { defaults.bool(forKey: WalkthroughGate.hasSeenKey) }
        set { defaults.set(newValue, forKey: WalkthroughGate.hasSeenKey) }
    }

    private let defaults: UserDefaults
    /// A replay must not be overruled by the automatic gate on the next state
    /// change, and must not be closed by one either.
    private var isReplaying = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Called whenever the session settles. Idempotent — a session that
    /// republishes `.signedOut` must not reopen something already dismissed,
    /// which is why `hasSeen` is written at the moment it opens rather than
    /// at the moment it closes.
    func consider(isSignedOut: Bool) {
        guard !isReplaying else { return }
        guard WalkthroughGate.shouldPresent(
            hasSeen: hasSeen,
            isSignedOut: isSignedOut
        ) else { return }

        hasSeen = true
        isPresented = true
    }

    /// From the account surface, and from the profile sheet before a couple
    /// exists. Always plays, however many times it is asked for.
    func replay() {
        isReplaying = true
        isPresented = true
    }

    func finish() {
        hasSeen = true
        isReplaying = false
        isPresented = false
    }
}
