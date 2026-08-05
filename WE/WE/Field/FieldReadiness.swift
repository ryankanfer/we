//
//  FieldReadiness.swift
//  WE
//
//  The circle: what the app knows about whether the two of them are open to
//  each other today, and everything it is allowed to say about it.
//
//  Three states and there is no fourth. `partner` — "they have marked, you
//  have not" — is the state this whole feature is built to be incapable of
//  representing, in the model as much as in the schema. Knowing your partner
//  is open while you have not answered turns an invitation into a request,
//  and a waiting indicator is precisely the residue the room is designed not
//  to leave. See `20260805090000_field_readiness.sql`.
//

import Foundation

// MARK: - What the app knows

/// `Sendable` and declared alongside `FieldState`'s neighbours, because it
/// crosses the same boundary they do: a nonisolated backend returns it to the
/// main-actor store.
enum FieldReadinessState: String, Codable, Hashable, Sendable {
    /// Nobody has marked today — or the partner has, alone, which is
    /// deliberately the same answer. Nothing distinguishes the two, here or in
    /// the RPC that produces them.
    case neither
    /// You have marked. Your partner has not, or has and the bloom has not
    /// reached this device yet.
    case you
    /// Both of you, independently. The only state that carries words.
    case both
}

/// The state, and the prompt if there is one.
///
/// The prompt arrives *with* the state rather than being chosen on device.
/// Two devices picking their own words from a shared seed is one refactor away
/// from two people looking at different questions, and the entire content of
/// the room is that they are looking at the same one.
struct FieldReadiness: Codable, Hashable, Sendable {
    var state: FieldReadinessState
    /// Non-nil exactly when `state` is `.both`.
    var prompt: String?
    /// The client's day, `yyyy-MM-dd`. Carried so a snapshot taken before
    /// midnight is recognisably not about today after it.
    var localDate: String

    static func neither(on localDate: String) -> FieldReadiness {
        FieldReadiness(state: .neither, prompt: nil, localDate: localDate)
    }

    var hasBloomed: Bool { state == .both }
}

// MARK: - The day

extension FieldReadiness {
    /// The one place a `Date` becomes the string the RPCs take.
    ///
    /// The device's own calendar day, not UTC: two people in different
    /// timezones each tap on their own evening, and a UTC day would put one of
    /// them into tomorrow's circle for part of every night.
    static func localDate(for date: Date) -> String {
        DateFormatter.fieldDay.string(from: date)
    }
}

// MARK: - What it says

/// The room's words, and the teaching that has to precede them.
///
/// First-use teaching is required rather than optional. A tap that visibly
/// does nothing is incomprehensible without it, and somebody who does not know
/// that is what is supposed to happen will tap again — which is the covert
/// pressure the design forbids. Explained once, then never again, the same
/// discipline as `YoursTeachingSheet`.
enum FieldCircleCopy {
    /// What the mark is, said before it is ever tapped.
    static let teachingTitle = "There's a way to say you're open."

    /// The three things somebody has to know, and nothing beyond them.
    ///
    /// The second sentence is the load-bearing one: without it the honest
    /// reading of a silent tap is "it didn't work", and the natural response
    /// to that is to tap again at somebody.
    static let teachingBody = """
        Touch the mark when you'd welcome a moment together.

        Nothing is shown to your partner. They won't know, and there's no \
        waiting — if they touch theirs on their own day, something opens for \
        both of you at once.
        """

    static let teachingDismiss = "Alright"

    /// The mark's accessibility label, which is also the only place the
    /// gesture is named for VoiceOver.
    static let markLabel = "Say you're open to a moment together"

    /// After a tap, for the person who marked first. Deliberately not a
    /// status: it describes what they did, not what is being waited for.
    static let marked = "Noted, just for you."

    /// The bloom's one line above the prompt.
    static let bloomTitle = "There's room for something together."

    /// The way out. The room closes without residue, so this is not "save" or
    /// "done" — nothing is being kept.
    static let close = "Close"

    /// Under the close, small. The whole promise of the room in one line.
    static let noResidue = "Nothing from here is kept."
}
