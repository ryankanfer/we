//
//  WEDiagnostics.swift
//  WE
//
//  Crash and hang reports, kept on the phone until someone decides to send
//  them.
//
//  This is not analytics and there is no place for it to become analytics.
//  Nothing here observes what a person does in the app — no screens, no taps,
//  no counts of what a couple wrote. MetricKit hands the process back a
//  record of how it *died*, the record is written to this app's own
//  container, and it stays there. There is no network path out of this file.
//  The only way a payload leaves the phone is a person reading it in
//  `WEFeedbackView` and choosing to send it, which is the same
//  confirm-before-egress rule the outreach surface already follows.
//
//  On availability, because the plan flagged it: `MXMetricManager` is current
//  on the iOS 26.2 SDK this app targets. Nothing in MetricKit's headers is
//  deprecated except `MXMetaData.DictionaryRepresentation`, the capitalised
//  Objective-C spelling that Swift never sees — Swift binds
//  `dictionaryRepresentation`. So the MX path is the path, not a fallback.
//
//  What it will not do, and this matters when reading an empty screen:
//  MetricKit delivers on a real device only, at most once every 24 hours,
//  and never in the simulator. An empty diagnostics list is the normal state
//  of a healthy app, and `pastDiagnosticPayloads` is consulted at launch so
//  that a crash from earlier in the week is not lost to that cadence.
//

import Foundation
import MetricKit
import os

// MARK: - Storage

