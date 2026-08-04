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
        ]

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
        request.url?.path.contains("/rest/v1/field_") == true
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

    static func run(
        _ backend: FieldBackend,
        _ test: XCTestCase
    ) async throws {
        try await heldTopicSurvivesARoundTrip(backend, test)
        try await holdingTheSameTopicTwiceIsOneDecision(backend, test)
        try await aFiledItemSurvivesAndIsNotDuplicated(backend, test)
        try await removingIsRealAndComplete(backend, test)
        try await theLearnedHourIsWrittenDown(backend, test)
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
