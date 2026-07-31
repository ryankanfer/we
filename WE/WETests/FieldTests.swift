//
//  FieldTests.swift
//  WETests
//
//  The handoff calls itself high-fidelity: "Every hex value, font size,
//  weight, letter-spacing, and string in this document is the intended value."
//
//  These tests assert the parts of that which are not a matter of taste — the
//  hard product constraints, the contrast floor, the routing rules, and the
//  three ranking inputs Today is specified to weigh. A design review catches a
//  wrong margin; only a test catches the day someone adds a streak.
//

import Foundation
import SwiftUI
import Testing
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

@testable import WE

// MARK: - Palette

struct FieldPaletteTests {
    /// WCAG 2.1 relative luminance.
    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0)
            + 0.7152 * channel(c.1)
            + 0.0722 * channel(c.2)
    }

    private static func contrast(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Composites ink at `alpha` over the canvas, which is what the eye
    /// actually sees — the ramp is opacity, not distinct colours.
    private static func inkOver(
        _ alpha: Double,
        background: (Double, Double, Double) = (
            0x16 / 255, 0x21 / 255, 0x1D / 255
        )
    ) -> (Double, Double, Double) {
        let ink = (232.0 / 255, 228.0 / 255, 217.0 / 255)
        return (
            ink.0 * alpha + background.0 * (1 - alpha),
            ink.1 * alpha + background.1 * (1 - alpha),
            ink.2 * alpha + background.2 * (1 - alpha)
        )
    }

    @Test
    func primaryInkClearsAAOnTheCanvas() {
        let ratio = Self.contrast(
            Self.inkOver(1.0),
            (0x16 / 255, 0x21 / 255, 0x1D / 255)
        )
        #expect(ratio >= 7, "headline ink should clear AAA, got \(ratio)")
    }

    /// The ramp's body-copy steps have to clear 4.5:1. The steps below
    /// `.sectionSubtitle` are used for labels at 9–10pt tracked wide, or for
    /// deliberately recessive metadata, and are exempt.
    @Test
    func bodyStepsClearAA() {
        let bodySteps: [FieldInk] = [
            .headline, .secondaryHeading, .quietListItem, .legend,
            .cardProse, .reasoning, .sectionSubtitle,
        ]

        for step in bodySteps {
            let ratio = Self.contrast(
                Self.inkOver(step.rawValue),
                (0x16 / 255, 0x21 / 255, 0x1D / 255)
            )
            #expect(
                ratio >= 4.5,
                "\(step) scored \(ratio), below the 4.5:1 body floor"
            )
        }
    }

    /// The ramp must stay monotonic. A step that is out of order means a
    /// screen has silently promoted something.
    @Test
    func rampIsMonotonic() {
        let values = FieldInk.allCases.map(\.rawValue)
        #expect(values == values.sorted(by: >))
    }

    @Test
    func personColoursMatchTheHandoff() {
        #expect(FieldSwatch.clay.color.fieldHex == 0xD98E5A)
        #expect(FieldSwatch.slate.color.fieldHex == 0x79A6B8)
        #expect(FieldPalette.bg.fieldHex == 0x16211D)
        #expect(FieldPalette.bgElevated.fieldHex == 0x1B2723)
        #expect(FieldPalette.bgDeep.fieldHex == 0x101A17)
        #expect(FieldPalette.ink.fieldHex == 0xE8E4D9)
    }

    /// The Reminders takeover sits *below* the page in perceived depth, so it
    /// must be darker than the canvas — and sheets, which sit above it,
    /// lighter. Getting this backwards is the single easiest mistake here.
    @Test
    func depthOrderingHolds() {
        let canvas = Self.luminance((0x16 / 255, 0x21 / 255, 0x1D / 255))
        let elevated = Self.luminance((0x1B / 255, 0x27 / 255, 0x23 / 255))
        let deep = Self.luminance((0x10 / 255, 0x1A / 255, 0x17 / 255))

        #expect(deep < canvas)
        #expect(elevated > canvas)
    }

    @Test
    func eachPaletteOffersFourSwatchesAndDefaultsToTheFirst() {
        #expect(FieldPersonPalette.warm.swatches.count == 4)
        #expect(FieldPersonPalette.cool.swatches.count == 4)
        #expect(FieldPersonPalette.warm.defaultSwatch == .clay)
        #expect(FieldPersonPalette.cool.defaultSwatch == .slate)
    }
}

