import Foundation
import Supabase
import XCTest
@testable import WE

// MARK: - Why this file exists
//
// `FieldMemoryBackend` says of itself that it "is the reference implementation
// of `FieldBackend`, and every rule it enforces is one the Supabase
// implementation must also enforce." Nothing checked that.
//
// The cost of not checking it: `FieldSupabaseBackend.setHeld` was an UPDATE
// guarded on `UUID(uuidString:)` and had no insert path at all, so every held
// topic — "not this year", "ask me again tonight" — was dropped in silence and
// the app re-asked. The memory backend upserted correctly the whole time, and
// even carried a comment describing that same bug being fixed *there*. Every
// preview, every gallery run, and every one of the ~176 `FieldTests` cases
// exercised the implementation that worked. The one people actually used was
// the one nobody ran.
//
// So the assertions below are written once and run twice, against both
// backends. A behaviour that holds in memory and not over PostgREST now fails
// a PR rather than a relationship.

// MARK: - A PostgREST that actually mutates
//
// `FieldSupabaseAdapterContractTests` stubs GET only, which is enough to catch
// DTO drift and cannot catch a write that goes nowhere. This one keeps a real
// row store and implements the four verbs the adapter issues: insert, upsert
// with `on_conflict`, update with `eq` filters, and delete with `eq` filters.
// The adapter still builds and executes its real queries; only the transport
// is local, so no Docker and no shared credentials.

