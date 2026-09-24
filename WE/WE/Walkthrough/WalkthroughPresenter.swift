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
//  It never opens by itself. It used to cover the screen on first launch,
//  in front of the welcome, which made the first thing a new person met an
//  explanation of an app they had not decided to use. Now it is offered:
//  "See how it works" on the welcome, and "See how WE works" in Account.
//

import Combine
import Foundation
import Observation
import SwiftUI

enum WalkthroughGate {
    /// Persisted across launches. `UserDefaults` is removed when the app is
    /// deleted, so a reinstall correctly gets its first run again.
    static let hasSeenKey = "hasSeenWalkthrough"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// From the welcome, and from Account. Always plays, however many times
    /// it is asked for.
    func replay() {
        isPresented = true
    }

    func finish() {
        hasSeen = true
        isPresented = false
    }
}