// MARK: - Hard product constraints
//
// "Do not violate these."

@MainActor
struct FieldConstraintTests {
    @Test
    func weIsIndexOneAndIsTheHome() {
        #expect(FieldZone.we.rawValue == 1)
        #expect(FieldStore().activeZone == .we)
    }

    @Test
    func zoneOrderIsFixed() {
        #expect(FieldZone.allCases == [.life, .we, .us])
    }

    /// The domain has no place to put a score, and that is deliberate. If a
    /// property named like one appears, this test is the tripwire.
    @Test
    func noScorekeepingSurfaceExists() {
        let mirror = Mirror(reflecting: FieldState.seed)
        let forbidden = ["streak", "score", "points", "percent", "rank", "balance"]

        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            for word in forbidden {
                #expect(
                    !label.contains(word),
                    "FieldState.\(label) reintroduces scorekeeping"
                )
            }
        }
    }

    /// Rhythm health is a two-case signal, never a count of consecutive weeks.
    /// The day someone adds `.onFire` this fails.
    @Test
    func rhythmHealthIsNotAStreak() {
        #expect(RhythmHealth.allCases.count == 2)
        #expect(Set(RhythmHealth.allCases) == [.running, .slipping])
    }

    @Test
    func questionsOfferExactlyTwoChoices() {
        for horizon in FieldSampleData.horizons {
            guard let question = horizon.openQuestion else { continue }
            #expect(
                question.choices.count == 2,
                "\(horizon.id) offers \(question.choices.count) choices"
            )
        }
    }

    /// Exactly one horizon leads Us.
    @Test
    func exactlyOneHorizonIsPrimary() {
        #expect(FieldSampleData.horizons.filter(\.isPrimary).count == 1)
    }

    /// Every request the app makes offers a way to decline it.
    @Test
    func everyMomentOffersAnEscape() {
        guard case .needsYou(let moment) = FieldTodaySelector.select(
            contextWithSomethingPressing()
        ) else {
            Issue.record("expected a pressing item in the seed data")
            return
        }
        #expect(moment.actions.contains { $0.weight == .quiet })
    }

    private func contextWithSomethingPressing() -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: FieldSampleData.today,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: FieldSampleData.lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: FieldSampleData.horizons,
            heldTopics: [],
            standingRules: []
        )
    }
}

// MARK: - Today