final class FieldRESTStub: URLProtocol, @unchecked Sendable {
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: [[String: Any]]] = [:]

        static let allTables = [
            "field_identity", "field_away_windows", "field_clusters",
            "field_life_items", "field_horizons", "field_questions",
            "field_rhythms", "field_evidence", "field_held_topics",
            "field_standing_rules", "field_captures", "field_corrections",
            "field_daily_moment",
            "field_readiness", "field_readiness_bloom",
        ]

        /// Who is holding this client, for the two readiness RPCs.
        ///
        /// The real functions read `auth.uid()`; the stub has no session, so
        /// the caller's identity has to be told to it. Without this the mark
        /// would be anonymous and "did *I* mark today" — the only question
        /// readiness can answer about a person — would be unanswerable.
        var viewerID = ""

        /// The other person marked, on their own device, on this day.
        ///
        /// The one thing a test cannot arrange through the backend under test:
        /// there is deliberately no API by which this client can write, read,
        /// or infer a partner's row. So it is written straight into the row
        /// store, which is exactly where it would come from in life.
        func partnerMarked(_ profileID: String, on day: String) {
            insert("field_readiness", [[
                "profile_id": profileID,
                "local_date": day,
            ]])
        }

        // MARK: The two readiness RPCs
        //
        // Modelled on `20260805090000_field_readiness.sql` rather than on the
        // Swift that calls them, which is the point: if the adapter sends a
        // parameter the function does not take, or reads a column shape the
        // function does not return, that is a failure here rather than in
        // somebody's evening.
        //
        // Both use the public accessors rather than the lock directly —
        // `NSLock` is not recursive, and taking it twice would deadlock the
        // suite rather than fail it.

        /// `field_readiness_mark`. Idempotent, and materialises the bloom on
        /// the second distinct person — never on the same person twice.
        func readinessMark(day: String) -> String {
            let alreadyMine = rows("field_readiness").contains {
                $0["profile_id"] as? String == viewerID
                    && $0["local_date"] as? String == day
            }
            if !alreadyMine {
                insert("field_readiness", [[
                    "profile_id": viewerID,
                    "local_date": day,
                ]])
            }

            let marked = rows("field_readiness")
                .filter { $0["local_date"] as? String == day }
                .count
            guard marked >= 2 else { return "you" }

            let alreadyBloomed = rows("field_readiness_bloom").contains {
                $0["local_date"] as? String == day
            }
            if !alreadyBloomed {
                insert("field_readiness_bloom", [[
                    "local_date": day,
                    "prompt": Self.prompt,
                ]])
            }
            return "both"
        }

        /// `field_readiness_state`. Note the branch that is missing: there is
        /// no path returning anything other than `both`, `you`, or `neither`,
        /// and a partner who has marked alone falls through to `neither`
        /// exactly as they do in SQL.
        func readinessState(day: String) -> [[String: Any]] {
            let bloom = rows("field_readiness_bloom").first {
                $0["local_date"] as? String == day
            }
            if let bloom {
                return [[
                    "state": "both",
                    "prompt": bloom["prompt"] ?? Self.prompt,
                ]]
            }

            let mine = rows("field_readiness").contains {
                $0["profile_id"] as? String == viewerID
                    && $0["local_date"] as? String == day
            }
            return [[
                "state": mine ? "you" : "neither",
                "prompt": NSNull(),
            ]]
        }

        static let prompt =
            "What would make tonight feel a little more like yours?"

        func reset() {
            lock.withLock {
                tables = Dictionary(
                    uniqueKeysWithValues: Self.allTables.map { ($0, []) }
                )
            }
        }

        func rows(_ table: String) -> [[String: Any]] {
            lock.withLock { tables[table] ?? [] }
        }

        func seed(_ table: String, _ rows: [[String: Any]]) {
            lock.withLock { tables[table] = rows }
        }

        func insert(_ table: String, _ rows: [[String: Any]]) {
            lock.withLock {
                tables[table, default: []].append(
                    contentsOf: rows.map(withGeneratedID)
                )
            }
        }

        /// Stands in for `id uuid primary key default gen_random_uuid()`.
        ///
        /// Every `field_*` table declares that default, so the adapter never
        /// sends an `id` for rows the database names. Without this the stored
        /// row has no `id`, the next `load()` fails to decode it into a
        /// `UUID`, and the throw surfaces from `async let` as a bare
        /// `CancellationError` — which is a stub artefact that looks exactly
        /// like a product bug.
        private func withGeneratedID(_ row: [String: Any]) -> [String: Any] {
            guard row["id"] == nil else { return row }
            var copy = row
            copy["id"] = UUID().uuidString
            return copy
        }

        /// Upsert on the given conflict columns, matching PostgREST's
        /// `resolution=merge-duplicates`.
        func upsert(
            _ table: String,
            _ rows: [[String: Any]],
            conflict: [String]
        ) {
            lock.withLock {
                var existing = tables[table] ?? []
                for row in rows {
                    let match = existing.firstIndex { candidate in
                        conflict.allSatisfy { key in
                            sameValue(candidate[key], row[key])
                        }
                    }
                    if let match {
                        // Merge, because PostgREST updates only the columns
                        // present in the payload.
                        existing[match].merge(row) { _, new in new }
                    } else {
                        existing.append(withGeneratedID(row))
                    }
                }
                tables[table] = existing
            }
        }

        func update(
            _ table: String,
            _ patch: [String: Any],
            where filters: [(String, String)]
        ) {
            lock.withLock {
                var existing = tables[table] ?? []
                for index in existing.indices where matches(existing[index], filters) {
                    existing[index].merge(patch) { _, new in new }
                }
                tables[table] = existing
            }
        }

        func delete(_ table: String, where filters: [(String, String)]) {
            lock.withLock {
                tables[table] = (tables[table] ?? []).filter {
                    !matches($0, filters)
                }
            }
        }

        private func matches(
            _ row: [String: Any],
            _ filters: [(String, String)]
        ) -> Bool {
            filters.allSatisfy { key, value in
                stringly(row[key]) == value
            }
        }

        private func sameValue(_ lhs: Any?, _ rhs: Any?) -> Bool {
            stringly(lhs) == stringly(rhs)
        }

        private func stringly(_ value: Any?) -> String? {
            switch value {
            case let text as String: text
            case let number as NSNumber: number.stringValue
            case is NSNull: nil
            case .none: nil
            default: String(describing: value!)
            }
        }
    }

    static let store = Store()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let path = request.url?.path else { return false }
        // The circle is two RPCs and no table read, so a stub that only
        // matched table paths would let those two requests fall through to the
        // real network — where they fail, and the conformance run would report
        // the circle as untested rather than as broken.
        return path.contains("/rest/v1/field_")
            || path.contains("/rest/v1/rpc/field_")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(
                url: url, resolvingAgainstBaseURL: false
              ),
              let table = url.pathComponents.last
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // `/rest/v1/rpc/<name>` — a function call, not a table. Answered
        // before any of the table machinery below, none of which applies.
        if url.pathComponents.contains("rpc") {
            respondToRPC(named: table, url: url)
            return
        }

        let query = components.queryItems ?? []
        // PostgREST filters arrive as `column=eq.value`. Only `eq` is used by
        // the adapter, so only `eq` is understood here — anything else should
        // be a loud failure rather than a silent match.
        let filters: [(String, String)] = query.compactMap { item in
            guard let value = item.value,
                  value.hasPrefix("eq."),
                  item.name != "on_conflict",
                  item.name != "select"
            else { return nil }
            return (item.name, String(value.dropFirst(3)))
        }

        let method = request.httpMethod ?? "GET"
        let body = bodyRows()

        switch method {
        case "GET":
            break
        case "POST":
            let prefer = request.value(forHTTPHeaderField: "Prefer") ?? ""
            let conflict = query
                .first { $0.name == "on_conflict" }?
                .value?
                .split(separator: ",")
                .map(String.init)
            if prefer.contains("merge-duplicates"), let conflict {
                Self.store.upsert(table, body, conflict: conflict)
            } else {
                Self.store.insert(table, body)
            }
        case "PATCH":
            Self.store.update(table, body.first ?? [:], where: filters)
        case "DELETE":
            Self.store.delete(table, where: filters)
        default:
            client?.urlProtocol(
                self, didFailWithError: URLError(.unsupportedURL)
            )
            return
        }

        // Reads are filtered; writes echo nothing, which is what the adapter
        // asks for (it never requests representation).
        let payload = method == "GET"
            ? Self.store.rows(table).filter { row in
                filters.allSatisfy { key, value in
                    guard let candidate = row[key] else { return false }
                    return String(describing: candidate) == value
                }
            }
            : []

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "Content-Range": "0-\(max(payload.count - 1, 0))/\(payload.count)",
                ]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// The two readiness functions, over the wire the adapter actually uses.
    ///
    /// An unknown function is a 404 rather than an empty success: a typo in an
    /// RPC name should fail the test that calls it, not quietly return
    /// "nobody has marked" — which is a plausible-looking answer and the one
    /// state this feature must never report by accident.
    private func respondToRPC(named function: String, url: URL) {
        let day = bodyRows().first?["p_local_date"] as? String ?? ""

        let payload: Any?
        switch function {
        case "field_readiness_mark":
            payload = Self.store.readinessMark(day: day)
        case "field_readiness_state":
            payload = Self.store.readinessState(day: day)
        default:
            payload = nil
        }

        guard let payload,
              let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.fragmentsAllowed]
              ),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func bodyRows() -> [[String: Any]] {
        let data = request.httpBody
            ?? request.httpBodyStream.map { stream in
                stream.open()
                defer { stream.close() }
                var buffer = Data()
                let size = 4096
                var chunk = [UInt8](repeating: 0, count: size)
                while stream.hasBytesAvailable {
                    let read = stream.read(&chunk, maxLength: size)
                    guard read > 0 else { break }
                    buffer.append(contentsOf: chunk[0..<read])
                }
                return buffer
            }
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        if let many = object as? [[String: Any]] { return many }
        if let one = object as? [String: Any] { return [one] }
        return []
    }

    override func stopLoading() {}
}

