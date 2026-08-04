//
//  YoursSupabaseBackend.swift
//  WE
//
//  The real one.
//
//  Two things it deliberately does not do, and both are the point of the
//  feature rather than omissions to fill in later:
//
//  IT DOES NOT SUBSCRIBE. `FieldSupabaseBackend` opens a realtime channel
//  keyed `field:<coupleID>`, because a partner's capture landing without a
//  refresh is most of what makes that surface feel shared. The equivalent here
//  would be a channel keyed on one account — a socket whose existence, timing
//  and traffic are metadata about a private space, on infrastructure shared
//  with the couple's. CIRCLE.md §10 forbids "not a row, not a timestamp"; a
//  subscription is worse than either. Multi-device agreement comes from §11:
//  the server holds authoritative state, the first saved action wins, and the
//  presentation gate is idempotent within a visit.
//
//  IT DOES NOT COMPUTE DATES. Every interval, window and bound in this feature
//  is decided by Postgres. A client that could compute `ready_at` is a client
//  that could send one, and `private.yours_stamp_entry` refuses exactly that.
//  Nothing in this file adds a day to anything.
//

import Foundation
import Supabase

// MARK: - Rows

private struct YoursEntryRow: Decodable {
    let id: UUID
    let client_id: UUID
    let body: String
    let state: String
    let renewal_count: Int
    let created_at: String
    let ready_at: String
    let unseen_delete_at: String
    let presented_at: String?
    let decide_by: String?
    let snoozed_at: String?
    let held_at: String?
}

private struct YoursOfferRow: Decodable {
    let id: UUID
    let client_id: UUID
    let source_entry_id: UUID?
    let title: String
    let question: String
    let options: [String]
    let prepared_at: String
    let ready_at: String
    let presented_at: String?
    let decide_by: String?
    let sent_at: String?
}

private struct YoursOwnerStateRow: Decodable {
    let taught_in_promise: Bool
    let taught_on_first_entry: Bool
}

/// Postgres emits `timestamptz` with fractional seconds sometimes and without
/// them others, depending on the value. Both are tried rather than assumed,
/// because the failure mode of guessing is a date that silently becomes nil
/// and an entry that looks like it has no return.
private func yoursDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601DateFormatter.weFlexible.date(from: value)
        ?? ISO8601DateFormatter.we.date(from: value)
}

private func yoursDate(required value: String) -> Date {
    yoursDate(value) ?? .distantPast
}

private extension YoursEntryRow {
    var entry: YoursEntry {
        let readyAt = yoursDate(required: ready_at)
        return YoursEntry(
            id: id.uuidString,
            clientID: client_id.uuidString,
            body: body,
            state: YoursEntryState(rawValue: state) ?? .living,
            renewalCount: renewal_count,
            createdAt: yoursDate(required: created_at),
            readyAt: readyAt,
            unseenDeleteAt: yoursDate(unseen_delete_at) ?? readyAt,
            presentedAt: yoursDate(presented_at),
            decideBy: yoursDate(decide_by),
            snoozedAt: yoursDate(snoozed_at),
            heldAt: yoursDate(held_at)
        )
    }
}

private extension YoursOfferRow {
    var offer: YoursPreparedOffer {
        YoursPreparedOffer(
            id: id.uuidString,
            clientID: client_id.uuidString,
            sourceEntryID: source_entry_id?.uuidString,
            title: title,
            question: question,
            options: options,
            preparedAt: yoursDate(required: prepared_at),
            readyAt: yoursDate(required: ready_at),
            presentedAt: yoursDate(presented_at),
            decideBy: yoursDate(decide_by),
            sentAt: yoursDate(sent_at)
        )
    }
}

// MARK: - Backend

final class YoursSupabaseBackend: YoursBackend, @unchecked Sendable {
    private let client: SupabaseClient

    init?(client: SupabaseClient?) {
        guard let client else { return nil }
        self.client = client
    }

    // MARK: Reading

    func load() async throws -> YoursSnapshot {
        // Owner-scoped by RLS — `owner_id = auth.uid()` and nothing else.
        // There is no couple in that predicate, so this returns the same rows
        // before pairing, after pairing, and after a relationship ends.
        async let rows: [YoursEntryRow] = client
            .from("yours_entries")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        async let offerRows: [YoursOfferRow] = client
            .from("yours_prepared_offers")
            .select()
            .is("sent_at", value: nil)
            .order("prepared_at", ascending: false)
            .execute()
            .value

        async let stateRows: [YoursOwnerStateRow] = client
            .from("yours_owner_state")
            .select("taught_in_promise,taught_on_first_entry")
            .limit(1)
            .execute()
            .value

        let entries = try await rows.map(\.entry)
        let ownerState = try await stateRows.first.map {
            YoursOwnerState(
                taughtInPromise: $0.taught_in_promise,
                taughtOnFirstEntry: $0.taught_on_first_entry
            )
        } ?? .unknown

        return YoursSnapshot(
            living: entries.filter { $0.state != .held },
            held: entries.filter { $0.state == .held },
            offers: try await offerRows.map(\.offer),
            ownerState: ownerState
        )
    }

    // MARK: Writing

    func save(clientID: String, body: String) async throws -> YoursEntry {
        // A plain insert rather than an RPC: the trigger stamps the owner, the
        // state and both dates, so there is nothing for a function to add.
        let row: YoursEntryRow = try await client
            .from("yours_entries")
            .insert(["client_id": clientID, "body": body])
            .select()
            .single()
            .execute()
            .value
        return row.entry
    }

