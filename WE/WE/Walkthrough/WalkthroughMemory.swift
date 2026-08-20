//
//  WalkthroughMemory.swift
//  WE
//
//  Screen 3 — Us. The possibilities that keep returning.
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
//  That rule is the one shared journeys inherit: a journey room reads the
//  couple's records through references and never copies them, and the views it
//  grows recede without taking anything with them. The caption names the other
//  half — that nothing opens on one person's say-so — because the mutual gate
//  is the part a person has to trust before they will add anything at all.
//
//  The promotion proposal remains the live engine here, deliberately. It is
//  derived on device from two real Life rows, so this screen can run offline
//  and during onboarding. A shared-journey question cannot: it is created
//  server-side from evidence a new couple does not have yet, and a walkthrough
//  that mocked one would be the illustration this file exists to avoid.
//

import SwiftUI

struct WalkthroughMemory: View {
    let proposal: FieldPromotion.Proposal
    let now: Date
    let journey: WalkthroughJourney
    let onClose: () -> Void

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
            journey: journey,
            onClose: onClose
        ) {
            stage
        } caption: {
            caption
        }
    }

    // MARK: The stage

    private var stage: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.cardGap) {
            mentionRows(mentions)
            WalkthroughAsk(question: proposal.question)
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

    // MARK: The caption

    private var caption: some View {
        WalkthroughBeat(
            label: "Us notices what returns",
            line: "Us notices what you keep returning to. Nothing opens until you both choose it."
        )
    }
}

#Preview("Memory") {
    WalkthroughJourneyView(
        journey: .us,
        now: Date(),
        onNextJourney: { _ in },
        onClose: {}
    )
}