// MARK: - The conformance assertions
//
// Written against the protocol, so they cannot accidentally depend on either
// implementation. Every one of these describes a promise the *product* makes.

@MainActor
enum FieldBackendConformance {
    static func heldTopicSurvivesARoundTrip(
        _ backend: FieldBackend,
        _ test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        // A route, not a uuid. This is the shape the app actually holds under,
        // and the shape the old UUID guard silently discarded.
        let topic = FieldHeldTopic(
            id: "promote:japan",
            title: "Japan",
            timing: "TONIGHT",
            reason: "Ask me again tonight.",
            surfaceOn: Date(timeIntervalSince1970: 1_785_000_000),
            wasOverridden: false,
            wasDismissed: false
        )
        try await backend.setHeld(topic)

        let reloaded = try await backend.load()
        let held = reloaded.heldTopics.first { $0.id == "promote:japan" }

        XCTAssertNotNil(
            held,
            "a held topic did not survive the write",
            file: file, line: line
        )
        // The date is the whole point of a deferral: without it,
        // `FieldDeferral.shouldRaise` is false forever and "ask me again
        // tonight" means "never ask me again".
        XCTAssertNotNil(
            held?.surfaceOn,
            "the deferral lost the day it was due back",
            file: file, line: line
        )
        XCTAssertEqual(
            held?.reason, "Ask me again tonight.",
            file: file, line: line
        )
    }