@MainActor
struct FieldTodayTests {
    private func context(
        now: Date = FieldSampleData.today,
        lifeItems: [LifeItem] = FieldSampleData.lifeItems,
        horizons: [FieldHorizon] = FieldSampleData.horizons,
        heldTopics: [FieldHeldTopic] = [],
        standingRules: [FieldStandingRule] = [],
        partners: [FieldPartner] = FieldSampleData.partners
    ) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: partners,
            lifeItems: lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: horizons,
            heldTopics: heldTopics,
            standingRules: standingRules
        )
    }

    /// Horizons with the open question answered — the state Us is in once the
    /// couple has picked a season.
    private var settledHorizons: [FieldHorizon] {
        FieldSampleData.horizons.map { horizon in
            var copy = horizon
            copy.openQuestion = nil
            return copy
        }
    }

    /// The item whose window closes tonight outranks everything else — the
    /// birthday four days out, the two-month-overdue air filter, and the Japan
    /// question included.
    @Test
    func aSameDayCutOffOutranksEverything() {
        guard case .needsYou(let moment) = FieldTodaySelector.select(context())
        else {
            Issue.record("expected something to need them")
            return
        }
        #expect(moment.id == "groceries")
    }

    /// Overdue with no cut-off decays rather than escalating. Two months of
    /// nothing breaking is evidence it is upkeep, and an assistant that
    /// escalates it starts nagging.
    @Test
    func anOverdueErrandDoesNotOutrankATonightDeadline() {
        let ranked = FieldTodaySelector.rank(context())
        let filter = ranked.first { candidate in
            if case .life(let item) = candidate.origin {
                return item.id == "filter"
            }
            return false
        }
        let groceries = ranked.first { candidate in
            if case .life(let item) = candidate.origin {
                return item.id == "groceries"
            }
            return false
        }

        guard let filter, let groceries else {
            Issue.record("expected both items to be ranked")
            return
        }
        #expect(groceries.priority > filter.priority)
    }

    /// Nothing needs you is a real state, not a fallback — with nothing open,
    /// the app says so rather than manufacturing a reason to speak.
    @Test
    func resolvedStateAppearsWhenNothingIsOpen() {
        let settled = FieldSampleData.lifeItems.map { item -> LifeItem in
            var copy = item
            copy.isDone = true
            return copy
        }
        let result = FieldTodaySelector.select(
            context(
                lifeItems: settled,
                horizons: settledHorizons,
                heldTopics: FieldSampleData.heldTopics
            )
        )

        guard case .resolved(let headline, _, _) = result else {
            Issue.record("expected the resolved state")
            return
        }
        #expect(headline == "Nothing needs you here.")
    }

    /// Deferral outranks urgency. A held topic is not a candidate, which is
    /// the whole point of 6d.
    @Test
    func heldTopicsAreNotSurfaced() {
        let held = [
            FieldHeldTopic(
                id: "hold-groceries",
                title: "grocery",
                timing: "TONIGHT",
                reason: "Not while your dad's here.",
                surfaceOn: FieldSampleData.date(2025, 9, 1),
                wasOverridden: false,
                wasDismissed: false
            )
        ]
        let ranked = FieldTodaySelector.rank(context(heldTopics: held))
        #expect(!ranked.contains { candidate in
            if case .life(let item) = candidate.origin {
                return item.id == "groceries"
            }
            return false
        })
    }

    /// A standing rule is obeyed before anything is optimised.
    @Test
    func standingRulesSuppressCandidates() {
        let morning = FieldSampleData.date(2025, 8, 13, hour: 8)
        let ranked = FieldTodaySelector.rank(
            context(
                now: morning,
                standingRules: FieldSampleData.standingRules
            )
        )
        #expect(!ranked.contains { candidate in
            if case .life(let item) = candidate.origin {
                return item.category == .money
            }
            return false
        })
    }

    /// Reachability, not availability. A shared item drops when either partner
    /// is away; a solo item only cares about its own owner.
    @Test
    func reachabilityDropsForSharedItemsWhenOneIsAway() {
        let away = FieldSampleData.date(2025, 8, 29)
        let sharedReach = FieldTodaySelector.reachability(
            for: .shared,
            context: context(now: away)
        )
        let dylanReach = FieldTodaySelector.reachability(
            for: .b,
            context: context(now: away)
        )

        #expect(sharedReach < 0.5)
        #expect(dylanReach == 1)
    }

    /// Every candidate the app surfaces carries a reason. A moment without one
    /// is a bug.
    @Test
    func everyMomentCarriesAReason() {
        guard case .needsYou(let moment) = FieldTodaySelector.select(context())
        else {
            Issue.record("expected something to need them")
            return
        }
        #expect(!moment.reasoning.isEmpty)
        #expect(!moment.source.isEmpty)
    }

    /// Today is derived. Reading it twice from an unchanged store gives the
    /// same answer; changing the store changes it, with nothing cached.
    @Test
    func todayIsDerivedNotStored() {
        let store = FieldStore()
        let first = store.todaySelection
        #expect(first == store.todaySelection)

        store.complete("groceries")
        #expect(store.todaySelection != first)
    }
}

// MARK: - The classifier
//
// The four canonical classifications are the handoff's few-shot set and the
// contract the model has to satisfy.

@MainActor
struct FieldClassifierTests {
    private var context: FieldClassifier.Context {
        FieldClassifier.Context(
            identity: FieldSampleData.identity,
            speaker: .a,
            now: FieldSampleData.today,
            oursItems: FieldSampleData.oursItems,
            horizons: FieldSampleData.horizons,
            rhythms: FieldSampleData.rhythms,
            corrections: [],
            partners: FieldSampleData.partners
        )
    }

    @Test
    func callMomSundayGoesToLifeCare() {
        let receipt = FieldClassifier.classify(
            "reminder to call mom sunday",
            context: context
        )
        #expect(receipt.destination.label == "LIFE · CARE")
    }

