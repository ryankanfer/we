//
//  YoursModel.swift
//  WE
//
//  The personal space, as values.
//
//  Deliberately not part of `FieldState`. Everything in the Field stack is
//  couple-scoped — one atomic value, cached to disk, read by the intelligence
//  engines, and reloaded from a realtime channel keyed on the couple. All four
//  of those are wrong here:
//
//    CIRCLE.md §10 forbids a partner-accessible event for creation, renewal,
//    expiry or deletion. A couple-scoped table announces every one of them on
//    a channel the other person is already listening to.
//
//    §10 also says raw text never reaches the shared intelligence layer, and
//    that layer reads `FieldState`.
//
//    `FieldStateCache` writes `FieldState` to disk. Entry text does not go
//    there.
//
//    And this space exists before pairing and after a relationship ends. It
//    belongs to a person.
//
//  `nonisolated` throughout, following `PrivateProposal`: these values cross
//  actor boundaries on their way to and from the backend, and the main-actor
//  isolation the rest of `FieldModel` carries would make that a fight.
//

import Foundation

// MARK: - Where an entry is in its life

/// One shape, five conditions — but only four of them are states. Letting go
/// is a transition, not a place: the circle contracts to nothing and the
/// surface returns to empty.
nonisolated enum YoursEntryState: String, Codable, Hashable, Sendable {
    /// Written, and not yet asking anything.
    case living
    /// Its interval elapsed. Presentable, and not yet at risk — the clock that
    /// can release something only ever runs once the person has been asked.
    case ready
    /// On screen, with seven days to answer.
    case presented
    /// Made permanent, deliberately. Reversible, because permanence people
    /// cannot undo is permanence they hesitate to use.
    case held
}

// MARK: - The entry

nonisolated struct YoursEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    /// The id this client minted before the row existed, so a retried save is
    /// the same entry rather than a second copy of somebody's private writing.
    let clientID: String
    var body: String
    var state: YoursEntryState

    /// Zero in first life, one in first renewal.
    ///
    /// Never rendered. §3 is emphatic and the prohibition is permanent: not
    /// exposed to the partner, not shown to the owner as a number, not fed to
    /// ranking, prioritisation or any suggestion, and never spoken back as
    /// "this must matter to you". Renewal is permission to ask, never
    /// permission to infer — keeping something twice can mean uncertainty,
    /// rumination, avoidance, or simply not being ready.
    ///
    /// It is carried here for exactly one purpose: deciding which of two
    /// questions the return asks.
    var renewalCount: Int

    let createdAt: Date
    /// When it becomes presentable.
    var readyAt: Date
    /// One year after `readyAt`, for an entry that is never reached. Follows
    /// the entry's state, never the person's behaviour.
    var unseenDeleteAt: Date
    /// Nil until it has actually been shown.
    var presentedAt: Date?
    /// The end of the seven days. Cannot exist without `presentedAt`, and the
    /// database refuses the combination outright.
    var decideBy: Date?
    var snoozedAt: Date?
    var heldAt: Date?

    /// The second return asks a different question from the first.
    var isSecondReturn: Bool { renewalCount >= 1 }

    /// One week, once.
    var canSnooze: Bool { snoozedAt == nil }
}

// MARK: - Moving through a life
//
// Written as transitions rather than as setters so that each one names the
// decision it represents, and so the rules that are easy to get subtly wrong —
// what an edit does to the stage, what a snooze does to the window, what
// letting something return clears — live next to each other where they can be
// compared.
//
// The server is authoritative for every one of these (§11). These exist so the
// in-memory backend and the optimistic paths behave the way the database does
// rather than approximately like it.

extension YoursEntry {
    /// Shown. The seven days start here and could not have started earlier.
    func presented(at now: Date, decideBy: Date) -> YoursEntry {
        var copy = self
        copy.state = .presented
        copy.presentedAt = now
        copy.decideBy = decideBy
        return copy
    }

    /// "Keep for now", at the first return only.
    func renewed(at now: Date, readyAt: Date) -> YoursEntry {
        var copy = renewedWithoutCounting(readyAt: readyAt)
        copy.renewalCount = renewalCount + 1
        return copy
    }

    /// A fresh interval at the same stage.
    ///
    /// Used when preparing an offer, which §3 does not describe as a renewal
    /// decision — so the count does not move, and the entry stays mortal and
    /// will ask again.
    func renewedWithoutCounting(readyAt: Date) -> YoursEntry {
        var copy = self
        copy.state = .living
        copy.readyAt = readyAt
        copy.unseenDeleteAt = YoursDates.outerBound(after: readyAt)
        copy.presentedAt = nil
        copy.decideBy = nil
        return copy
    }

    /// Permanence, chosen.
    func held(at now: Date) -> YoursEntry {
        var copy = self
        copy.state = .held
        copy.heldAt = heldAt ?? now
        copy.presentedAt = nil
        copy.decideBy = nil
        return copy
    }

    /// "Update Held" — overwrites, and explicitly keeps the new version
    /// permanent. There is no version history: a revision log would be an
    /// accumulating, undeletable record of exactly the material this design
    /// exists to let go of.
    func heldWith(body: String, at now: Date) -> YoursEntry {
        var copy = held(at: now)
        copy.body = body
        return copy
    }

