import Foundation
import Supabase
import XCTest
@testable import WE

private final class RealtimeSubscriptionAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribed = false
    private var failureDetail: String?

    func recordSuccess() {
        lock.withLock { subscribed = true }
    }

    func recordFailure(_ detail: String) {
        lock.withLock { failureDetail = detail }
    }

    var didSubscribe: Bool {
        lock.withLock { subscribed }
    }

    var failure: String? {
        lock.withLock { failureDetail }
    }
}

/// The literal two-simulator seam.
///
/// Nightly starts the Partner A method in one simulator and waits until its
/// Realtime channel has subscribed. It then starts the Partner B method in a
/// second simulator. The host coordinator only uses the service role to
/// provision and clean the disposable users; neither test process receives it.
@MainActor
final class FieldTwoSimulatorContractTests: XCTestCase {
    private struct RoleConfiguration {
        let supabase: SupabaseConfiguration
        let runID: String
        let email: String
        let password: String
        let captureText: String
        let readyText: String

        static func partnerA() throws -> RoleConfiguration {
            try fromEnvironment(
                emailName: "WE_QA_PARTNER_A_EMAIL",
                passwordName: "WE_QA_PARTNER_A_PASSWORD"
            )
        }

        static func partnerB() throws -> RoleConfiguration {
            try fromEnvironment(
                emailName: "WE_QA_PARTNER_B_EMAIL",
                passwordName: "WE_QA_PARTNER_B_PASSWORD"
            )
        }

        private static func fromEnvironment(
            emailName: String,
            passwordName: String
        ) throws -> RoleConfiguration {
            let values = ProcessInfo.processInfo.environment
            guard let rawURL = values["WE_QA_SUPABASE_URL"],
                  let url = URL(string: rawURL),
                  let anonKey = values["WE_QA_SUPABASE_ANON_KEY"],
                  !anonKey.isEmpty,
                  let runID = values["WE_QA_RUN_ID"],
                  !runID.isEmpty,
                  let email = values[emailName],
                  !email.isEmpty,
                  let password = values[passwordName],
                  !password.isEmpty,
                  let captureText = values["WE_QA_TWO_SIM_CAPTURE_TEXT"],
                  !captureText.isEmpty,
                  let readyText = values["WE_QA_TWO_SIM_READY_TEXT"],
                  !readyText.isEmpty
            else {
                throw XCTSkip(
                    "The two-simulator contract runs only through "
                        + "scripts/qa/run-two-simulator-contract.sh."
                )
            }

            XCTAssertNil(
                values["WE_QA_SUPABASE_SERVICE_ROLE_KEY"],
                "the service role must never enter an XCTest process"
            )
            return RoleConfiguration(
                supabase: SupabaseConfiguration(
                    url: url,
                    publishableKey: anonKey
                ),
                runID: runID,
                email: email,
                password: password,
                captureText: captureText,
                readyText: readyText
            )
        }
    }

    private struct CaptureActorRow: Decodable {
        let spoken_by: UUID
    }

