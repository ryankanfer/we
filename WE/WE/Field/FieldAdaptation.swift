//
//  FieldAdaptation.swift
//  WE
//
//  The rules every surface that appears on its own has to obey.
//
//  FieldIntelligence already holds the derivations themselves — pure enum
//  namespaces of static functions over an explicit Context, each returning a
//  reason alongside its result. This file adds the three things that were
//  implicit while there was only one adaptive surface, and stop being safe to
//  leave implicit once surfaces can appear, deepen, and recede:
//
//  1. Whose eyes the output lands in (`FieldPresenceKind`).
//  2. What it takes to earn a place, and to keep one (`FieldThreshold`).
//  3. Which material a shared surface is allowed to read at all
//     (`FieldSharedPresenceContext`).
//

import Foundation

// MARK: - Whose eyes

/// Whether a derivation's output changes what *both* people see exists, or only
/// the order of one person's own view.
///
/// This is the distinction the app was missing. Ranking the things in front of
/// you may legitimately read everything you can see, including your own
/// uncrossed solo history — it is your view. But a *room*, a *chapter*, or a
/// *capability* is furniture in a space two people share. If one person's
/// private material can conjure furniture, then the other person is living in a
/// room whose shape they cannot account for, and the first person's privacy is
/// leaking as architecture rather than as text.
///
/// So every derivation declares which kind it is, and `.shared` ones are handed
/// a context that has already had private material removed. The rule is
/// enforced by construction rather than by remembering.
nonisolated enum FieldPresenceKind: Sendable {
    /// Output both people see. Must read only shared material.
    case shared
    /// Output that orders one person's own view. May read everything that
    /// person can see.
    case personal
}

// MARK: - Earning a place, and keeping it

/// How much material a surface needs before it appears, and how much it needs
/// to stay.
///
/// The two numbers differ on purpose. A surface that appears at three items and
/// vanishes at two will flicker every time one thing is finished and another
/// added, and a room that blinks is worse than a room that never opened. So it
/// earns at `earnsAt` and keeps at one less.
///
/// The memory of having earned is *not* held on the device. Two people must see
/// the same furniture, and a per-device flag would give whoever crossed the
/// threshold first a room the other one does not have — the exact asymmetry
/// `FieldPresenceKind` exists to prevent. It is persisted per couple instead;
/// see `field_adaptations`.
nonisolated struct FieldThreshold: Hashable, Sendable {
    let earnsAt: Int

    init(earnsAt: Int) {
        precondition(earnsAt > 1, "a threshold of one cannot be hysteretic")
        self.earnsAt = earnsAt
    }

    /// One less than it took to appear, and never zero: a surface with nothing
    /// behind it recedes rather than lingering as an empty frame.
    var keepsAt: Int { max(1, earnsAt - 1) }

    func isMet(count: Int, hasEarned: Bool) -> Bool {
        count >= (hasEarned ? keepsAt : earnsAt)
    }
}

// MARK: - Naming an adaptation

/// The stable identity of one adaptive surface, used as the key for both marks
/// a surface can carry: that it has been earned, and that it has been set down.
///
/// Content-free by construction — a kind and a record id, never a title. These
/// keys sit in a table both people can read, so anything descriptive in them
/// would be a disclosure channel.
nonisolated enum FieldAdaptationKey {
    static func capability(_ capability: String, journeyID: String) -> String {
        "capability:\(capability):\(journeyID)"
    }
}

// MARK: - What a shared surface may read

/// The material a `.shared` derivation is allowed to see.
///
/// Note what is and is not filtered. Only the tables that carry a `visibility`
/// column can hold private rows — life items, captures, corrections, standing
/// rules, held topics. Clusters and horizons have no such column and are shared
/// by construction, so they arrive whole. `FieldOwner` is *not* a privacy
/// boundary: an item tinted to one person is still an item both people see.
nonisolated struct FieldSharedPresenceContext: Sendable {
    let now: Date
    /// Shared items only. Built through `init` below so a caller cannot hand in
    /// an unfiltered array by accident.
    let lifeItems: [LifeItem]
    let clusters: [FieldCluster]
    let horizons: [FieldHorizon]
    let evidence: [FieldEvidence]
    /// Surfaces the couple has set down. Reversible: the inputs are untouched.
    let setDown: Set<String>
    /// Surfaces that have earned their place at least once, for hysteresis.
    let earned: Set<String>
    let calendar: Calendar

    init(
        now: Date,
        lifeItems: [LifeItem],
        clusters: [FieldCluster],
        horizons: [FieldHorizon],
        evidence: [FieldEvidence] = [],
        setDown: Set<String> = [],
        earned: Set<String> = [],
        calendar: Calendar = .gregorianUS
    ) {
        self.now = now
        // The filter is here, in the initialiser, rather than at each call
        // site. There is exactly one way to build this value and it is not
        // possible to build a leaky one.
        self.lifeItems = lifeItems.filter(\.isSharedPresence)
        self.clusters = clusters
        self.horizons = horizons
        self.evidence = evidence
        self.setDown = setDown
        self.earned = earned
        self.calendar = calendar
    }

    func hasSetDown(_ key: String) -> Bool { setDown.contains(key) }
    func hasEarned(_ key: String) -> Bool { earned.contains(key) }
}
