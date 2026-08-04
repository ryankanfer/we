//
//  FieldMutation.swift
//  WE
//
//  Every write in `FieldBackend`, as one value that can be stored, replayed,
//  and compacted.
//
//  The outbox needs three things a method call cannot give it: a mutation has
//  to survive being written to disk, it has to be applicable to a `FieldState`
//  that came back from the server, and two mutations about the same thing have
//  to be recognisable as such. So the eleven writes become eleven cases.
//
//  `apply(to:)` is deliberately the *only* description of what a write does to
//  local state. `FieldMemoryBackend` is written in terms of it, which means the
//  in-memory backend and the outbox's replay cannot drift apart — the same
//  structural fix the shared conformance suite made for the in-memory and
//  Supabase backends, applied to the third implementation this phase adds.
//  Divergence between two hand-written copies of "insert at 0, or replace by
//  id" is precisely how `setHeld` stayed broken in production while passing
//  every test.
//

import Foundation

// MARK: - The write

/// `Codable` and `Sendable`, deliberately not `Hashable`.
///
/// Synthesising `Hashable` here would require every payload's `Hashable`
/// conformance at a point where this value is being handled off the main
/// actor, and those conformances are main-actor isolated along with the rest
/// of `FieldModel`. Nothing needs it: compaction keys on `Subject`, which is
/// built from strings.
enum FieldMutation: Codable, Sendable {
    case append(FieldCapture)
    case record(FieldCorrection)
    case upsertItem(LifeItem)
    case deleteItem(id: String)
    case upsertHorizon(FieldHorizon)
    case upsertCluster(FieldCluster)
    case answer(question: String, choice: String)
    case setHeld(FieldHeldTopic)
    case setStandingRule(FieldStandingRule)
    case setIdentity(FieldIdentity)
    case setDailyMoment(FieldDailyMoment)
}

// MARK: - Replay

extension FieldMutation {
    /// What this write does to local state.
    ///
    /// Used twice, and it matters that it is the same code both times: once by
    /// `FieldMemoryBackend`, and once by the outbox replaying still-unsent
    /// writes over a snapshot that has just come back from the server. If
    /// those two disagreed, a write would look one way before a reload and
    /// another way after it, which is the exact texture of a bug nobody can
    /// reproduce.
    func apply(to state: inout FieldState) {
        switch self {
        case .append(let capture):
            // Newest first, matching every read path's expectation.
            state.captures.removeAll { $0.id == capture.id }
            state.captures.insert(capture, at: 0)

        case .record(let correction):
            state.corrections.removeAll { $0.id == correction.id }
            state.corrections.append(correction)

        case .upsertItem(let item):
            Self.upsert(item, id: \.id, into: &state.lifeItems)

        case .deleteItem(let id):
            // Both, because a captured item and the capture it was filed from
            // share one identity. Removing only the item leaves the chip under
            // the capture field pointing at something gone.
            state.lifeItems.removeAll { $0.id == id }
            state.captures.removeAll { $0.id == id }

        case .upsertHorizon(let horizon):
            Self.upsert(horizon, id: \.id, into: &state.horizons)

        case .upsertCluster(let cluster):
            Self.upsert(cluster, id: \.id, into: &state.clusters)

        case .answer:
            // Answering a question is recorded server-side and read back as
            // part of the next load. There is no local projection of it, and
            // inventing one here would be the replay showing something the
            // server never confirmed.
            break

        case .setHeld(let topic):
            if let index = state.heldTopics.firstIndex(where: {
                $0.id == topic.id
            }) {
                state.heldTopics[index] = topic
            } else {
                state.heldTopics.append(topic)
            }

        case .setStandingRule(let rule):
            state.standingRules.removeAll { $0.id == rule.id }
            state.standingRules.append(rule)

        case .setIdentity(let identity):
            state.identity = identity

        case .setDailyMoment(let moment):
            state.dailyMoment = moment
        }
    }

    /// Replace in place, or insert newest-first. Written once rather than
    /// three times, because the three call sites above differing by a line is
    /// how this kind of thing goes wrong.
    ///
    /// Keyed by an explicit key path rather than constrained to
    /// `Identifiable`: requiring that conformance here would require it off
    /// the main actor, and `LifeItem` and its neighbours are main-actor
    /// isolated like everything else in `FieldModel`.
    private static func upsert<T>(
        _ value: T,
        id: KeyPath<T, String>,
        into collection: inout [T]
    ) {
        let identity = value[keyPath: id]
        if let index = collection.firstIndex(where: {
            $0[keyPath: id] == identity
        }) {
            collection[index] = value
        } else {
            collection.insert(value, at: 0)
        }
    }
}

