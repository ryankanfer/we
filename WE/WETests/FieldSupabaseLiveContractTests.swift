import Foundation
import PostgREST
import Supabase
import XCTest
@testable import WE

private final class OfflineFieldURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.notConnectedToInternet)
        )
    }

    override func stopLoading() {}
}

/// The real two-person seam.
///
/// This suite is intentionally absent from preview data. Nightly CI points it
/// at an isolated Supabase stack. Its host coordinator supplies disposable
/// Partner A, Partner B, and outsider credentials, but never the service role.
/// A normal local/PR unit run skips it; pgTAP and the pure adapter regression
/// tests remain the fast schema/ownership gate on every pull request.
@MainActor
final class FieldSupabaseLiveContractTests: XCTestCase {
    private struct Configuration {
        let supabase: SupabaseConfiguration
        let runID: String
        let partnerA: TestUser
        let partnerB: TestUser
        let outsider: TestUser

        static func fromEnvironment() throws -> Configuration {
            let values = ProcessInfo.processInfo.environment
            guard let rawURL = values["WE_QA_SUPABASE_URL"],
                  let url = URL(string: rawURL),
                  let anonKey = values["WE_QA_SUPABASE_ANON_KEY"],
                  !anonKey.isEmpty,
                  let runID = values["WE_QA_RUN_ID"],
                  !runID.isEmpty
            else {
                throw XCTSkip(
                    "Run the isolated live-couple contract through "
                        + "scripts/qa/run-live-repository-contract.sh."
                )
            }
            XCTAssertNil(
                values["WE_QA_SUPABASE_SERVICE_ROLE_KEY"],
                "the service role must never enter an XCTest process"
            )
            return Configuration(
                supabase: SupabaseConfiguration(
                    url: url,
                    publishableKey: anonKey
                ),
                runID: runID,
                partnerA: try testUser(
                    values,
                    prefix: "WE_QA_PARTNER_A",
                    name: "Contract A"
                ),
                partnerB: try testUser(
                    values,
                    prefix: "WE_QA_PARTNER_B",
                    name: "Contract B"
                ),
                outsider: try testUser(
                    values,
                    prefix: "WE_QA_OUTSIDER",
                    name: "Contract Outsider"
                )
            )
        }

        private static func testUser(
            _ values: [String: String],
            prefix: String,
            name: String
        ) throws -> TestUser {
            guard let id = values["\(prefix)_ID"],
                  !id.isEmpty,
                  let email = values["\(prefix)_EMAIL"],
                  !email.isEmpty,
                  let password = values["\(prefix)_PASSWORD"],
                  !password.isEmpty
            else {
                throw XCTSkip(
                    "The host coordinator did not provide \(prefix)."
                )
            }
            return TestUser(
                id: id,
                name: name,
                email: email,
                password: password
            )
        }
    }

    private struct TestUser {
        let id: String
        let name: String
        let email: String
        let password: String
    }

    private struct VisibleFieldRow: Decodable {
        let id: UUID
    }

    private struct VisibleInsightRow: Decodable {
        let insight_id: UUID
    }

    private struct CaptureActorRow: Decodable {
        let spoken_by: UUID
    }

    private struct CorrectionActorRow: Decodable {
        let corrected_by: UUID
    }

    private struct LifeItemActorRow: Decodable {
        let owner: String
        let created_by: UUID?
    }

    private struct PersistedPartnerBWrite {
        let state: FieldState
        let item: LifeItem
        let capture: CaptureActorRow
        let correction: CorrectionActorRow
        let lifeItem: LifeItemActorRow
    }

    func testRealCoupleLifecycleAndPrivacy() async throws {
        let configuration = try Configuration.fromEnvironment()
        try await exerciseContract(
            configuration: configuration.supabase,
            partnerA: configuration.partnerA,
            partnerB: configuration.partnerB,
            outsider: configuration.outsider,
            run: configuration.runID
        )
    }

