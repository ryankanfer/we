//
//  FieldSupabaseBackend.swift
//  WE
//
//  The real backend. Replaces FieldMemoryBackend once a couple exists.
//
//  Reads and writes the `field_*` tables from
//  supabase/migrations/20260730120000_field_zones.sql. Everything is
//  couple-scoped and RLS enforces it server-side, so no query here filters by
//  couple defensively — if a row comes back, the viewer is allowed to see it.
//
//  Two mappings are worth knowing:
//
//   · Ownership is stored as 'a' | 'b' | 'shared' on most tables, because that
//     is what the design encodes and it survives a partner changing their
//     colour. Only `added_by` and `spoken_by` store a profile uuid, since
//     those record who actually typed something. `owner(for:)` bridges them.
//   · The couple's two profile ids are resolved once at construction. Person A
//     is whoever joined first, which matches how `couple_members` is seeded.
//

import Foundation
import Supabase

// MARK: - Rows
//
// Deliberately separate from the domain types. The domain models what the
// product means; these model what Postgres returns, and the two are allowed to
// drift.

private struct IdentityRow: Codable {
    let swatch_a: String
    let swatch_b: String
    // Nullable: every onboarding question is skippable.
    let lives_together: Bool?
    let saving_for: String?
    let looks_after: String?
}

private struct AwayWindowRow: Codable {
    let id: UUID
    let profile_id: UUID
    let starts_at: Date
    let ends_at: Date
    let reason: String
    let place: String?
}

private struct ClusterRow: Codable {
    let id: UUID
    let title: String
    let rationale: String
    let tint: String
    let timeframe: String
    let anchor_date: String?
}

private struct LifeItemRow: Codable {
    let id: UUID
    let title: String
    let category: String
    let owner: String
    let due_on: String?
    let closes_at: Date?
    let cluster_id: UUID?
    let source: String
    let detail: String?
    let is_time_critical: Bool
    let is_done: Bool
}

private struct HorizonRow: Codable {
    let id: UUID
    let title: String
    let window_label: String?
    let owner: String
    let is_primary: Bool
    let thesis: String?
    let target_date: String?
    let linked_life_item_ids: [String]?
}

private struct QuestionRow: Codable {
    let id: UUID
    let horizon_id: UUID
    let prompt: String
    let stakes: String
    let reasoning: String
    let choice_a: String
    let choice_b: String
    let answered_choice: String?
}

private struct RhythmRow: Codable {
    let id: UUID
    let title: String
    let cadence: String
    let health: String
    let horizon_id: UUID?
    let occurrences: Int
    let last_occurred_at: Date?
}

private struct EvidenceRow: Codable {
    let id: UUID
    let statement: String
    let owner: String
    let horizon_id: UUID?
    let occurred_at: Date
}

private struct HeldTopicRow: Codable {
    let id: UUID
    /// The id the *app* holds things under — `promote:japan`,
    /// `occasion:<cluster>:<item>`, or an item's uuid. `id` is the row's own
    /// key and is never what `FieldIntelligence` matches against.
    let client_id: String
    let title: String
    let timing: String
    let reason: String
    let surface_on: String?
    let was_overridden: Bool
    let was_dismissed: Bool
}

private struct StandingRuleRow: Codable {
    let id: UUID
    /// The id the app wrote the rule under, and what it must come back as —
    /// otherwise the row the outbox is still holding and the row that arrived
    /// from the server are two different rules that say the same sentence.
    ///
    /// Optional on purpose, unlike `HeldTopicRow.client_id`. `load()` decodes
    /// thirteen tables concurrently and one failed decode fails all of them,
    /// so a database that has not taken
    /// `20260803120000_field_mutation_idempotency` yet degrades to the old
    /// behaviour instead of being unable to load at all.
    let client_id: String?
    let text: String
    let set_at: Date
}

private struct CaptureRow: Codable {
    let id: UUID
    let text: String
    let spoken_by: UUID?
    let captured_at: Date
}

private struct CorrectionRow: Codable {
    let id: UUID
    /// See `StandingRuleRow.client_id`.
    let client_id: String?
    let input: String
    let original_destination: String
    let corrected_destination: String
    let corrected_at: Date
}

private struct DailyMomentRow: Codable {
    let send_minute: Int
    let hour_rationale: String
    let reply_rate_before: Double
    let reply_rate_after: Double
    let last_sent_on: String?
}

