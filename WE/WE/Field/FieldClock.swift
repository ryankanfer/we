//
//  FieldClock.swift
//  WE
//
//  Where `now` comes from.
//
//  Today is derived and never stored — the whole zone is a reading of Life and
//  Us taken at an instant. Which means there is nothing to clear at the end of
//  a day: the day turns because `now` turns, and everything downstream falls
//  out of that on the next read.
//
//  Except `now` never turned. It was assigned once in `FieldStore.init` from a
//  `Date()` evaluated at launch, and the app spent the rest of the process
//  dated to that instant — yesterday's header, yesterday's hero, and a daily
//  moment planned against a clock that had stopped. The architecture was
//  right and inert.
//
//  So the instant becomes a dependency, like the backend already is. A pinned
//  clock is a real clock and not a missing feature: previews, the gallery and
//  the screenshot contracts all run on a fixed date and have to stay exactly
//  reproducible, so "it does not move" is a conformance here rather than a
//  special case somewhere else.
//

import Foundation

protocol FieldClock: Sendable {
    var now: Date { get }

    /// False for a pinned clock. When it is false the store never installs
    /// the observers at all — a preview must not be moved off its date by a
    /// notification the simulator happens to post.
    var advances: Bool { get }
}

/// The shipping clock.
struct FieldLiveClock: FieldClock {
    var now: Date { Date() }
    var advances: Bool { true }
}

/// An instant somebody chose. Previews, the sample couple, and any harness
/// that pinned the date.
struct FieldFixedClock: FieldClock {
    let now: Date
    var advances: Bool { false }
}

/// A clock moved by hand.
///
/// Tests need a midnight, and waiting for one is not a test. Everything about
/// the day turning — the carried-forward sentence, a held topic coming back,
/// the week that captures are counted over — is a fact about two instants, so
/// this is the only honest way to assert on it.
final class FieldSteppedClock: FieldClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ start: Date) {
        instant = start
    }

    var now: Date { lock.withLock { instant } }
    var advances: Bool { true }

    func advance(by interval: TimeInterval) {
        lock.withLock { instant += interval }
    }

    func advance(days: Int) {
        advance(by: TimeInterval(days) * 86_400)
    }

    func set(_ date: Date) {
        lock.withLock { instant = date }
    }
}

extension FieldLiveClock {
    /// The app's clock — unless a harness pinned the date, in which case the
    /// pin wins. Resolved in one place so no call site has to remember that
    /// `WE_QA_FIXED_NOW` exists.
    @MainActor
    static var app: FieldClock {
        if let frozen = AppTestConfiguration.current.frozenNow {
            return FieldFixedClock(now: frozen)
        }
        return FieldLiveClock()
    }
}
