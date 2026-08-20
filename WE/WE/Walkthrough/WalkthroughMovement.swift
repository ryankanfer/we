//
//  WalkthroughMovement.swift
//  WE
//
//  Screen 1 — Today. Start where the app starts.
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

    @ViewBuilder
    private var stage: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
            WalkthroughSaid(text: receipt.input, owner: receipt.accent)

            WalkthroughFiled(
                title: receipt.title,
                category: receipt.category,
                dueOn: receipt.dueOn,
                reasoning: receipt.reasoning,
                owner: receipt.accent
            )
        }
    }

    // MARK: The caption

    private var caption: some View {
        WalkthroughBeat(
            label: "Start in Today",
            line: "Tell WE anything. It files it for you, and tells you why.",
            detail: "Swipe or tap LIFE and US. Tap WE to come home."
        )
    }

    // MARK: Moving on

    private var next: (() -> Void)? {
        guard let following = journey.next else { return nil }
        return { onNextJourney(following) }
    }
}

#Preview("Movement") {
    WalkthroughJourneyView(
        journey: .today,
        now: Date(),
        onNextJourney: { _ in },
        onClose: {}
    )
}
