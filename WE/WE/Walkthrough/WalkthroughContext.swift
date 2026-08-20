//
//  WalkthroughContext.swift
//  WE
//
//  Screen 2 — Life. The details both people have mentioned.
//
//  This is the journey that has to earn the most trust, because the rule it
//  shows is the one with the most to lose. `FieldOccasion`'s own header says
//  it plainly: "a wrong guess here is worse than silence — it files somebody's
//  private thought under somebody else's visit." So the journey shows the
//  narrowness as the feature. Two beats are about what the app did; the third
//  is about what it will not do, and what "no" costs.
//
//  The question drawn here is `proposal.question` — the real one, with the
//  real reasoning line naming the real person. Nothing about it is written in
//  this file, which is why the sentence "WE notices what belongs together" can
//  be checked rather than merely asserted.
//

import SwiftUI

struct WalkthroughContext: View {
    let proposal: FieldOccasion.Proposal
    let journey: WalkthroughJourney
    let onNextJourney: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    var body: some View {
        WalkthroughScaffold(
            journey: journey,
            onNext: next,
            onClose: onClose
        ) {
            stage
        } caption: {
            caption
        }
    }

    // MARK: The stage

    private var stage: some View {
        apart
    }

    /// The two rows as Life actually holds them before anything is asked:
    /// separate, in different categories, filed by different people.
    private var apart: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
            WalkthroughFiled(
                title: proposal.occasionTitle,
                category: .care,
                dueOn: proposal.anchorDate,
                owner: .a
            )

            WalkthroughFiled(
                title: proposal.itemTitle,
                category: .buys,
                owner: .b
            )
        }
    }

    // MARK: The caption

    private var caption: some View {
        WalkthroughBeat(
            label: "Life keeps the details",
            line: "Life holds what you both mention, organized by what it is and when it matters."
        )
    }

    // MARK: Moving on

    private var next: (() -> Void)? {
        guard let following = journey.next else { return nil }
        return { onNextJourney(following) }
    }
}

#Preview("Context") {
    WalkthroughJourneyView(
        journey: .life,
        now: Date(),
        onNextJourney: { _ in },
        onClose: {}
    )
}