    func edit(entryID: String, body: String) async throws -> YoursEntry {
        // Also a plain update, and it is worth saying why this one is safe:
        // the trigger reduces any non-lifecycle update to a body change,
        // restarts the current interval, and refuses outright if the entry is
        // held. A client cannot turn this into a renewal.
        let row: YoursEntryRow = try await client
            .from("yours_entries")
            .update(["body": body])
            .eq("id", value: entryID)
            .select()
            .single()
            .execute()
            .value
        return row.entry
    }

    // MARK: The gate

    func presentNext(visit: YoursVisit) async throws -> YoursEntry? {
        let row: YoursEntryRow? = try await client
            .rpc("yours_present_next", params: ["p_visit": visit.id.uuidString])
            .execute()
            .value
        return row?.entry
    }

    func presentNextOffer(visit: YoursVisit) async throws -> YoursPreparedOffer? {
        let row: YoursOfferRow? = try await client
            .rpc(
                "yours_present_next_offer",
                params: ["p_visit": visit.id.uuidString]
            )
            .execute()
            .value
        return row?.offer
    }

    // MARK: Answering

    func keepForNow(entryID: String, visit: YoursVisit) async throws -> YoursEntry {
        try await entryRPC(
            "yours_keep_for_now",
            ["p_entry": entryID, "p_visit": visit.id.uuidString]
        )
    }

    func hold(entryID: String, visit: YoursVisit?) async throws -> YoursEntry {
        try await entryRPC(
            "yours_hold",
            ["p_entry": .string(entryID), "p_visit": visitJSON(visit)]
        )
    }

    func snooze(entryID: String, visit: YoursVisit) async throws -> YoursEntry {
        try await entryRPC(
            "yours_snooze",
            ["p_entry": entryID, "p_visit": visit.id.uuidString]
        )
    }

    func letThisReturn(entryID: String, body: String?) async throws -> YoursEntry {
        try await entryRPC(
            "yours_let_this_return",
            [
                "p_entry": .string(entryID),
                "p_body": body.map { AnyJSON.string($0) } ?? .null,
            ]
        )
    }

    func updateHeld(entryID: String, body: String) async throws -> YoursEntry {
        try await entryRPC(
            "yours_update_held",
            ["p_entry": entryID, "p_body": body]
        )
    }

    /// The only client-reachable route to `private.yours_destroy`.
    ///
    /// There is no delete policy on `yours_entries`, so this is not one door
    /// among several — it is the door.
    func letGo(
        entryID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws {
        try await client
            .rpc(
                "yours_let_go",
                params: [
                    "p_entry": .string(entryID),
                    "p_visit": visitJSON(visit),
                    "p_reason": reason.map { AnyJSON.string($0.rawValue) } ?? .null,
                ]
            )
            .execute()
    }

    // MARK: Offers

    func prepareOffer(
        entryID: String,
        clientID: String,
        title: String,
        question: String,
        options: [String],
        visit: YoursVisit?
    ) async throws -> YoursPreparedOffer {
        let row: YoursOfferRow = try await client
            .rpc(
                "yours_prepare_offer",
                params: [
                    "p_entry": .string(entryID),
                    "p_client_id": .string(clientID),
                    "p_title": .string(title),
                    "p_question": .string(question),
                    "p_options": .array(options.map { .string($0) }),
                    "p_visit": visitJSON(visit),
                ]
            )
            .execute()
            .value
        return row.offer
    }

    func sendOffer(offerID: String) async throws {
        try await client
            .rpc("yours_send_offer", params: ["p_offer": offerID])
            .execute()
    }

    func letOfferGo(
        offerID: String,
        visit: YoursVisit?,
        reason: YoursReleaseReason?
    ) async throws {
        try await client
            .rpc(
                "yours_offer_let_go",
                params: [
                    "p_offer": .string(offerID),
                    "p_visit": visitJSON(visit),
                    "p_reason": reason.map { AnyJSON.string($0.rawValue) } ?? .null,
                ]
            )
            .execute()
    }

    // MARK: Presence and teaching

    /// Called on foreground, whether or not this space is opened.
    ///
    /// §5's ninety-day rule is about the product, not this room. If this only
    /// fired when somebody opened Yours, a person who used the shared side
    /// every day would have their private writing swept out from under them.
    func touch() async throws {
        try await client.rpc("yours_touch").execute()
    }

    func markTaught(_ moment: YoursTeachingMoment) async throws -> YoursOwnerState {
        let row: YoursOwnerStateRow = try await client
            .rpc("yours_mark_taught", params: ["p_which": moment.rawValue])
            .execute()
            .value
        return YoursOwnerState(
            taughtInPromise: row.taught_in_promise,
            taughtOnFirstEntry: row.taught_on_first_entry
        )
    }

    // MARK: -

    private func entryRPC(
        _ name: String,
        _ params: [String: AnyJSON]
    ) async throws -> YoursEntry {
        let row: YoursEntryRow = try await client
            .rpc(name, params: params)
            .execute()
            .value
        return row.entry
    }

    private func entryRPC(
        _ name: String,
        _ params: [String: String]
    ) async throws -> YoursEntry {
        try await entryRPC(name, params.mapValues { AnyJSON.string($0) })
    }

    private func visitJSON(_ visit: YoursVisit?) -> AnyJSON {
        visit.map { AnyJSON.string($0.id.uuidString) } ?? .null
    }
}