    /// "Let this return." A fresh first life, prior renewal history cleared,
    /// and not itself a renewal. The snooze is cleared too — a new life is
    /// entitled to its own week.
    func returningToNaturalLife(at now: Date, body: String) -> YoursEntry {
        var copy = self
        copy.body = body
        copy.state = .living
        copy.renewalCount = 0
        copy.readyAt = YoursDates.projectedReadyAt(from: now)
        copy.unseenDeleteAt = YoursDates.outerBound(after: copy.readyAt)
        copy.heldAt = nil
        copy.presentedAt = nil
        copy.decideBy = nil
        copy.snoozedAt = nil
        return copy
    }

    /// "Give me a week."
    ///
    /// The entry leaves the screen now and becomes presentable again in
    /// exactly seven days — but `decideBy` is set here, fourteen days out, and
    /// the sweep honours it whether or not the entry is ever shown again. That
    /// asymmetry is the one place a clock runs while nobody is looking, and it
    /// is why the exact final date is stated before this is confirmed.
    func snoozed(at now: Date) -> YoursEntry {
        var copy = self
        copy.state = .ready
        copy.snoozedAt = now
        copy.readyAt = now.addingTimeInterval(7 * 86_400)
        copy.decideBy = now.addingTimeInterval(14 * 86_400)
        copy.unseenDeleteAt = YoursDates.outerBound(after: copy.readyAt)
        return copy
    }
}

// MARK: - Prepared offers

/// §6. A separate, frozen artifact carrying the exact wording the person
/// approved. Not a pointer to the entry, and it does not carry the entry's
/// text — which is why there is no `body` here and why `sourceEntryID` is
/// allowed to go nil underneath it.
///
/// Its own, shorter life: two weeks, one return, send or let go. No third
/// option and no permanence. Without that, this design rebuilds the pile one
/// room over with heavier objects, because an addressed unsent thing weighs
/// more than a private note.
nonisolated struct YoursPreparedOffer: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let clientID: String
    let sourceEntryID: String?
    let title: String
    let question: String
    let options: [String]
    let preparedAt: Date
    let readyAt: Date
    var presentedAt: Date?
    var decideBy: Date?
    var sentAt: Date?
}

extension YoursPreparedOffer {
    func presented(at now: Date, decideBy: Date) -> YoursPreparedOffer {
        var copy = self
        copy.presentedAt = now
        copy.decideBy = decideBy
        return copy
    }

    /// It crossed. From the partner's side this is indistinguishable from a
    /// topic composed from scratch that morning — they never see the source
    /// entry, the renewal count, the dates, or the fact that anything matured.
    func sent(at now: Date) -> YoursPreparedOffer {
        var copy = self
        copy.sentAt = now
        copy.presentedAt = nil
        copy.decideBy = nil
        return copy
    }
}

// MARK: - Why somebody let something go

/// §13's sharpest measure.
///
/// A prepared offer is already partner-directed, so releasing one is
/// avoidance-shaped — "I wasn't serious about that apartment anyway" — and
/// will read as relief for reasons unrelated to the thesis. Free writing about
/// oneself is a different emotional object, and releasing *that* is the only
/// result that says anything about whether this works.
///
/// So the answer is never pooled across the two kinds, and the four reasons
/// split along the line that matters:
///
///   `resolved`, `neverMattered`   relief from indecision
///   `noLongerTrue`, `notReady`    the personal register
///
/// A closed set rather than a text field, because §10 forbids raw text
/// reaching analytics — and because a text box at the moment of letting go is
/// an interview nobody agreed to.
nonisolated enum YoursReleaseReason: String, Codable, Hashable, Sendable, CaseIterable {
    case resolved
    case noLongerTrue
    case neverMattered
    case notReady

    /// Shown as the options under "Let go", in this order. Answering is
    /// optional and declining records nothing.
    var prompt: String {
        switch self {
        case .resolved: "I decided"
        case .noLongerTrue: "I don't feel this way now"
        case .neverMattered: "It wasn't important"
        case .notReady: "I don't want to look at this"
        }
    }
}

/// Which kind of thing was released. Present on every recorded release and in
/// the group-by of every report run against them — a single pooled release
/// rate would let prepared-offer volume drown the free-writing signal and
/// still read as healthy.
nonisolated enum YoursReleaseKind: String, Codable, Hashable, Sendable {
    case entry
    case preparedOffer = "prepared_offer"
}

// MARK: - What the owner state carries

nonisolated struct YoursOwnerState: Codable, Hashable, Sendable {
    /// §2 allows the word "Yours" exactly twice in a person's lifetime: once
    /// during the Promise, once on first entry. After that the mark is
    /// wordless permanently — no title, no navigation label, no section
    /// header, no settings row.
    ///
    /// Server-side rather than `@AppStorage` because a lifetime belongs to the
    /// person and `@AppStorage` belongs to a device: a second phone would
    /// teach it a third and fourth time.
    var taughtInPromise: Bool
    var taughtOnFirstEntry: Bool

    static let unknown = YoursOwnerState(
        taughtInPromise: false,
        taughtOnFirstEntry: false
    )
}

// MARK: - A visit

/// One foreground session.
///
/// The presentation gate is written in terms of this: `presentNext` is
/// idempotent within a visit, so a client that asks twice gets the same entry
/// rather than promoting a second one, and after something is resolved the
/// next entry waits for the next visit. §5: "the next ready entry appears on
/// the owner's next visit, not immediately."
nonisolated struct YoursVisit: Hashable, Sendable {
    let id: UUID

    init() { id = UUID() }
    init(id: UUID) { self.id = id }
}