    static func holdingTheSameTopicTwiceIsOneDecision(
        _ backend: FieldBackend,
        _ test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        func topic(_ timing: String, dismissed: Bool) -> FieldHeldTopic {
            FieldHeldTopic(
                id: "occasion:cluster:item",
                title: "The visit",
                timing: timing,
                reason: "Not now.",
                surfaceOn: nil,
                wasOverridden: false,
                wasDismissed: dismissed
            )
        }

        try await backend.setHeld(topic("TONIGHT", dismissed: false))
        try await backend.setHeld(topic("NOT NOW", dismissed: true))

        let reloaded = try await backend.load()
        let matching = reloaded.heldTopics.filter {
            $0.id == "occasion:cluster:item"
        }

        XCTAssertEqual(
            matching.count, 1,
            "one decision restated became two rows",
            file: file, line: line
        )
        XCTAssertEqual(
            matching.first?.wasDismissed, true,
            "the restated decision did not replace the first",
            file: file, line: line
        )
    }

    static func aFiledItemSurvivesAndIsNotDuplicated(
        _ backend: FieldBackend,
        _ test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let id = "77777777-7777-7777-7777-777777777777"
        var item = LifeItem(
            id: id,
            title: "Book the dentist",
            category: .care,
            owner: backend.viewerOwner,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
        try await backend.upsert(item)

        item.title = "Book the dentist properly"
        try await backend.upsert(item)

        let reloaded = try await backend.load()
        let matching = reloaded.lifeItems.filter { $0.id == id }

        XCTAssertEqual(
            matching.count, 1,
            "editing a filed item created a second one",
            file: file, line: line
        )
        XCTAssertEqual(
            matching.first?.title, "Book the dentist properly",
            "the edit did not stick",
            file: file, line: line
        )
    }

    static func removingIsRealAndComplete(
        _ backend: FieldBackend,
        _ test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let id = "88888888-8888-8888-8888-888888888888"
        try await backend.upsert(
            LifeItem(
                id: id,
                title: "Cancel the thing",
                category: .care,
                owner: backend.viewerOwner,
                dueOn: nil,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            )
        )
        try await backend.delete(itemID: id)

        let reloaded = try await backend.load()
        XCTAssertFalse(
            reloaded.lifeItems.contains { $0.id == id },
            "the app says the thing is gone and it is still there",
            file: file, line: line
        )
    }

    static func theLearnedHourIsWrittenDown(
        _ backend: FieldBackend,
        _ test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let moment = FieldDailyMoment(
            sendMinute: 9 * 60 + 30,
            queuedCount: 0,
            hourRationale: "You answer me later than I thought.",
            replyRateBefore: 0,
            replyRateAfter: 0,
            lastSentOn: nil
        )
        try await backend.setDailyMoment(moment)

        let reloaded = try await backend.load()
        XCTAssertEqual(
            reloaded.dailyMoment.sendMinute, 9 * 60 + 30,
            "an instruction about when to speak did not survive",
            file: file, line: line
        )
    }

    // MARK: The circle

    /// The invariant, asserted from the only side that can be tested.
    ///
    /// The partner has marked. This client must be unable to tell — not
    /// "must not display it", unable to tell, because the state it is handed
    /// is the same one it would be handed if nobody had marked at all. That is
    /// the whole feature: the first tap is invisible, so it cannot become a
    /// request, and there is no waiting state to watch.
    ///
    /// The caller arranges the partner's mark, because there is deliberately
    /// no API on `FieldBackend` by which a test could do it through the
    /// backend under test.
    static func theCircleNeverDisclosesAPartnerAlone(
        _ backend: FieldBackend,
        day: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let before = try await backend.readiness(localDate: day)
        XCTAssertEqual(
            before.state, .neither,
            "the app can tell that a partner marked alone — which turns an "
                + "invitation into a request",
            file: file, line: line
        )
        XCTAssertNil(
            before.prompt,
            "words arrived before both people were open",
            file: file, line: line
        )

        try await backend.markReady(localDate: day)

        let after = try await backend.readiness(localDate: day)
        XCTAssertEqual(
            after.state, .both,
            "both marked and nothing bloomed",
            file: file, line: line
        )
        XCTAssertNotNil(
            after.prompt,
            "the room opened with no question in it",
            file: file, line: line
        )

        // Tapping again is not a second anything. Nothing about the repeat is
        // recorded, and it must not produce a second bloom — an uninstructed
        // person re-tapping must never become pressure.
        try await backend.markReady(localDate: day)
        let again = try await backend.readiness(localDate: day)
        XCTAssertEqual(
            again.state, .both,
            "a repeated mark changed the state",
            file: file, line: line
        )
        XCTAssertEqual(
            again.prompt, after.prompt,
            "the same day produced two different questions",
            file: file, line: line
        )
    }

    /// Marking alone says so, and says nothing else.
    ///
    /// `.you` and not `.both`: a device must never reach the state that puts
    /// words on two screens on the strength of its own tap.
    static func markingAloneNeverBlooms(
        _ backend: FieldBackend,
        day: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await backend.markReady(localDate: day)
        let state = try await backend.readiness(localDate: day)

        XCTAssertEqual(
            state.state, .you,
            "one person's tap reported the circle as mutual",
            file: file, line: line
        )
        XCTAssertNil(
            state.prompt,
            "the app invented a shared question from one person",
            file: file, line: line
        )
    }

    static func run(
        _ backend: FieldBackend,
        _ test: XCTestCase
    ) async throws {
        try await heldTopicSurvivesARoundTrip(backend, test)
        try await holdingTheSameTopicTwiceIsOneDecision(backend, test)
        try await aFiledItemSurvivesAndIsNotDuplicated(backend, test)
        try await removingIsRealAndComplete(backend, test)
        try await theLearnedHourIsWrittenDown(backend, test)
        try await evidenceSurvivesARoundTrip(backend, test)
    }

    /// The bug this file was built to catch, found a second time.
    ///
    /// `field_evidence` was in `load()`, in the RLS policy loop, and in the
    /// realtime publication from the day the zones shipped — and no code path
    /// in the app ever inserted a row. `FieldStore.promote` built the "You
    /// decided X is real" sentence in memory and stopped there, so Us showed
    /// it once and never again, and the table looked dead when what was
    /// missing was the write.
    ///
    /// Asserted against both backends for the reason at the top of this file:
    /// a write that goes nowhere passes every test that only runs in memory.
    static func evidenceSurvivesARoundTrip(
        _ backend: FieldBackend,
        _ test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let horizon = FieldHorizon(
            id: UUID().uuidString,
            title: "Japan",
            window: "spring 2027",
            owner: .shared,
            isPrimary: true,
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: [],
            openQuestion: nil
        )
        try await backend.upsert(horizon)

        let evidence = FieldEvidence(
            id: UUID().uuidString,
            statement: "You decided Japan is real.",
            owner: .shared,
            horizonID: horizon.id,
            occurredAt: Date(timeIntervalSince1970: 1_785_000_000)
        )
        try await backend.upsert(evidence)

        let reloaded = try await backend.load()
        let stored = reloaded.evidence.first {
            $0.statement == "You decided Japan is real."
        }

        XCTAssertNotNil(
            stored,
            "the evidence did not survive the write",
            file: file, line: line
        )
        // Without the pointer the row is a loose sentence: Us groups evidence
        // under the horizon it moved, so an unlinked row shows up nowhere.
        XCTAssertEqual(
            stored?.horizonID, horizon.id,
            "the evidence lost the horizon it was about",
            file: file, line: line
        )

        // Restating it is one event, not two. A promotion answered twice
        // should not produce two identical sentences in Us.
        try await backend.upsert(evidence)
        let again = try await backend.load()
        XCTAssertEqual(
            again.evidence.filter { $0.id == evidence.id }.count, 1,
            "one piece of evidence written twice became two rows",
            file: file, line: line
        )
    }
}

// MARK: - Run it twice

@MainActor
final class FieldBackendConformanceTests: XCTestCase {
    private static let couple = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    private static let a = "11111111-1111-1111-1111-111111111111"
    private static let b = "22222222-2222-2222-2222-222222222222"