private struct MemberRow: Codable {
    let profile_id: UUID
    let name: String?
}

/// PostgreSQL `date` is intentionally not a timestamp. PostgREST returns it
/// as `YYYY-MM-DD`, which Foundation's ISO-8601 `Date` decoder rejects.
private func postgresDay(_ value: String?) -> Date? {
    value.flatMap { DateFormatter.fieldDay.date(from: $0) }
}

// MARK: - Backend

final class FieldSupabaseBackend: FieldBackend, @unchecked Sendable {
    private let client: SupabaseClient
    private let coupleID: UUID
    private let viewerID: UUID
    /// Person A is whoever joined the couple first.
    private let profileA: UUID
    private let profileB: UUID?
    private let nameA: String
    private let nameB: String
    let viewerOwner: FieldOwner

    init?(
        client: SupabaseClient?,
        coupleID: String,
        viewerID: String,
        members: [Member],
        firstMemberID: String
    ) {
        guard let client,
              let coupleUUID = UUID(uuidString: coupleID),
              let viewerUUID = UUID(uuidString: viewerID),
              let aUUID = UUID(uuidString: firstMemberID)
        else { return nil }

        let bUUID = members
            .first { $0.id != firstMemberID }
            .flatMap { UUID(uuidString: $0.id) }
        guard viewerUUID == aUUID || viewerUUID == bUUID else {
            // Never turn an unknown profile into Partner A. RLS remains the
            // server boundary; this guard keeps attribution correct even if
            // the caller accidentally hands this adapter the wrong snapshot.
            return nil
        }

        self.client = client
        self.coupleID = coupleUUID
        self.viewerID = viewerUUID
        self.profileA = aUUID
        self.profileB = bUUID
        self.nameA = members.first { $0.id == firstMemberID }?.name ?? "You"
        self.nameB = members.first { $0.id != firstMemberID }?.name ?? "Them"
        self.viewerOwner = viewerUUID == aUUID ? .a : .b
    }

    /// Which side of the relationship a profile id sits on. A row written
    /// before the second partner joined resolves to `.a` rather than throwing —
    /// the app should never fail to render because of a missing join.
    private func owner(for id: UUID?) -> FieldOwner {
        guard let id else { return .shared }
        if id == profileA { return .a }
        if let profileB, id == profileB { return .b }
        return .shared
    }

    private func owner(_ raw: String) -> FieldOwner {
        FieldOwner(rawValue: raw) ?? .shared
    }

    // MARK: Load

    func load() async throws -> FieldState {
        // Issued concurrently — this is the app's cold start, and fourteen
        // sequential round trips would be the whole launch budget.
        async let identity = fetchIdentity()
        async let windows = fetch([AwayWindowRow].self, from: "field_away_windows")
        async let clusters = fetch([ClusterRow].self, from: "field_clusters")
        async let lifeItems = fetch([LifeItemRow].self, from: "field_life_items")
        async let horizons = fetch([HorizonRow].self, from: "field_horizons")
        async let questions = fetch([QuestionRow].self, from: "field_questions")
        async let rhythms = fetch([RhythmRow].self, from: "field_rhythms")
        async let evidence = fetch([EvidenceRow].self, from: "field_evidence")
        async let held = fetch([HeldTopicRow].self, from: "field_held_topics")
        async let rules = fetch([StandingRuleRow].self, from: "field_standing_rules")
        async let captures = fetchCaptures()
        async let corrections = fetch([CorrectionRow].self, from: "field_corrections")
        async let moment = fetchMoment()

        let resolvedIdentity = try await identity
        let resolvedQuestions = try await questions

        return FieldState(
            identity: resolvedIdentity,
            partners: try await partners(windows: windows),
            lifeItems: try await lifeItems.map(map),
            clusters: try await clusters.map(map),
            horizons: try await horizons.map { map($0, questions: resolvedQuestions) },
            rhythms: try await rhythms.map(map),
            anchors: [],
            threads: [],
            evidence: try await evidence.map(map),
            seasons: [],
            heldTopics: try await held.map(map),
            standingRules: try await rules.map(map),
            corrections: try await corrections.map(map),
            captures: try await captures.map(map),
            dailyMoment: try await moment,
            learningSince: try await rules.map(\.set_at).min() ?? Date()
        )
    }

