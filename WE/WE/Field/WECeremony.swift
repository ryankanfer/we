//
//  WECeremony.swift
//  WE
//
//  The Joining: three beats, two phones, and no way to finish alone.
//
//  Every other product in this category lets one person configure everything
//  and then invite a partner into a finished room. WE refuses. The moment two
//  people arrive, the app performs its own promise instead of describing it:
//  three commitments, shown one at a time, on two phones at once, where
//  neither screen advances until both people have acknowledged the beat. The
//  rule each beat describes is the rule governing the beat.
//
//  This file is the model and the client. The surfaces come later; what
//  matters here is that the state a surface can ask for is *only* the state
//  the direction permits it to know.
//

import Foundation

// MARK: - The beats

/// The three commitments, in the order they are performed.
///
/// Named rather than numbered, all the way down to the database. An index
/// would invite reading "how far along is the other person" out of a maximum,
/// and it would not survive the beats being reordered.
enum WEBeat: String, CaseIterable, Codable, Sendable, Identifiable {
    case yoursStaysYours = "yours_stays_yours"
    case nothingMovesWithoutYou = "nothing_moves_without_you"
    case whatOpensOpensTogether = "what_opens_opens_together"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yoursStaysYours: "Yours stays yours."
        case .nothingMovesWithoutYou: "Nothing moves without you."
        case .whatOpensOpensTogether: "What opens, opens together."
        }
    }

    /// The one supporting line. Never a second paragraph: the beat is the
    /// commitment, and explaining a commitment at length is hedging it.
    func detail(partner: String) -> String {
        switch self {
        case .yoursStaysYours:
            "Nothing you write reaches \(partner) unless you send it."
        case .nothingMovesWithoutYou:
            "You see the topic before you see anything else."
        case .whatOpensOpensTogether:
            "Two answers, one direction, neither of you first."
        }
    }

    var next: WEBeat? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else {
            return nil
        }
        return all[i + 1]
    }
}

// MARK: - What a beat can be

/// The three states of a beat, and the entire vocabulary a surface gets.
///
/// There is deliberately no case for "they have acknowledged and I have not."
/// From this device that state is indistinguishable from `waiting`, and it is
/// indistinguishable on purpose — showing one person the other's action before
/// it lands is the thing the ceremony exists to not do.
enum WEBeatState: Equatable, Sendable {
    /// Neither of us has acknowledged, or they have and I cannot tell.
    case waiting
    /// I have acknowledged. Whether they have is not knowable from here.
    case held
    /// Both of us have. The beat resolves, on both phones, at once.
    case kept
}

// MARK: - The ceremony's state

/// Everything a ceremony surface is allowed to know.
///
/// `mine` is this device's own acknowledgements, read from rows only this
/// person can select. `kept` is the aggregate, one bare boolean per beat. The
/// two are combined here rather than on a server so that the combination
/// itself cannot become a thing the network reports.
struct WECeremonyState: Equatable, Sendable {
    var mine: Set<WEBeat> = []
    var kept: Set<WEBeat> = []

    func state(of beat: WEBeat) -> WEBeatState {
        if kept.contains(beat) { return .kept }
        if mine.contains(beat) { return .held }
        return .waiting
    }

    /// The beat the ceremony is currently on.
    ///
    /// Resumption lands here: the first beat not yet kept. Someone returning
    /// after a day walks back into the room rather than restarting, and
    /// someone who has kept a beat and is waiting sees that same beat still,
    /// unchanged, with nothing accumulating on it.
    var currentBeat: WEBeat? {
        WEBeat.allCases.first { !kept.contains($0) }
    }

    var isComplete: Bool { currentBeat == nil }

    /// Whether this device has done its part on the current beat.
    var hasGivenCurrentBeat: Bool {
        guard let beat = currentBeat else { return true }
        return mine.contains(beat)
    }
}

// MARK: - The client

/// What a ceremony needs from a backend. Two reads and one write, and no
/// method that could answer "when did they."
protocol WECeremonyBackend: Sendable {
    /// This person's own acknowledgements. Owner-only RLS means the query
    /// cannot return the partner's rows even if it were written to try.
    func myAcknowledgements() async throws -> Set<WEBeat>

    /// The aggregate, from `ceremony_beat_is_kept()`. One boolean per beat:
    /// no identity, no ordering, no count, no timestamp.
    func keptBeats() async throws -> Set<WEBeat>

    /// Idempotent. A phone that loses its connection mid-beat can say the
    /// same thing again without being told it already did.
    func keepBeat(_ beat: WEBeat) async throws

    /// Whether this couple performs the ceremony at all.
    ///
    /// Deliberately not derived from the acknowledgements. A couple who
    /// arrived before the ceremony existed has no rows, and so does a couple
    /// who arrived a moment ago — reading "no rows" as "not started" walks
    /// every existing couple into The Joining months into a relationship.
    /// Absence of rows means nothing was written, and that is all it means.
    func ceremonyIsRequired() async throws -> Bool
}

/// Reads both halves and combines them.
///
/// Deliberately two calls rather than one. A single server call returning the
/// combined state would have to know both people's rows *and* which caller it
/// was answering, which is a shape that can leak by accident. Two calls, one
/// of which is owner-scoped by RLS and one of which returns bare booleans,
/// cannot.
extension WECeremonyBackend {
    func ceremonyState() async throws -> WECeremonyState {
        async let mine = myAcknowledgements()
        async let kept = keptBeats()
        return try await WECeremonyState(mine: mine, kept: kept)
    }
}
