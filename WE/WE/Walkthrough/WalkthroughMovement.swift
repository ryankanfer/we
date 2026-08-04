//
//  WalkthroughMovement.swift
//  WE
//
//  Journey 1 — Greek food. Something said goes somewhere.
//
//  The first rule, and the one everything else rests on: there is one place to
//  put a thought, and the app decides where it lands. Every list app in the
//  world asks which list first; this journey is about the fact that WE does
//  not, and that it tells you why afterward rather than asking you to trust it.
//
//  The receipt drawn here is not written down anywhere — it comes back from
//  `FieldClassifier.classify` at the moment this is read. The category, the
//  tidied title, the reasoning line: all three are the classifier's, so if
//  routing changes this screen changes with it.
//

import SwiftUI

struct WalkthroughMovement: View {
    let receipt: FieldReceipt
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

    @ViewBuilder
    private var stage: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
            WalkthroughSaid(text: receipt.input, owner: receipt.accent)

            // From step 1 the same sentence is also shown filed. Both stay on
            // screen: the whole point is the relationship between what was
            // typed and where it went, and replacing one with the other would
            // make it a transition rather than a consequence.
            if step >= 1 {
                WalkthroughFiled(
                    title: receipt.title,
                    category: receipt.category,
                    dueOn: receipt.dueOn,
                    reasoning: receipt.reasoning,
                    owner: receipt.accent
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: step)
    }

    // MARK: The caption

    /// One short line per beat. There were three beats here with a paragraph
    /// under each, and the third was purely an explanation of the correction
    /// rule with nothing on screen to look at — which is the shape of writing
    /// people skip, and skipping the last beat means skipping the point.
    @ViewBuilder
    private var caption: some View {
        switch step {
        case 0:
            WalkthroughBeat(
                label: "Ryan says it",
                line: "He doesn't pick a list."
            )
        default:
            WalkthroughBeat(label: "Filed", line: filedLine)
        }
    }

    /// Named from the receipt rather than written, so the sentence cannot
    /// claim a category the classifier did not choose.
    private var filedLine: String {
        "Straight to \(receipt.category.rawValue.capitalized) — with a reason."
    }

    // MARK: Moving on

    private var isLastStep: Bool { step == Self.stepCount - 1 }

    private var nextTitle: String {
        isLastStep ? WalkthroughEnding.nextTitle(after: journey) : "Next"
    }

    /// Nil closes the walkthrough, which the scaffold renders as "Done". Only
    /// reached on the last step of the last journey.
    private var next: (() -> Void)? {
        guard isLastStep else {
            return { step += 1 }
        }
        guard let following = journey.next else { return nil }
        return { onNextJourney(following) }
    }
}

#Preview("Movement") {
    WalkthroughJourneyView(
        journey: .movement,
        now: Date(),
        onNextJourney: { _ in },
        onClose: {}
    )
}
