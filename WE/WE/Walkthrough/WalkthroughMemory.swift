//
//  WalkthroughMemory.swift
//  WE
//
//  Journey 3 — Japan. Something said twice stops being a passing remark.
//
//  The last journey, and the one that explains Us. Us is the only zone with no
//  way in: there is no button that files to it and no branch of the classifier
//  that reaches it. A horizon exists exactly one way — the app notices a
//  subject twice, asks once, and somebody says yes.
//
//  The beat that matters most is the third. A horizon is *a reading of things
//  already written down*, not a copy of them somewhere else, and the linked
//  items stay in Life. If they moved, the list where you actually look for
//  them would quietly empty itself out — which is the failure mode this
//  journey exists to rule out in the reader's mind before they ever see Us.
//

import SwiftUI

struct WalkthroughMemory: View {
    let proposal: FieldPromotion.Proposal
    let now: Date
    @Binding var step: Int
    let journey: WalkthroughJourney
    let onNextJourney: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    private static let stepCount = 2

    /// The two Life rows the proposal came from, in the order they were said.
    ///
    /// Seeded from the same `now` the proposal was, not from `Date()`. Nothing
    /// about these two rows is dated, so it makes no visible difference today
    /// — it is here because "every journey agrees what day it is" is the rule,
    /// and a second clock in the file is how that stops being true later.
    private var mentions: [LifeItem] {
        let items = WalkthroughSeed.promotionItems(now: now)
        return proposal.itemIDs.compactMap { id in
            items.first { $0.id == id }
        }
    }

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

    /// Beat one asks; beat two is the horizon with both notes still under it.
    ///
    /// The beat that went was the one showing a single mention doing nothing.
    /// "Said once, nothing happens" is a real rule, but drawing a row that
    /// does nothing costs a whole screen to make a negative point — and the
    /// question in beat one already says "twice" in its own reasoning line.
    @ViewBuilder
    private var stage: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
                mentionRows(mentions)
                WalkthroughAsk(question: proposal.question)
            }
        default:
            VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
                horizon
                // Still there, still in Trips. Drawn *under* the horizon so
                // the relationship reads as "this is about those" rather than
                // "those became this".
                mentionRows(mentions)
            }
        }
    }

    private func mentionRows(_ items: [LifeItem]) -> some View {
        VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
            ForEach(items) { item in
                WalkthroughFiled(
                    title: item.title,
                    category: item.category,
                    owner: item.owner
                )
            }
        }
    }

    /// Us's own type: the largest in the app, with the countdown beside it.
    /// Built here rather than as a shared component because Us draws exactly
    /// one of these and no other journey has a horizon to show.
    private var horizon: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Now in Us")

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(proposal.subject)
                    .font(FieldType.horizon)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text("NO DATE")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.legend))
            }

            Rectangle()
                .fill(FieldRule.us)
                .frame(height: 1)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(proposal.subject), now in Us, no date")
    }

    // MARK: The caption

    @ViewBuilder
    private var caption: some View {
        switch step {
        case 0:
            WalkthroughBeat(
                label: "Said twice",
                line: "Once is a remark. Twice is worth asking about."
            )
        default:
            WalkthroughBeat(
                label: "Say yes",
                line: "It becomes a horizon. Both notes stay in Trips."
            )
        }
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

#Preview("Memory") {
    WalkthroughJourneyView(
        journey: .memory,
        now: Date(),
        onNextJourney: { _ in },
        onClose: {}
    )
}