    @Test
    func steakGoesToOursEating() {
        let receipt = FieldClassifier.classify("steak", context: context)
        guard case .ours(let list) = receipt.destination else {
            Issue.record("steak should be an appetite, got \(receipt.destination)")
            return
        }
        #expect(list == .eating)
    }

    @Test
    func aFilmTitleGoesToTheWatchlist() {
        let receipt = FieldClassifier.classify(
            "fast and furious",
            context: context
        )
        guard case .ours(let list) = receipt.destination else {
            Issue.record("expected Ours, got \(receipt.destination)")
            return
        }
        #expect(list == .watchlist)
    }

    /// The app never invents a plan, and it never invents an occasion either.
    /// The watchlist sentence may only name a stretch it can source from a
    /// real away window.
    @Test
    func theStretchIsSourcedOrOmitted() {
        let sourced = FieldClassifier.classify(
            "fast and furious",
            context: context
        )
        #expect(sourced.reasoning.contains("Hamptons"))

        var noWindows = context
        noWindows.partners = context.partners.map { partner in
            var copy = partner
            copy.awayWindows = []
            return copy
        }
        let unsourced = FieldClassifier.classify(
            "fast and furious",
            context: noWindows
        )
        #expect(!unsourced.reasoning.contains("enough for"))
    }

    @Test
    func aLeaningGoesToTheHorizon() {
        let receipt = FieldClassifier.classify(
            "japan in the fall maybe",
            context: context
        )
        #expect(receipt.destination.label == "US · HORIZONS")
        // The reasoning has to name the horizon, not the category.
        #expect(receipt.reasoning.localizedCaseInsensitiveContains("japan"))
    }

    /// "The reasoning must reference this couple's actual state, not generic
    /// category logic. That specificity is the entire product."
    @Test
    func everyReceiptCarriesReasoning() {
        for input in FieldSampleData.canonicalInputs {
            let receipt = FieldClassifier.classify(input, context: context)
            #expect(!receipt.reasoning.isEmpty, "\(input) produced no reason")
            #expect(
                receipt.reasoning.count > 40,
                "\(input) produced a reason too thin to be specific"
            )
        }
    }

    /// Tell me once and it stops.
    @Test
    func aCorrectionChangesLaterRouting() {
        let receipt = FieldClassifier.classify("steak", context: context)
        let result = FieldClassifier.correct(
            receipt,
            to: .life(.food),
            context: context
        )

        var learned = context
        learned.corrections = [result.correction]

        let second = FieldClassifier.classify("steak", context: learned)
        #expect(second.destination.label == "LIFE · FOOD")
    }
}

// MARK: - One moment a day

@MainActor
struct FieldMomentSchedulerTests {
    private func decide(
        at now: Date,
        lastSentOn: Date? = nil
    ) -> FieldMomentScheduler.Decision {
        var moment = FieldSampleData.dailyMoment
        moment.lastSentOn = lastSentOn

        let context = FieldTodaySelector.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: FieldSampleData.lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: FieldSampleData.horizons,
            heldTopics: [],
            standingRules: []
        )

        return FieldMomentScheduler.decide(
            moment: moment,
            candidates: FieldTodaySelector.rank(context),
            selection: FieldTodaySelector.select(context),
            now: now
        )
    }

    @Test
    func nothingSendsBeforeTheLearnedHour() {
        let early = FieldSampleData.date(2025, 8, 13, hour: 7)
        #expect(decide(at: early).shouldSend == false)
    }

    @Test
    func oneSendsAfterTheLearnedHour() {
        let after = FieldSampleData.date(2025, 8, 13, hour: 9)
        #expect(decide(at: after).shouldSend)
    }

    /// No second attempt, ever.
    @Test
    func nothingSendsTwiceInADay() {
        let after = FieldSampleData.date(2025, 8, 13, hour: 9)
        let decision = decide(
            at: after,
            lastSentOn: FieldSampleData.date(2025, 8, 13, hour: 8, minute: 12)
        )
        #expect(decision.shouldSend == false)
    }

    /// The app stays quiet rather than sending a "you're all caught up" push.
    @Test
    func aResolvedDaySendsNothing() {
        let settled = FieldSampleData.lifeItems.map { item -> LifeItem in
            var copy = item
            copy.isDone = true
            return copy
        }
        let now = FieldSampleData.date(2025, 8, 13, hour: 9)
        let context = FieldTodaySelector.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: settled,
            clusters: FieldSampleData.clusters,
            horizons: [],
            heldTopics: [],
            standingRules: []
        )

        let decision = FieldMomentScheduler.decide(
            moment: FieldSampleData.dailyMoment,
            candidates: FieldTodaySelector.rank(context),
            selection: FieldTodaySelector.select(context),
            now: now
        )
        #expect(decision.shouldSend == false)
    }
}

