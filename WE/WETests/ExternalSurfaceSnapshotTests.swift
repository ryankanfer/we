import Foundation
import Testing
@testable import WE

@MainActor
struct ExternalSurfaceSnapshotTests {
    @Test
    func genericWordingIsTheDefaultBoundary() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "WE.ExternalSurfaceTests.generic")
        )
        defaults.removePersistentDomain(
            forName: "WE.ExternalSurfaceTests.generic"
        )
        let store = ExternalSurfaceStore(defaults: defaults)
        let approved = try #require(
            ExplicitlyPermittedSharedWording(
                sharedDirection: sharedDirection(
                    title: "Start with a little room"
                )
            )
        )
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let snapshot = ExternalSurfaceSnapshot(
            displayState: .sharedRoomActive,
            expiresAt: now.addingTimeInterval(600),
            permittedSharedWording: approved,
            now: now
        )

        store.save(snapshot, allowsSpecificWording: false)
        let stored = try #require(store.read(now: now))

        #expect(!stored.containsSpecificWording)
        #expect(
            stored.wording(at: now)
                == ExternalSurfaceDisplayState.sharedRoomActive.genericWording
        )
    }

    @Test
    func specificWordingRequiresStoredOptIn() throws {
        let suite = "WE.ExternalSurfaceTests.optIn"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = ExternalSurfaceStore(defaults: defaults)
        let approved = try #require(
            ExplicitlyPermittedSharedWording(
                sharedDirection: sharedDirection(
                    title: "  Start with\n a   little room  "
                )
            )
        )
        let now = Date(timeIntervalSinceReferenceDate: 200)
        let snapshot = ExternalSurfaceSnapshot(
            displayState: .sharedRoomActive,
            expiresAt: now.addingTimeInterval(600),
            permittedSharedWording: approved,
            now: now
        )

        store.setSpecificWordingOptIn(true)
        store.save(snapshot, allowsSpecificWording: true)
        #expect(
            store.read(now: now)?.wording(at: now)
                == "Start with a little room"
        )

        store.setSpecificWordingOptIn(false)
        let generic = try #require(store.read(now: now))
        #expect(!generic.containsSpecificWording)
        #expect(generic.wording(at: now) == "Shared room is active.")
    }

    @Test
    func expiryReturnsQuietAtTheExactBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 300)
        let expiry = now.addingTimeInterval(60)
        let snapshot = ExternalSurfaceSnapshot(
            displayState: .roomAvailable,
            expiresAt: expiry,
            now: now
        )

        #expect(snapshot.effectiveState(at: expiry) == .quiet)
        #expect(snapshot.wording(at: expiry) == "Nothing needs you here.")
    }

    @Test
    func expiryCannotOutliveTheAmbientSurfaceLimit() {
        let now = Date(timeIntervalSinceReferenceDate: 350)
        let snapshot = ExternalSurfaceSnapshot(
            displayState: .roomAvailable,
            expiresAt: now.addingTimeInterval(
                WEExternalSurface.maximumLifetime * 3
            ),
            now: now
        )

        #expect(
            snapshot.expiresAt
                == now.addingTimeInterval(
                    WEExternalSurface.maximumLifetime
                )
        )
        #expect(
            snapshot.effectiveState(
                at: now.addingTimeInterval(
                    WEExternalSurface.maximumLifetime
                )
            ) == .quiet
        )
    }

    @Test
    func payloadHasNoPrivateOrRelationshipFields() throws {
        let now = Date(timeIntervalSinceReferenceDate: 400)
        let snapshot = ExternalSurfaceSnapshot(
            displayState: .resolved,
            expiresAt: now.addingTimeInterval(60),
            now: now
        )
        let object = try #require(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(snapshot)
            ) as? [String: Any]
        )
        let forbidden = [
            "answer",
            "choice",
            "identity",
            "partner",
            "invitation",
            "pending",
            "receipt",
            "profile",
        ]

        for key in object.keys {
            for word in forbidden {
                #expect(!key.lowercased().contains(word))
            }
        }
    }

    @Test
    func externalWordingRejectsUnknownOrAlteredDirections() {
        #expect(
            ExplicitlyPermittedSharedWording(
                sharedDirection: sharedDirection(
                    title: "PRIVATE ANSWER",
                    key: "shared-room"
                )
            ) == nil
        )
        #expect(
            ExplicitlyPermittedSharedWording(
                sharedDirection: sharedDirection(
                    title: "Start with a little room",
                    key: "unreviewed-server-key"
                )
            ) == nil
        )
    }

    private func sharedDirection(
        title: String,
        key: String = "shared-room"
    ) -> SharedDirection {
        SharedDirection(
            insightID: "safe-shared-direction",
            key: key,
            eyebrow: "BETWEEN YOU",
            title: title,
            message: "A reviewed shared message.",
            symbol: "sun.horizon",
            createdAt: nil
        )
    }
}
