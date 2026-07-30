import Foundation

struct ExternalSurfaceStore {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: WEExternalSurface.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
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