// MARK: - Store behaviour

@MainActor
struct FieldStoreTests {
    /// The mark returns to Today from anywhere, and closes the takeover on the
    /// way. A hard requirement.
    @Test
    func theMarkAlwaysReturnsHome() {
        let store = FieldStore()
        store.go(to: .us)
        store.openReminders()

        store.returnHome()

        #expect(store.activeZone == .we)
        #expect(store.remindersOpen == false)
    }

    /// A capture is filed, not just receipted. Without this the receipt is
    /// theatre.
    @Test
    func captureMaterialisesIntoItsZone() {
        let store = FieldStore()
        let before = store.state.oursItems.count

        store.captureDraft = "past lives"
        store.submitCapture()

        #expect(store.state.oursItems.count == before + 1)
        #expect(store.lastReceipt != nil)
    }

    /// Correcting moves the object as well as the label, and logs the signal.
    @Test
    func correctionMovesTheObjectAndLogsTheSignal() {
        let store = FieldStore()
        store.captureDraft = "steak"
        store.submitCapture()

        guard let receipt = store.lastReceipt else {
            Issue.record("expected a receipt")
            return
        }
        let lifeBefore = store.state.lifeItems.count

        store.beginCorrection()
        store.correct(to: .life(.food))

        #expect(store.state.lifeItems.count == lifeBefore + 1)
        #expect(!store.state.oursItems.contains { $0.id == receipt.id })
        #expect(store.state.corrections.count == 1)
    }

    /// Onboarding's preview updates live because the identity is the source
    /// every person-coloured element reads.
    @Test
    func choosingASwatchRethemesEverything() {
        let store = FieldStore()
        store.choose(.amber, for: .a)

        #expect(store.identity.personA == .amber)
        #expect(store.identity.color(for: .a) == FieldSwatch.amber.color)
    }

    /// Clusters are ordered by urgency, not by insertion.
    @Test
    func clustersOrderByUrgency() {
        let store = FieldStore()
        #expect(store.orderedClusters.first?.id == "dad")
        #expect(store.orderedClusters.last?.id == "upkeep")
    }
}

// MARK: - Splash and launch (9b)

@Suite("The collapse")
struct WESplashTests {
    private let calendar = Calendar.gregorianUS
    private func at(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        FieldSampleData.date(y, m, d, hour: hour)
    }

    /// The arrival it was designed for.
    @Test
    func playsOnAFirstRun() {
        #expect(WESplashGate.shouldPlay(lastPlayed: nil, now: at(2026, 7, 31)))
    }

