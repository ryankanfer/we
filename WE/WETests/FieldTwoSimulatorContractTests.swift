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

    /// Deliberately selects `profile_id`, which is the column the RLS policy
    /// exists to keep on one side of the couple. A test that only ever asked
    /// for its own rows could not tell a working policy from a missing one.
    private struct CeremonyRow: Decodable {
        let profile_id: UUID
        let beat: String
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

        // MARK: The ceremony, from A's side
        //
        // Deliberately before the readiness row, which is the coordinator's
        // barrier: B has not signed in yet, so "the aggregate is still false"
        // is a fact rather than a race. This is the assertion the hermetic
        // suite can only make against a fake — one phone cannot advance a beat
        // alone, and here the refusing party is the real RPC.
        let beat = WEBeat.yoursStaysYours
        try await backend.keepBeat(beat)

        let mine: Set<WEBeat> = try await backend.myAcknowledgements()
        XCTAssertTrue(
            mine.contains(beat),
            "A's own acknowledgement did not come back to A"
        )
        let keptAlone = try await backend.keptBeats()
        XCTAssertFalse(
            keptAlone.contains(beat),
            "the aggregate resolved on one acknowledgement"
        )

        // Idempotent, against the live `on conflict do nothing`. A phone that
        // loses its connection mid beat says the same thing again, and must
        // not be told it already did.
        try await backend.keepBeat(beat)
        let mineAgain = try await backend.myAcknowledgements()
        XCTAssertEqual(mineAgain, mine)

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

        // MARK: The beat resolving, on the other phone's acknowledgement
        //
        // Through the aggregate, and only through the aggregate. There is no
        // row event to wait on here by design: `ceremony_acknowledgements` is
        // absent from `observedTables`, because a realtime row event carries
        // its own arrival time, which is the partner's timing wearing a
        // different hat. Polling a bare boolean is the whole mechanism.
        let resolved: Bool = try await eventually(timeout: .seconds(90)) {
            let kept = try await backend.keptBeats()
            return kept.contains(beat) ? true : nil
        }
        XCTAssertTrue(resolved)

        // MARK: What A can read of B's side, which is nothing
        //
        // Owner only RLS on select, exercised against the live policy rather
        // than against a fake that was written to honour it. Asking for every
        // row of the couple's table returns A's own and stops there — even
        // though both people have now acknowledged the same beat.
        let client = try XCTUnwrap(provider.client)
        let rows: [CeremonyRow] = try await client
            .from("ceremony_acknowledgements")
            .select("profile_id,beat")
            .execute()
            .value
        XCTAssertFalse(rows.isEmpty, "A cannot see its own acknowledgement")
        XCTAssertTrue(
            rows.allSatisfy { $0.profile_id == UUID(uuidString: signedIn.id) },
            "a partner's acknowledgement row reached the other phone"
        )
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

        // MARK: The ceremony, from B's side
        //
        // A kept this beat before the readiness barrier, so the aggregate is
        // waiting on this acknowledgement and nothing else. It flips here, on
        // B's write, which is what "neither screen advances until both people
        // have acknowledged" means when the two screens are on two devices.
        let beat = WEBeat.yoursStaysYours
        let keptBeforeB = try await backend.keptBeats()
        XCTAssertFalse(
            keptBeforeB.contains(beat),
            "the aggregate resolved before B acknowledged"
        )
        try await backend.keepBeat(beat)

        let kept: Bool = try await eventually(timeout: .seconds(30)) {
            let beats = try await backend.keptBeats()
            return beats.contains(beat) ? true : nil
        }
        XCTAssertTrue(kept)

        // B's own row is B's, and B sees no more of the table than A does.
        let rows: [CeremonyRow] = try await client
            .from("ceremony_acknowledgements")
            .select("profile_id,beat")
            .execute()
            .value
        XCTAssertTrue(
            rows.allSatisfy { $0.profile_id == UUID(uuidString: signedIn.id) },
            "a partner's acknowledgement row reached the other phone"
        )
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
