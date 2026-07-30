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
    let anchor_date: Date?
}

private struct LifeItemRow: Codable {
    let id: UUID
    let title: String
    let category: String
    let owner: String
    let due_on: Date?
    let closes_at: Date?
    let cluster_id: UUID?
    let source: String
    let detail: String?
    let is_time_critical: Bool
    let is_done: Bool
}

private struct OursItemRow: Codable {
    let id: UUID
    let title: String
    let list: String
    let added_by: UUID?
    let added_at: Date
    let both_added: Bool
    let coincidence_note: String?
    let horizon_id: UUID?
    let is_standing_note: Bool
}

private struct HorizonRow: Codable {
    let id: UUID
    let title: String
    let window_label: String?
    let owner: String
    let is_primary: Bool
    let thesis: String?
    let target_date: Date?
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
    let title: String
    let timing: String
    let reason: String
    let surface_on: Date?
    let was_overridden: Bool
    let was_dismissed: Bool
}

private struct StandingRuleRow: Codable {
    let id: UUID
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
    let last_sent_on: Date?
}

private struct MemberRow: Codable {
    let profile_id: UUID
    let name: String?
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

        self.client = client
        self.coupleID = coupleUUID
        self.viewerID = viewerUUID
        self.profileA = aUUID
        self.profileB = members
            .first { $0.id != firstMemberID }
            .flatMap { UUID(uuidString: $0.id) }
        self.nameA = members.first { $0.id == firstMemberID }?.name ?? "You"
        self.nameB = members.first { $0.id != firstMemberID }?.name ?? "Them"
    }

    /// Which side of the relationship a profile id sits on. A row written
    /// before the second partner joined resolves to `.a` rather than throwing —
    /// the app should never fail to render because of a missing join.
    private func owner(for id: UUID?) -> FieldOwner {
        guard let id else { return .shared }
        if id == profileA { return .a }
        if let profileB, id == profileB { return .b }
        return .a
    }

    private func owner(_ raw: String) -> FieldOwner {
        FieldOwner(rawValue: raw) ?? .shared
    }

    private var viewerOwner: FieldOwner { owner(for: viewerID) }

    // MARK: Load

    func load() async throws -> FieldState {
        // Issued concurrently — this is the app's cold start, and fourteen
        // sequential round trips would be the whole launch budget.
        async let identity = fetchIdentity()
        async let windows = fetch([AwayWindowRow].self, from: "field_away_windows")
        async let clusters = fetch([ClusterRow].self, from: "field_clusters")
        async let lifeItems = fetch([LifeItemRow].self, from: "field_life_items")
        async let oursItems = fetch([OursItemRow].self, from: "field_ours_items")
        async let horizons = fetch([HorizonRow].self, from: "field_horizons")
        async let questions = fetch([QuestionRow].self, from: "field_questions")
        async let rhythms = fetch([RhythmRow].self, from: "field_rhythms")
        async let evidence = fetch([EvidenceRow].self, from: "field_evidence")
        async let held = fetch([HeldTopicRow].self, from: "field_held_topics")
        async let rules = fetch([StandingRuleRow].self, from: "field_standing_rules")
        async let captures = fetch([CaptureRow].self, from: "field_captures")
        async let corrections = fetch([CorrectionRow].self, from: "field_corrections")
        async let moment = fetchMoment()

        let resolvedIdentity = try await identity
        let resolvedQuestions = try await questions

        return FieldState(
            identity: resolvedIdentity,
            partners: try await partners(windows: windows),
            lifeItems: try await lifeItems.map(map),
            clusters: try await clusters.map(map),
            oursItems: try await oursItems.map(map),
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
            nameB: nameB
        )
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
            lastSentOn: row.last_sent_on
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
            anchorDate: row.anchor_date
        )
    }

    private func map(_ row: LifeItemRow) -> LifeItem {
        LifeItem(
            id: row.id.uuidString,
            title: row.title,
            category: LifeCategory(rawValue: row.category) ?? .calendar,
            owner: owner(row.owner),
            dueOn: row.due_on,
            closesAt: row.closes_at,
            clusterID: row.cluster_id?.uuidString,
            source: FieldItemSource(rawValue: row.source) ?? .captured,
            detail: row.detail,
            isTimeCritical: row.is_time_critical,
            isDone: row.is_done
        )
    }

    private func map(_ row: OursItemRow) -> OursItem {
        OursItem(
            id: row.id.uuidString,
            title: row.title,
            list: OursList(rawValue: row.list) ?? .someday,
            addedBy: row.both_added ? .shared : owner(for: row.added_by),
            addedAt: row.added_at,
            bothAdded: row.both_added,
            coincidenceNote: row.coincidence_note,
            horizonID: row.horizon_id?.uuidString,
            isStandingNote: row.is_standing_note
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
            targetDate: row.target_date,
            linkedLifeItemIDs: [],
            linkedOursItemIDs: [],
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

    private func map(_ row: HeldTopicRow) -> FieldHeldTopic {
        FieldHeldTopic(
            id: row.id.uuidString,
            title: row.title,
            timing: row.timing,
            reason: row.reason,
            surfaceOn: row.surface_on,
            wasOverridden: row.was_overridden,
            wasDismissed: row.was_dismissed
        )
    }

    private func map(_ row: StandingRuleRow) -> FieldStandingRule {
        FieldStandingRule(
            id: row.id.uuidString,
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
            id: row.id.uuidString,
            input: row.input,
            original: destination(row.original_destination),
            corrected: destination(row.corrected_destination),
            correctedAt: row.corrected_at
        )
    }

    /// Destinations round-trip through their display label, so the column is
    /// readable in the Supabase table editor. Anything unrecognised falls to
    /// Someday rather than throwing — a correction log is not worth a crash.
    private func destination(_ label: String) -> FieldDestination {
        FieldDestination.allCases.first { $0.label == label } ?? .ours(.someday)
    }

    // MARK: Writes

    func append(_ capture: FieldCapture) async throws {
        _ = try await client.from("field_captures").insert([
            "couple_id": AnyJSON.string(coupleID.uuidString),
            "text": .string(capture.text),
            "spoken_by": .string(viewerID.uuidString),
            "destination": .string(""),
            "reasoning": .string(""),
        ]).execute()
    }

    func record(_ correction: FieldCorrection) async throws {
        _ = try await client.from("field_corrections").insert([
            "couple_id": AnyJSON.string(coupleID.uuidString),
            "input": .string(correction.input),
            "original_destination": .string(correction.original.label),
            "corrected_destination": .string(correction.corrected.label),
            "corrected_by": .string(viewerID.uuidString),
        ]).execute()
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
        _ = try await client
            .from("field_life_items")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    func upsert(_ item: OursItem) async throws {
        var payload: [String: AnyJSON] = [
            "couple_id": .string(coupleID.uuidString),
            "title": .string(item.title),
            "list": .string(item.list.rawValue),
            "added_by": .string(viewerID.uuidString),
            "is_standing_note": .bool(item.isStandingNote),
        ]
        if let existing = UUID(uuidString: item.id) {
            payload["id"] = .string(existing.uuidString)
        }
        // `both_added` and `coincidence_note` are deliberately not sent. The
        // trigger owns them, because only the database can see both partners'
        // rows at once — and that inference is the app's best trick.
        _ = try await client
            .from("field_ours_items")
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

    func setHeld(_ topic: FieldHeldTopic) async throws {
        guard let id = UUID(uuidString: topic.id) else { return }
        _ = try await client
            .from("field_held_topics")
            .update([
                "was_overridden": AnyJSON.bool(topic.wasOverridden),
                "was_dismissed": .bool(topic.wasDismissed),
            ])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func setStandingRule(_ rule: FieldStandingRule) async throws {
        _ = try await client.from("field_standing_rules").insert([
            "couple_id": AnyJSON.string(coupleID.uuidString),
            "text": .string(rule.text),
            "set_by": .string(viewerID.uuidString),
        ]).execute()
    }

    func setIdentity(_ identity: FieldIdentity) async throws {
        _ = try await client
            .from("field_identity")
            .upsert([
                "couple_id": AnyJSON.string(coupleID.uuidString),
                "swatch_a": .string(identity.personA.rawValue),
                "swatch_b": .string(identity.personB.rawValue),
            ], onConflict: "couple_id")
            .execute()
    }

    // MARK: Realtime
    //
    // The partner's captures and corrections have to land without a refresh —
    // "both added it, a week apart" is only impressive if it appears on its
    // own.

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { [client, coupleID] in
                let channel = client.channel("field:\(coupleID.uuidString)")
                let stream = channel.postgresChange(
                    AnyAction.self,
                    schema: "public"
                )
                await channel.subscribe()

                for await _ in stream {
                    if Task.isCancelled { break }
                    continuation.yield()
                }
                await channel.unsubscribe()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
