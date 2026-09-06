//
//  SharedJourneyCapabilityPolicy.swift
//  WE
//
//  Which views a journey has earned, and the proof of why.
//
//  Pure, in the same shape as `SharedJourneyPolicy` and the FieldIntelligence
//  namespaces: static functions over an explicit context, testable without
//  SwiftUI, Supabase, or a model provider.
//
//  Two things are worth reading before changing anything here.
//
//  First, `eligible` takes no viewer. That is not an oversight — this is a
//  `.shared` derivation, and a capability that could be computed differently
//  for the two people would be exactly the asymmetry `FieldPresenceKind`
//  exists to rule out. The context it receives has already had private rows
//  removed, and there is no parameter through which a viewer could re-enter.
//
//  Second, nothing here writes. A capability binds to records the couple
//  already has and reads them; it never copies what it displays. That is what
//  lets a surface recede without taking anything with it.
//

import Foundation
import os

/// A record a journey points at, resolved to something renderable.
nonisolated struct JourneySubject: Identifiable, Hashable, Sendable {
    var id: FieldReference { reference }
    let reference: FieldReference
    let title: String
    let detail: String?
}

nonisolated enum SharedJourneyCapabilityPolicy {
    static let presence: FieldPresenceKind = .shared

    /// Three is the point at which a list stops being a coincidence.
    ///
    /// Two things in common is two things in common; three is a pattern worth
    /// giving a surface to. It keeps at two so that finishing one item does
    /// not close the room — see `FieldThreshold`.
    static let criteriaThreshold = FieldThreshold(earnsAt: 3)

    // MARK: Resolution

    /// The journey's references, resolved against material both people can
    /// see, in the order the journey recorded them.
    ///
    /// A reference that resolves to nothing is dropped rather than rendered as
    /// a gap: the record may have been deleted, or — the case that matters —
    /// it may be one person's private row, which this context has already
    /// removed. Both are the same answer. Nothing here can tell the two apart,
    /// and that is deliberate.
    static func subjects(
        for journey: SharedJourney,
        context: FieldSharedPresenceContext
    ) -> [JourneySubject] {
        journey.subjectReferences.compactMap { resolve($0, context: context) }
    }

    static func resolve(
        _ reference: FieldReference,
        context: FieldSharedPresenceContext
    ) -> JourneySubject? {
        switch reference.kind {
        case FieldReference.Kind.lifeItem:
            guard let item = context.lifeItems.first(where: {
                $0.id == reference.id
            }) else { return nil }
            return JourneySubject(
                reference: reference, title: item.title, detail: item.detail
            )
        case FieldReference.Kind.cluster:
            guard let cluster = context.clusters.first(where: {
                $0.id == reference.id
            }) else { return nil }
            return JourneySubject(
                reference: reference,
                title: cluster.title,
                detail: cluster.rationale
            )
        case FieldReference.Kind.horizon:
            guard let horizon = context.horizons.first(where: {
                $0.id == reference.id
            }) else { return nil }
            return JourneySubject(
                reference: reference, title: horizon.title, detail: horizon.thesis
            )
        case FieldReference.Kind.evidence:
            guard let evidence = context.evidence.first(where: {
                $0.id == reference.id
            }) else { return nil }
            return JourneySubject(
                reference: reference, title: evidence.statement, detail: nil
            )
        case FieldReference.Kind.fieldQuestion,
             FieldReference.Kind.rhythm,
             FieldReference.Kind.oursItem:
            // Known trigger kinds that this context does not yet carry.
            //
            // They resolve to nothing today, and that is a real gap rather
            // than a safe silence: the journey's originating subject is
            // absent from its own provenance. It is not a threshold problem —
            // accumulated evidence and Life items supply the count — so it is
            // recorded here rather than hidden behind the same `nil` that
            // means "private row".
            WELog.persistence.notice(
                "journey subject kind not carried by the shared context"
            )
            return nil
        default:
            // A kind this build has never heard of — a row from a newer build,
            // or a vocabulary drift like the one that made `field_question`
            // unresolvable for the whole life of this feature. Dropping it is
            // still the only safe reading, because guessing would put
            // something on a shared screen this version does not understand.
            //
            // But it is dropped *loudly*. A silent drop here is
            // indistinguishable from the deliberate silence that protects a
            // private row, and that is exactly how the earlier mismatch
            // survived. In debug this trips; in release it is collectable.
            assertionFailure("unknown journey subject kind")
            WELog.persistence.error("unknown journey subject kind")
            return nil
        }
    }

    // MARK: Eligibility

    /// Every capability this journey has earned, in a fixed order.
    ///
    /// `allCases` order rather than anything derived, so the room does not
    /// reshuffle itself between two reads of the same state.
    static func eligible(
        for journey: SharedJourney,
        context: FieldSharedPresenceContext
    ) -> [JourneyCapabilityBinding] {
        let resolved = subjects(for: journey, context: context)
        return JourneyCapability.allCases.compactMap { capability in
            binding(capability, journey: journey, subjects: resolved, context: context)
        }
    }

    /// Keys whose threshold is met but which have never been marked earned.
    ///
    /// The caller records these so hysteresis has a memory that both people
    /// share; see `field_adaptations`. Separated from `eligible` so that
    /// deriving what to show stays a pure read.
    static func newlyEarned(
        for journey: SharedJourney,
        context: FieldSharedPresenceContext
    ) -> [String] {
        let resolved = subjects(for: journey, context: context)
        return JourneyCapability.allCases.compactMap { capability in
            let key = key(capability, journey: journey)
            guard !context.hasEarned(key),
                  meetsThreshold(
                      capability,
                      subjects: resolved,
                      hasEarned: false
                  )
            else { return nil }
            return key
        }
    }

    /// Capabilities this couple set down that would otherwise be showing.
    ///
    /// `eligible` cannot answer this: set-down wins there, so a put-away
    /// surface is indistinguishable from one that never qualified. Taking
    /// something back up needs to know the difference, so the threshold is
    /// re-read here with the set-down check deliberately skipped.
    ///
    /// Only surfaces that would return if taken up are listed. Offering to
    /// restore something that would immediately vanish again would make the
    /// gesture read as broken.
    static func setDown(
        for journey: SharedJourney,
        context: FieldSharedPresenceContext
    ) -> [JourneyCapability] {
        let resolved = subjects(for: journey, context: context)
        return JourneyCapability.allCases.filter { capability in
            let key = key(capability, journey: journey)
            guard context.hasSetDown(key) else { return false }
            return meetsThreshold(
                capability,
                subjects: resolved,
                hasEarned: context.hasEarned(key)
            )
        }
    }

    static func key(
        _ capability: JourneyCapability,
        journey: SharedJourney
    ) -> String {
        FieldAdaptationKey.capability(capability.rawValue, journeyID: journey.id)
    }

    private static func binding(
        _ capability: JourneyCapability,
        journey: SharedJourney,
        subjects: [JourneySubject],
        context: FieldSharedPresenceContext
    ) -> JourneyCapabilityBinding? {
        let key = key(capability, journey: journey)
        // Set down wins over everything. A couple who put a surface away are
        // not asked again by the material continuing to qualify.
        guard !context.hasSetDown(key) else { return nil }
        guard meetsThreshold(
            capability,
            subjects: subjects,
            hasEarned: context.hasEarned(key)
        ) else { return nil }

        return JourneyCapabilityBinding(
            capability: capability,
            provenance: FieldProvenance(
                reason: reason(capability),
                sources: subjects.map(\.reference)
            )
        )
    }

    /// The one place a capability's own rule lives.
    ///
    /// Exhaustive with no `default:`, so a new case cannot be added without
    /// deciding what earns it. The four that return `false` are declared and
    /// not yet built; saying so here is cheaper than pretending they do not
    /// exist and rediscovering the question later.
    private static func meetsThreshold(
        _ capability: JourneyCapability,
        subjects: [JourneySubject],
        hasEarned: Bool
    ) -> Bool {
        switch capability {
        case .criteria:
            return criteriaThreshold.isMet(
                count: subjects.count, hasEarned: hasEarned
            )
        case .comparison, .schedule, .budgetBand, .checklist:
            return false
        }
    }

    /// What to call a capability when naming it rather than rendering it.
    ///
    /// Only the put-away list needs this today: a surface that is not on
    /// screen still has to be nameable, or taking it back up is a guess.
    /// Exhaustive for the same reason `meetsThreshold` is — a new capability
    /// cannot be added without deciding what it is called.
    static func word(_ capability: JourneyCapability) -> String {
        switch capability {
        case .criteria: "What you keep pointing at"
        case .comparison: "Side by side"
        case .schedule: "When this happens"
        case .budgetBand: "What this costs"
        case .checklist: "What is left"
        }
    }

    private static func reason(_ capability: JourneyCapability) -> String {
        switch capability {
        case .criteria:
            "This grew from things you already share."
        case .comparison, .schedule, .budgetBand, .checklist:
            ""
        }
    }
}
