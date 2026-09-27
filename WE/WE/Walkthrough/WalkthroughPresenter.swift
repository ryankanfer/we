//
//  WalkthroughPresenter.swift
//  WE
//
//  When the walkthrough plays, and who can ask for it again.
//
//  It plays once, by itself, right after somebody creates an account: the
//  first moment there is a person to welcome by name and an app worth
//  explaining. Not before. Explaining an app to somebody who has not decided
//  to use it was the old order, and it made the first thing a stranger met a
//  tutorial.
//
//  The signal is a flag written the moment sign up succeeds
//  (`WalkthroughGate.markAccountCreated`). It survives an email verification
//  round trip and a relaunch, and it is spent the first time the session
//  reaches a signed in state that has an app behind it. Signing in to an
//  existing account never sets it, so returning people land where they left.
//
//  `WalkthroughPresenter` lives at the scene's root so both branches of
//  `WEApp.content` can reach it: the pre-couple screens and the zones. That
//  is what makes "See how WE works" in Account work without threading a
//  closure through three view layers.
//

import Combine
import Foundation
import Observation
import SwiftUI

enum WalkthroughGate {
    /// Persisted across launches. `UserDefaults` is removed when the app is
    /// deleted, so a reinstall correctly gets its first run again.
    static let hasSeenKey = "hasSeenWalkthrough"

    /// Set when an account is created, cleared when the walkthrough finishes.
    static let pendingKey = "walkthroughPendingAfterSignUp"

    /// Called from `AppSession.signUp` the moment the backend accepts the new
    /// account, whether or not the email still needs verifying.
    static func markAccountCreated(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
    }
}

@MainActor
final class WalkthroughPresenter: ObservableObject {
    @Published private(set) var isPresented = false

    /// True when this presentation is the one that follows sign up, rather
    /// than a replay from Account. It changes the greeting and the last
    /// button, nothing else.
    @Published private(set) var isFirstRun = false

    /// Not `@AppStorage`: that is a `View` property wrapper, and this has to
    /// be readable from a model that outlives any particular view. The key is
    /// the same one the harness sets with `-hasSeenWalkthrough`, so a launch
    /// argument and a real run agree about what "seen" means.
    private(set) var hasSeen: Bool {
        get { defaults.bool(forKey: WalkthroughGate.hasSeenKey) }
        set { defaults.set(newValue, forKey: WalkthroughGate.hasSeenKey) }
    }

    private var isPending: Bool {
        get { defaults.bool(forKey: WalkthroughGate.pendingKey) }
        set { defaults.set(newValue, forKey: WalkthroughGate.pendingKey) }
    }

    /// UI tests launch with `-hasSeenWalkthrough YES` to walk straight past
    /// it. That lives in the argument domain only, so it never suppresses a
    /// real person's first run.
    private var isSuppressedByLaunchArgument: Bool {
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        return arguments[WalkthroughGate.hasSeenKey] != nil && hasSeen
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Plays the first run walkthrough if an account was just created and the
    /// session has arrived somewhere with an app behind it.
    func presentIfPending(for state: AppSession.State) {
        guard isPending, !isPresented else { return }
        if isSuppressedByLaunchArgument {
            isPending = false
            return
        }
        switch state {
        case .needsCouple, .waitingForPartner, .ready:
            isFirstRun = true
            isPresented = true
        default:
            break
        }
    }

    /// From Account. Always plays, however many times it is asked for.
    func replay() {
        isFirstRun = false
        isPresented = true
    }

    func finish() {
        hasSeen = true
        isPending = false
        isPresented = false
        isFirstRun = false
    }
}
