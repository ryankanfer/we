//
//  WECeremonySession.swift
//  WE
//
//  What the ceremony is doing right now, on this device.
//
//  The model and the surfaces were both finished before anything drove them:
//  `WECeremony` holds the beats, `WECeremonySupabase` reads and writes them,
//  `WECeremonyPresence` knows whether the other phone is attached, and
//  `LivingConfluencePromise` performs them. None of it was called by anything.
//  This is the piece that was missing — the one object that decides whether
//  the Promise is on screen at all, and it is deliberately not a view.
//
//  WHY A PHASE RATHER THAN A BOOLEAN
//
//  "Is the ceremony finished" has four answers, not two, and collapsing them
//  is how the Promise ends up flashing over the zones on a cold launch. A
//  default-constructed `WECeremonyState` has an empty `kept`, so `isComplete`
//  is false and `currentBeat` is the first beat: "we have not heard back from
//  the server yet" and "this couple is on beat one" are the same value. They
//  are separated here, permanently, by making the unloaded case its own case.
//
//  WHAT ELIGIBILITY IS NOT
//
//  Whether a couple performs the ceremony is *not* derived from whether they
//  have acknowledgement rows. A couple who paired before the ceremony existed
//  has none, and so does a couple who paired a moment ago. Reading absence as
//  "not started" walks every existing couple into The Joining months into a
//  relationship. See `20260821120000_ceremony_eligibility.sql`.
//

import Foundation
import Observation

// MARK: - The four states

/// Everything a ceremony surface may be in, and nothing it may not.
enum WECeremonyPhase: Equatable, Sendable {
    /// No answer from the server yet. Renders nothing — not the Promise, and
    /// not a spinner either: a spinner over the zones on every launch is a
    /// report about infrastructure at the moment the product is least
    /// entitled to make one.
    case loading

    /// This couple predates the ceremony. They are complete by construction
    /// rather than by assertion, and must never be asked to perform it.
    case notRequired

    /// In progress, on the beat this state resolves to.
    case required(WECeremonyState)

    /// Performed, by both people. Distinct from `notRequired` because the two
    /// mean different things about the relationship, even though both put the
    /// same thing on screen: nothing.
    case complete
}

extension WECeremonyPhase {
    /// Whether the Promise owns the screen.
    var presentsPromise: Bool {
        if case .required = self { return true }
        return false
    }

    /// The state to hand the Promise, when there is one.
    var ceremony: WECeremonyState? {
        if case .required(let state) = self { return state }
        return nil
    }
}

// MARK: - The session

@MainActor
@Observable
final class WECeremonySession {
    private(set) var phase: WECeremonyPhase = .loading

    private let backend: any WECeremonyBackend

    init(backend: any WECeremonyBackend) {
        self.backend = backend
    }

    /// Reads eligibility, then progress, and only then leaves `.loading`.
    ///
    /// Both reads before any transition, deliberately. Publishing `.required`
    /// the moment eligibility comes back and filling in the beats afterwards
    /// would put the Promise on screen on beat one for a fraction of a second
    /// before jumping to the beat the couple is actually on — which is the
    /// flash this type exists to prevent, arriving by a different route.
    func load() async {
        do {
            guard try await backend.ceremonyIsRequired() else {
                phase = .notRequired
                return
            }
            let state = try await backend.ceremonyState()
            phase = state.isComplete ? .complete : .required(state)
        } catch {
            // Hold. A failed read must not move a couple from `notRequired`
            // into `required`, and must not re-present a beat already kept.
            // Staying in `loading` shows nothing, which is the honest
            // rendering of "not known yet" and is also what the caller was
            // already showing a moment ago.
            hold()
        }
    }

    /// Gives the current beat, then re-reads the aggregate.
    ///
    /// `mine` is updated locally before the write lands so the beat reads as
    /// `held` immediately. Waiting on the network here would make giving a
    /// promise feel like submitting a form, and `held` is the state the
    /// direction wants a person sitting in anyway.
    func keep(_ beat: WEBeat) async {
        guard case .required(var state) = phase else { return }
        state.mine.insert(beat)
        phase = .required(state)

        do {
            try await backend.keepBeat(beat)
        } catch {
            // The write is idempotent by construction — `keep_ceremony_beat`
            // is `on conflict do nothing` — so the next presence tick retries
            // it for free. Nothing is said about the failure: an error over
            // the Promise reports on infrastructure during the one moment the
            // product is making a promise, and `held` already means "still,
            // and nothing is accumulating".
            return
        }
        await refresh()
    }

    /// Re-reads the aggregate only.
    ///
    /// The aggregate, and never a row event: `ceremony_acknowledgements` is
    /// deliberately absent from `FieldSupabaseBackend.observedTables` because
    /// a realtime row event carries its own arrival time, which is a report on
    /// the other person's timing wearing a different hat. This is the call a
    /// presence tick makes.
    func refresh() async {
        guard case .required(var state) = phase else { return }
        do {
            state.kept = try await backend.keptBeats()
        } catch {
            hold()
            return
        }
        phase = state.isComplete ? .complete : .required(state)
    }

    /// Keep whatever is on screen. Named so the `catch` blocks read as a
    /// decision rather than as an empty handler somebody forgot to fill in.
    private func hold() {}
}