    private func fetch<T: Decodable>(
        _ type: T.Type,
        from table: String
    ) async throws -> T {
        try await client
            .from(table)
            .select()
            .execute()
            .value
    }

    private func fetchIdentity() async throws -> FieldIdentity {
        let rows: [IdentityRow] = try await fetch([IdentityRow].self, from: "field_identity")
        let row = rows.first
        return FieldIdentity(
            personA: row.flatMap { FieldSwatch(rawValue: $0.swatch_a) } ?? .clay,
            personB: row.flatMap { FieldSwatch(rawValue: $0.swatch_b) } ?? .slate,
            nameA: nameA,
            nameB: nameB,
            livesTogether: row?.lives_together,
            savingFor: row?.saving_for,
            looksAfter: row?.looks_after
        )
    }

    /// Captures are the one table that grows without bound and is only ever
    /// read as "this week".
    ///
    /// Thirty days rather than seven, deliberately: the screen filters again
    /// against the store's own clock, and a fetch that returned exactly seven
    /// would be the server quietly deciding the answer for a clock it knows
    /// nothing about.
    private func fetchCaptures() async throws -> [CaptureRow] {
        let since = Calendar.gregorianUS.date(
            byAdding: .day,
            value: -30,
            to: Date()
        ) ?? .distantPast

        return try await client
            .from("field_captures")
            .select()
            .gte("captured_at", value: ISO8601DateFormatter.we.string(from: since))
            .order("captured_at", ascending: false)
            .execute()
            .value
    }

    private func fetchMoment() async throws -> FieldDailyMoment {
        let rows: [DailyMomentRow] = try await fetch(
            [DailyMomentRow].self,
            from: "field_daily_moment"
        )
        guard let row = rows.first else {
            // 8:12 is the handoff's learned hour and a defensible starting
            // guess. It moves as soon as there is reply data to move it.
            return FieldDailyMoment(
                sendMinute: 8 * 60 + 12,
                queuedCount: 0,
                hourRationale: "I haven't learned your hour yet, so I'm "
                    + "starting in the morning and watching when you reply.",
                replyRateBefore: 0,
                replyRateAfter: 0,
                lastSentOn: nil
            )
        }
        return FieldDailyMoment(
            sendMinute: row.send_minute,
            queuedCount: 0,
            hourRationale: row.hour_rationale,
            replyRateBefore: row.reply_rate_before,
            replyRateAfter: row.reply_rate_after,
            lastSentOn: postgresDay(row.last_sent_on)
        )
    }

    private func partners(
        windows: [AwayWindowRow]
    ) async throws -> [FieldPartner] {
        func build(_ id: UUID?, _ name: String, _ side: FieldOwner) -> FieldPartner {
            FieldPartner(
                id: id?.uuidString ?? side.rawValue,
                name: name,
                swatch: side == .a ? .clay : .slate,
                owner: side,
                awayWindows: windows
                    .filter { $0.profile_id == id }
                    .map {
                        FieldAwayWindow(
                            id: $0.id.uuidString,
                            start: $0.starts_at,
                            end: $0.ends_at,
                            reason: $0.reason,
                            place: $0.place
                        )
                    },
                standingPreferences: []
            )
        }
        return [
            build(profileA, nameA, .a),
            build(profileB, nameB, .b),
        ]
    }

    // MARK: Row to domain

    private func map(_ row: ClusterRow) -> FieldCluster {
        FieldCluster(
            id: row.id.uuidString,
            title: row.title,
            rationale: row.rationale,
            tint: owner(row.tint),
            timeframe: row.timeframe,
            anchorDate: postgresDay(row.anchor_date)
        )
    }

    private func map(_ row: LifeItemRow) -> LifeItem {
        LifeItem(
            id: row.id.uuidString,
            title: row.title,
            category: LifeCategory(rawValue: row.category),
            owner: owner(row.owner),
            dueOn: postgresDay(row.due_on),
            closesAt: row.closes_at,
            clusterID: row.cluster_id?.uuidString,
            source: FieldItemSource(rawValue: row.source) ?? .captured,
            detail: row.detail,
            isTimeCritical: row.is_time_critical,
            isDone: row.is_done
        )
    }

