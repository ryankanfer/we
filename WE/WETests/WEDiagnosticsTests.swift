//
//  WEDiagnosticsTests.swift
//  WETests
//
//  The two things worth asserting about diagnostics: that the store keeps
//  what it promises and forgets what it promises to forget, and that the
//  report a person reads before sending is the report that actually goes.
//
//  `MXDiagnosticPayload` cannot be constructed — it has no public
//  initialiser and MetricKit never delivers in a simulator — which is exactly
//  why `WEDiagnosticsStore` is written against `WEDiagnosticPayload` instead.
//  The MetricKit-shaped half is one small `init` at the seam; everything
//  below is the half that can go wrong quietly.
//

import Foundation
import Testing
@testable import WE

struct WEDiagnosticsStoreTests {
    /// A directory per test. `WEDiagnosticsStore()` with no argument points
    /// at the real Application Support container, and a test that purges it
    /// would delete a developer's own captured payloads.
    private func makeStore() -> WEDiagnosticsStore {
        WEDiagnosticsStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "WEDiagnosticsTests-\(UUID().uuidString)")
        )
    }

    private func payload(
        end: Date,
        summary: [String] = ["Crash — test"],
        json: String = #"{"crashDiagnostics":[{}]}"#
    ) -> WEDiagnosticPayload {
        WEDiagnosticPayload(
            begin: end.addingTimeInterval(-3600),
            end: end,
            json: Data(json.utf8),
            summary: summary
        )
    }

    @Test
    func writesAndReadsBack() throws {
        let store = makeStore()
        defer { store.purge() }

        #expect(store.isEmpty)

        store.write(payload(end: Date()))

        #expect(store.stored().count == 1)
        #expect(!store.isEmpty)
    }

    /// Not just "the cap holds" but *which* reports survive it. Written
    /// oldest-payload-last on purpose: that is what the launch sweep of
    /// `pastDiagnosticPayloads` does, and sorting those by file modification
    /// date would keep the oldest crash and discard the one that just
    /// happened.
    @Test
    func keepsTheMostRecentCrashesRatherThanTheMostRecentlyWritten() throws {
        let store = makeStore()
        defer { store.purge() }

        let now = Date()
        let ends = (0...WEDiagnosticsStore.keepAtMost).map {
            now.addingTimeInterval(TimeInterval(-3600 * $0))
        }
        for end in ends {
            store.write(payload(end: end))
        }

        let kept = store.stored()
        #expect(kept.count == WEDiagnosticsStore.keepAtMost)

        // Newest first, and the single dropped one is the oldest.
        let names = kept.map(\.lastPathComponent)
        #expect(names == names.sorted(by: >))
        #expect(!names.contains {
            $0.contains(Self.stamp(of: ends.last!))
        })
        #expect(names.contains { $0.contains(Self.stamp(of: ends.first!)) })
    }

    /// Anything past the age cutoff goes even when the count cap has room —
    /// a crash from a build that no longer exists is noise in a report.
    @Test
    func forgetsAnythingOlderThanTheCutoff() throws {
        let store = makeStore()
        defer { store.purge() }

        store.write(payload(end: Date()))
        store.write(payload(end: Date().addingTimeInterval(
            -WEDiagnosticsStore.keepNewerThan - 86_400
        )))

        #expect(store.stored().count == 1)
    }

    /// The filename is the sort key, so its shape is a contract rather than
    /// an implementation detail: UTC, no colons, lexicographically ordered.
    private static func stamp(of date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// The same payload arriving twice — the launch sweep of
    /// `pastDiagnosticPayloads` overlapping a live delivery — must not become
    /// two files, or the cap above throws away real reports to hold copies.
    @Test
    func theSamePayloadTwiceIsOneFile() throws {
        let store = makeStore()
        defer { store.purge() }

        let end = Date()
        store.write(payload(end: end))
        store.write(payload(end: end))

        #expect(store.stored().count == 1)
    }

    /// Part of the Phase 1d purge contract, asserted the way the plan states
    /// it: the container is empty afterwards.
    @Test
    func purgeLeavesNothingBehind() throws {
        let store = makeStore()

        store.write(payload(end: Date()))
        store.write(payload(end: Date().addingTimeInterval(-7200)))
        #expect(!store.isEmpty)

        store.purge()

        #expect(store.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }

    @Test
    func combinedJSONIsOneArrayOfEveryPayload() throws {
        let store = makeStore()
        defer { store.purge() }

        store.write(payload(
            end: Date(),
            json: #"{"crashDiagnostics":[{}]}"#
        ))
        store.write(payload(
            end: Date().addingTimeInterval(-7200),
            json: #"{"hangDiagnostics":[{}]}"#
        ))

        let combined = try #require(store.combinedJSON())
        let parsed = try JSONSerialization.jsonObject(with: combined)
        let array = try #require(parsed as? [Any])

        #expect(array.count == 2)
    }

    @Test
    func combinedJSONIsNilWhenThereIsNothingToSend() {
        let store = makeStore()
        defer { store.purge() }

        #expect(store.combinedJSON() == nil)
    }

    /// Corrupt files are the normal end state of a process killed mid-write.
    /// They must be skipped, not crashed on — the same recovery posture the
    /// outbox will need in Phase 1b.
    @Test
    func corruptFilesAreSkippedRatherThanFatal() throws {
        let store = makeStore()
        defer { store.purge() }

        store.write(payload(end: Date()))

        try Data("{ this is not json".utf8).write(
            to: store.directory.appending(path: "diagnostic-corrupt.json")
        )

        let combined = try #require(store.combinedJSON())
        let array = try #require(
            try JSONSerialization.jsonObject(with: combined) as? [Any]
        )

        #expect(store.stored().count == 2)
        #expect(array.count == 1)
    }
}