    func testPartnerAWitnessesPartnerBCaptureOverRealtime() async throws {
        let configuration = try RoleConfiguration.partnerA()
        let provider = SupabaseClientProvider(
            configuration: configuration.supabase,
            authStorageKey: "we.qa.two-sim.\(configuration.runID).a"
        )
        let repository = SupabaseRepository(provider: provider)
        let signedIn = try await repository.signIn(
            email: configuration.email,
            password: configuration.password
        )
        let snapshot = try await repository.loadRelationship(for: signedIn)
        let backend = try makeBackend(
            provider: provider,
            snapshot: snapshot,
            viewerID: signedIn.id
        )
        XCTAssertEqual(backend.viewerOwner, .a)

        let subscriptionAttempted = expectation(
            description: "Partner A Realtime subscription attempt completed"
        )
        let subscriptionAttempt = RealtimeSubscriptionAttempt()
        let arrived = expectation(
            description: "Partner A observes Partner B's capture"
        )
        let changes = backend.changes(
            onSubscribed: {
                subscriptionAttempt.recordSuccess()
                subscriptionAttempted.fulfill()
            },
            onSubscriptionFailed: { detail in
                subscriptionAttempt.recordFailure(detail)
                subscriptionAttempted.fulfill()
            }
        )
        let observer = Task { @MainActor in
            for await _ in changes {
                guard let state = try? await backend.load(),
                      state.captures.contains(where: {
                          $0.text == configuration.captureText
                              && $0.owner == .b
                      })
                else { continue }
                arrived.fulfill()
                break
            }
        }
        defer { observer.cancel() }

        await fulfillment(of: [subscriptionAttempted], timeout: 20)
        if let failure = subscriptionAttempt.failure {
            XCTFail("Realtime subscription failed: \(failure)")
            return
        }
        guard subscriptionAttempt.didSubscribe else {
            XCTFail("Realtime subscription did not complete before timeout")
            return
        }

        // The coordinator polls for this exact row before it launches the B
        // process. Seeing it proves this process reached the subscribed state;
        // no guessed sleep sits between subscription and the partner write.
        try await backend.append(
            FieldCapture(
                id: UUID().uuidString,
                text: configuration.readyText,
                owner: .a,
                capturedAt: Date()
            )
        )

        await fulfillment(of: [arrived], timeout: 90)
        let observed: FieldCapture = try await eventually(timeout: .seconds(20)) {
            let state = try await backend.load()
            return state.captures.first {
                $0.text == configuration.captureText && $0.owner == .b
            }
        }
        XCTAssertEqual(observed.owner, .b)
    }

    func testPartnerBWritesCaptureAsPartnerB() async throws {
        let configuration = try RoleConfiguration.partnerB()
        let provider = SupabaseClientProvider(
            configuration: configuration.supabase,
            authStorageKey: "we.qa.two-sim.\(configuration.runID).b"
        )
        let repository = SupabaseRepository(provider: provider)
        let signedIn = try await repository.signIn(
            email: configuration.email,
            password: configuration.password
        )
        let snapshot = try await repository.loadRelationship(for: signedIn)
        let backend = try makeBackend(
            provider: provider,
            snapshot: snapshot,
            viewerID: signedIn.id
        )
        XCTAssertEqual(backend.viewerOwner, .b)

        // Deliberately lie in the in-memory owner field. The live adapter and
        // database actor trigger must derive authorship from B's session.
        try await backend.append(
            FieldCapture(
                id: UUID().uuidString,
                text: configuration.captureText,
                owner: .a,
                capturedAt: Date()
            )
        )

        let client = try XCTUnwrap(provider.client)
        let actor: CaptureActorRow = try await eventually {
            let rows: [CaptureActorRow] = try await client
                .from("field_captures")
                .select("spoken_by")
                .eq("text", value: configuration.captureText)
                .execute()
                .value
            return rows.first
        }
        XCTAssertEqual(actor.spoken_by, UUID(uuidString: signedIn.id))

        let reloaded: FieldCapture = try await eventually {
            let state = try await backend.load()
            return state.captures.first {
                $0.text == configuration.captureText
            }
        }
        XCTAssertEqual(reloaded.owner, .b)
    }

    private func makeBackend(
        provider: SupabaseClientProvider,
        snapshot: RelationshipSnapshot,
        viewerID: String
    ) throws -> FieldSupabaseBackend {
        let coupleID = try XCTUnwrap(snapshot.membership?.coupleID)
        let firstMemberID = try XCTUnwrap(snapshot.members.first?.id)
        return try XCTUnwrap(
            FieldSupabaseBackend(
                client: provider.client,
                coupleID: coupleID,
                viewerID: viewerID,
                members: snapshot.members,
                firstMemberID: firstMemberID
            )
        )
    }

    private func eventually<T>(
        timeout: Duration = .seconds(20),
        operation: @escaping @MainActor () async throws -> T?
    ) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let value = try await operation() {
                return value
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw NSError(
            domain: "WE.FieldTwoSimulatorContract",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Timed out waiting for the cross-simulator contract."
            ]
        )
    }
}
