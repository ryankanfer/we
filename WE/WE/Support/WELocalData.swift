//
//  WELocalData.swift
//  WE
//
//  Everything this device keeps, in one list, so that leaving actually means
//  leaving.
//
//  The list exists because it was scattered. `AppSession.signOut` removed the
//  relationship cache and nothing else; `FieldMomentDelivery.cancel()` was
//  called from the account surface but from neither of the two pre-couple
//  "Sign out" buttons, so signing out from the pairing screen left a
//  notification scheduled for a relationship you had just left. The join code
//  in `UserDefaults` was never cleared by anything at all. Each of those is a
//  small oversight, and each is the same oversight: the knowledge of what this
//  device holds lived in whoever last remembered to add a line.
//
//  So it lives here instead, once. Sign-out, account deletion, and — when it
//  exists — unpairing all call the same method, and the test asserts the
//  container is empty afterwards rather than asserting that four particular
//  removals happened. That is the difference between a list that stays correct
//  and a list that was correct when it was written.
//
//  Everything is removed wholesale rather than per partition. Sign-out does not
//  always know which couple it is leaving, and a device that has held two
//  accounts should not keep the first one's queue because the second one's
//  identifiers were the ones to hand.
//

import Foundation

@MainActor
struct WELocalData {
    var outbox = FieldOutboxStore()
    var fieldState = FieldStateCache()
    var diagnostics = WEDiagnosticsStore()
    var defaults: UserDefaults = .standard
    var cancelNotifications: @MainActor () -> Void = {
        FieldMomentDelivery.cancel()
    }

    /// Called when somebody leaves — signing out, deleting their account, or
    /// unpairing.
    ///
    /// Deliberately not `throws`. A purge that stops at the first failure
    /// leaves *more* behind than one that continues, and there is no useful
    /// recovery from "the diagnostics folder could not be removed" other than
    /// to carry on removing the rest.
    func purge() {
        // Unsent writes, and the last snapshot they were queued against.
        // These are the relationship itself and go first.
        outbox.removeAll()
        fieldState.removeAll()

        // Crash reports describing a build this account was using. Harmless
        // in content and wrong to keep: they outlive the account otherwise.
        diagnostics.purge()

        // A join code held from before there was an account. It persisted
        // indefinitely, so the next person to sign in on this phone would be
        // offered somebody else's relationship to join.
        defaults.removeObject(forKey: PendingInvitation.defaultsKey)

        // Whether this person answered the crossing question (2a). Keyed by
        // user and couple, so the keys are enumerated rather than named — and
        // they have to go, or the next person to sign in on this phone
        // inherits an answer about their private history that they never gave.
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(FieldCrossingDecision.defaultsPrefix) {
            defaults.removeObject(forKey: key)
        }

        // Nothing should be waiting for someone who has left.
        cancelNotifications()
    }

    /// What the purge is responsible for, for the test that asserts nothing
    /// survives it. Kept next to `purge()` so the two cannot drift.
    var directories: [URL] {
        [outbox.directory, fieldState.directory, diagnostics.directory]
    }

    var defaultsKeys: [String] {
        [PendingInvitation.defaultsKey]
    }
}
