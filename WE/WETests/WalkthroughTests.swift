//
//  WalkthroughTests.swift
//  WETests
//
//  The walkthrough claims to show the real rule rather than a picture of one.
//  That claim is only worth something if it can fail.
//
//  So these tests are not about the surface. They are about the seeds: that
//  each journey's context actually makes its rule fire, that the rule fires on
//  the subject the journey says it is about, and that nothing else fires
//  alongside it. A seed that stops producing a proposal turns the walkthrough
//  into an empty frame, and a seed that produces the *wrong* proposal turns it
//  into a confident lie — which is worse, and which only a test catches.
//
//  Everything is checked across a year of start dates. The seeds derive their
//  dates from `now`, so a journey that only works on a Wednesday is a journey
//  that is broken six days a week, and a fixed test date would never say so.
//

import Foundation
import Testing

@testable import WE

// MARK: - Every journey has something to show

struct WalkthroughSeedTests {
    /// A year of Mondays-through-Sundays, so weekday-dependent phrasing and
    /// the three-week occasion window are both exercised properly.
    private static let starts: [Date] = (0..<365).compactMap { offset in
        Calendar.gregorianUS.date(
            byAdding: .day,
            value: offset,
            to: FieldSampleData.date(2026, 1, 1, hour: 9)
        )
    }

    /// The one that matters. `WalkthroughJourneyView` renders a "nothing to
    /// show" state when this fails, and it should be unreachable.
    @Test
    func everyJourneyResolvesOnEveryDayOfTheYear() {
        for start in Self.starts {
            for journey in WalkthroughJourney.allCases {
                #expect(
                    WalkthroughOutcome.resolve(journey, now: start) != nil,
                    "\(journey.rawValue) had nothing to show on \(start)"
                )
            }
        }
    }

    @Test
    func theGreekPlaceIsFiledUnderFood() {
        for start in Self.starts {
            guard case .movement(let receipt)? = WalkthroughOutcome.resolve(
                .movement,
                now: start
            ) else {
                Issue.record("no receipt on \(start)")
                continue
            }

            #expect(receipt.category == .food)
            // The journey's second beat quotes the input back verbatim, so a
            // classifier that started rewriting the input rather than the
            // title would make that beat say something untrue.
            #expect(receipt.input == WalkthroughSeed.capture)
        }
    }

    /// The occasion journey names Ryan's dad in its caption via
    /// `proposal.evidence`. If the reading ever changed to `.referred`, the
    /// caption would start explaining the pronoun rule over a sentence that
    /// contains no pronoun.
    @Test
    func theBottleIsReadAsNamingRyansDad() {
        for start in Self.starts {
            guard case .context(let proposal)? = WalkthroughOutcome.resolve(
                .context,
                now: start
            ) else {
                Issue.record("no occasion on \(start)")
                continue
            }

            #expect(proposal.itemTitle == "A bottle for Ryan's dad")
            #expect(proposal.occasionTitle == "Ryan's dad is in town")
            #expect(proposal.anchorDate != nil)

            if case .named = proposal.evidence {
                // As specified.
            } else {
                Issue.record("expected a named reading on \(start)")
            }
        }
    }

    /// The occasion seed has no cluster in it, so the journey's third stage is
    /// the app forming one. A seed that arrived with a cluster already made
    /// would make that beat a tautology.
    @Test
    func theOccasionDoesNotExistUntilItIsAgreedTo() {
        guard case .context(let proposal)? = WalkthroughOutcome.resolve(
            .context,
            now: FieldSampleData.today
        ) else {
            Issue.record("no occasion")
            return
        }

        #expect(proposal.clusterID == nil)
        #expect(proposal.anchorItemID == "wt.visit")
    }

    @Test
    func japanIsTheSubjectSaidTwice() {
        for start in Self.starts {
            guard case .memory(let proposal)? = WalkthroughOutcome.resolve(
                .memory,
                now: start
            ) else {
                Issue.record("no promotion on \(start)")
                continue
            }

            #expect(proposal.subject == "Japan")
            #expect(proposal.category == .trips)
            // Exactly the two mentions, and the journey draws a row per ID.
            #expect(proposal.itemIDs.count == FieldPromotion.minimumMentions)
        }
    }

    /// Both Japan rows are dateless, which is what makes them promotable at
    /// all — `FieldPromotion` only ever asks about something that is not
    /// already a plan.
    @Test
    func theJapanMentionsCarryNoDates() {
        let items = WalkthroughSeed.promotionItems(now: FieldSampleData.today)

        #expect(items.allSatisfy { $0.dueOn == nil })
        #expect(items.allSatisfy { !$0.category.carriesDates })
        // One each. The second beat says "two different people".
        #expect(Set(items.map(\.owner)) == [.a, .b])
    }

    /// Every question in the app offers exactly two choices, and the
    /// walkthrough draws whatever it is given. This is the same constraint
    /// `FieldConstraintTests` holds the product to, asserted here because the
    /// stage lays the two answers out side by side and a third would overflow.
    @Test
    func everyQuestionTheWalkthroughDrawsOffersTwoAnswers() {
        for journey in WalkthroughJourney.allCases {
            switch WalkthroughOutcome.resolve(
                journey,
                now: FieldSampleData.today
            ) {
            case .context(let proposal):
                #expect(proposal.question.choices.count == 2)
            case .memory(let proposal):
                #expect(proposal.question.choices.count == 2)
            case .movement, nil:
                // The classifier files rather than asks; no question to draw.
                break
            }
        }
    }
}

