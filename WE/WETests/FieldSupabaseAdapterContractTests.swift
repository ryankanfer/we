import Foundation
import Supabase
import XCTest
@testable import WE

/// A deterministic PostgREST surface for the live Field adapter.
///
/// These are not repository fakes: `FieldSupabaseBackend` still builds and
/// executes the real Supabase queries and decodes their real response shape.
/// Only the transport is local, so a Swift DTO/schema drift fails every PR
/// without requiring Docker or shared credentials.
private final class FieldAdapterURLProtocol: URLProtocol, @unchecked Sendable {
    private static let a = "11111111-1111-1111-1111-111111111111"
    private static let b = "22222222-2222-2222-2222-222222222222"
    private static let life = "33333333-3333-3333-3333-333333333333"
    private static let horizon = "44444444-4444-4444-4444-444444444444"

    private static let bodies: [String: String] = [
        "field_identity": """
        [{
          "swatch_a":"clay",
          "swatch_b":"slate",
          "lives_together":true,
          "saving_for":"a quiet week",
          "looks_after":null
        }]
        """,
        "field_away_windows": "[]",
        "field_clusters": """
        [{
          "id":"55555555-5555-5555-5555-555555555555",
          "title":"Saturday",
          "rationale":"Three things share a day.",
          "tint":"shared",
          "timeframe":"this weekend",
          "anchor_date":"2026-08-01"
        }]
        """,
        "field_life_items": """
        [{
          "id":"\(life)",
          "title":"Book the dentist",
          "category":"care",
          "owner":"b",
          "due_on":"2026-08-01",
          "closes_at":null,
          "cluster_id":null,
          "source":"captured",
          "detail":null,
          "is_time_critical":false,
          "is_done":false
        }]
        """,
        "field_horizons": """
        [{
          "id":"\(horizon)",
          "title":"Make more room",
          "window_label":"this season",
          "owner":"shared",
          "is_primary":true,
          "thesis":"Protect ordinary time.",
          "target_date":"2026-12-01",
          "linked_life_item_ids":["\(life)"]
        }]
        """,
        "field_questions": """
        [{
          "id":"66666666-6666-6666-6666-666666666666",
          "horizon_id":"\(horizon)",
          "prompt":"Keep this?",
          "stakes":"It changes the week.",
          "reasoning":"You both named it.",
          "choice_a":"Keep it",
          "choice_b":"Change it",
          "answered_choice":null
        }]
        """,
        "field_rhythms": """
        [{
          "id":"77777777-7777-7777-7777-777777777777",
          "title":"Thursday dinner",
          "cadence":"weekly",
          "health":"running",
          "horizon_id":"\(horizon)",
          "occurrences":4,
          "last_occurred_at":"2026-07-30T22:00:00Z"
        }]
        """,
        "field_evidence": """
        [{
          "id":"88888888-8888-8888-8888-888888888888",
          "statement":"You protected dinner.",
          "owner":"shared",
          "horizon_id":"\(horizon)",
          "occurred_at":"2026-07-30T22:00:00Z"
        }]
        """,
        "field_held_topics": """
        [{
          "id":"99999999-9999-9999-9999-999999999999",
          "client_id":"promote:the move",
          "title":"The move",
          "timing":"after the weekend",
          "reason":"Not tonight.",
          "surface_on":"2026-08-03",
          "was_overridden":false,
          "was_dismissed":false
        }]
        """,
        "field_standing_rules": """
        [{
          "id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "text":"Never on a work morning.",
          "set_at":"2026-07-01T12:00:00Z"
        }]
        """,
        "field_captures": """
        [{
          "id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          "text":"Book the dentist",
          "spoken_by":"\(b)",
          "captured_at":"2026-07-31T12:00:00Z"
        }]
        """,
        "field_corrections": """
        [{
          "id":"cccccccc-cccc-cccc-cccc-cccccccccccc",
          "input":"book the dentist",
          "original_destination":"Notes",
          "corrected_destination":"Care",
          "corrected_at":"2026-07-31T12:01:00Z"
        }]
        """,
        "field_daily_moment": """
        [{
          "send_minute":492,
          "hour_rationale":"It is when you both reply.",
          "reply_rate_before":0.25,
          "reply_rate_after":0.5,
          "last_sent_on":"2026-07-30"
        }]
        """,
        // Two rows, deliberately out of order. `load()` sorts them, because a
        // `FieldState` differing from the replay's only in this array's order
        // would compare unequal and redraw LIFE for nothing.
        //
        // The extra columns are here and unread: the table records who put a
        // group away and when, and nothing on screen ever names either. A DTO
        // that started decoding `hidden_by` would be the first step toward
        // copy that tells one partner the other did it.
        "field_hidden_categories": """
        [
          {
            "category":"watchlist",
            "hidden_by":"\(b)",
            "hidden_at":"2026-08-02T09:00:00Z"
          },
          {
            "category":"money",
            "hidden_by":"\(a)",
            "hidden_at":"2026-08-01T09:00:00Z"
          }
        ]
        """,
    ]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.contains("/rest/v1/field_") == true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let table = url.pathComponents.last,
              let body = Self.bodies[table],
              let data = body.data(using: .utf8),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "Content-Range": "0-0/1",
                ]
              )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class FieldSupabaseAdapterContractTests: XCTestCase {
    func testEveryLiveFieldRowDecodesWithPartnerBOwnership() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FieldAdapterURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let baseURL = try XCTUnwrap(
            URL(string: "https://field-contract.invalid")
        )
        let client = SupabaseClient(
            supabaseURL: baseURL,
            supabaseKey: "adapter-contract-key",
            options: SupabaseClientOptions(
                auth: .init(
                    // PostgREST asks the Supabase client for the current
                    // access token before sending a request. Supplying one
                    // here exercises that real authenticated path while the
                    // local URLProtocol remains the only transport.
                    accessToken: { "adapter-contract-access-token" }
                ),
                global: .init(session: session)
            ),
        )
        let couple = "dddddddd-dddd-dddd-dddd-dddddddddddd"
        let a = "11111111-1111-1111-1111-111111111111"
        let b = "22222222-2222-2222-2222-222222222222"
        let backend = try XCTUnwrap(
            FieldSupabaseBackend(
                client: client,
                coupleID: couple,
                viewerID: b,
                members: [
                    Member(id: a, name: "Partner A", hue: .clay),
                    Member(id: b, name: "Partner B", hue: .sage),
                ],
                firstMemberID: a
            )
        )

        let state = try await backend.load()

        XCTAssertEqual(backend.viewerOwner, .b)
        XCTAssertEqual(state.identity.nameA, "Partner A")
        XCTAssertEqual(state.identity.nameB, "Partner B")
        XCTAssertEqual(state.identity.savingFor, "a quiet week")
        XCTAssertEqual(state.lifeItems.first?.owner, .b)
        XCTAssertEqual(state.lifeItems.first?.category, .care)
        XCTAssertNotNil(state.lifeItems.first?.dueOn)
        XCTAssertNotNil(state.clusters.first?.anchorDate)
        XCTAssertNotNil(state.horizons.first?.openQuestion)
        XCTAssertNotNil(state.horizons.first?.targetDate)
        XCTAssertEqual(state.rhythms.first?.occurrences, 4)
        XCTAssertEqual(state.evidence.first?.owner, .shared)
        XCTAssertEqual(state.heldTopics.first?.title, "The move")
        XCTAssertNotNil(state.heldTopics.first?.surfaceOn)
        XCTAssertEqual(state.standingRules.first?.text, "Never on a work morning.")
        XCTAssertEqual(state.captures.first?.owner, .b)
        XCTAssertEqual(state.corrections.first?.corrected, .care)
        XCTAssertEqual(state.dailyMoment.sendMinute, 492)
        XCTAssertEqual(state.dailyMoment.replyRateAfter, 0.5)
        XCTAssertNotNil(state.dailyMoment.lastSentOn)
        XCTAssertEqual(
            state.hiddenCategories, ["money", "watchlist"],
            "put-away groups arrived in the order the rows happened to come "
                + "back, which the replay would never produce"
        )
    }
}