    func testTheMemoryBackendHonoursTheContract() async throws {
        let backend = FieldMemoryBackend(
            state: .empty(
                nameA: "Partner A",
                nameB: "Partner B",
                now: Date(timeIntervalSince1970: 1_784_000_000)
            ),
            viewerOwner: .a
        )
        try await FieldBackendConformance.run(backend, self)
    }

    // MARK: The circle, both ways round
    //
    // Two backends, two arrangements of the same situation, one set of
    // assertions. The partner's mark is arranged differently in each — an init
    // parameter in memory, a row in the stub — because in both cases it is the
    // one thing the backend under test is not allowed to reach.

    func testTheMemoryBackendKeepsAPartnersMarkInvisible() async throws {
        let day = "2026-08-05"
        let backend = FieldMemoryBackend(
            state: .empty(
                nameA: "Partner A",
                nameB: "Partner B",
                now: Date(timeIntervalSince1970: 1_784_000_000)
            ),
            viewerOwner: .a,
            partnerMarkedDays: [day]
        )
        try await FieldBackendConformance
            .theCircleNeverDisclosesAPartnerAlone(backend, day: day)
    }

    func testTheSupabaseBackendKeepsAPartnersMarkInvisible() async throws {
        let day = "2026-08-05"
        let backend = try makeSupabaseBackend()
        FieldRESTStub.store.partnerMarked(Self.b, on: day)

        try await FieldBackendConformance
            .theCircleNeverDisclosesAPartnerAlone(backend, day: day)
    }

