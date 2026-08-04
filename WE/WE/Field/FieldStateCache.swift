//
//  FieldStateCache.swift
//  WE
//
//  What the zones can draw before the network answers.
//
//  Without this, `FieldStore` starts every launch at `FieldState.empty` and
//  stays there until Supabase replies — thirteen queries away. A couple who
//  opens the app on a train sees a new account: no items, no occasions, no
//  horizons, and a Today that says the day is clear. The app is not wrong for
//  long, but it is wrong at precisely the moment somebody looked at it, and
//  what they saw was their relationship having been forgotten.
//
//  `FieldState` is already one atomic `Codable` value, so this is a file and
//  not a database. The scheme is `FileRelationshipCache`'s, deliberately —
//  same complete file protection, same versioned envelope, same
//  quarantine-rather-than-crash posture as the outbox next door. A second
//  invented persistence scheme is a second set of bugs.
//
//  Partitioned by user *and* couple for the same reason the outbox is: a
//  cached relationship must not survive into a different account on a shared
//  device, and clearing it is part of the Phase 1d purge contract.
//

import Foundation
import os

/// The envelope. Versioned from the start — a cache that cannot say "I do not
/// understand this" has no choice but to hand back a misread relationship.
struct CachedFieldState: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var state: FieldState
    var savedAt: Date

    init(version: Int = Self.currentVersion, state: FieldState, savedAt: Date) {
        self.version = version
        self.state = state
        self.savedAt = savedAt
    }
}

struct FieldStateCache: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "WE/FieldState", directoryHint: .isDirectory)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Reading

    /// Never throws, and never partially succeeds.
    ///
    /// A cache miss and a corrupt cache are the same thing to a caller: start
    /// from nothing and load. The difference is that a corrupt file is said
    /// out loud and removed, so the next launch is not the same launch again.
    func load(_ partition: FieldOutboxPartition) -> CachedFieldState? {
        let url = url(for: partition)
        guard let data = try? Data(contentsOf: url) else { return nil }

        guard let cached = try? decoder.decode(
            CachedFieldState.self,
            from: data
        ) else {
            WELog.persistence.error(
                "Field state cache could not be read; discarding it."
            )
            remove(partition)
            return nil
        }

        guard cached.version == CachedFieldState.currentVersion else {
            // Written by a different build. Unlike the outbox — which holds
            // writes a person believes they made, and quarantines the file so
            // they are at least recoverable — this is only a copy of what the
            // server already has, so it is simply dropped.
            WELog.persistence.notice(
                """
                Field state cache is version \
                \(cached.version, privacy: .public), expected \
                \(CachedFieldState.currentVersion, privacy: .public); \
                discarding it.
                """
            )
            remove(partition)
            return nil
        }

        return cached
    }

    // MARK: Writing

    /// Called after every successful load. Failure is logged and otherwise
    /// ignored: an uncached state costs a slow first screen, and there is
    /// nothing a caller could usefully do about it.
    func save(
        _ state: FieldState,
        for partition: FieldOutboxPartition,
        at date: Date = Date()
    ) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            let data = try encoder.encode(
                CachedFieldState(state: state, savedAt: date)
            )
            try data.write(
                to: url(for: partition),
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            WELog.persistence.error(
                "Could not cache the field state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: Forgetting

    /// Phase 1d. Sign-out, account deletion, and unpairing all land here.
    func remove(_ partition: FieldOutboxPartition) {
        try? FileManager.default.removeItem(at: url(for: partition))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(for partition: FieldOutboxPartition) -> URL {
        directory.appending(path: partition.filename)
    }
}
