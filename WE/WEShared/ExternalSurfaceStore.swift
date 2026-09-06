import Foundation
import os

struct ExternalSurfaceStore {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The store is constructed per read, so the warning below would
    /// otherwise repeat on every widget timeline refresh.
    nonisolated(unsafe) private static var hasWarned = false

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: WEExternalSurface.appGroupIdentifier
        )
    ) {
        self.defaults = defaults

        // `UserDefaults(suiteName:)` returns nil when the app group is not
        // actually granted, and every read and write below then degrades to
        // silently doing nothing. That is the correct runtime behaviour and
        // the worst possible development one: the widgets simply draw nothing
        // and nobody learns why.
        //
        // It fails when the App ID is a wildcard, because app groups cannot
        // be attached to one — the entitlement is stripped at signing with no
        // build error. Add the App Groups capability to both the WE and
        // WEWidgets targets in Signing & Capabilities so Xcode registers an
        // explicit App ID.
        //
        // Logged rather than asserted: the app is perfectly usable without
        // widgets, and trapping here would make a provisioning problem look
        // like a crash.
        //
        // No longer `#if DEBUG`: the signing configuration that causes this
        // is exactly the one that differs between a local build and the one
        // that goes to TestFlight, so a warning only a developer can see is
        // a warning aimed at the wrong build.
        if defaults == nil, !Self.hasWarned {
            Self.hasWarned = true
            WELog.externalSurfaces.error(
                """
                No access to app group \
                \(WEExternalSurface.appGroupIdentifier, privacy: .public) — \
                the widgets will read and write nothing. The App Groups \
                capability is missing from the WE and WEWidgets targets; it \
                cannot be granted on a wildcard App ID.
                """
            )
        }
    }

    var specificWordingOptedIn: Bool {
        defaults?.bool(
            forKey: WEExternalSurface.specificWordingOptInKey
        ) ?? false
    }

    func setSpecificWordingOptIn(_ isEnabled: Bool) {
        defaults?.set(
            isEnabled,
            forKey: WEExternalSurface.specificWordingOptInKey
        )

        if !isEnabled, let existing = storedSnapshot() {
            save(
                existing.withoutSpecificWording(),
                allowsSpecificWording: false
            )
        }
    }

    func read(now: Date = Date()) -> ExternalSurfaceSnapshot? {
        guard let data = defaults?.data(
            forKey: WEExternalSurface.snapshotKey
        ),
        let decoded = try? decoder.decode(
            ExternalSurfaceSnapshot.self,
            from: data
        ),
        decoded.version == ExternalSurfaceSnapshot.schemaVersion else {
            return nil
        }

        if decoded.expiresAt <= now {
            return .quiet(now: now)
        }
        return specificWordingOptedIn
            ? decoded
            : decoded.withoutSpecificWording()
    }

    func save(
        _ snapshot: ExternalSurfaceSnapshot,
        allowsSpecificWording: Bool
    ) {
        let safeSnapshot = allowsSpecificWording && specificWordingOptedIn
            ? snapshot
            : snapshot.withoutSpecificWording()
        guard let data = try? encoder.encode(safeSnapshot) else { return }
        defaults?.set(data, forKey: WEExternalSurface.snapshotKey)
    }

    func remove() {
        defaults?.removeObject(forKey: WEExternalSurface.snapshotKey)
    }

    private func storedSnapshot() -> ExternalSurfaceSnapshot? {
        guard let data = defaults?.data(
            forKey: WEExternalSurface.snapshotKey
        ),
        let snapshot = try? decoder.decode(
            ExternalSurfaceSnapshot.self,
            from: data
        ),
        snapshot.version == ExternalSurfaceSnapshot.schemaVersion else {
            return nil
        }
        return snapshot
    }
}