// MARK: -

struct WEFeedbackReportTests {
    private func report(
        note: String = "The capture field ate my sentence.",
        diagnostics: [String] = [],
        attachment: Data? = nil
    ) -> WEFeedbackReport {
        WEFeedbackReport(
            note: note,
            accountID: "0f2c8b7a-1111-4444-8888-aaaaaaaaaaaa",
            email: "tester@example.com",
            diagnostics: diagnostics,
            attachment: attachment
        )
    }

    /// The screen's promise is that what it lists is what gets sent. That is
    /// only true if the body is assembled from the same lines the screen
    /// renders — so assert every one of them survives into it.
    @Test
    func everyLineShownOnScreenIsInTheBody() {
        let subject = report(diagnostics: ["1 crash", "2 hangs"])
        let body = subject.body

        for line in subject.environmentLines {
            #expect(body.contains(line))
        }
        for line in subject.accountLines {
            #expect(body.contains(line))
        }
        #expect(body.contains("1 crash"))
        #expect(body.contains("2 hangs"))
        #expect(body.contains("The capture field ate my sentence."))
    }

    @Test
    func saysSoWhenThereIsNothingToReport() {
        #expect(report().body.contains("No crashes or hangs recorded."))
    }

    @Test
    func namesTheAttachmentAndItsSize() {
        let subject = report(attachment: Data(count: 2048))
        #expect(subject.body.contains(WEFeedbackReport.attachmentFilename))
    }

    @Test
    func anEmptyNoteWithNothingRecordedIsNotWorthSending() {
        #expect(!report(note: "   \n ").isSendable)
    }

    @Test
    func aCrashIsWorthSendingWithoutAWordTyped() {
        #expect(report(note: "", diagnostics: ["1 crash"]).isSendable)
    }

    @Test
    func aTypedNoteIsWorthSendingWithoutACrash() {
        #expect(report().isSendable)
    }

    /// Feedback has to work before there is an account — the funnel's worst
    /// moments are the ones before pairing.
    @Test
    func worksWithNoAccountAtAll() {
        let anonymous = WEFeedbackReport(
            note: "Can't get past the code screen.",
            accountID: nil,
            email: nil,
            diagnostics: [],
            attachment: nil
        )

        #expect(anonymous.accountLines.isEmpty)
        #expect(anonymous.isSendable)
        #expect(anonymous.body.contains("Can't get past the code screen."))
    }

    /// The reason this file exists at all: the report is the boundary, and a
    /// boundary is only real if crossing it is a test failure.
    /// The report is assembled from a fixed set of fields and nothing reads
    /// `FieldState`, so the assertion is about the shape: the body is the
    /// note plus the declared lines, and there is no room in it for anything
    /// else. Written as a set difference rather than a search for one sample
    /// string, because a search only fails for the string somebody thought
    /// of.
    @Test
    func theBodyIsTheNoteAndTheDeclaredLinesAndNothingElse() {
        let subject = report(note: "It froze.", diagnostics: ["1 crash"])

        let declared = Set(
            ["It froze.", "—", "", "Recorded on this device:", "· 1 crash"]
                + subject.environmentLines
                + subject.accountLines
        )
        let actual = Set(subject.body.components(separatedBy: "\n"))

        #expect(actual.subtracting(declared).isEmpty)
    }

    @Test
    func subjectCarriesTheBuildBeingTested() {
        #expect(report().subject.contains(WEFeedbackReport.version))
        #expect(report().subject.contains(WEFeedbackReport.build))
    }
}