    /// Reopening an hour later is not an absence, and a ceremony that plays
    /// anyway is just time between someone and their partner's list.
    @Test
    func staysOutOfTheWayOnTheSameDay() {
        let now = at(2026, 7, 31, hour: 18)
        #expect(
            WESplashGate.shouldPlay(
                lastPlayed: at(2026, 7, 31, hour: 9),
                now: now,
                calendar: calendar
            ) == false
        )
    }

    /// A new day is the absence it is meant to mark.
    @Test
    func playsAgainAfterADayAway() {
        #expect(
            WESplashGate.shouldPlay(
                lastPlayed: at(2026, 7, 30, hour: 23),
                now: at(2026, 7, 31, hour: 7),
                calendar: calendar
            )
        )
    }

    /// A clock that has gone backwards is not evidence of having been away.
    @Test
    func aBackwardsClockIsNotAnAbsence() {
        #expect(
            WESplashGate.shouldPlay(
                lastPlayed: at(2026, 8, 2),
                now: at(2026, 7, 31),
                calendar: calendar
            ) == false
        )
    }

    /// The hold is allowed to be silent, but not endless — without a ceiling
    /// a stalled sync has no way out and the offline state is never reached.
    @Test
    func theHoldIsBounded() {
        #expect(WESplashGate.holdCeiling <= .seconds(6))
        #expect(WESplashGate.holdCeiling >= .seconds(2))
    }

    /// Every mark number derives from one width, at the source artwork's
    /// 0.66 scale — 200 viewBox units drawn at 132pt.
    @Test
    func lensGeometryMatchesTheSourceArtwork() {
        let offsets = WELens.centreOffsets(diameter: 132)
        #expect(abs(offsets.trailing - 17.16) < 0.01)
        #expect(abs(offsets.leading + 17.16) < 0.01)
        #expect(abs(WELens.circleRadius(diameter: 132) - 36.96) < 0.01)

        // And it holds at any size, which is the point of deriving it.
        #expect(abs(WELens.circleRadius(diameter: 264) - 73.92) < 0.01)
        #expect(abs(WELens.centreOffsets(diameter: 264).trailing - 34.32) < 0.01)
    }

    /// The launch asset and the collapse's first frame are the same image —
    /// the seam is prevented by construction, not by matching five stops.
    @Test
    func theLaunchGradientAssetExists() {
        #if canImport(UIKit)
        #expect(UIImage(named: "WELaunchGradient") != nil)
        #endif
    }
}

// MARK: - Category rooms
//
// The band split is the whole defence against a room becoming the wall Life
// was designed to avoid, so it is tested rather than eyeballed.

