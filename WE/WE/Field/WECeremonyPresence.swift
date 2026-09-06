//
//  WECeremonyPresence.swift
//  WE
//
//  Is the other phone in the room right now.
//
//  Every ritual in The Joining is downstream of this, and it did not exist:
//  `FieldSupabaseBackend` subscribes to seventeen tables via `postgresChange`
//  for data sync, which is a mechanism for "something changed" rather than
//  for "somebody is here."
//
//  WHAT THIS CARRIES, AND WHAT IT REFUSES TO
//
//  Liveness, and nothing else. Presence never carries who acknowledged what,
//  and it is not the source of truth for how far the ceremony has got — that
//  is the aggregate RPC in `WECeremonySupabase`. Keeping the two separate is
//  what stops presence becoming a side channel: a payload that grew a "beat"
//  field would report the other person's timing to the millisecond, which is
//  the one thing the direction forbids outright.
//
//  It is also *ephemeral*. Nothing is written, no table is created, and no
//  `updated_at` is touched on any shared object, which satisfies the standing
//  rule that no partner-accessible event may be generated. Presence lives in
//  the channel and dies with it.
//
//  "Nothing reports on the other person's timing, ever." Presence is binary
//  and is only ever *announced* on arrival — the surfaces may use it to know
//  the ceremony can begin, and may not use it to draw a dot, a last-seen, or
//  a typing indicator.
//

import Foundation
import Supabase

// MARK: - What a surface may ask

/// The whole vocabulary. Two states, no timestamps, no history.
enum WEPresence: Equatable, Sendable {
    /// This device is attached; the other is not, or not yet known to be.
    case alone
    /// Both devices are attached to the ceremony right now.
    case together
}

// MARK: - The channel

/// An ephemeral Supabase Realtime presence channel keyed to the couple.
///
/// The channel is joined before either person can act, and the readiness
/// callback is concrete API rather than part of a protocol for the same
/// reason `FieldSupabaseBackend.changes(onSubscribed:)` is: a two-simulator
/// test has to prove the channel joined before Partner B writes, and a timed
/// sleep can miss a slow subscription.
actor WECeremonyPresence {
    private let client: SupabaseClient
    private let coupleID: UUID
    private let deviceKey: String

    /// A per-attachment key, not a per-person one.
    ///
    /// Presence keys are visible to everybody on the channel, so a profile id
    /// here would publish which of the two people is attached rather than
    /// merely how many are. The count is what the product needs; the identity
    /// is what it must not have.
    init(client: SupabaseClient, coupleID: UUID) {
        self.client = client
        self.coupleID = coupleID
        self.deviceKey = UUID().uuidString
    }

    /// Joins, then yields a value every time the room's occupancy changes.
    ///
    /// The first value arrives on join, so a caller never has to guess an
    /// initial state or race the subscription.
    nonisolated func presence(
        onSubscribed: @escaping @Sendable () -> Void = {},
        onSubscriptionFailed: @escaping @Sendable (String) -> Void = { _ in }
    ) -> AsyncStream<WEPresence> {
        AsyncStream { continuation in
            let task = Task { [client, coupleID, deviceKey] in
                let channel = client.channel("ceremony:\(coupleID.uuidString)") {
                    $0.presence.key = deviceKey
                }
                let changes = channel.presenceChange()

                do {
                    try await channel.subscribeWithError()
                } catch {
                    onSubscriptionFailed(String(describing: error))
                    continuation.finish()
                    return
                }

                // Tracking with an empty payload is deliberate. Presence
                // supports arbitrary state, and every field anyone might add
                // here would be a fact about one person reaching the other
                // outside the consent the ceremony is establishing.
                do {
                    try await channel.track([String: String]())
                } catch {
                    onSubscriptionFailed(String(describing: error))
                    continuation.finish()
                    await channel.unsubscribe()
                    return
                }
                onSubscribed()

                // Realtime reports joins and leaves rather than occupancy, so
                // the room is counted here. The set holds opaque per
                // attachment keys and never leaves this loop: what the caller
                // receives is one of two cases, so no surface downstream is
                // able to hold the identities even if it wanted them.
                //
                // The initial state arrives as joins on subscribe, which is
                // why the first value reaches the caller without anyone
                // having to guess an initial state or race the subscription.
                var attached: Set<String> = []

                for await change in changes {
                    if Task.isCancelled { break }
                    attached.formUnion(change.joins.keys)
                    attached.subtract(change.leaves.keys)
                    continuation.yield(attached.count > 1 ? .together : .alone)
                }

                await channel.untrack()
                await channel.unsubscribe()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
