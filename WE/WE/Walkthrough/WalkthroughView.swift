//
//  WalkthroughView.swift
//  WE
//
//  "See how WE works" — a three-screen orientation to Today, Life, and Us.
//
//  The walkthrough starts where the app starts and gives each space one
//  screen. It teaches the navigation and the expectation of each space; the
//  deeper intelligence stays where it belongs, in the moment it is useful.
//
//  Nothing here is skippable-once. `WalkthroughPresenter.replay()` always
//  plays, and every screen carries Skip. See that file for when it opens by
//  itself, which is: signed out, first install, and not under test.
//

import SwiftUI

struct WalkthroughView: View {
    let onFinish: () -> Void

    /// Resolved once, at the moment the walkthrough opens, and passed down.
    /// Every journey has to agree about what day it is — a journey that read
    /// `Date()` per step could cross midnight mid-explanation and start
    /// describing a different week than the one it opened with.
    @State private var now = Date()
    @State private var journey: WalkthroughJourney = .today

    var body: some View {
        WalkthroughJourneyView(
            journey: journey,
            now: now,
            onNextJourney: { self.journey = $0 },
            onClose: onFinish
        )
        .id(journey.id)
        // No container identifier here. `.accessibilityIdentifier` on a view
        // wrapping this much hierarchy does not label the container — it
        // stamps itself onto descendants, and both of the scaffold's buttons
        // came back identified as "walkthrough" instead of as themselves. The
        // journeys were unreachable from a test and from Voice Control alike.
    }
}

// MARK: - Hosting one journey

/// Resolves the real example for one space and offers the next space.
///
/// The engine is asked once, in `init`, and the answer is held. Not a computed
/// property: `FieldClassifier.classify` and the two proposal functions are
/// pure but not free, and a computed one would re-derive the couple's whole
/// week on every step change merely to redraw a caption. `WalkthroughView`
/// gives this an `.id` per journey, so "once" means once per journey.
struct WalkthroughJourneyView: View {
    let journey: WalkthroughJourney
    let now: Date
    let onNextJourney: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    private let outcome: WalkthroughOutcome?

    init(
        journey: WalkthroughJourney,
        now: Date,
        onNextJourney: @escaping (WalkthroughJourney) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.journey = journey
        self.now = now
        self.onNextJourney = onNextJourney
        self.onClose = onClose
        self.outcome = WalkthroughOutcome.resolve(journey, now: now)
    }

    var body: some View {
        switch outcome {
        case .movement(let receipt):
            WalkthroughMovement(
                receipt: receipt,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case .context(let proposal):
            WalkthroughContext(
                proposal: proposal,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case .memory(let proposal):
            WalkthroughMemory(
                proposal: proposal,
                now: now,
                journey: journey,
                onClose: onClose
            )
        case nil:
            silence
        }
    }

    /// The rule declined to fire, so there is nothing true to show.
    ///
    /// This is not a designed state and should be unreachable —
    /// `WalkthroughTests` asserts every journey resolves. It exists because
    /// the alternative to handling `nil` is forcing it, and an explanation
    /// that crashes rather than admit it has nothing to say is the worst of
    /// the available behaviours.
    private var silence: some View {
        WalkthroughScaffold(
            journey: journey,
            onClose: onClose
        ) {
            EmptyView()
        } caption: {
            WalkthroughBeat(
                label: "Nothing to show",
                line: "WE would rather say nothing than invent an example."
            )
        }
    }
}

#Preview("Walkthrough") {
    WalkthroughView(onFinish: {})
}
