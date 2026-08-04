//
//  WalkthroughContext.swift
//  WE
//
//  Journey 2 — Ryan's dad. Two things turn out to be one thing.
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
    @Binding var step: Int
    let journey: WalkthroughJourney
    let onNextJourney: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    private static let stepCount = 2

    var body: some View {
        WalkthroughScaffold(
            label: journey.subject,
            step: step,
            stepCount: Self.stepCount,
            onNext: next,
            nextTitle: nextTitle,
            onClose: onClose
        ) {
            stage
        } caption: {
            caption
        }
    }

    // MARK: The stage

    /// Beat one is the two rows apart; beat two is the question over them.
    ///
    /// The third beat used to be the formed occasion, and it went because it
    /// was the least interesting thing on screen — the surprise is the app
    /// asking at all, and once the question has been read, two rows becoming
    /// one card is a foregone conclusion drawn slowly.
    @ViewBuilder
    private var stage: some View {
        switch step {
        case 0:
            apart
        default:
            VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
                apart
                WalkthroughAsk(question: proposal.question)
            }
        }
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

    @ViewBuilder
    private var caption: some View {
        switch step {
        case 0:
            WalkthroughBeat(
                label: "Filed apart",
                line: "Different lists. Different people. Days apart."
            )
        default:
            WalkthroughBeat(label: "So WE asks", line: askLine)
        }
    }

    /// The day is read off `proposal.anchorDate`, never written here. It said
    /// "Saturday" while the seed dated the visit to a Friday — the caption
    /// contradicting the card directly above it, which is the precise failure
    /// this whole file is arranged to prevent.
    private var askLine: String {
        guard let day = proposal.anchorDate.map({
            DateFormatter.fieldWeekday.string(from: $0)
        }) else {
            return "It doesn't just file the bottle. It asks who it's for."
        }
        return "Is the bottle for \(day)?"
    }

    // MARK: Moving on

    private var isLastStep: Bool { step == Self.stepCount - 1 }

    private var nextTitle: String {
        isLastStep ? WalkthroughEnding.nextTitle(after: journey) : "Next"
    }

    private var next: (() -> Void)? {
        guard isLastStep else {
            return { step += 1 }
        }
        guard let following = journey.next else { return nil }
        return { onNextJourney(following) }
    }
}

#Preview("Context") {
    WalkthroughJourneyView(
        journey: .context,
        now: Date(),
        onNextJourney: { _ in },
        onClose: {}
    )
}