@MainActor
@Suite("Category rooms")
struct FieldCategoryDigestTests {
    private func context(
        now: Date = FieldSampleData.today,
        lifeItems: [LifeItem] = FieldSampleData.lifeItems
    ) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: FieldSampleData.horizons,
            heldTopics: [],
            standingRules: []
        )
    }

    /// However bad the week, the room opens to something readable in one
    /// breath.
    @Test
    func theExplainedBandIsCapped() {
        // Ten things, all closing tonight — the worst case the ranking can
        // produce.
        let crowded = (0..<10).map { index in
            LifeItem(
                id: "urgent-\(index)",
                title: "Thing \(index)",
                category: .care,
                owner: .a,
                dueOn: FieldSampleData.date(2025, 8, 13),
                closesAt: FieldSampleData.date(2025, 8, 13, hour: 21),
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: true,
                isDone: false
            )
        }

        let result = FieldCategoryDigest.digest(
            for: .care,
            context: context(lifeItems: crowded)
        )

        #expect(result.pressing.count == FieldCategoryDigest.pressingLimit)
        #expect(result.quiet.count == 7)
        #expect(result.total == 10)
    }

    /// A calm category renders calm — nothing is promoted just to fill the
    /// band.
    @Test
    func nothingPressingLeavesEveryItemQuiet() {
        let distant = (0..<4).map { index in
            LifeItem(
                id: "someday-\(index)",
                title: "Someday \(index)",
                category: .home,
                owner: .a,
                dueOn: nil,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            )
        }

        let result = FieldCategoryDigest.digest(
            for: .home,
            context: context(lifeItems: distant)
        )

        #expect(result.pressing.isEmpty)
        #expect(result.quiet.count == 4)
    }

    /// Completed things are not in a room at all.
    @Test
    func doneItemsDoNotAppear() {
        let settled = FieldSampleData.lifeItems.map { item -> LifeItem in
            var copy = item
            copy.isDone = true
            return copy
        }

        let result = FieldCategoryDigest.digest(
            for: .food,
            context: context(lifeItems: settled)
        )

        #expect(result.isEmpty)
    }

    /// Every explained row says something, and a cut-off says it first.
    @Test
    func aCutOffTonightIsWhatGetsSaid() {
        let result = FieldCategoryDigest.digest(
            for: .food,
            context: context()
        )

        guard let groceries = result.pressing.first(where: {
            $0.item.id == "groceries"
        }) else {
            Issue.record("the grocery window should have earned an explanation")
            return
        }
        #expect(groceries.reason == "Closes 9 PM.")
    }

    /// Overdue upkeep states the fact and does not nag about it.
    @Test
    func overdueUpkeepIsStatedFlatly() {
        let filter = FieldSampleData.lifeItems.first { $0.id == "filter" }
        guard let filter else {
            Issue.record("expected the air filter in the seed")
            return
        }

        let reason = FieldCategoryDigest.briefReason(
            for: filter,
            candidate: FieldTodaySelector.Candidate(
                origin: .life(filter),
                priority: 0.2,
                timePressure: 0.15,
                unblockingValue: 0.1,
                reachability: 1
            ),
            context: context()
        )

        #expect(reason == "Two months over.")
    }

    /// Only the item an occasion is actually waiting on says so. Two
    /// occasions may each have a lead — what must not happen is two items of
    /// the *same* occasion both claiming it, which is the same sentence twice
    /// explaining nothing about either.
    @Test
    func onlyOneItemPerClusterClaimsToBeTheBlocker() {
        for category in LifeCategory.allCases {
            let result = FieldCategoryDigest.digest(
                for: category,
                context: context()
            )

            let claimedClusters = result.pressing
                .filter { $0.reason?.contains("wait") == true }
                .compactMap { $0.item.clusterID }

            #expect(
                claimedClusters.count == Set(claimedClusters).count,
                "\(category.word) has two items claiming the same occasion"
            )
        }
    }

    /// The subtitle falls back to the derived summary until something is
    /// written, and never to nothing.
    @Test
    func subtitleFallsBackToTheDerivedSummary() {
        let store = FieldStore()
        #expect(store.writtenSubtitles[.food] == nil)
        #expect(store.subtitle(for: .food) == store.summary(for: .food))
        #expect(!store.subtitle(for: .food).isEmpty)
    }

    /// The fingerprint is what stops an unrelated change re-running five
    /// model calls, so it has to move for the right reasons and only those.
    @Test
    func theRefreshKeyTracksItemsNotRanking() {
        let store = FieldStore()
        let before = store.subtitleRefreshKey

        // Re-reading, and time passing, change the ranking but not the words.
        store.now = FieldSampleData.date(2025, 8, 13, hour: 20)
        #expect(store.subtitleRefreshKey == before)

        // Completing something changes what there is to say.
        store.complete("groceries")
        #expect(store.subtitleRefreshKey != before)
    }

    /// A model answer that came back as a list, or too long to fit one line,
    /// is refused rather than truncated.
    @Test
    func unusableGenerationsAreRefused() {
        #expect(FieldCategoryVoice.sanitized("") == nil)
        #expect(FieldCategoryVoice.sanitized("- one\n- two") == nil)
        #expect(
            FieldCategoryVoice.sanitized(
                String(repeating: "x", count: 200)
            ) == nil
        )
        #expect(
            FieldCategoryVoice.sanitized("\"Two things close today.\"")
                == "Two things close today."
        )
    }

    /// An item with nothing true to say about it says nothing.
    @Test
    func anUnremarkableItemGetsNoReason() {
        let quiet = LifeItem(
            id: "quiet",
            title: "Sometime",
            category: .home,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )

        let reason = FieldCategoryDigest.briefReason(
            for: quiet,
            candidate: FieldTodaySelector.Candidate(
                origin: .life(quiet),
                priority: 0.1,
                timePressure: 0.08,
                unblockingValue: 0.2,
                reachability: 1
            ),
            context: context(lifeItems: [quiet])
        )

        #expect(reason == nil)
    }
}

// MARK: - Delivering the moment (6c)
//
// `decide` answers "would I speak now"; these cover "when, and with what",
// which is the part the OS actually acts on.

@Suite("Moment delivery")
struct FieldMomentDeliveryTests {
    private let calendar = Calendar.gregorianUS

    private func moment(lastSentOn: Date? = nil) -> FieldDailyMoment {
        var moment = FieldSampleData.dailyMoment
        moment.lastSentOn = lastSentOn
        return moment
    }

