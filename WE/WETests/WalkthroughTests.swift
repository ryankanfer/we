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
                .today,
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
                .life,
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
            .life,
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
                .us,
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

    /// Us shows the real question with its two answers side by side. A third
    /// would overflow the compact orientation screen.
    @Test
    func theUsQuestionOffersTwoAnswers() {
        guard case .memory(let proposal)? = WalkthroughOutcome.resolve(
            .us,
            now: FieldSampleData.today
        ) else {
            Issue.record("no Us question")
            return
        }

        #expect(proposal.question.choices.count == 2)
    }
}

// MARK: - The orientation's order and labels

struct WalkthroughJourneyOrderTests {
    /// The walkthrough begins at the app's home, gives every space exactly one
    /// screen, and finishes by opening the product.
    @Test
    func theJourneysChainAndThenStop() {
        let ordered = WalkthroughJourney.ordered

        #expect(ordered == [.today, .life, .us])
        #expect(ordered.map(\.progressIndex) == [0, 1, 2])
        #expect(WalkthroughJourney.today.next == .life)
        #expect(WalkthroughJourney.life.next == .us)
        #expect(WalkthroughJourney.us.next == nil)
        #expect(WalkthroughJourney.today.headerLabel == "TODAY · HOME")
        #expect(WalkthroughJourney.life.headerLabel == "LIFE")
        #expect(WalkthroughJourney.us.headerLabel == "US")
        #expect(WalkthroughJourney.today.nextTitle == "Next: Life")
        #expect(WalkthroughJourney.life.nextTitle == "Next: Us")
        #expect(WalkthroughJourney.us.nextTitle == "Open WE")
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
