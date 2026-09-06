//
//  WELog.swift
//  WE
//
//  One vocabulary for anything the app says to itself.
//
//  `print` writes to a console nobody is attached to on a tester's phone, and
//  it says the same thing at every severity. `os.Logger` is routed, levelled,
//  and collectable from a device after the fact — which is the only reason
//  any of this exists.
//
//  Privacy is the reason the categories are separate rather than one logger:
//  everything here is interpolated with the default redaction, so a value has
//  to be marked `privacy: .public` deliberately, one site at a time. Nothing
//  a couple wrote is ever a candidate for that.
//

import Foundation
import os

nonisolated enum WELog {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.rk.WE"

    /// The app-group handoff to widgets and Live Activities.
    static let externalSurfaces = Logger(
        subsystem: subsystem,
        category: "external-surfaces"
    )

    /// Reads and writes that are allowed to fail quietly at the seam, and
    /// must not fail quietly in the log — the outbox and state cache land
    /// here in Phase 1.
    static let persistence = Logger(
        subsystem: subsystem,
        category: "persistence"
    )

    /// Crash and hang payloads arriving from MetricKit, and the feedback
    /// route that carries them out.
    static let diagnostics = Logger(
        subsystem: subsystem,
        category: "diagnostics"
    )
}