    private func context(now: Date) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: FieldSampleData.lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: FieldSampleData.horizons,
            heldTopics: [],
            standingRules: []
        )
    }

    /// Before the learned hour, today's slot is still ahead.
    @Test
    func schedulesTodayWhenTheHourHasNotPassed() {
        let now = FieldSampleData.date(2025, 8, 13, hour: 7)
        let fire = FieldMomentDelivery.nextSend(
            after: now,
            moment: moment(),
            calendar: calendar
        )

        #expect(fire == FieldSampleData.date(2025, 8, 13, hour: 8, minute: 12))
    }

    /// After it, the next one is tomorrow — never "right now" to catch up.
    @Test
    func rollsToTomorrowOnceTheHourHasPassed() {
        let now = FieldSampleData.date(2025, 8, 13, hour: 9)
        let fire = FieldMomentDelivery.nextSend(
            after: now,
            moment: moment(),
            calendar: calendar
        )

        #expect(fire == FieldSampleData.date(2025, 8, 14, hour: 8, minute: 12))
    }

    /// "No second attempt" — a day already spoken on is skipped entirely,
    /// even when the hour is still ahead of `now`.
    @Test
    func skipsADayItHasAlreadySpokenOn() {
        let now = FieldSampleData.date(2025, 8, 13, hour: 7)
        let fire = FieldMomentDelivery.nextSend(
            after: now,
            moment: moment(
                lastSentOn: FieldSampleData.date(2025, 8, 13, hour: 6)
            ),
            calendar: calendar
        )

        #expect(fire == FieldSampleData.date(2025, 8, 14, hour: 8, minute: 12))
    }

    /// Nothing needing them is silence, not a "you're all caught up" push.
    @Test
    func plansNothingWhenNothingNeedsThem() {
        let now = FieldSampleData.date(2025, 8, 13, hour: 7)
        var state = FieldState.seed
        state.lifeItems = state.lifeItems.map { item in
            var copy = item
            copy.isDone = true
            return copy
        }
        state.horizons = state.horizons.map { horizon in
            var copy = horizon
            copy.openQuestion = nil
            return copy
        }
        state.heldTopics = FieldSampleData.heldTopics

        var resolvedContext = context(now: now)
        resolvedContext.lifeItems = state.lifeItems
        resolvedContext.horizons = state.horizons
        resolvedContext.heldTopics = state.heldTopics

        let plan = FieldMomentDelivery.plan(
            state: state,
            selection: FieldTodaySelector.select(resolvedContext),
            now: now,
            calendar: calendar
        )

        #expect(plan == nil)
    }

    /// Without permission the app schedules nothing and fails quietly.
    ///
    /// The test host is never authorised, so this is the real path here — and
    /// it is the one most likely to rot, because a missing authorisation
    /// check produces no error, just a silently dropped request.
    @Test
    func schedulesNothingWithoutAuthorisation() async {
        let center = UNUserNotificationCenter.current()
        await FieldMomentDelivery.refresh(
            state: FieldState.seed,
            selection: FieldTodaySelector.select(
                context(now: FieldSampleData.date(2025, 8, 13, hour: 7))
            ),
            now: FieldSampleData.date(2025, 8, 13, hour: 7),
            calendar: calendar,
            center: center
        )

        let pending = await center.pendingNotificationRequests()
        #expect(
            pending.contains { $0.identifier == FieldMomentDelivery.requestIdentifier }
                == false
        )
    }

    /// The notification carries the moment's own words — the app does not
    /// write a second, punchier version of itself for the lock screen.
    @Test
    func carriesTheMomentsOwnWords() {
        let now = FieldSampleData.date(2025, 8, 13, hour: 7)
        let selection = FieldTodaySelector.select(context(now: now))
        guard case .needsYou(let expected) = selection else {
            Issue.record("expected something to need them")
            return
        }

        let plan = FieldMomentDelivery.plan(
            state: FieldState.seed,
            selection: selection,
            now: now,
            calendar: calendar
        )

        #expect(plan?.statement == expected.headline)
        #expect(plan?.detail == expected.reasoning)
    }
}

// MARK: - Test helpers

extension Color {
    /// Round-trips a Color back to the hex the handoff quotes, so a token
    /// drifting by one channel fails loudly.
    var fieldHex: UInt32 {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(round(r * 255)) << 16
            | UInt32(round(g * 255)) << 8
            | UInt32(round(b * 255))
        #else
        return 0
        #endif
    }
}
