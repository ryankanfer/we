//
//  YoursDestroyQueue.swift
//  WE
//
//  The one thing about this space that survives a relaunch on disk, and it is
//  a list of identifiers.
//
//  CIRCLE.md §11: "Let go takes effect locally immediately and queues
//  destruction if offline." That sentence needs somewhere durable to put the
//  intent, because an app killed between the tap and the network call would
//  otherwise leave an entry alive that its owner was told was gone — the
//  precise failure this whole design exists to make impossible.
//
//  `FieldOutbox` already solves durable writes, and it is the wrong tool here:
//  it persists the mutation *payload*, which for this feature would mean
//  writing private text to a second place on disk in order to delete it. So
//  this queue carries the id and the release reason and nothing else. The
//  words are never here, not even briefly.
//
//  Complete file protection, like `FieldStateCache` — the file is unreadable
//  while the device is locked. Small enough that it never needs pruning by
//  size, and self-clearing, because an entry only leaves the queue when the
//  server has confirmed it is gone.
//

import Foundation
import os

nonisolated struct YoursPendingDestruction: Codable, Hashable, Sendable {
    let entryID: String
    let reason: YoursReleaseReason?
    let queuedAt: Date
}

private struct YoursDestroyEnvelope: Codable {
    static let currentVersion = 1
    var version: Int = YoursDestroyEnvelope.currentVersion
    var pending: [YoursPendingDestruction]
}

final class YoursDestroyQueue: @unchecked Sendable {
    static let shared = YoursDestroyQueue()

    private let lock = NSLock()
    private let url: URL
    private let log = Logger(subsystem: "com.we.app", category: "yours")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        url = base.appendingPathComponent("yours-destroy.json")
    }

    func enqueue(entryID: String, reason: YoursReleaseReason?) {
        lock.withLock {
            var envelope = read()
            guard !envelope.pending.contains(where: { $0.entryID == entryID }) else {
                return
            }
            envelope.pending.append(
                YoursPendingDestruction(
                    entryID: entryID,
                    reason: reason,
                    queuedAt: Date()
                )
            )
            write(envelope)
        }
    }

    func pending() -> [YoursPendingDestruction] {
        lock.withLock { read().pending }
    }

    /// Confirmed gone. The only way anything leaves this file.
    func clear(entryID: String) {
        lock.withLock {
            var envelope = read()
            envelope.pending.removeAll { $0.entryID == entryID }
            write(envelope)
        }
    }

    /// Phase 1d's purge contract: leaving the account leaves nothing behind.
    func removeAll() {
        lock.withLock {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: -

    private func read() -> YoursDestroyEnvelope {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(
                  YoursDestroyEnvelope.self, from: data
              )
        else {
            return YoursDestroyEnvelope(pending: [])
        }
        guard envelope.version == YoursDestroyEnvelope.currentVersion else {
            // A queue written by a version that shaped it differently. Dropped
            // rather than guessed at: the server's own sweep is the backstop,
            // and inventing a destruction from a format nobody can read is the
            // one mistake this file must not make.
            log.notice("Yours destroy queue version mismatch; dropped")
            return YoursDestroyEnvelope(pending: [])
        }
        return envelope
    }

    private func write(_ envelope: YoursDestroyEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