    private func map(
        _ row: HorizonRow,
        questions: [QuestionRow]
    ) -> FieldHorizon {
        let question = questions.first {
            $0.horizon_id == row.id && $0.answered_choice == nil
        }
        return FieldHorizon(
            id: row.id.uuidString,
            title: row.title,
            window: row.window_label,
            owner: owner(row.owner),
            isPrimary: row.is_primary,
            thesis: row.thesis,
            targetDate: postgresDay(row.target_date),
            linkedLifeItemIDs: row.linked_life_item_ids ?? [],
            openQuestion: question.map {
                FieldQuestion(
                    id: $0.id.uuidString,
                    prompt: $0.prompt,
                    stakes: $0.stakes,
                    reasoning: $0.reasoning,
                    choices: [
                        FieldChoice(
                            id: "\($0.id.uuidString)-a",
                            title: $0.choice_a,
                            tint: .a
                        ),
                        FieldChoice(
                            id: "\($0.id.uuidString)-b",
                            title: $0.choice_b,
                            tint: .b
                        ),
                    ]
                )
            }
        )
    }

    private func map(_ row: RhythmRow) -> FieldRhythm {
        FieldRhythm(
            id: row.id.uuidString,
            title: row.title,
            cadence: row.cadence,
            health: RhythmHealth(rawValue: row.health) ?? .running,
            horizonID: row.horizon_id?.uuidString,
            occurrences: row.occurrences,
            lastOccurred: row.last_occurred_at
        )
    }

    private func map(_ row: EvidenceRow) -> FieldEvidence {
        FieldEvidence(
            id: row.id.uuidString,
            statement: row.statement,
            owner: owner(row.owner),
            horizonID: row.horizon_id?.uuidString,
            occurredAt: row.occurred_at
        )
    }

    /// Identified by `client_id`, not by the row's uuid.
    ///
    /// `FieldIntelligence` matches a held topic against the question or item id
    /// it was held under (`FieldIntelligence.swift`, `violatesStandingRule` and
    /// the suppression checks). Returning `row.id` here handed it a uuid it
    /// could never match, so a hold that survived the write still failed to
    /// suppress anything.
    private func map(_ row: HeldTopicRow) -> FieldHeldTopic {
        FieldHeldTopic(
            id: row.client_id,
            title: row.title,
            timing: row.timing,
            reason: row.reason,
            surfaceOn: postgresDay(row.surface_on),
            wasOverridden: row.was_overridden,
            wasDismissed: row.was_dismissed
        )
    }

    private func map(_ row: StandingRuleRow) -> FieldStandingRule {
        FieldStandingRule(
            id: row.client_id ?? row.id.uuidString,
            text: row.text,
            setAt: row.set_at
        )
    }

    private func map(_ row: CaptureRow) -> FieldCapture {
        FieldCapture(
            id: row.id.uuidString,
            text: row.text,
            owner: owner(for: row.spoken_by),
            capturedAt: row.captured_at
        )
    }

    private func map(_ row: CorrectionRow) -> FieldCorrection {
        FieldCorrection(
            id: row.client_id ?? row.id.uuidString,
            input: row.input,
            original: destination(row.original_destination),
            corrected: destination(row.corrected_destination),
            correctedAt: row.corrected_at
        )
    }

    /// Destinations round-trip through their display label, so the column is
    /// readable in the Supabase table editor. Anything unrecognised falls to
    /// Notes rather than throwing — a correction log is not worth a crash.
    ///
    /// `legacyLabel` rather than a plain category, because a couple's log
    /// predates the collapse into one filing system: rows written as
    /// `OURS · EATING` still have to teach the classifier what they were
    /// recorded to teach.
    private func destination(_ label: String) -> LifeCategory {
        LifeCategory(legacyLabel: label) ?? .notes
    }

    // MARK: Writes