/// The on-disk half. Deliberately separate from the MetricKit subscriber, so
/// the purge contract (Phase 1d) and the tests can reach it without a live
/// `MXMetricManager` in the process.
nonisolated struct WEDiagnosticsStore: Sendable {
    /// Kept small on purpose. These files exist to describe the last few bad
    /// moments, not to be a history.
    static let keepAtMost = 8
    static let keepNewerThan: TimeInterval = 30 * 24 * 60 * 60

    let directory: URL

    /// `Application Support` rather than `Caches` — the system may evict
    /// caches under pressure, and the one report worth reading is the one
    /// written moments before a device filled up.
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL.temporaryDirectory
            self.directory = support.appending(
                path: "Diagnostics",
                directoryHint: .isDirectory
            )
        }
    }

    // MARK: Writing

    /// Writes one payload and prunes. Returns the file it wrote, if it wrote.
    @discardableResult
    func write(_ payload: WEDiagnosticPayload) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let name = Self.filename(for: payload)
            let url = directory.appending(path: name)

            // A payload arriving twice — the launch sweep of
            // `pastDiagnosticPayloads` overlapping a live delivery — is the
            // expected case, not an error. Same window, same content, same
            // filename, so it simply overwrites.
            try payload.json.write(to: url, options: .atomic)
            try Self.excludeFromBackup(url)
            prune()
            return url
        } catch {
            // Nothing above is recoverable from here, and a diagnostics
            // system that crashes the app it is diagnosing is worse than no
            // diagnostics system.
            WELog.diagnostics.error(
                "Could not write diagnostic payload: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: Reading

    /// Newest first, by the moment the payload *describes* rather than the
    /// moment it was written.
    ///
    /// The distinction is the whole reason the timestamp is in the filename.
    /// `start()` sweeps `pastDiagnosticPayloads` and writes up to a week of
    /// reports within the same millisecond, in whatever order MetricKit
    /// returns them — so a modification date sorts them arbitrarily, and a
    /// retention cap applied to an arbitrary order throws away the crash that
    /// just happened. The filename stamp is UTC, which makes a lexicographic
    /// sort exactly a chronological one, including across a timezone change.
    func stored() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var isEmpty: Bool { stored().isEmpty }

    /// Every stored payload as one JSON array, which is what gets attached to
    /// an email. Returns nil when there is nothing to attach.
    func combinedJSON() -> Data? {
        let payloads = stored().compactMap { url -> Any? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        guard !payloads.isEmpty else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: payloads,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: Removing

    /// Part of the Phase 1d purge contract: signing out and deleting the
    /// account land here, as would unpairing if it existed — it does not yet.
    /// A crash report outliving the account it belongs to is the same category
    /// of mistake as a cached relationship outliving it.
    func purge() {
        for url in stored() {
            try? FileManager.default.removeItem(at: url)
        }
        // The directory too, so "the container is empty afterwards" can be
        // asserted literally.
        try? FileManager.default.removeItem(at: directory)
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.keepNewerThan)
        let doomed = stored().enumerated().filter { index, url in
            index >= Self.keepAtMost || Self.date(of: url).map {
                $0 < cutoff
            } ?? false
        }

        for (_, url) in doomed {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A crash report should not follow someone onto a new phone. It
    /// describes a build and a device that are both about to stop existing.
    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Built per call rather than shared: `ISO8601DateFormatter` is a class
    /// and not `Sendable`, and a `static let` of one would be main-actor
    /// isolated under this target's default isolation — reachable from
    /// MetricKit's delivery queue only by lying about it. This runs once per
    /// stored crash.
    ///
    /// UTC and no colons: colons are legal in a filename on APFS and a
    /// nuisance everywhere else, and a fixed zone is what makes the sort in
    /// `stored()` chronological.
    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func filename(for payload: WEDiagnosticPayload) -> String {
        "diagnostic-\(formatter().string(from: payload.end))Z.json"
    }

    /// The inverse, for the age cutoff. A file whose name does not parse is
    /// left alone by age and removed only by the count cap — deleting
    /// something unrecognised is how you lose the one report that mattered.
    private static func date(of url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("diagnostic-"), name.hasSuffix("Z") else {
            return nil
        }
        let stamp = name
            .dropFirst("diagnostic-".count)
            .dropLast()
        return formatter().date(from: String(stamp))
    }
}

// MARK: - A payload, independent of MetricKit

/// The store is written against this rather than `MXDiagnosticPayload` so it
/// can be tested without a device that has crashed.
nonisolated struct WEDiagnosticPayload: Sendable {
    let begin: Date
    let end: Date
    let json: Data

    /// One line per diagnostic inside this envelope. Not what the feedback
    /// screen displays — that is re-derived from the stored JSON, so a report
    /// still describes itself after a relaunch. This decides whether the
    /// envelope is worth storing at all.
    let summary: [String]
}

extension WEDiagnosticPayload {
    /// `nonisolated` one member at a time: the type carries it, but an
    /// extension takes this target's default isolation instead, and MetricKit
    /// delivers on its own queue.
    nonisolated init(_ payload: MXDiagnosticPayload) {
        self.begin = payload.timeStampBegin
        self.end = payload.timeStampEnd
        self.json = payload.readableJSON()

        var lines: [String] = []
        for crash in payload.crashDiagnostics ?? [] {
            let reason = crash.terminationReason ?? "no stated reason"
            let signal = crash.signal.map { "signal \($0)" } ?? "no signal"
            lines.append("Crash — \(reason), \(signal)")
        }
        for hang in payload.hangDiagnostics ?? [] {
            let seconds = hang.hangDuration.converted(to: .seconds).value
            lines.append(String(format: "Hang — %.1fs unresponsive", seconds))
        }
        for _ in payload.appLaunchDiagnostics ?? [] {
            lines.append("Slow launch")
        }
        for _ in payload.cpuExceptionDiagnostics ?? [] {
            lines.append("CPU exception — sustained high usage")
        }
        for _ in payload.diskWriteExceptionDiagnostics ?? [] {
            lines.append("Excessive disk writes")
        }
        self.summary = lines
    }

    /// Whether this payload says anything at all. MetricKit will hand over an
    /// envelope with every array empty, and storing those turns a list of
    /// four real problems into a list of forty files.
    nonisolated var isEmpty: Bool { summary.isEmpty }
}

// MARK: - The subscriber

/// Long-lived, because `MXMetricManager` holds subscribers weakly and a
/// subscriber that deallocates simply stops receiving.
///
/// `NSObject` and `nonisolated`: MetricKit calls back on its own queue, and
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise make these
/// protocol methods main-actor-isolated, which is both a conformance the
/// compiler has to complain about and a hop this work does not need. The
/// store underneath is value-typed file IO.
nonisolated final class WEDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = WEDiagnostics()

    private let store: WEDiagnosticsStore

    init(store: WEDiagnosticsStore = WEDiagnosticsStore()) {
        self.store = store
        super.init()
    }

    /// Called once, at launch. Idempotent — `addSubscriber` with the same
    /// object twice does not double-deliver, and the past-payload sweep
    /// overwrites rather than duplicates.
    func start() {
        // The simulator has no MetricKit daemon; subscribing there is a
        // no-op that also never delivers, so say so once rather than leaving
        // a developer waiting for a payload that cannot arrive.
        #if targetEnvironment(simulator)
        WELog.diagnostics.info(
            "MetricKit does not deliver in the simulator; diagnostics will stay empty here."
        )
        #endif

        let manager = MXMetricManager.shared
        manager.add(self)
        absorb(manager.pastDiagnosticPayloads)
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        absorb(payloads)
    }

    /// Required by the protocol and deliberately empty. Metric payloads are
    /// aggregate performance measurements — battery, launch times, scrolling
    /// — and this product has no use for them that would justify keeping
    /// them on the device.
    func didReceive(_ payloads: [MXMetricPayload]) {}

    // MARK: -

    private func absorb(_ payloads: [MXDiagnosticPayload]) {
        let received = payloads.map(WEDiagnosticPayload.init).filter {
            !$0.isEmpty
        }
        guard !received.isEmpty else { return }

        for payload in received {
            store.write(payload)
        }

        WELog.diagnostics.notice(
            "Stored \(received.count, privacy: .public) diagnostic payload(s)."
        )
    }
}

// MARK: -

private extension MXDiagnosticPayload {
    /// Deliberately not named `jsonRepresentation` — that is MetricKit's own
    /// method, and an extension of the same name on the same type shadows it
    /// into infinite recursion rather than overriding it.
    ///
    /// The method is non-optional in the header but has been observed to
    /// return an empty value for an envelope with nothing in it; falling back
    /// to the dictionary keeps a payload readable either way.
    nonisolated func readableJSON() -> Data {
        let json = jsonRepresentation()
        if !json.isEmpty { return json }
        return (try? JSONSerialization.data(
            withJSONObject: dictionaryRepresentation(),
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
    }
}