    private func exerciseContract(
        configuration: SupabaseConfiguration,
        partnerA: TestUser,
        partnerB: TestUser,
        outsider: TestUser,
        run: String
    ) async throws {
        let providerA = provider(
            configuration,
            storageKey: "we.qa.\(run).a"
        )
        let providerB = provider(
            configuration,
            storageKey: "we.qa.\(run).b"
        )
        let providerOutsider = provider(
            configuration,
            storageKey: "we.qa.\(run).outsider"
        )
        let repositoryA = SupabaseRepository(provider: providerA)
        let repositoryB = SupabaseRepository(provider: providerB)
        let repositoryOutsider = SupabaseRepository(provider: providerOutsider)

        let signedInA = try await repositoryA.signIn(
            email: partnerA.email,
            password: partnerA.password
        )
        let signedInB = try await repositoryB.signIn(
            email: partnerB.email,
            password: partnerB.password
        )
        let signedInOutsider = try await repositoryOutsider.signIn(
            email: outsider.email,
            password: outsider.password
        )

        try await repositoryA.createCouple()
        var snapshotA = try await repositoryA.loadRelationship(for: signedInA)
        let joinCode = try XCTUnwrap(snapshotA.couple?.joinCode)
        try await repositoryB.joinCouple(code: joinCode)

        snapshotA = try await repositoryA.loadRelationship(for: signedInA)
        var snapshotB = try await repositoryB.loadRelationship(for: signedInB)
        let outsiderSnapshot = try await repositoryOutsider.loadRelationship(
            for: signedInOutsider
        )

        XCTAssertEqual(snapshotA.members.map(\.id), [partnerA.id, partnerB.id])
        XCTAssertEqual(snapshotB.members.map(\.id), [partnerA.id, partnerB.id])
        XCTAssertNil(outsiderSnapshot.membership)
        XCTAssertTrue(outsiderSnapshot.members.isEmpty)

        let coupleID = try XCTUnwrap(snapshotA.membership?.coupleID)
        let firstMemberID = try XCTUnwrap(snapshotA.members.first?.id)
        let backendA = try XCTUnwrap(
            FieldSupabaseBackend(
                client: providerA.client,
                coupleID: coupleID,
                viewerID: signedInA.id,
                members: snapshotA.members,
                firstMemberID: firstMemberID
            )
        )
        let backendB = try XCTUnwrap(
            FieldSupabaseBackend(
                client: providerB.client,
                coupleID: coupleID,
                viewerID: signedInB.id,
                members: snapshotB.members,
                firstMemberID: firstMemberID
            )
        )
        XCTAssertEqual(backendA.viewerOwner, .a)
        XCTAssertEqual(backendB.viewerOwner, .b)
        XCTAssertNil(
            FieldSupabaseBackend(
                client: providerOutsider.client,
                coupleID: coupleID,
                viewerID: signedInOutsider.id,
                members: snapshotA.members,
                firstMemberID: firstMemberID
            )
        )

        // Onboarding writes the holder's colour only. Each partner sees the
        // same shared answers, while B cannot overwrite A's side.
        var identityA = try await backendA.load().identity
        identityA.personA = .amber
        identityA.personB = .indigo
        identityA.livesTogether = true
        identityA.savingFor = "Contract cabin \(run.prefix(8))"
        identityA.looksAfter = "Contract dog"
        try await backendA.setIdentity(identityA)

        var identityB = try await backendB.load().identity
        XCTAssertEqual(identityB.personA, .amber)
        XCTAssertEqual(identityB.personB, .slate)
        identityB.personA = .rust
        identityB.personB = .teal
        try await backendB.setIdentity(identityB)

        let onboardedA = try await backendA.load().identity
        let onboardedB = try await backendB.load().identity
        XCTAssertEqual(onboardedA.personA, .amber)
        XCTAssertEqual(onboardedA.personB, .teal)
        XCTAssertEqual(onboardedB.personA, .amber)
        XCTAssertEqual(onboardedB.personB, .teal)
        XCTAssertEqual(
            onboardedB.savingFor,
            "Contract cabin \(run.prefix(8))"
        )

        // Capture → correct → send through the real store and live adapter.
        // The database result, A's view, and B's view must all agree on B.
        let initialB = try await backendB.load()
        let storeB = FieldStore(
            state: initialB,
            now: Date(),
            backend: backendB
        )
        let partnerBClient = try XCTUnwrap(providerB.client)
        let realtimeReady = expectation(
            description: "Partner A's realtime channel is subscribed"
        )
        let realtime = expectation(description: "Partner A receives B's write")
        let changes = backendA.changes(
            onSubscribed: {
                realtimeReady.fulfill()
            },
            onSubscriptionFailed: { detail in
                XCTFail("Realtime subscription failed: \(detail)")
                realtimeReady.fulfill()
            }
        )
        let realtimeTask = Task {
            for await _ in changes {
                realtime.fulfill()
                break
            }
        }
        await fulfillment(of: [realtimeReady], timeout: 12)

        let capturedTitle = "Contract plumber \(run.prefix(8))"
        storeB.captureDraft = capturedTitle
        storeB.submitCapture()
        storeB.beginCorrection()
        storeB.correct(to: .home)
        storeB.send()

        await fulfillment(of: [realtime], timeout: 12)
        realtimeTask.cancel()

        let persisted: PersistedPartnerBWrite = try await eventually {
            let state = try await backendB.load()
            guard let item = state.lifeItems.first(where: {
                $0.title.localizedCaseInsensitiveContains("contract plumber")
            }) else { return nil }

            async let captureRequest: [CaptureActorRow] = partnerBClient
                .from("field_captures")
                .select("spoken_by")
                .eq("couple_id", value: coupleID)
                .eq("text", value: item.title)
                .execute()
                .value
            async let correctionRequest: [CorrectionActorRow] = partnerBClient
                .from("field_corrections")
                .select("corrected_by")
                .eq("couple_id", value: coupleID)
                .eq("input", value: capturedTitle)
                .execute()
                .value
            async let itemRequest: [LifeItemActorRow] = partnerBClient
                .from("field_life_items")
                .select("owner,created_by")
                .eq("id", value: item.id)
                .execute()
                .value

            let (captures, corrections, items) = try await (
                captureRequest,
                correctionRequest,
                itemRequest
            )
            guard let capture = captures.first,
                  let correction = corrections.first,
                  let lifeItem = items.first
            else { return nil }
            return PersistedPartnerBWrite(
                state: state,
                item: item,
                capture: capture,
                correction: correction,
                lifeItem: lifeItem
            )
        }
        let reloadedB = persisted.state
        let filedByB = persisted.item
        XCTAssertEqual(filedByB.owner, .b)
        XCTAssertEqual(
            reloadedB.captures.first {
                $0.text.localizedCaseInsensitiveContains("contract plumber")
            }?.owner,
            .b
        )
        let reloadedA = try await backendA.load()
        XCTAssertEqual(
            reloadedA.lifeItems.first { $0.id == filedByB.id }?.owner,
            .b
        )

        let outsiderClient = try XCTUnwrap(providerOutsider.client)
        XCTAssertEqual(
            persisted.capture.spoken_by.uuidString,
            partnerB.id
        )
        XCTAssertEqual(
            persisted.correction.corrected_by.uuidString,
            partnerB.id
        )
        XCTAssertEqual(persisted.lifeItem.owner, FieldOwner.b.rawValue)
        XCTAssertEqual(
            persisted.lifeItem.created_by?.uuidString,
            partnerB.id
        )

        let outsiderRows: [VisibleFieldRow] = try await outsiderClient
            .from("field_life_items")
            .select("id")
            .execute()
            .value
        XCTAssertTrue(outsiderRows.isEmpty)

        // Private answer content remains owner-only before and after mutual
        // reveal. The only shared output is the safe direction.
        let idleRecord = try XCTUnwrap(
            snapshotA.insights.first {
                $0.consent == nil || $0.consent?.readiness == .idle
            },
            "the seeded relationship needs an idle consent topic"
        )
        let insight = idleRecord.insight
        let firstChoice = try XCTUnwrap(insight.options.first)
        let secondChoice = insight.options.dropFirst().first ?? firstChoice
        try await repositoryA.requestReveal(insightID: insight.id)
        try await repositoryB.acceptReveal(insightID: insight.id)
        try await repositoryA.submitResponse(
            insightID: insight.id,
            choice: firstChoice,
            note: "PRIVATE_A_\(run)"
        )

        snapshotB = try await repositoryB.loadRelationship(for: signedInB)
        var recordB = try XCTUnwrap(
            snapshotB.insights.first { $0.id == insight.id }
        )
        XCTAssertFalse(
            recordB.responses.contains {
                $0.choice == firstChoice || $0.note == "PRIVATE_A_\(run)"
            }
        )

        try await repositoryB.submitResponse(
            insightID: insight.id,
            choice: secondChoice,
            note: "PRIVATE_B_\(run)"
        )
        snapshotA = try await repositoryA.loadRelationship(for: signedInA)
        snapshotB = try await repositoryB.loadRelationship(for: signedInB)
        let recordA = try XCTUnwrap(
            snapshotA.insights.first { $0.id == insight.id }
        )
        recordB = try XCTUnwrap(
            snapshotB.insights.first { $0.id == insight.id }
        )
        XCTAssertNotNil(recordA.sharedDirection)
        XCTAssertNotNil(recordB.sharedDirection)
        XCTAssertFalse(
            recordA.responses.contains {
                $0.choice == secondChoice || $0.note == "PRIVATE_B_\(run)"
            }
        )
        XCTAssertFalse(
            recordB.responses.contains {
                $0.choice == firstChoice || $0.note == "PRIVATE_A_\(run)"
            }
        )

        let outsiderPrivateRows: [VisibleInsightRow] = try await outsiderClient
            .from("responses")
            .select("insight_id")
            .eq("insight_id", value: insight.id)
            .execute()
            .value
        let outsiderDirectionRows: [VisibleInsightRow] = try await outsiderClient
            .from("shared_directions")
            .select("insight_id")
            .eq("insight_id", value: insight.id)
            .execute()
            .value
        XCTAssertTrue(outsiderPrivateRows.isEmpty)
        XCTAssertTrue(outsiderDirectionRows.isEmpty)

        // A fresh repository with B's storage key restores the same session
        // even when transport is offline. The relationship load fails closed,
        // then an online client with the same storage key reconnects and sees
        // the persisted row. Sign-out clears that restoration.
        let offlineConfiguration = URLSessionConfiguration.ephemeral
        offlineConfiguration.protocolClasses = [OfflineFieldURLProtocol.self]
        let offlineProviderB = provider(
            configuration,
            storageKey: "we.qa.\(run).b",
            session: URLSession(configuration: offlineConfiguration)
        )
        let offlineRepositoryB = SupabaseRepository(provider: offlineProviderB)
        let offlineRestoredB = try await offlineRepositoryB.restoreSession()
        XCTAssertEqual(offlineRestoredB?.id, partnerB.id)
        do {
            _ = try await offlineRepositoryB.loadRelationship(for: signedInB)
            XCTFail("an offline transport must not fabricate live state")
        } catch {
            // Reaching this branch is the contract. Supabase may wrap the
            // URLProtocol's URLError in a PostgREST error between SDK releases;
            // requiring the wrapper type would turn a real fail-closed result
            // into a version-sensitive false failure.
        }

        let restartedProviderB = provider(
            configuration,
            storageKey: "we.qa.\(run).b"
        )
        let restartedRepositoryB = SupabaseRepository(
            provider: restartedProviderB
        )
        let restoredB = try await restartedRepositoryB.restoreSession()
        XCTAssertEqual(restoredB?.id, partnerB.id)
        try await restartedRepositoryB.signOut()
        let signedOutSession = try await restartedRepositoryB.restoreSession()
        XCTAssertNil(signedOutSession)
        _ = try await restartedRepositoryB.signIn(
            email: partnerB.email,
            password: partnerB.password
        )
        let restartedSnapshotB = try await restartedRepositoryB
            .loadRelationship(for: signedInB)
        let restartedBackendB = try XCTUnwrap(
            FieldSupabaseBackend(
                client: restartedProviderB.client,
                coupleID: coupleID,
                viewerID: signedInB.id,
                members: restartedSnapshotB.members,
                firstMemberID: firstMemberID
            )
        )
        let restartedStateB = try await restartedBackendB.load()
        XCTAssertEqual(
            restartedStateB.lifeItems.first { $0.id == filedByB.id }?.owner,
            .b
        )

        // Deleting B archives the shared relationship for A and removes the
        // live couple. Field rows disappear with the couple cascade.
        try await restartedRepositoryB.deleteAccount(
            email: partnerB.email,
            password: partnerB.password
        )
        let afterDeletionA = try await repositoryA.loadRelationship(
            for: signedInA
        )
        XCTAssertNil(afterDeletionA.membership)
        XCTAssertEqual(afterDeletionA.archives.count, 1)
        XCTAssertTrue(afterDeletionA.members.isEmpty)
    }

    private func provider(
        _ configuration: SupabaseConfiguration,
        storageKey: String,
        session: URLSession? = nil
    ) -> SupabaseClientProvider {
        SupabaseClientProvider(
            configuration: configuration,
            authStorageKey: storageKey,
            session: session
        )
    }

    private func eventually<T>(
        timeout: Duration = .seconds(12),
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
            domain: "WE.FieldSupabaseLiveContract",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Timed out waiting for the live Supabase contract."
            ]
        )
    }
}
