//
//  FieldChangeDebouncer.swift
//  WE
//
//  Collapses a burst of realtime notifications into one reload.
//
//  Sending a single capture writes to `field_captures`, `field_life_items`,
//  and — if the classifier was corrected on the way — `field_corrections`.
//  That is three realtime events describing one thing a person did, and each
//  one used to trigger a full thirteen-query reload. The partner's phone did
//  thirty-nine queries to learn about one sentence.
//
//  300ms is chosen to be shorter than anybody notices and longer than a
//  multi-table write takes to arrive. It is a trailing debounce rather than a
//  leading one deliberately: firing on the first event and ignoring the rest
//  would reload after the capture row landed but before the life item did,
//  which is a reload guaranteed to fetch a half-written state.
//

import Foundation

/// A `final class` with a lock, matching the backends it serves, and
/// `nonisolated` because it is driven from the realtime task group rather than
/// from the main actor.
nonisolated final class FieldChangeDebouncer: @unchecked Sendable {
    /// One value per quiet period.
    let ticks: AsyncStream<Void>

    private let continuation: AsyncStream<Void>.Continuation
    private let interval: Duration
    private let lock = NSLock()
    private var pending: Task<Void, Never>?

    init(interval: Duration = .milliseconds(300)) {
        self.interval = interval

        var escaping: AsyncStream<Void>.Continuation!
        // One buffered value: a consumer busy running a thirteen-query reload
        // needs to know that *something* changed while it was working, not how
        // many times.
        ticks = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            escaping = $0
        }
        continuation = escaping
    }

    /// Something changed. Restarts the quiet period.
    func tick() {
        let scheduled = Task { [interval, continuation] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            continuation.yield()
        }

        // Swapped under the lock and cancelled outside it. The new task is
        // created first and sleeps, so there is no window in which a burst
        // ends with nothing scheduled.
        let previous: Task<Void, Never>? = lock.withLock {
            let previous = pending
            pending = scheduled
            return previous
        }
        previous?.cancel()
    }

    /// No more changes are coming. Cancels anything still waiting and ends the
    /// stream, so a consumer's `for await` returns rather than hanging.
    func finish() {
        let outstanding: Task<Void, Never>? = lock.withLock {
            let outstanding = pending
            pending = nil
            return outstanding
        }
        outstanding?.cancel()
        continuation.finish()
    }

    deinit {
        pending?.cancel()
        continuation.finish()
    }
}