    func append(_ capture: FieldCapture) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": AnyJSON.string(coupleID.uuidString),
            "text": .string(capture.text),
            "spoken_by": .string(viewerID.uuidString),
            "destination": .string(""),
            "reasoning": .string(""),
        ]
        // A capture and the Life item materialised from its receipt share one
        // durable identity. Besides making restart behavior stable, this gives
        // migrations and diagnostics an exact join instead of guessing from
        // matching text and timestamps.
        if let id = UUID(uuidString: capture.id) {
            payload["id"] = .string(id.uuidString)
        }
        // Upsert rather than insert, so the outbox can send this again after
        // a write that committed and then timed out. The receipt's UUID is
        // already the durable identity here — the same one the materialised
        // Life item takes — so the conflict target costs nothing and needs no
        // column that did not already exist.
        _ = try await client
            .from("field_captures")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    /// Keyed on the correction's own id, for the same reason as above.
    ///
    /// This was the more dangerous of the two unkeyed inserts: a correction is
    /// training signal, and a duplicate does not merely show twice — it
    /// doubles the weight of one person's single opinion about what a word
    /// means, in the one genuinely adaptive path in the app.
    func record(_ correction: FieldCorrection) async throws {
        _ = try await client
            .from("field_corrections")
            .upsert([
                "couple_id": AnyJSON.string(coupleID.uuidString),
                "client_id": .string(correction.id),
                "input": .string(correction.input),
                "original_destination": .string(correction.original.label),
                "corrected_destination": .string(correction.corrected.label),
                "corrected_by": .string(viewerID.uuidString),
            ], onConflict: "couple_id,client_id")
            .execute()
    }

    func upsert(_ item: LifeItem) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "title": .string(item.title),
            "category": .string(item.category.rawValue),
            "owner": .string(item.owner.rawValue),
            "source": .string(item.source.rawValue),
            "is_time_critical": .bool(item.isTimeCritical),
            "is_done": .bool(item.isDone),
        ]
        if let existing = UUID(uuidString: item.id) {
            payload["id"] = .string(existing.uuidString)
        }
        if let detail = item.detail { payload["detail"] = .string(detail) }
        // The dates, which were missing: the phrasing layer lifts "sunday" out
        // of what somebody typed and turns it into a real day, and dropping it
        // on the way to the database threw that away on every reload.
        // Written explicitly as null when absent, never omitted. An upsert
        // that leaves the key out preserves whatever was in the column, so
        // taking a date off an item — `FieldStore.redate(_:to: nil)` — would
        // have looked right until the next load put the old day back.
        payload["due_on"] = item.dueOn.map {
            .string(DateFormatter.fieldDay.string(from: $0))
        } ?? .null
        payload["closes_at"] = item.closesAt.map {
            .string(ISO8601DateFormatter.we.string(from: $0))
        } ?? .null
        // Read since the beginning, written never. Which occasion something
        // belongs to was the one fact about an item this method could not
        // carry, so the answer to "does this belong with Friday" survived
        // exactly until the next load. Explicitly null when absent, for the
        // same reason the dates above are: an upsert that omits a key keeps
        // whatever the column already had, and taking something *out* of an
        // occasion would have looked right and done nothing.
        payload["cluster_id"] = item.clusterID.map { .string($0) } ?? .null

        _ = try await client
            .from("field_life_items")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    /// Gone, rather than flagged. The `field_life_items_write` policy is
    /// `for all` scoped to the caller's couple, so DELETE is already covered —
    /// see `20260730120000_field_zones.sql`.
    func delete(itemID: String) async throws {
        // Only a real row. Imported calendar items carry a `cal:` id and are
        // refused in `FieldStore` before they reach here; this guard means a
        // future caller cannot send one either.
        guard let id = UUID(uuidString: itemID) else { return }

        _ = try await client
            .from("field_life_items")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        // And the capture it was filed from, which shares the same id. Without
        // this the row survives the item, and the next load — or the partner's
        // phone, which never saw the local removal — puts the chip back under
        // the capture field for a thing that is gone.
        _ = try await client
            .from("field_captures")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// The only way Us ever gains anything: somebody answered a promotion
    /// question with a yes.
    func upsert(_ horizon: FieldHorizon) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "title": .string(horizon.title),
            "owner": .string(horizon.owner.rawValue),
            "is_primary": .bool(horizon.isPrimary),
            "linked_life_item_ids": .array(
                horizon.linkedLifeItemIDs.map { .string($0) }
            ),
        ]
        if let existing = UUID(uuidString: horizon.id) {
            payload["id"] = .string(existing.uuidString)
        }
        if let window = horizon.window { payload["window_label"] = .string(window) }
        if let thesis = horizon.thesis { payload["thesis"] = .string(thesis) }
        if let target = horizon.targetDate {
            payload["target_date"] = .string(
                DateFormatter.fieldDay.string(from: target)
            )
        }
        _ = try await client
            .from("field_horizons")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    /// And the only way Life ever gains an occasion: somebody answered an
    /// occasion question with a yes.
    func upsert(_ cluster: FieldCluster) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "title": .string(cluster.title),
            "rationale": .string(cluster.rationale),
            "tint": .string(cluster.tint.rawValue),
            "timeframe": .string(cluster.timeframe),
        ]
        if let existing = UUID(uuidString: cluster.id) {
            payload["id"] = .string(existing.uuidString)
        }
        payload["anchor_date"] = cluster.anchorDate.map {
            .string(DateFormatter.fieldDay.string(from: $0))
        } ?? .null

        _ = try await client
            .from("field_clusters")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    func answer(question: String, choice: String) async throws {
        guard let id = UUID(uuidString: question) else { return }
        _ = try await client
            .from("field_questions")
            .update([
                "answered_choice": AnyJSON.string(choice),
                "answered_at": .string(ISO8601DateFormatter.we.string(from: Date())),
            ])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Upsert on the couple's own id for the topic, carrying every field.
    ///
    /// This was an UPDATE guarded by `UUID(uuidString: topic.id)`, which meant
    /// three separate failures at once. The guard rejected every route-shaped
    /// id — `promote:japan`, `occasion:…` — and returned without writing or
    /// throwing. The ids that passed it updated zero rows, because nothing has
    /// ever inserted into this table. And `surface_on` was not in the payload
    /// at all, so even a hit would not have recorded *when* to come back.
    ///
    /// The in-memory backend has upserted correctly for some time, with a
    /// comment describing this exact bug being fixed there — which is why no
    /// preview, gallery run, or UI test ever saw it. That asymmetry is the
    /// thing to fix structurally; see the shared backend conformance suite.
    func setHeld(_ topic: FieldHeldTopic) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "client_id": .string(topic.id),
            "title": .string(topic.title),
            "timing": .string(topic.timing),
            "reason": .string(topic.reason),
            "was_overridden": .bool(topic.wasOverridden),
            "was_dismissed": .bool(topic.wasDismissed),
        ]
        // A `date` column, and the reason a deferral comes back at all.
        payload["surface_on"] = topic.surfaceOn.map {
            .string(DateFormatter.fieldDay.string(from: $0))
        } ?? .null

        _ = try await client
            .from("field_held_topics")
            .upsert(payload, onConflict: "couple_id,client_id")
            .execute()
    }

    /// One row per couple, so this upserts on the couple rather than
    /// inserting a second opinion about what hour they reply at.
    ///
    /// `last_sent_on` is a `date` and not a timestamp — the question it
    /// answers is "have I already spoken today", which is a day and not an
    /// instant.
    func setDailyMoment(_ moment: FieldDailyMoment) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "send_minute": .integer(moment.sendMinute),
            "hour_rationale": .string(moment.hourRationale),
            "reply_rate_before": .double(moment.replyRateBefore),
            "reply_rate_after": .double(moment.replyRateAfter),
        ]
        payload["last_sent_on"] = moment.lastSentOn
            .map { .string(DateFormatter.fieldDay.string(from: $0)) } ?? .null

        _ = try await client
            .from("field_daily_moment")
            .upsert(payload, onConflict: "couple_id")
            .execute()
    }

    /// Also keyed, and also previously unkeyed. A rule sent twice is the same
    /// sentence printed twice on the surface whose entire job is to say what
    /// the two of them have already decided.
    func setStandingRule(_ rule: FieldStandingRule) async throws {
        _ = try await client
            .from("field_standing_rules")
            .upsert([
                "couple_id": AnyJSON.string(coupleID.uuidString),
                "client_id": .string(rule.id),
                "text": .string(rule.text),
                "set_by": .string(viewerID.uuidString),
            ], onConflict: "couple_id,client_id")
            .execute()
    }

    func setIdentity(_ identity: FieldIdentity) async throws {
        // A skipped question writes null rather than "", so the two stay
        // distinguishable after a round trip.
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "lives_together": identity.livesTogether
                .map(AnyJSON.bool) ?? .null,
            "saving_for": identity.savingFor
                .map(AnyJSON.string) ?? .null,
            "looks_after": identity.looksAfter
                .map(AnyJSON.string) ?? .null,
        ]
        switch viewerOwner {
        case .a:
            payload["swatch_a"] = .string(identity.personA.rawValue)
        case .b:
            payload["swatch_b"] = .string(identity.personB.rawValue)
        case .shared:
            break
        }

        _ = try await client
            .from("field_identity")
            .upsert(payload, onConflict: "couple_id")
            .execute()
    }

    // MARK: The solo-to-shared boundary (2a)
    //
    // Both are `security definer` RPCs scoped server-side to the caller's own
    // rows. Deliberately not expressed as table writes: `visibility` is frozen
    // by `private.field_stamp_visibility()` precisely so that a client — or a
    // partner — cannot publish somebody's private history by writing a column.
    // The RPC is the only door, and it only ever opens onto the caller's side.

    func soloHistoryCount() async throws -> Int {
        try await client
            .rpc("field_solo_history_count")
            .execute()
            .value
    }

    func shareSoloHistory() async throws -> Int {
        try await client
            .rpc("field_share_solo_history")
            .execute()
            .value
    }

    // MARK: Realtime
    //
    // The partner's captures and corrections have to land without a refresh —
    // "both added it, a week apart" is only impressive if it appears on its
    // own.

    func changes() -> AsyncStream<Void> {
        changes(
            onSubscribed: {},
            onSubscriptionFailed: { _ in }
        )
    }

    /// The readiness callback is intentionally concrete-backend API rather
    /// than part of `FieldBackend`: production callers only need changes,
    /// while the live contract must prove the Realtime channel is joined
    /// before Partner B writes. A timed sleep can miss a slow subscription.
    func changes(
        onSubscribed: @escaping @Sendable () -> Void,
        onSubscriptionFailed: @escaping @Sendable (String) -> Void = { _ in }
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { [client, coupleID] in
                let channel = client.channel("field:\(coupleID.uuidString)")

                // One subscription per table rather than one for the whole
                // `public` schema.
                //
                // The schema-wide subscription woke this stream for every
                // change to every table the viewer can see — profiles,
                // couples, memberships, the legacy v2 tables, all of it — and
                // each wake ran a full thirteen-query reload. Nothing outside
                // `field_*` can alter a `FieldState`, so every one of those
                // reloads was thirteen queries to arrive at the same answer.
                let streams = Self.observedTables.map { table in
                    channel.postgresChange(
                        AnyAction.self,
                        schema: "public",
                        table: table
                    )
                }

                do {
                    try await channel.subscribeWithError()
                } catch {
                    onSubscriptionFailed(String(describing: error))
                    continuation.finish()
                    return
                }
                onSubscribed()

                // Merged by hand, because the tables are separate streams now
                // and a change is a change regardless of which one it came
                // from. The debounce is what makes that safe: sending one
                // capture writes to `field_captures` and `field_life_items`,
                // and a correction with it — three ticks, one action, and
                // without this three full reloads.
                let debounced = FieldChangeDebouncer()

                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await _ in debounced.ticks {
                            if Task.isCancelled { break }
                            continuation.yield()
                        }
                    }

                    // The inner group finishes when every table stream has
                    // ended — which is what cancellation looks like from here.
                    // Only then is the forwarder above told to stop, so a tick
                    // still in flight is not dropped on the way out.
                    await withTaskGroup(of: Void.self) { tables in
                        for stream in streams {
                            tables.addTask {
                                for await _ in stream {
                                    if Task.isCancelled { break }
                                    debounced.tick()
                                }
                            }
                        }
                    }
                    debounced.finish()
                }
                await channel.unsubscribe()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every table a `FieldState` is built from, and nothing else.
    ///
    /// Listed rather than derived: a table added to `load()` and forgotten
    /// here shows up as a partner's change not arriving until the next
    /// foreground, which is a slow and confusing bug. Adding to `load()`
    /// should mean adding here in the same edit.
    /// Exactly the thirteen `load()` reads, in the same order.
    ///
    /// A table here that realtime does not publish is harmless — it simply
    /// never fires. A table in `load()` and missing here is not: the partner's
    /// change lands in the database and does not reach the screen until the
    /// next foreground, which reads as the app being slow rather than as a
    /// subscription being wrong.
    static let observedTables = [
        "field_identity",
        "field_away_windows",
        "field_clusters",
        "field_life_items",
        "field_horizons",
        "field_questions",
        "field_rhythms",
        "field_evidence",
        "field_held_topics",
        "field_standing_rules",
        "field_captures",
        "field_corrections",
        "field_daily_moment",
    ]
}
