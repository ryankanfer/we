//
//  WEFeedbackReport.swift
//  WE
//
//  Everything that leaves the phone when a tester sends feedback, assembled
//  in one place so that the screen can show it and a test can assert it.
//
//  The rule this file exists to keep: a person can read the entire thing
//  before it goes. That is only possible if it is small and if it is text, so
//  the report is a list of lines rather than a serialised object graph, and
//  nothing a couple wrote is ever one of the lines. What a person typed into
//  the note is theirs and is included because they typed it knowing where it
//  was going.
//

import Foundation

nonisolated struct WEFeedbackReport: Sendable {
    /// What the tester wrote. The only free text in the report.
    var note: String

    /// Identifiers that make a report findable in the database. Optional
    /// because feedback is reachable before there is an account to name.
    var accountID: String?
    var email: String?

    /// One line per stored diagnostic. Kinds and counts, never a call stack.
    var diagnostics: [String]

    /// The raw MetricKit JSON, attached rather than inlined. This is the one
    /// part a person cannot reasonably read line by line, so the screen shows
    /// it as a named file with a stated size and lets them open it.
    var attachment: Data?

    static let attachmentFilename = "we-diagnostics.json"
    static let attachmentMIMEType = "application/json"

    // MARK: What it says

    var subject: String {
        "WE beta — \(Self.version) (\(Self.build))"
    }

    /// The whole message, in reading order: the person's words first, because
    /// they are the point and the rest is context for them.
    var body: String {
        var out: [String] = []

        out.append(note.trimmingCharacters(in: .whitespacesAndNewlines))
        out.append("")
        out.append("—")
        out.append("")

        for line in environmentLines { out.append(line) }

        if !accountLines.isEmpty {
            out.append("")
            for line in accountLines { out.append(line) }
        }

        out.append("")
        if diagnostics.isEmpty {
            out.append("No crashes or hangs recorded.")
        } else {
            out.append("Recorded on this device:")
            for line in diagnostics { out.append("· \(line)") }
        }

        if let attachment {
            out.append("")
            out.append(
                "Attached: \(Self.attachmentFilename) "
                    + "(\(Self.formatted(bytes: attachment.count)))"
            )
        }

        return out.joined(separator: "\n")
    }

    // MARK: The parts, shown separately on screen

    var environmentLines: [String] {
        [
            "WE \(Self.version) (\(Self.build))",
            "iOS \(Self.systemVersion) on \(Self.deviceModel)",
            "Region \(Locale.current.region?.identifier ?? "unknown")",
        ]
    }

    var accountLines: [String] {
        var lines: [String] = []
        if let email { lines.append("Signed in as \(email)") }
        if let accountID { lines.append("Account \(accountID)") }
        return lines
    }

    /// Whether there is anything worth sending. A note of nothing plus no
    /// diagnostics is somebody who opened the screen and changed their mind.
    var isSendable: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !diagnostics.isEmpty
    }

    // MARK: Environment

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    /// `ProcessInfo` rather than `UIDevice`, for the same reason there is no
    /// `import UIKit` above: every accessor on `UIDevice` is main-actor
    /// isolated, and a report has to be assemblable from wherever a failure
    /// happened to be noticed.
    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
            + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
    }

    /// `UIDevice.model` says "iPhone" for every iPhone ever made, which is not
    /// a useful thing to know about a layout bug. `utsname` gives the machine
    /// identifier — iPhone17,1 and so on.
    static var deviceModel: String {
        var system = utsname()
        uname(&system)
        let identifier = withUnsafeBytes(of: &system.machine) { raw in
            raw.prefix { $0 != 0 }.map { String(UnicodeScalar($0)) }.joined()
        }
        return identifier.isEmpty ? "unknown device" : identifier
    }

    static func formatted(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: Where it goes

    /// Read from the bundle rather than written here, so the TestFlight build
    /// and a development build can differ without a code change — the same
    /// separation Phase 4f asks for on the Supabase keys.
    static var supportAddress: String? {
        let value = Bundle.main.infoDictionary?["WESupportEmail"] as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
