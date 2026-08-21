//
//  WECeremonySupabase.swift
//  WE
//
//  The ceremony's two reads and one write, against Postgres.
//
//  See `supabase/migrations/20260820210000_ceremony_acknowledgements.sql` for
//  why the shape is what it is. The short version: owner-only RLS makes the
//  partner's row and its timestamp unreadable by construction, the aggregate
//  RPC returns a bare boolean per beat, and the table is deliberately absent
//  from `FieldSupabaseBackend.observedTables` so a write generates no realtime
//  event on the partner's subscription. A row event would carry its own
//  arrival time, which is the timestamp again wearing a different hat.
//

import Foundation
import Supabase

private struct AcknowledgementRow: Decodable {
    let beat: String
}

private struct KeptRow: Decodable {
    let beat: String
    let kept: Bool
}

extension FieldSupabaseBackend: WECeremonyBackend {

    /// This person's own rows. The `select` needs no `profile_id` filter —
    /// the policy is the filter, and writing one here would suggest the
    /// policy were optional.
    func myAcknowledgements() async throws -> Set<WEBeat> {
        let rows: [AcknowledgementRow] = try await client
            .from("ceremony_acknowledgements")
            .select("beat")
            .execute()
            .value
        return Set(rows.compactMap { WEBeat(rawValue: $0.beat) })
    }

    /// The aggregate. Beats nobody has touched come back too, as `false`, so
    /// the client never has to infer anything from which rows are missing.
    func keptBeats() async throws -> Set<WEBeat> {
        let rows: [KeptRow] = try await client
            .rpc("ceremony_beat_is_kept")
            .execute()
            .value
        return Set(
            rows.lazy
                .filter(\.kept)
                .compactMap { WEBeat(rawValue: $0.beat) }
        )
    }

    func keepBeat(_ beat: WEBeat) async throws {
        try await client
            .rpc("keep_ceremony_beat", params: ["p_beat": beat.rawValue])
            .execute()
    }
}