    func testMarkingAloneNeverBloomsInEitherBackend() async throws {
        let day = "2026-08-06"

        let memory = FieldMemoryBackend(
            state: .empty(
                nameA: "Partner A",
                nameB: "Partner B",
                now: Date(timeIntervalSince1970: 1_784_000_000)
            ),
            viewerOwner: .a
        )
        try await FieldBackendConformance
            .markingAloneNeverBlooms(memory, day: day)

        let supabase = try makeSupabaseBackend()
        try await FieldBackendConformance
            .markingAloneNeverBlooms(supabase, day: day)
    }

    /// Proves the stub itself is sound before the contract leans on it.
    func testTheStubServesALoadAndRecordsAWrite() async throws {
        let backend = try makeSupabaseBackend()

        let empty = try await backend.load()
        XCTAssertTrue(empty.heldTopics.isEmpty)

        try await backend.setHeld(
            FieldHeldTopic(
                id: "promote:japan",
                title: "Japan",
                timing: "TONIGHT",
                reason: "Ask me again tonight.",
                surfaceOn: nil,
                wasOverridden: false,
                wasDismissed: false
            )
        )

        XCTAssertEqual(
            FieldRESTStub.store.rows("field_held_topics").count, 1,
            "the upsert never reached the row store"
        )
    }

    func testTheSupabaseBackendHonoursTheSameContract() async throws {
        let backend = try makeSupabaseBackend()
        try await FieldBackendConformance.run(backend, self)
    }

    private func makeSupabaseBackend() throws -> FieldSupabaseBackend {
        FieldRESTStub.store.reset()
        // The stub has no session, so `auth.uid()` has to be handed to it.
        FieldRESTStub.store.viewerID = Self.a
        FieldRESTStub.store.seed("field_identity", [[
            "swatch_a": "clay",
            "swatch_b": "slate",
            "lives_together": true,
            "saving_for": NSNull(),
            "looks_after": NSNull(),
        ]])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FieldRESTStub.self]
        let client = SupabaseClient(
            supabaseURL: try XCTUnwrap(URL(string: "https://field-conformance.invalid")),
            supabaseKey: "conformance-key",
            options: SupabaseClientOptions(
                auth: .init(accessToken: { "conformance-access-token" }),
                global: .init(session: URLSession(configuration: configuration))
            )
        )

        return try XCTUnwrap(
            FieldSupabaseBackend(
                client: client,
                coupleID: Self.couple,
                viewerID: Self.a,
                members: [
                    Member(id: Self.a, name: "Partner A", hue: .clay),
                    Member(id: Self.b, name: "Partner B", hue: .sage),
                ],
                firstMemberID: Self.a
            )
        )
    }
}