// MARK: - Sending

extension FieldMutation {
    /// Hand this write to a real backend.
    ///
    /// The mirror of `apply(to:)`: one describes the local effect, this one
    /// the remote. Keeping them adjacent is the point — a case added to the
    /// enum fails to compile in both places until both are answered.
    func send(to backend: any FieldBackend) async throws {
        switch self {
        case .append(let capture):
            try await backend.append(capture)
        case .record(let correction):
            try await backend.record(correction)
        case .upsertItem(let item):
            try await backend.upsert(item)
        case .deleteItem(let id):
            try await backend.delete(itemID: id)
        case .upsertHorizon(let horizon):
            try await backend.upsert(horizon)
        case .upsertCluster(let cluster):
            try await backend.upsert(cluster)
        case .answer(let question, let choice):
            try await backend.answer(question: question, choice: choice)
        case .setHeld(let topic):
            try await backend.setHeld(topic)
        case .setStandingRule(let rule):
            try await backend.setStandingRule(rule)
        case .setIdentity(let identity):
            try await backend.setIdentity(identity)
        case .setDailyMoment(let moment):
            try await backend.setDailyMoment(moment)
        }
    }
}

// MARK: - Compaction

extension FieldMutation {
    /// What this mutation is *about*, so that two mutations about the same
    /// thing can be collapsed.
    ///
    /// A person editing one item four times while offline should send one
    /// write, not four — and the four are indistinguishable to the server
    /// anyway, since each is a full upsert of the same row.
    ///
    /// Every case has a subject, and deliberately so: an earlier draft gave
    /// `answer` a freshly generated one, which is not a subject at all but a
    /// value that differs every time it is read. Compaction looked each entry
    /// up under a key it could never match, and dropped every queued answer.
    enum Subject: Hashable, Sendable {
        case capture(String)
        case correction(String)
        case item(String)
        case horizon(String)
        case cluster(String)
        case heldTopic(String)
        case standingRule(String)
        /// The question answered, not the answer. Changing your mind before
        /// the queue drains should send the answer you settled on.
        case question(String)
        /// One row per couple, so the last one written is the only one that
        /// has ever mattered.
        case identity
        case dailyMoment
    }

    var subject: Subject {
        switch self {
        case .append(let capture): .capture(capture.id)
        case .record(let correction): .correction(correction.id)
        // An item and the capture it came from share an id, and a delete has
        // to supersede a queued edit of either — so both land on `.item`.
        case .upsertItem(let item): .item(item.id)
        case .deleteItem(let id): .item(id)
        case .upsertHorizon(let horizon): .horizon(horizon.id)
        case .upsertCluster(let cluster): .cluster(cluster.id)
        case .setHeld(let topic): .heldTopic(topic.id)
        case .setStandingRule(let rule): .standingRule(rule.id)
        case .setIdentity: .identity
        case .setDailyMoment: .dailyMoment
        case .answer(let question, _): .question(question)
        }
    }

    /// Whether this write makes every earlier queued write about the same
    /// subject pointless.
    ///
    /// True for all of them, and that is not laziness: every remaining case is
    /// a whole-value upsert or a delete, so the last one wins by construction.
    /// It is stated explicitly because the moment a partial update is added to
    /// `FieldBackend` — patching one column rather than writing the row — this
    /// has to become false for that case, and a silent `true` would quietly
    /// throw away the earlier half of somebody's edit.
    var supersedesEarlierWritesToTheSameSubject: Bool { true }
}

// MARK: - Compacting a queue

extension Array where Element == FieldMutation {
    /// Keep the last write per subject, in the order the surviving writes were
    /// made.
    ///
    /// Order is preserved rather than rebuilt, because a create followed by an
    /// edit collapses to the edit — which still has to be sent *before* an
    /// unrelated later mutation that might depend on it.
    func compacted() -> [FieldMutation] {
        var lastIndex: [FieldMutation.Subject: Int] = [:]
        for (index, mutation) in enumerated()
        where mutation.supersedesEarlierWritesToTheSameSubject {
            lastIndex[mutation.subject] = index
        }

        return enumerated().compactMap { index, mutation in
            guard mutation.supersedesEarlierWritesToTheSameSubject else {
                return mutation
            }
            return lastIndex[mutation.subject] == index ? mutation : nil
        }
    }
}
