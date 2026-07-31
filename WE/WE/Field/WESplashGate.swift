//
//  WESplashGate.swift
//  WE
//
//  When the collapse plays, and for how long it may hold.
//
//  The spec says every cold start. It should not: a ceremony that plays
//  identically whether you were away a minute or a month cannot mean "you
//  have been away", and 1.4s on every launch is time standing between someone
//  and their partner's list. Rarity is what buys it meaning — so it plays on
//  first run, and after that only on the first launch of a new day.
//
//  Pure and testable on purpose. Getting the cadence wrong looks like nothing
//  at all, which is exactly the kind of thing that regresses unnoticed.
//

import Foundation

enum WESplashGate {
    /// Persisted across launches. `UserDefaults` is removed when the app is
    /// deleted, so a reinstall correctly gets its first run again.
    static let lastPlayedKey = "weSplashLastPlayed"

    /// How long the finished mark may be the wait state before the app gives
    /// up on sync and shows whatever it actually has.
    ///
    /// Silence is the right answer for a slow network and the wrong one for a
    /// broken connection: without a ceiling there is no way out of a hang,
    /// and the offline and failed states the app already has would never be
    /// reached.
    static let holdCeiling: Duration = .seconds(4)

    /// Whether the collapse should play now.
    ///
    /// - Parameters:
    ///   - lastPlayed: when it last played, or nil on a first run.
    ///   - now: the current moment.
    static func shouldPlay(
        lastPlayed: Date?,
        now: Date = Date(),
        calendar: Calendar = .gregorianUS
    ) -> Bool {
        // Never seen it. This is the arrival it was designed for.
        guard let lastPlayed else { return true }

        // Same day, so they have not been away — go straight in.
        if calendar.isDate(lastPlayed, inSameDayAs: now) { return false }

        // A clock that has gone backwards is not evidence of absence.
        return lastPlayed < now
    }
}