// MARK: - The chooser's ordering

struct WalkthroughJourneyOrderTests {
    /// Each journey offers the next by name, and the last offers none. The
    /// three views all read `journey.next` to decide whether their final
    /// button says "Next: …" or "Done".
    @Test
    func theJourneysChainAndThenStop() {
        let ordered = WalkthroughJourney.ordered

        #expect(ordered == [.movement, .context, .memory])
        #expect(ordered.first?.next == .context)
        #expect(WalkthroughJourney.context.next == .memory)
        #expect(WalkthroughJourney.memory.next == nil)
        #expect(WalkthroughEnding.nextTitle(after: .memory) == "Done")
        #expect(
            WalkthroughEnding.nextTitle(after: .movement)
                == "Next: Ryan's dad"
        )
    }
}

// MARK: - What the first screen shows

/// The chooser stopped describing the journeys and started showing them: each
/// door carries the couple's actual words and where they ended up. That only
/// holds if the preview really is drawn from the resolved outcome, which is
/// what these check.
struct WalkthroughPreviewTests {
    private func preview(
        _ journey: WalkthroughJourney
    ) -> WalkthroughOutcome.Preview? {
        WalkthroughOutcome
            .resolve(journey, now: FieldSampleData.today)?
            .preview
    }

    @Test
    func everyDoorQuotesSomethingTheCoupleActuallyWrote() {
        #expect(preview(.movement)?.said == [WalkthroughSeed.capture])
        #expect(preview(.context)?.said.count == 2)
        #expect(preview(.memory)?.said.count == 2)

        // Nothing empty, and nothing placeholder-shaped. A blank quotation
        // mark on the first screen is worse than no example at all.
        for journey in WalkthroughJourney.allCases {
            let said = preview(journey)?.said ?? []
            #expect(!said.isEmpty)
            #expect(said.allSatisfy { !$0.trimmingCharacters(
                in: .whitespaces
            ).isEmpty })
        }
    }

    /// The destination is the classifier's word, not one written here.
    @Test
    func theGreekDoorNamesTheCategoryItWasFiledTo() {
        #expect(preview(.movement)?.landed == "FOOD")
    }

    @Test
    func theJapanDoorQuotesBothMentions() {
        let said = preview(.memory)?.said ?? []
        #expect(said.contains("Japan in the spring"))
        #expect(said.contains("Japan rail pass — worth it?"))
    }
}

// MARK: - When it plays

struct WalkthroughGateTests {
    /// Signed out and only signed out — and never twice.
    @Test
    func itOpensOnceForSomeoneSignedOut() {
        #expect(
            WalkthroughGate.shouldPresent(
                hasSeen: false,
                isSignedOut: true,
                isSkipped: false
            )
        )
        #expect(
            !WalkthroughGate.shouldPresent(
                hasSeen: true,
                isSignedOut: true,
                isSkipped: false
            )
        )
        #expect(
            !WalkthroughGate.shouldPresent(
                hasSeen: false,
                isSignedOut: false,
                isSkipped: false
            )
        )
        #expect(
            !WalkthroughGate.shouldPresent(
                hasSeen: false,
                isSignedOut: true,
                isSkipped: true
            )
        )
    }

    /// A replay always plays, and `consider` must not close it or reopen it
    /// underneath the person reading it.
    @MainActor
    @Test
    func aReplayIsNotOverruledByTheAutomaticGate() {
        let defaults = UserDefaults(
            suiteName: "walkthrough.tests.\(UUID().uuidString)"
        )!
        let presenter = WalkthroughPresenter(defaults: defaults)

        presenter.consider(isSignedOut: true)
        #expect(presenter.isPresented)

        presenter.finish()
        #expect(!presenter.isPresented)

        // Seen, so the gate declines.
        presenter.consider(isSignedOut: true)
        #expect(!presenter.isPresented)

        // Asked for anyway.
        presenter.replay()
        #expect(presenter.isPresented)

        // A session republishing its state must not close it.
        presenter.consider(isSignedOut: true)
        #expect(presenter.isPresented)

        presenter.finish()
        #expect(!presenter.isPresented)
    }
}
