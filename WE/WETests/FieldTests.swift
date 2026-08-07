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

    /// The calendar takeover sits *below* the page in perceived depth, so it
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
        clusters: [FieldCluster] = FieldSampleData.clusters,
        heldTopics: [FieldHeldTopic] = [],
        standingRules: [FieldStandingRule] = [],
        partners: [FieldPartner] = FieldSampleData.partners
    ) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: partners,
            lifeItems: lifeItems,
            clusters: clusters,
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

    /// The resolved state is a real state, not a fallback — with nothing open,
    /// the app says so rather than manufacturing a reason to speak. It says it
    /// as a resolution, because that is what it is.
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

        guard case .resolved(let headline, let detail, _) = result else {
            Issue.record("expected the resolved state")
            return
        }
        #expect(headline == "Today is clear.")
        // The two halves are derived together and must agree: a clear day is
        // claimed only where there is something that actually cleared.
        #expect(settled.contains { detail.contains($0.title) })
    }

    /// An account with nothing in it is not a clear day — it is an unknown
    /// one, and claiming otherwise is the one reassurance the app has not
    /// earned. Done items still count as knowing something.
    @Test
    func anEmptyAccountSaysItIsStillLearning() {
        let result = FieldTodaySelector.select(
            context(lifeItems: [], horizons: [], clusters: [])
        )

        guard case .resolved(let headline, let detail, _) = result else {
            Issue.record("expected the resolved state")
            return
        }
        #expect(headline == "I'm still learning your week.")
        #expect(detail.contains("Say anything below"))
    }

    /// A couple who finished everything has a history. They get the clear day,
    /// not the beginner's line.
    @Test
    func aFinishedWeekIsClearRatherThanUnlearned() {
        let settled = FieldSampleData.lifeItems.map { item -> LifeItem in
            var copy = item
            copy.isDone = true
            return copy
        }
        let result = FieldTodaySelector.select(
            context(lifeItems: settled, horizons: [], clusters: [])
        )

        guard case .resolved(let headline, _, _) = result else {
            Issue.record("expected the resolved state")
            return
        }
        #expect(headline == "Today is clear.")
    }

    /// A question one of them asked leads the watch list. Three horizon
    /// questions must not push the thing somebody just raised off the end of
    /// a list that only holds three.
    @Test
    func anAskedQuestionLeadsWhatImWatching() {
        let asked = LifeItem(
            id: "asked",
            title: "Christmas at your parents",
            category: .talk,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
        let items = FieldTodaySelector.watching(
            context(
                lifeItems: [asked] + FieldSampleData.lifeItems,
                heldTopics: FieldSampleData.heldTopics
            )
        )

        #expect(items.count <= 3)
        #expect(items.first?.id == "asked")
        #expect(items.first?.text.contains("Christmas at your parents") == true)
        #expect(
            items.first?.text.contains(FieldSampleData.identity.nameA) == true
        )
        // The line is a reading of a real item, so it carries the way back to
        // it. Without this the row is a printout and the tap goes nowhere.
        #expect(items.first?.itemID == "asked")
    }

    /// A horizon question is not an item, so it says so rather than offering a
    /// tap that would open nothing.
    @Test
    func aHorizonQuestionCarriesNoItemToOpen() {
        let items = FieldTodaySelector.watching(
            context(
                lifeItems: FieldSampleData.lifeItems,
                heldTopics: FieldSampleData.heldTopics
            )
        )

        for item in items where item.itemID != nil {
            #expect(
                FieldSampleData.lifeItems.contains { $0.id == item.itemID }
            )
        }
    }

    /// A finished conversation stops being watched. Nothing here nags.
    @Test
    func anAnsweredQuestionLeavesWhatImWatching() {
        var asked = LifeItem(
            id: "asked",
            title: "Christmas at your parents",
            category: .talk,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
        asked.isDone = true

        let items = FieldTodaySelector.watching(context(lifeItems: [asked]))
        #expect(!items.contains { $0.id == "asked" })
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
            lifeItems: FieldSampleData.lifeItems + FieldSampleData.mentioned,
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
        #expect(receipt.category == .care)
    }

    /// A question is not an errand. Filing it as one is how "do we want to do
    /// Christmas at your parents?" ends up between the dry cleaning and the
    /// air filter.
    @Test
    func aQuestionGoesToTalkWithNoDate() {
        let receipt = FieldClassifier.classify(
            "do we want to do christmas at your parents?",
            context: context
        )
        #expect(receipt.category == .talk)
        #expect(receipt.dueOn == nil)
        #expect(receipt.category.carriesDates == false)
    }

    /// Most people do not type the mark on a phone.
    @Test
    func aQuestionWithoutTheMarkIsStillAQuestion() {
        let receipt = FieldClassifier.classify(
            "should we talk about the wedding budget",
            context: context
        )
        #expect(receipt.category == .talk)
    }

    /// A task phrased as a question is still a question — nobody has been
    /// assigned anything. The task shape does not outrank the asking.
    @Test
    func aTaskPhrasedAsAQuestionIsStillAsked() {
        let receipt = FieldClassifier.classify(
            "should we call the plumber?",
            context: context
        )
        #expect(receipt.category == .talk)
    }

    /// A day word disqualifies it. That belongs to the day, not to the pile of
    /// things to talk about.
    @Test
    func aQuestionWithADayIsNotJustTalk() {
        let receipt = FieldClassifier.classify(
            "can we call the plumber tomorrow?",
            context: context
        )
        #expect(receipt.category != .talk)
    }

    /// Trips still win. `FieldPromotion` owns whether a mentioned place
    /// becomes real, and asking about it does not change that.
    @Test
    func aTripAskedAboutIsStillATrip() {
        let receipt = FieldClassifier.classify(
            "should we do japan in the fall?",
            context: context
        )
        #expect(receipt.category == .trips)
    }

    @Test
    func steakIsAnUndatedFoodItem() {
        let receipt = FieldClassifier.classify("steak", context: context)
        #expect(receipt.category == .food)
        // An appetite is an item with no date. That is the whole of what the
        // Ours/Life distinction used to be.
        #expect(receipt.dueOn == nil)
    }

    @Test
    func aFilmTitleGoesToTheWatchlist() {
        let receipt = FieldClassifier.classify(
            "fast and furious",
            context: context
        )
        #expect(receipt.category == .watchlist)
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
    func aTripGoesToTripsAndNamesTheHorizon() {
        let receipt = FieldClassifier.classify(
            "japan in the fall maybe",
            context: context
        )
        #expect(receipt.category == .trips)
        // It does not become a horizon by being said — that only happens when
        // somebody answers the question. But the reasoning still has to name
        // this couple's actual state rather than talking about "a place".
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
            to: .buys,
            context: context
        )

        var learned = context
        learned.corrections = [result.correction]

        let second = FieldClassifier.classify("steak", context: learned)
        #expect(second.category == .buys)
    }

    /// Routing reads the sentence; filing reads the thought. Tidying must not
    /// be able to change where something goes — if it could, removing
    /// "reminder to" would silently reroute the thing it was trying to file.
    @Test
    func tidyingNeverChangesTheDestination() {
        let spoken = FieldClassifier.classify(
            "reminder to call mom sunday",
            context: context
        )
        let bare = FieldClassifier.classify("call mom sunday", context: context)
        #expect(spoken.category == bare.category)
        #expect(spoken.title == "Call mom")
    }

    /// The day named in the sentence becomes a date on the item. Without this
    /// the phrase is filed as decoration and nothing can rank it.
    @Test
    func aNamedDayBecomesADate() {
        let receipt = FieldClassifier.classify(
            "reminder to call mom sunday",
            context: context
        )
        // 13 August 2025 is a Wednesday; the coming Sunday is the 17th.
        let expected = FieldSampleData.date(2025, 8, 17)
        #expect(receipt.dueOn == expected)
    }

    /// An appetite has no due date, whatever day was said around it.
    @Test
    func appetitesNeverCarryADate() {
        let receipt = FieldClassifier.classify(
            "we should watch past lives maybe",
            context: context
        )
        #expect(receipt.dueOn == nil)
        #expect(receipt.title == "Watch past lives")
    }

    /// Nothing fits, so a category is grown rather than everything landing in
    /// Calendar by default.
    @Test
    func anUnfamiliarObligationGrowsACategory() {
        let receipt = FieldClassifier.classify(
            "book the dentist tomorrow",
            context: context
        )
        let category = receipt.category
        #expect(category == LifeCategory(named: "health"))
        #expect(!category.isBuiltIn)
        #expect(receipt.reasoning.contains("Health"))
    }

    /// And having grown one, it uses it again instead of growing a second
    /// name for the same thing.
    @Test
    func anExistingCategoryBeatsANewOne() {
        var grown = context
        grown.lifeCategories = LifeCategory.builtIn + [LifeCategory(rawValue: "pets")]

        let receipt = FieldClassifier.classify(
            "order more pets food",
            context: grown
        )
        #expect(receipt.category.rawValue == "pets")
        // An existing category is not news, so it is not announced as one.
        #expect(!receipt.reasoning.contains("I started"))
    }

    /// An obligation noun with no verb around it is still an obligation.
    /// "rent" used to read as a film title.
    @Test
    func anObligationNounWithNoVerbIsStillLife() {
        let receipt = FieldClassifier.classify("rent", context: context)
        #expect(receipt.category == .money)
    }

    /// A category is a heading. Anything that cannot be one is refused, and
    /// the caller falls back rather than filing under a fragment.
    @Test
    func aCategoryMustReadAsAHeading() {
        #expect(LifeCategory(named: "") == nil)
        #expect(LifeCategory(named: "a") == nil)
        #expect(LifeCategory(named: "the whole of everything else") == nil)
        #expect(LifeCategory(named: "  Pets ")?.rawValue == "pets")
        #expect(LifeCategory(named: "oil-change")?.rawValue == "oil change")
        #expect(LifeCategory(rawValue: "!!") == .notes)
    }

    /// Calendar is a surface, not a list. Taking it out of `builtIn` was not
    /// enough — categories are derived from the items carrying them, so one
    /// stray row saying `calendar` put the word straight back on Life. It has
    /// to be impossible, not merely absent.
    @Test
    func calendarCanNeverBecomeACategory() {
        #expect(LifeCategory(named: "calendar") == nil)
        #expect(LifeCategory(named: "  Calendar ") == nil)
        // Non-failable, because a decode must never lose an item: a legacy row
        // lands in Notes rather than vanishing or reviving the word.
        #expect(LifeCategory(rawValue: "calendar") == .notes)
        #expect(!LifeCategory.builtIn.contains { $0.rawValue == "calendar" })

        // And the classifier cannot route to it either. Asserted on the raw
        // value, not against `LifeCategory(rawValue: "calendar")` — that now
        // resolves to Notes itself, so comparing the two types says nothing.
        for input in ["put it in the calendar", "calendar thing friday"] {
            #expect(
                FieldClassifier.classify(input, context: context)
                    .category.rawValue != "calendar",
                "\(input) revived the word"
            )
        }
    }

    /// Labels are how a category round-trips through the database, and a
    /// correction log predates the collapse into one filing system. An old
    /// row still has to teach what it was recorded to teach.
    @Test
    func aLegacyLabelStillReadsAsACategory() {
        let pets = LifeCategory(rawValue: "pets")
        #expect(LifeCategory(legacyLabel: pets.label) == pets)
        #expect(LifeCategory(legacyLabel: "OURS · WATCHLIST") == .watchlist)
        #expect(LifeCategory(legacyLabel: "OURS · EATING") == .food)
        #expect(LifeCategory(legacyLabel: "OURS · PLACES") == .trips)
        #expect(LifeCategory(legacyLabel: "US · HORIZONS") == .trips)
        #expect(LifeCategory(legacyLabel: "") == nil)
    }

    /// Not everything needs a new category.
    ///
    /// "mark hotel event tomorrow" grew a list called Mark: the invention rule
    /// read the first long word it saw, and that word was a verb the app
    /// happens not to know. A thing happening once on a named day is an event
    /// — the date is what makes it findable, and a heading over one item is
    /// clutter the couple has to live in.
    @Test
    func aDatedThingWithNoKnownSubjectIsAnEventNotAList() {
        let receipt = FieldClassifier.classify(
            "mark event tomorrow",
            context: context
        )
        #expect(receipt.category == .notes)
        #expect(receipt.dueOn != nil, "it has to reach the calendar")
        #expect(receipt.reasoning.localizedCaseInsensitiveContains("calendar"))
    }

    /// The real sentence, which does have a subject the app knows.
    @Test
    func aKnownSubjectStillOutranksTheEventRule() {
        let receipt = FieldClassifier.classify(
            "mark hotel event tomorrow",
            context: context
        )
        #expect(receipt.category.rawValue == "travel")
        #expect(receipt.dueOn != nil)
        #expect(receipt.category.rawValue != "mark")
    }

    /// Scaffolding is never a heading. Every one of these describes the act of
    /// writing something down rather than the subject of it.
    @Test
    func schedulingWordsNeverBecomeCategories() {
        let banned = ["mark", "event", "meeting", "reminder", "schedule",
                      "note", "plan", "list", "task", "todo"]
        for word in banned {
            #expect(
                FieldClassifier.invented(from: "\(word) something") == nil,
                "\(word) became a category"
            )
        }
    }

    /// A dated capture still routes on its subject where there is one.
    @Test
    func theEventRuleDoesNotSwallowRealCategories() {
        let cases: [(String, LifeCategory)] = [
            ("pay rent tomorrow", .money),
            ("trash tonight", .home),
            ("book the vet friday", .care),
            ("order batteries tomorrow", .buys),
        ]
        for (input, expected) in cases {
            #expect(
                FieldClassifier.classify(input, context: context).category
                    == expected,
                "\(input) lost its category"
            )
        }
    }

    /// Us cannot be filed to. There is no branch of the classifier that
    /// reaches it, which is the whole point of the collapse — if one existed
    /// the two-destination confusion would come straight back.
    @Test
    func nothingCanBeFiledToUs() {
        let inputs = [
            "japan in the fall maybe", "buy a house someday",
            "we should go to italy next year", "eventually a bigger place",
            "reminder to call mom sunday", "steak", "fast and furious",
        ]
        for input in inputs {
            let receipt = FieldClassifier.classify(input, context: context)
            #expect(
                receipt.category.label.hasPrefix("LIFE · "),
                "\(input) escaped Life"
            )
        }
    }
}

// MARK: - Saying it once

@MainActor
struct FieldPhrasingTests {
    private let now = FieldSampleData.today

    @Test
    func openersAreDropped() {
        #expect(FieldPhrasing.tidy("remind me to pay rent", now: now).title
            == "Pay rent")
        #expect(FieldPhrasing.tidy("don't forget the trash", now: now).title
            == "The trash")
        #expect(FieldPhrasing.tidy("we should book the vet", now: now).title
            == "Book the vet")
    }

    @Test
    func hedgesGoFromTheEnds() {
        #expect(FieldPhrasing.tidy("japan in the fall maybe", now: now).title
            == "Japan in the fall")
    }

    /// Only the first letter. A name, a place, or an acronym is the person's
    /// own capitalisation and must survive intact.
    @Test
    func theirCapitalisationSurvives() {
        #expect(FieldPhrasing.tidy("call the DMV about Miso", now: now).title
            == "Call the DMV about Miso")
    }

    /// The preposition holding the day goes with the day.
    @Test
    func theDayLeavesCleanly() {
        let result = FieldPhrasing.tidy("pay the rent on friday", now: now)
        #expect(result.title == "Pay the rent")
        #expect(result.dueOn == FieldSampleData.date(2025, 8, 15))
    }

    /// Saying a weekday on that weekday means today, not a week away.
    @Test
    func theComingDayIncludesToday() {
        // 13 August 2025 is a Wednesday.
        let result = FieldPhrasing.tidy("laundry wednesday", now: now)
        #expect(result.dueOn == FieldSampleData.date(2025, 8, 13))
    }

    /// A capture that is nothing but scaffolding still files something. The
    /// input is all there is, so the input is what gets kept.
    @Test
    func aStrippedCaptureFallsBackToWhatWasSaid() {
        let result = FieldPhrasing.tidy("reminder for tomorrow", now: now)
        #expect(!result.title.isEmpty)
        #expect(result.dueOn == FieldSampleData.date(2025, 8, 14))
    }
}

// MARK: - What to suggest

@MainActor
struct FieldCaptureSuggestionTests {
    private var context: FieldCaptureSuggestions.Context {
        FieldCaptureSuggestions.Context(
            now: FieldSampleData.today,
            lifeItems: FieldSampleData.lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: FieldSampleData.horizons,
            rhythms: FieldSampleData.rhythms,
            partners: FieldSampleData.partners
        )
    }

    /// A couple with a week behind them gets suggestions about that week, not
    /// the four demo strings.
    @Test
    func suggestionsComeFromTheCouplesOwnState() {
        let suggestions = FieldCaptureSuggestions.suggest(context)
        #expect(!suggestions.isEmpty)
        #expect(suggestions != FieldSampleData.canonicalInputs)
        #expect(suggestions.count <= FieldCaptureSuggestions.limit)
    }

    /// And a couple on their first day gets nothing at all.
    ///
    /// This used to return `FieldSampleData.canonicalInputs` — the four demo
    /// phrases. A pill is not a picture of an input: tapping one sets the
    /// draft and submits it, so the fallback filed "steak" and "fast and
    /// furious" into a real couple's Life on the day they arrived. Saying
    /// nothing is the rule everywhere else in the app, and it applies here.
    @Test
    func anEmptyStateOffersNothingRatherThanTheDemoPhrases() {
        var empty = context
        empty.lifeItems = []
        empty.clusters = []
        empty.horizons = []
        empty.rhythms = []
        empty.partners = []
        empty.captures = []
        empty.corrections = []

        #expect(FieldCaptureSuggestions.suggest(empty).isEmpty)
    }

    /// The demo phrases must never reach a suggestion, by any route.
    ///
    /// A regression test with a name rather than a mechanism: whatever the
    /// rules do in future, none of them may answer with the fictional
    /// couple's life.
    @Test
    func noSuggestionIsEverADemoPhrase() {
        var empty = context
        empty.lifeItems = []
        empty.clusters = []
        empty.horizons = []
        empty.rhythms = []
        empty.partners = []
        empty.captures = []
        empty.corrections = []

        for suggestions in [
            FieldCaptureSuggestions.suggest(context),
            FieldCaptureSuggestions.suggest(empty),
        ] {
            for phrase in suggestions {
                #expect(
                    !FieldSampleData.canonicalInputs.contains(phrase),
                    "\(phrase) is a demo phrase offered as a suggestion"
                )
            }
        }
    }

    /// Every suggestion has to survive being tapped: it is submitted verbatim,
    /// so a phrase that classifies into nonsense is a bug with a button on it.
    @Test
    func everySuggestionClassifiesSomewhereSensible() {
        let classifier = FieldClassifier.Context(
            identity: FieldSampleData.identity,
            speaker: .a,
            now: FieldSampleData.today,
            lifeItems: FieldSampleData.lifeItems + FieldSampleData.mentioned,
            horizons: FieldSampleData.horizons,
            rhythms: FieldSampleData.rhythms,
            corrections: [],
            partners: FieldSampleData.partners
        )

        for phrase in FieldCaptureSuggestions.suggest(context) {
            let receipt = FieldClassifier.classify(phrase, context: classifier)
            #expect(!receipt.title.isEmpty, "\(phrase) tidied away to nothing")
            #expect(
                !receipt.reasoning.isEmpty,
                "\(phrase) produced no reason"
            )
        }
    }

    /// The pills are a live reading, not a remembered set. Once a suggested
    /// phrase is filed, the next read must make room for something else.
    @Test
    func suggestionsRefreshAfterTheUserFilesOne() throws {
        let store = FieldStore()
        let before = store.captureSuggestions
        let first = try #require(before.first)

        store.captureDraft = first
        store.submitCapture()
        store.send()

        #expect(store.captureSuggestions != before)
        #expect(!store.captureSuggestions.contains(first))
    }

    /// Refiling is the clearest category preference the couple can express.
    /// It may reorder two otherwise relevant ideas, but it never invents a
    /// suggestion: both phrases still have to be justified by current state.
    @Test
    func recentCorrectionsTuneTheOrderOfRelevantSuggestions() {
        let occasion = FieldCluster(
            id: "birthday",
            title: "Dylan's birthday",
            rationale: "",
            tint: .b,
            timeframe: "NEXT WEEK",
            anchorDate: FieldSampleData.date(2025, 8, 20)
        )
        let foodCorrections = (0..<3).map { index in
            FieldCorrection(
                id: "food-\(index)",
                input: "Dinner idea \(index)",
                original: .notes,
                corrected: .food,
                correctedAt: FieldSampleData.today
            )
        }
        var tuned = FieldCaptureSuggestions.Context(
            now: FieldSampleData.today,
            lifeItems: [],
            clusters: [occasion],
            horizons: [],
            rhythms: [],
            partners: []
        )
        tuned.corrections = foodCorrections

        let suggestions = FieldCaptureSuggestions.suggest(tuned)

        #expect(suggestions.contains("gift for dylan's birthday"))
        #expect(suggestions.contains("dinner friday"))
        #expect(suggestions.first == "dinner friday")
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

// MARK: - The day turning
//
// Today is derived and never stored, so there is nothing to clear at the end
// of a day: it turns because `now` turns. It never turned — `now` was read
// once at launch and believed for the rest of the process.

@MainActor
struct FieldClockTests {
    /// Every existing caller is a pinned clock, and pinned means pinned. The
    /// gallery, the previews and the screenshot contracts all depend on it.
    @Test
    func aStoreWithNoClockIsStillTheSampleCouplesDay() {
        let store = FieldStore()
        #expect(store.now == FieldSampleData.today)

        store.tick()
        #expect(store.now == FieldSampleData.today, "a pinned clock moved")
    }

    /// An explicit `now:` is a pinned clock too. Forty-odd tests say so.
    @Test
    func anExplicitInstantIsAPinnedClock() {
        let instant = FieldSampleData.today.addingTimeInterval(-86_400)
        let store = FieldStore(now: instant)

        store.tick()

        #expect(store.now == instant)
    }

    /// The whole point. A day passes with the app open, and Today is a
    /// different reading of the same state.
    @Test
    func aDayPassingMovesTheStoresInstant() {
        let clock = FieldSteppedClock(FieldSampleData.today)
        let store = FieldStore(clock: clock)

        clock.advance(days: 1)
        store.tick()

        #expect(
            Calendar.gregorianUS.isDate(
                store.now,
                inSameDayAs: FieldSampleData.today.addingTimeInterval(86_400)
            )
        )
    }

    /// Two minutes is not news. `now` is observable and writing it redraws all
    /// three zones, so the hour is the finest grain anything depends on.
    @Test
    func aFewMinutesChangesNothing() {
        let clock = FieldSteppedClock(FieldSampleData.today)
        let store = FieldStore(clock: clock)

        clock.advance(by: 120)
        store.tick()

        #expect(store.now == FieldSampleData.today)
    }

    /// A preview must not be moved off its date by a notification the
    /// simulator happens to post, so the observers are never installed at all.
    @Test
    func aPinnedClockNeverFollowsAnything() async {
        let store = FieldStore(now: FieldSampleData.today)
        // Returns rather than suspending forever, which is the assertion.
        await store.followTheClock()
        #expect(store.now == FieldSampleData.today)
    }
}

// MARK: - Yesterday, named once

@MainActor
struct FieldCarryForwardTests {
    private func item(dueOn: Date) -> LifeItem {
        LifeItem(
            id: "carried",
            title: "Call the vet",
            category: .care,
            // Shared, so with no partners in the context reachability is 1
            // and the ranking turns on the date alone — which is the thing
            // under test.
            owner: .shared,
            dueOn: dueOn,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
    }

    private func context(_ items: [LifeItem]) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: FieldSampleData.today,
            identity: FieldSampleData.identity,
            partners: [],
            lifeItems: items,
            clusters: [],
            horizons: [],
            heldTopics: [],
            standingRules: []
        )
    }

    private func day(_ offset: Int) -> Date {
        Calendar.gregorianUS.date(
            byAdding: .day,
            value: offset,
            to: FieldSampleData.today
        )!
    }

    /// Nothing is cleared and nothing sinks silently. It says so, once.
    @Test
    func yesterdaysUnfinishedThingSaysSo() {
        let selection = FieldTodaySelector.select(context([item(dueOn: day(-1))]))

        guard case .needsYou(let moment) = selection else {
            Issue.record("yesterday's item stopped surfacing")
            return
        }
        #expect(moment.reasoning.hasPrefix("This was yesterday's"))
    }

    /// It stops being news. A thing a fortnight late is upkeep, and describing
    /// it as yesterday's would be the app losing track of the week too.
    @Test
    func olderThanYesterdayIsNamedInThePast() {
        let selection = FieldTodaySelector.select(context([item(dueOn: day(-4))]))

        guard case .needsYou(let moment) = selection else {
            Issue.record("an overdue item stopped surfacing")
            return
        }
        #expect(moment.reasoning.contains("still open"))
        #expect(
            !moment.reasoning.contains("lands"),
            "a date that has gone by was described in the present tense"
        )
    }

    /// The cliff is deliberate: an item that slips loses pressure so a
    /// two-month-late air filter cannot outrank tonight's window. It is also
    /// exactly what makes the sentence above the *only* thing that had to
    /// change — so lock the numbers, because "fixing" the cliff would turn
    /// the app into a nag.
    @Test
    func slippingCostsPressureAndThatIsTheDesign() {
        let calendar = Calendar.gregorianUS
        let now = FieldSampleData.today

        #expect(item(dueOn: day(0)).pressure(now: now, calendar: calendar) == 0.8)

        let yesterday = item(dueOn: day(-1)).pressure(now: now, calendar: calendar)
        #expect(abs(yesterday - 0.5333) < 0.001)
        // And it still clears the bar on its own, which is why "carried
        // forward" is a sentence rather than a re-ranking.
        #expect(yesterday * 0.5 + 0.2 * 0.3 + 1 * 0.2 > FieldTodaySelector.surfacingThreshold)

        #expect(item(dueOn: day(-400)).pressure(now: now, calendar: calendar) == 0.15)
    }
}

// MARK: - The escapes
//
// "Ask me again tonight" was wired to nothing at all: the handler switched on
// a button's weight and only knew what to do with the filled one. And every
// hold was written with no date, which `shouldRaise` reads as "never". Both
// failures are quiet in the same way — the person taps, believes the app, and
// the thing comes back anyway.

@MainActor
struct FieldEscapeTests {
    private func deferralContext(_ now: Date) -> FieldDeferral.Context {
        FieldDeferral.Context(
            now: now,
            identity: FieldSampleData.identity,
            partners: [],
            standingRules: []
        )
    }

    /// Tonight means tonight, and it is a date rather than a nil.
    @Test
    func holdingUntilTonightComesBackTonight() {
        let morning = FieldSampleData.date(2025, 8, 13, hour: 9)
        let store = FieldStore(now: morning)

        store.hold(
            id: "groceries",
            subject: "Order the groceries",
            until: .thisEvening,
            reason: "You asked me to come back to it."
        )

        guard let topic = store.state.heldTopics.first(where: {
            $0.id == "groceries"
        }) else {
            Issue.record("nothing was held")
            return
        }
        #expect(topic.surfaceOn != nil, "held with no date is held forever")
        #expect(topic.timing == "TONIGHT")

        // Not before, and then yes.
        #expect(
            !FieldDeferral.shouldRaise(topic, context: deferralContext(morning))
        )
        #expect(
            FieldDeferral.shouldRaise(
                topic,
                context: deferralContext(
                    FieldSampleData.date(2025, 8, 13, hour: 21)
                )
            )
        )
    }

    /// Agreeing to come back at a time already behind you is the same broken
    /// promise as never coming back.
    @Test
    func aHoldMadeAfterSevenStillComesBack() {
        let night = FieldSampleData.date(2025, 8, 13, hour: 23)
        let surfaceOn = FieldDeferral.surfaceDate(
            .thisEvening,
            from: night,
            moment: FieldState.seed.dailyMoment
        )
        #expect(surfaceOn > night)
    }

    /// It has to leave the ranking while it is being held, or the escape is
    /// decorative.
    @Test
    func aHeldItemStopsBeingACandidate() {
        var state = FieldState.seed
        let store = FieldStore(state: state, now: FieldSampleData.today)

        guard case .needsYou(let moment) = store.todaySelection else {
            Issue.record("expected something to surface")
            return
        }

        store.hold(
            id: moment.id,
            subject: moment.headline,
            until: .thisEvening,
            reason: "You asked me to come back to it."
        )

        if case .needsYou(let next) = store.todaySelection {
            #expect(next.id != moment.id, "a held thing came straight back")
        }

        // And it is held by id, not by its words — a topic titled "Rent"
        // must not silently suppress everything with that word in it.
        state = store.state
        #expect(state.heldTopics.contains { $0.id == moment.id })
    }

    /// The reference backend accepted a new hold and dropped it, so nothing
    /// outside a unit test had ever seen one survive.
    @Test
    func aNewHoldSurvivesTheBackend() async throws {
        let backend = FieldMemoryBackend()
        try await backend.setHeld(
            FieldHeldTopic(
                id: "new",
                title: "Something",
                timing: "TONIGHT",
                reason: "You asked me to come back to it.",
                surfaceOn: FieldSampleData.today,
                wasOverridden: false,
                wasDismissed: false
            )
        )
        let loaded = try await backend.load()
        #expect(loaded.heldTopics.contains { $0.id == "new" })
    }

    /// The presence rule says its piece once. Overruling it is not an
    /// argument the app gets to keep having.
    @Test
    func askingAnywayStopsTheAppReAddressingIt() {
        // Inside Ryan's Hamptons window, which is the only time the presence
        // rule has anything to say.
        let away = FieldSampleData.date(2025, 8, 29, hour: 9)
        var state = FieldState.seed
        state.lifeItems = [
            LifeItem(
                id: "shared-thing",
                title: "Decide the Rhinebeck drive",
                category: .care,
                owner: .shared,
                dueOn: away,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            ),
        ]
        state.partners = FieldSampleData.partners
        let store = FieldStore(state: state, now: away)

        guard case .needsYou(let before) = store.todaySelection,
              before.addressedTo != nil
        else {
            Issue.record("expected the item to be addressed to one of them")
            return
        }

        store.raiseWithBoth(before.id)

        guard case .needsYou(let after) = store.todaySelection else {
            Issue.record("the item stopped surfacing")
            return
        }
        #expect(after.addressedTo == nil)
    }

    /// Every action now says what it is for, so no button can fall through a
    /// handler into silence.
    @Test
    func noActionIsWiredToNothing() {
        let store = FieldStore()
        guard case .needsYou(let moment) = store.todaySelection else {
            Issue.record("expected something to surface")
            return
        }
        #expect(!moment.actions.isEmpty)
        for action in moment.actions {
            switch action.role {
            case .act, .choice, .postpone, .overrideAbsence:
                continue
            }
        }
    }
}

// MARK: - Caught this week, and the moment that is remembered

@MainActor
struct FieldCaughtThisWeekTests {
    private func capture(_ id: String, daysAgo: Int) -> FieldCapture {
        FieldCapture(
            id: id,
            text: "Something",
            owner: .a,
            capturedAt: Calendar.gregorianUS.date(
                byAdding: .day,
                value: -daysAgo,
                to: FieldSampleData.today
            )!
        )
    }

    /// The label says this week, so the number has to be about this week.
    @Test
    func onlyTheLastSevenDaysAreCaughtThisWeek() {
        var state = FieldState.seed
        state.captures = [
            capture("today", daysAgo: 0),
            capture("recent", daysAgo: 6),
            capture("older", daysAgo: 8),
            capture("ancient", daysAgo: 400),
        ]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        let ids = Set(store.capturesThisWeek.map(\.id))

        #expect(ids == ["today", "recent"])
        #expect(store.state.captures.count == 4, "nothing was deleted")
    }

    /// The sample couple's fourteen all sit inside the window, so the gallery
    /// reads exactly as it did.
    @Test
    func theSampleWeekIsStillAWholeWeek() {
        let store = FieldStore()
        #expect(store.capturesThisWeek.count == store.state.captures.count)
    }

    /// "It goes for both of you, from every screen." Every screen includes the
    /// one under the capture field — the chip used to survive the thing it
    /// filed, going inert but staying in the count.
    @Test
    func removingAFiledThingTakesItsChipWithIt() async throws {
        let backend = FieldMemoryBackend()
        let store = FieldStore(backend: backend)

        store.captureDraft = "book the dentist"
        store.submitCapture()
        let filedID = try #require(store.lastReceipt?.id)
        store.send()

        #expect(store.capturesThisWeek.contains { $0.id == filedID })

        // Let the append land first: the writes are fire-and-forget, and a
        // delete that overtakes its own insert would prove nothing.
        try await Task.sleep(for: .milliseconds(80))
        store.remove(filedID)

        #expect(store.state.lifeItems.allSatisfy { $0.id != filedID })
        #expect(store.capturesThisWeek.allSatisfy { $0.id != filedID })

        // And it stays gone across a reload, rather than coming back as a chip
        // for something that no longer exists.
        try await Task.sleep(for: .milliseconds(80))
        let loaded = try await backend.load()
        #expect(loaded.captures.allSatisfy { $0.id != filedID })
    }

    /// An hour somebody shifted, or a day they told the app to stay quiet.
    /// Both used to evaporate on relaunch.
    @Test
    func theDailyMomentIsWrittenDown() async throws {
        let backend = FieldMemoryBackend()
        let store = FieldStore(backend: backend)
        let before = store.state.dailyMoment.sendMinute

        store.shiftMoment(byHours: 1)
        store.skipToday()

        // The writes are fire-and-forget, so let them land.
        try await Task.sleep(for: .milliseconds(80))
        let loaded = try await backend.load()

        #expect(loaded.dailyMoment.sendMinute == before + 60)
        #expect(loaded.dailyMoment.lastSentOn != nil)
    }
}

// MARK: - The verb on the button

@MainActor
struct FieldVerbTests {
    private func item(_ title: String, _ category: LifeCategory) -> LifeItem {
        LifeItem(
            id: title,
            title: title,
            category: category,
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

    /// Care held both "book the vet" and "call your mother", and the button
    /// said Book it under each. The category is a guess at what you do with
    /// something; the sentence usually just says.
    @Test
    func theWordingDecidesTheVerbBeforeTheCategoryDoes() {
        #expect(
            FieldTodaySelector.primaryVerb(for: item("Call your mother", .care))
                == "Make the call"
        )
        #expect(
            FieldTodaySelector.primaryVerb(for: item("Book the vet", .care))
                == "Book it"
        )
        #expect(
            FieldTodaySelector.primaryVerb(for: item("Rent", .money))
                == "Pay it"
        )
        #expect(
            FieldTodaySelector.primaryVerb(
                for: item("Renew the registration", LifeCategory(rawValue: "car"))
            ) == "Renew it"
        )
    }

    /// Silence rather than a guess. Wording that gives nothing away gets the
    /// honest general verb, whatever it was filed under — the app does not
    /// decide that Groceries are sent, Buys are ordered, or Pets are booked.
    @Test
    func wordingThatSaysNothingFallsBack() {
        #expect(FieldTodaySelector.verbFromWording("Recital") == nil)
        #expect(
            FieldTodaySelector.primaryVerb(for: item("Batteries", .buys))
                == "Mark it done"
        )
        #expect(
            FieldTodaySelector.primaryVerb(for: item("Groceries", .food))
                == "Mark it done"
        )
        #expect(
            FieldTodaySelector.primaryVerb(
                for: item("Recital", LifeCategory(rawValue: "notes"))
            ) == "Mark it done"
        )
    }

    /// The reason the category tier is gone, stated as a property rather than
    /// a list of examples.
    ///
    /// A button may only promise what the tap will actually do. `.none` is
    /// marked done and nothing else, so a `.none` item may not be offered a
    /// verb that describes anything else happening. This holds across every
    /// category, including ones grown later that nobody thought about here —
    /// which is the whole point of asserting it this way.
    @Test
    func aVerbNeverPromisesMoreThanTheTapDoes() {
        let categories: [LifeCategory] =
            LifeCategory.builtIn + [LifeCategory(rawValue: "pets")]

        for category in categories {
            let quiet = item("Recital", category)
            #expect(
                FieldTodaySelector.primaryAct(for: quiet) == .none,
                "\(category.rawValue) invented an act from nothing"
            )
            #expect(
                FieldTodaySelector.primaryVerb(for: quiet) == "Mark it done",
                "\(category.rawValue) put a verb on a button that does nothing"
            )
        }
    }
}

// MARK: - Reaching the phone
//
// The rule the whole feature stands on: a number is never invented, and
// nothing is ever dialled without a person reading it first.

/// Finds exactly what it was told to find. There is no network here and there
/// never should be — see `FieldNoTargetResolver` for why previews use the one
/// that finds nobody.
struct FieldStubTargetResolver: FieldTargetResolver {
    var results: [FieldTarget]
    func resolve(_ query: FieldTargetQuery) async -> [FieldTarget] { results }
}

@MainActor
struct FieldOutreachTests {
    private func item(
        _ title: String,
        dueOn: Date? = nil,
        detail: String? = nil
    ) -> LifeItem {
        LifeItem(
            id: "x",
            title: title,
            category: .care,
            owner: .a,
            dueOn: dueOn,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: detail,
            isTimeCritical: false,
            isDone: false
        )
    }

    private var vet: FieldTarget {
        FieldTarget(
            name: "Hudson Vet",
            phoneNumber: "(212) 555-0134",
            emailAddress: nil,
            address: "1 Hudson St",
            source: .maps
        )
    }

    /// The classification was always being made and always thrown away.
    @Test
    func theWordingDecidesTheAct() {
        #expect(FieldTodaySelector.primaryAct(for: item("Call your mother")) == .call)
        #expect(FieldTodaySelector.primaryAct(for: item("Book the vet")) == .book)
        #expect(FieldTodaySelector.primaryAct(for: item("Email the landlord")) == .email)
        #expect(FieldTodaySelector.primaryAct(for: item("Text Dylan")) == .message)
        // A category's verb is a fair label and a bad reason to pick up a
        // phone, so wording that says nothing produces no act.
        #expect(FieldTodaySelector.primaryAct(for: item("Recital")) == .none)
        // And the app was told about a conversation, not asked to start one.
        #expect(FieldTodaySelector.primaryAct(for: item("Talk to Sam")) == .none)

        // The verb somebody actually said beats a noun the app recognises.
        // "Call the vet" is a call; the vet is only where the call goes.
        #expect(FieldTodaySelector.primaryAct(for: item("Call the vet")) == .call)
        #expect(
            FieldTodaySelector.verbFromWording("Call the vet") == "Make the call"
        )
        // With no verb at all, the noun is the only thing left to read.
        #expect(FieldTodaySelector.primaryAct(for: item("Dentist tuesday")) == .book)
    }

    /// Same table, so the words on the buttons cannot drift from the acts.
    @Test
    func everyVerbStillReadsExactlyAsItDid() {
        let cases: [(String, String)] = [
            ("Call your mother", "Make the call"),
            ("Book the vet", "Book it"),
            ("Rent", "Pay it"),
            ("Order more batteries", "Order it"),
            ("Pack for the hamptons", "Pack it"),
            ("Renew the registration", "Renew it"),
            ("Email the landlord", "Send it"),
        ]
        for (title, verb) in cases {
            #expect(
                FieldTodaySelector.verbFromWording(title) == verb,
                "\(title) changed its word"
            )
        }
    }

    /// Digits and a leading plus, and nothing that is not a number at all.
    @Test
    func aNumberIsNormalisedOrRefused() {
        #expect(FieldDial.normalised("(212) 555-0134") == "2125550134")
        #expect(FieldDial.normalised("+44 20 7946 0018") == "+442079460018")
        #expect(FieldDial.normalised("call me") == nil)
        #expect(FieldDial.normalised("12") == nil, "a house number is not a phone")
    }

    @Test
    func theDestinationIsTheRightURL() {
        let now = FieldSampleData.today

        guard case .call(let url, let display, _) = FieldOutreach.destination(
            act: .call,
            item: item("Call the vet"),
            target: vet,
            now: now
        ) else {
            Issue.record("expected a call")
            return
        }
        #expect(url.absoluteString == "tel:2125550134")
        #expect(display == "(212) 555-0134")

        guard case .message(let sms, _, _) = FieldOutreach.destination(
            act: .message,
            item: item("Text the vet"),
            target: vet,
            now: now
        ) else {
            Issue.record("expected a message")
            return
        }
        #expect(sms.absoluteString == "sms:2125550134")
        // No prefilled body. Words the couple did not write would be sent
        // under their name.
        #expect(!sms.absoluteString.contains("body"))
    }

    /// The common case, and a designed state rather than a failure.
    @Test
    func noTargetIsUnresolvedAndNeverAGuess() {
        guard case .unresolved(let act, let name) = FieldOutreach.destination(
            act: .call,
            item: item("Call the vet"),
            target: nil,
            now: FieldSampleData.today
        ) else {
            Issue.record("a missing number produced a destination anyway")
            return
        }
        #expect(act == .call)
        #expect(name == nil)
    }

    /// Acts with no honest destination on this phone do what they always did.
    @Test
    func payingAndOrderingStillJustComplete() {
        for act in [FieldAct.pay, .order, .none] {
            #expect(
                FieldOutreach.destination(
                    act: act,
                    item: item("Pay the rent"),
                    target: nil,
                    now: FieldSampleData.today
                ) == .complete
            )
        }
    }

    /// A draft, and only from what the item already says.
    @Test
    func theEventDraftIsTheThingsOwnWords() {
        let due = FieldSampleData.date(2025, 8, 20)
        let draft = FieldOutreach.draft(
            for: item("Dentist", dueOn: due, detail: "Ask about the crown"),
            now: FieldSampleData.today
        )

        #expect(draft.title == "Dentist")
        #expect(draft.notes == "Ask about the crown")
        #expect(
            Calendar.gregorianUS.component(.hour, from: draft.startDate) == 9
        )

        // Nothing to write in the notes is nothing, not a sentence the app
        // made up on somebody's behalf.
        #expect(FieldOutreach.draft(for: item("Dentist"), now: FieldSampleData.today).notes == nil)
    }
}

@MainActor
struct FieldTargetPhrasingTests {
    private let identity = FieldSampleData.identity

    @Test
    func theSubjectComesOutOfTheSentence() {
        let vet = FieldTargetPhrasing.extract(
            from: "Book the vet Friday",
            act: .book,
            identity: identity
        )
        #expect(vet?.target == "vet")
        #expect(vet?.kind == .place)

        let mom = FieldTargetPhrasing.extract(
            from: "Call mom sunday",
            act: .call,
            identity: identity
        )
        #expect(mom?.target == "mom")
        #expect(mom?.kind == .person)
    }

    /// A partner's own name is a person. Everything the app is not sure about
    /// is a business — a wrong place is an address on a screen, and a wrong
    /// person is somebody's real phone number.
    @Test
    func onlyRealReasonsMakeSomethingAPerson() {
        #expect(
            FieldTargetPhrasing.extract(
                from: "Call Dylan tomorrow",
                act: .call,
                identity: identity
            )?.kind == .person
        )
        #expect(
            FieldTargetPhrasing.extract(
                from: "Call the plumber",
                act: .call,
                identity: identity
            )?.kind == .place
        )
    }

    /// A sentence that names nobody returns nothing, and the app says so.
    @Test
    func aSentenceWithNoSubjectExtractsNothing() {
        #expect(
            FieldTargetPhrasing.extract(
                from: "Book it",
                act: .book,
                identity: identity
            ) == nil
        )
    }
}

@MainActor
struct FieldOutreachStoreTests {
    private func store(
        finding targets: [FieldTarget],
        title: String = "Call the vet"
    ) -> FieldStore {
        var state = FieldState.seed
        state.lifeItems = [
            LifeItem(
                id: "vet",
                title: title,
                category: .care,
                owner: .a,
                dueOn: FieldSampleData.today,
                closesAt: nil,
                clusterID: nil,
                source: .captured,
                detail: nil,
                isTimeCritical: false,
                isDone: false
            ),
        ]
        return FieldStore(
            state: state,
            now: FieldSampleData.today,
            resolver: FieldStubTargetResolver(results: targets)
        )
    }

    /// It stops and shows what it found. It does not dial.
    @Test
    func actingOutwardWaitsForAYes() async {
        let target = FieldTarget(
            name: "Hudson Vet",
            phoneNumber: "212-555-0134",
            emailAddress: nil,
            address: "1 Hudson St",
            source: .maps
        )
        let store = store(finding: [target])

        await store.begin(.call, for: "vet")

        #expect(store.pendingOutreach?.state == .found)
        #expect(store.pendingOutreach?.candidates == [target])
        // Nothing has happened to the item, because nothing has happened.
        #expect(store.state.lifeItems[0].isDone == false)
    }

    @Test
    func findingNobodyIsItsOwnState() async {
        let store = store(finding: [])

        await store.begin(.call, for: "vet")

        #expect(store.pendingOutreach?.state == .foundNothing)
        #expect(store.state.lifeItems[0].isDone == false)
    }

    /// Opening the phone is not evidence the thing got done. The app asks.
    @Test
    func openingSomethingAsksRatherThanAssumes() async {
        let store = store(finding: [])
        await store.begin(.call, for: "vet")
        guard let request = store.pendingOutreach else {
            Issue.record("nothing pending")
            return
        }

        store.outreachDidOpen(request, target: nil)

        #expect(store.pendingOutreach == nil)
        #expect(store.awaitingOutcome?.id == "vet")
        #expect(store.state.lifeItems[0].isDone == false, "the app decided for them")

        store.resolveOutcome(store.awaitingOutcome!, done: true)
        #expect(store.state.lifeItems[0].isDone)
        #expect(store.awaitingOutcome == nil)
    }

    /// "Not yet" is an answer, and it is not asked again.
    @Test
    func notYetLeavesItAlone() async {
        let store = store(finding: [])
        await store.begin(.call, for: "vet")
        store.outreachDidOpen(store.pendingOutreach!, target: nil)

        store.resolveOutcome(store.awaitingOutcome!, done: false)

        #expect(store.awaitingOutcome == nil)
        #expect(store.state.lifeItems[0].isDone == false)
    }

    /// Booking is a phone call when there is somebody to call, which is what
    /// booking a vet actually is.
    @Test
    func bookingLooksForANumberBeforeItLooksForACalendar() async {
        let target = FieldTarget(
            name: "Hudson Vet",
            phoneNumber: "212-555-0134",
            emailAddress: nil,
            address: "1 Hudson St",
            source: .maps
        )
        let store = store(finding: [target], title: "Book the vet")

        await store.begin(.book, for: "vet")

        #expect(store.pendingOutreach?.state == .found)
        guard case .call = FieldOutreach.destination(
            act: .book,
            item: store.state.lifeItems[0],
            target: target,
            now: store.now
        ) else {
            Issue.record("a bookable thing with a number did not become a call")
            return
        }
    }

    /// Nothing outward to do, so the button does exactly what it always did.
    @Test
    func anActWithNoOutwardMeaningJustCompletes() async {
        let store = store(finding: [], title: "Pack for the hamptons")

        await store.begin(.none, for: "vet")

        #expect(store.pendingOutreach == nil)
        #expect(store.state.lifeItems[0].isDone)
    }

    /// Previews, the gallery, and every screenshot run must never reach out
    /// of the process or read this machine's address book.
    @Test
    func theDefaultResolverFindsNobody() async {
        let found = await FieldNoTargetResolver().resolve(
            FieldTargetQuery(text: "vet", kind: .place)
        )
        #expect(found.isEmpty)
    }
}

// MARK: - Store behaviour

@MainActor
struct FieldStoreTests {
    /// A couple who has corrected nothing is told nothing.
    ///
    /// `behaviourChanges` used to fall back to
    /// `FieldSampleData.behaviourChanges` below three derived cards. The third
    /// card reads a reply rate and nothing in the app writes a reply rate, so
    /// the threshold was unreachable and the fallback was not a fallback — it
    /// was the only answer the property ever gave. Every couple was shown the
    /// fictional couple's changes and told they were their own.
    @Test
    func anUncorrectedFieldClaimsToHaveLearnedNothing() {
        let store = FieldStore(
            state: .empty(
                nameA: "Ryan",
                nameB: "Dylan",
                now: FieldSampleData.today
            )
        )

        #expect(store.state.corrections.isEmpty)
        #expect(
            store.behaviourChanges.isEmpty,
            "a field with no corrections reported behaviour changes"
        )
    }

    /// And what a real couple is told is derived from what *they* corrected.
    ///
    /// Deliberately not asserted against the seeded store: that store is the
    /// fictional couple, and `FieldSampleData.behaviourChanges` was authored to
    /// read like what the engine derives from their corrections — so the two
    /// coinciding there is the sample data being right, not the fallback
    /// coming back. The couple who must never see those sentences is the one
    /// who did not write them.
    @Test
    func aRealCouplesChangesComeFromTheirOwnCorrections() {
        var state = FieldState.empty(
            nameA: "Ryan",
            nameB: "Dylan",
            now: FieldSampleData.today
        )
        state.corrections = [
            FieldCorrection(
                id: "one",
                input: "tulips",
                original: .buys,
                corrected: LifeCategory(named: "garden") ?? .notes,
                correctedAt: FieldSampleData.today
            ),
            FieldCorrection(
                id: "two",
                input: "compost",
                original: .buys,
                corrected: LifeCategory(named: "garden") ?? .notes,
                correctedAt: FieldSampleData.today
            ),
        ]

        let store = FieldStore(state: state)

        for change in store.behaviourChanges {
            #expect(
                !FieldSampleData.behaviourChanges.contains(where: {
                    $0.change == change.change
                }),
                "\(change.change) is the fictional couple's sentence"
            )
        }
    }

    /// The mark returns to Today from anywhere, and closes the takeover on the
    /// way. A hard requirement.
    @Test
    func theMarkAlwaysReturnsHome() {
        let store = FieldStore()
        store.go(to: .us)
        store.openCalendar()

        store.returnHome()

        #expect(store.activeZone == .we)
        #expect(store.calendarOpen == false)
    }

    /// Typing shows where it *would* go and files nothing. Nothing crosses
    /// until it is sent — the app says so out loud in Soft Start.
    @Test
    func submittingOnlyProposes() {
        let store = FieldStore()
        let before = store.state.lifeItems.count

        store.captureDraft = "past lives"
        store.submitCapture()

        #expect(store.lastReceipt != nil)
        #expect(store.state.lifeItems.count == before)
    }

    /// The classifier grows categories on its own and is deliberately shy
    /// about it, which means it sometimes has no word for a thing that plainly
    /// deserves one. Naming it is the other direction of the same act, and it
    /// teaches the classifier exactly like any other correction.
    @Test
    func aCategoryCanBeNamedFromTheCorrectionPicker() {
        let store = FieldStore()
        store.captureDraft = "resole the brown boots"
        store.submitCapture()
        store.beginCorrection()

        let created = store.correct(toNewCategory: "Repairs")

        #expect(created?.rawValue == "repairs")
        #expect(store.lastReceipt?.category.rawValue == "repairs")
        #expect(store.lastReceipt?.wasCorrected == true)
        #expect(store.correctingReceipt == nil)
        #expect(store.state.corrections.last?.corrected.rawValue == "repairs")

        // And it is a real destination afterwards, offered like any other.
        store.send()
        #expect(store.correctionCategories.contains {
            $0.rawValue == "repairs"
        })
    }

    /// Refused rather than mangled. Taking the first two words of a sentence
    /// would file things under a heading nobody wrote.
    @Test
    func aNameThatIsNotAHeadingIsRefusedAndNothingMoves() {
        let store = FieldStore()
        store.captureDraft = "resole the brown boots"
        store.submitCapture()
        let original = store.lastReceipt?.category
        store.beginCorrection()

        #expect(store.correct(toNewCategory: "the whole of everything else") == nil)
        #expect(store.correct(toNewCategory: "calendar") == nil)

        #expect(store.lastReceipt?.category == original)
        #expect(store.lastReceipt?.wasCorrected == false)
        #expect(store.state.corrections.isEmpty)
        // Still open, because nothing was decided.
        #expect(store.correctingReceipt != nil)
    }

    /// Opening the picker is not a commitment. Before this, a person who
    /// tapped "Wrong place" to see the options and decided the app had been
    /// right could only leave by moving the thing somewhere.
    @Test
    func theCorrectionPickerCanBeLeftWithoutMovingAnything() {
        let store = FieldStore()
        store.captureDraft = "past lives"
        store.submitCapture()
        let original = store.lastReceipt
        store.beginCorrection()

        store.cancelCorrection()

        #expect(store.correctingReceipt == nil)
        #expect(store.lastReceipt == original)
        #expect(store.state.corrections.isEmpty)
    }

    /// "For today" sets a date and takes it back off. It is a toggle because
    /// the person tapping it is deciding, not committing.
    @Test
    func forTodayDatesTheReceiptAndUndatesIt() {
        let store = FieldStore()
        store.captureDraft = "call the plumber"
        store.submitCapture()

        store.toggleForToday()
        let dueOn = store.lastReceipt?.dueOn
        #expect(dueOn != nil)
        #expect(
            Calendar.gregorianUS.isDate(
                dueOn ?? .distantPast,
                inSameDayAs: store.now
            )
        )

        store.toggleForToday()
        #expect(store.lastReceipt?.dueOn == nil)
    }

    /// A film is not due on Thursday, and it is not due today either. The
    /// control is refused where a date would be a lie.
    @Test
    func forTodayIsRefusedWhereADateWouldBeALie() {
        let store = FieldStore()
        store.captureDraft = "past lives"
        store.submitCapture()
        #expect(store.lastReceipt?.category.carriesDates == false)

        store.toggleForToday()
        #expect(store.lastReceipt?.dueOn == nil)
    }

    /// The whole point of the control: something put on today comes back as
    /// the thing Today shows. Without this it is a date nobody ever sees.
    @Test
    func somethingPutOnTodaySurfacesOnToday() {
        // A real couple's account rather than the seed, whose grocery window
        // closes tonight and would outrank anything added here. This is the
        // case that matters anyway: the screen was clear a moment ago.
        let now = FieldSampleData.today
        let store = FieldStore(
            state: .empty(nameA: "Maya", nameB: "Dylan", now: now),
            now: now
        )
        #expect({
            if case .resolved = store.todaySelection { return true }
            return false
        }())

        store.captureDraft = "call the plumber"
        store.submitCapture()
        store.toggleForToday()
        store.send()

        guard case .needsYou(let moment) = store.todaySelection else {
            Issue.record("expected the thing just added to need them")
            return
        }
        #expect(moment.headline.localizedCaseInsensitiveContains("plumber"))
    }

    /// Us has nothing to say until there is a horizon or a week's evidence,
    /// and a heading over nothing is the app talking to fill the silence.
    @Test
    func usIsEmptyUntilThereIsAHorizonOrEvidence() {
        let now = FieldSampleData.today
        let fresh = FieldStore(
            state: .empty(nameA: "Maya", nameB: "Dylan", now: now),
            now: now
        )
        #expect(fresh.usIsEmpty)

        #expect(!FieldStore(state: .seed, now: now).usIsEmpty)
    }

    /// A capture is filed, not just receipted. Without this the receipt is
    /// theatre.
    @Test
    func sendingFilesItIntoItsCategory() {
        let store = FieldStore()
        let before = store.state.lifeItems.count

        store.captureDraft = "past lives"
        store.submitCapture()
        store.send()

        #expect(store.state.lifeItems.count == before + 1)
        #expect(store.lastReceipt == nil)
        #expect(
            store.state.lifeItems.contains {
                $0.title == "Past lives" && $0.category == .watchlist
            }
        )
    }

    /// And it has to survive a reload.
    ///
    /// This is the bug this test exists for: `materialise` only ever inserted
    /// into local state, so a sent item looked filed and then vanished on the
    /// next load from Supabase. The backend had `upsert` all along and
    /// nothing called it.
    @Test
    func aSentItemSurvivesAReload() async {
        let backend = FieldMemoryBackend(state: .seed)
        let store = FieldStore(state: .seed, backend: backend)

        store.captureDraft = "past lives"
        store.submitCapture()
        store.send()

        // "Past lives", not "past lives" — what gets filed is the tidied
        // thought, and sentence case is part of tidying it.
        guard let filed = store.state.lifeItems.first(where: {
            $0.title == "Past lives"
        }) else {
            Issue.record("expected it in the local list")
            return
        }

        // Whatever the store did locally, the question is what the backend
        // was actually told.
        try? await Task.sleep(for: .milliseconds(120))
        let reloaded = try? await backend.load()
        #expect(reloaded?.lifeItems.contains { $0.id == filed.id } == true)
        #expect(reloaded?.captures.contains { $0.id == filed.id } == true)
    }

    /// Partner identity is persistence state, not a tint. This is the
    /// regression guard for the production bug where every device returned
    /// `.a`, causing Partner B's capture and filed item to survive as A's.
    @Test
    func partnerBCaptureSurvivesAsPartnerB() async {
        let backend = FieldMemoryBackend(
            state: .seed,
            viewerOwner: .b
        )
        let store = FieldStore(state: .seed, backend: backend)

        #expect(store.speaker == .b)
        store.captureDraft = "book the dentist"
        store.submitCapture()
        store.send()

        try? await Task.sleep(for: .milliseconds(120))
        let reloaded = try? await backend.load()
        #expect(
            reloaded?.captures.first {
                $0.text == "Book the dentist"
            }?.owner == .b
        )
        #expect(
            reloaded?.lifeItems.first {
                $0.title == "Book the dentist"
            }?.owner == .b
        )
    }

    @Test
    func liveBackendRejectsAnOutsiderInsteadOfAttributingThemToA() throws {
        let a = UUID()
        let b = UUID()
        let outsider = UUID()
        let couple = UUID()
        let provider = SupabaseClientProvider(
            configuration: SupabaseConfiguration(
                url: try #require(URL(string: "http://127.0.0.1:54321")),
                publishableKey: "contract-test-key"
            )
        )
        let members = [
            Member(id: a.uuidString, name: "A", hue: .clay),
            Member(id: b.uuidString, name: "B", hue: .sage),
        ]

        let partnerB = try #require(
            FieldSupabaseBackend(
                client: provider.client,
                coupleID: couple.uuidString,
                viewerID: b.uuidString,
                members: members,
                firstMemberID: a.uuidString
            )
        )
        #expect(partnerB.viewerOwner == .b)
        #expect(
            FieldSupabaseBackend(
                client: provider.client,
                coupleID: couple.uuidString,
                viewerID: outsider.uuidString,
                members: members,
                firstMemberID: a.uuidString
            ) == nil
        )
    }

    @Test
    func liveOnboardingCannotChooseThePartnersSwatch() {
        var state = FieldState.seed
        state.identity.personA = .clay
        state.identity.personB = .slate
        let backend = FieldMemoryBackend(
            state: state,
            viewerOwner: .b
        )
        let store = FieldStore(state: state, backend: backend)

        store.choose(.amber, for: .a)
        store.choose(.teal, for: .b)

        #expect(store.identity.personA == .clay)
        #expect(store.identity.personB == .teal)
    }

    /// Walking away files nothing, because nothing had been filed.
    @Test
    func dismissingSendsNothing() {
        let store = FieldStore()
        let before = store.state.lifeItems.count

        store.captureDraft = "past lives"
        store.submitCapture()
        store.dismissReceipt()

        #expect(store.state.lifeItems.count == before)
        #expect(store.lastReceipt == nil)
    }

    /// Correcting before sending changes where it is about to go, and logs
    /// the signal. There is nothing materialised to move.
    @Test
    func correctionRetargetsAndLogsTheSignal() {
        let store = FieldStore()
        store.captureDraft = "steak"
        store.submitCapture()

        let lifeBefore = store.state.lifeItems.count

        store.beginCorrection()
        store.correct(to: .money)

        #expect(store.state.corrections.count == 1)
        #expect(store.state.lifeItems.count == lifeBefore)

        store.send()
        #expect(store.state.lifeItems.count == lifeBefore + 1)
        #expect(
            store.state.lifeItems.contains {
                $0.title == "Steak" && $0.category == .money
            }
        )
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
        for category in LifeCategory.builtIn {
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
        let clock = FieldSteppedClock(FieldSampleData.today)
        let store = FieldStore(clock: clock)
        let before = store.subtitleRefreshKey

        // Re-reading, and time passing, change the ranking but not the words.
        clock.set(FieldSampleData.date(2025, 8, 13, hour: 20))
        store.tick()
        #expect(store.now != FieldSampleData.today, "the clock did not move")
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

// MARK: - The calendar is a record, not a filter

@MainActor
struct FieldCalendarTests {
    private func item(
        _ id: String,
        dueOn: Date?,
        isDone: Bool
    ) -> LifeItem {
        LifeItem(
            id: id,
            title: "Jake's party",
            category: .care,
            owner: .a,
            dueOn: dueOn,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: isDone
        )
    }

    /// A party you went to did not stop having happened because you ticked it
    /// off. Filtering completed items out of the calendar applied to-do logic
    /// to the one surface in the app that is not a to-do list.
    @Test
    func completingSomethingDoesNotEraseItFromTheCalendar() {
        var state = FieldState.seed
        let day = FieldSampleData.date(2025, 8, 14)
        state.lifeItems = [
            item("done", dueOn: day, isDone: true),
            item("open", dueOn: day, isDone: false),
            item("undated", dueOn: nil, isDone: false),
        ]
        let store = FieldStore(state: state)

        let onTheCalendar = store.state.lifeItems.filter { $0.dueOn != nil }
        #expect(onTheCalendar.count == 2)
        #expect(onTheCalendar.contains { $0.id == "done" })
        // Undated things are not on a calendar at all — there is no day to put
        // them on, which is the whole of what "appetite" means now.
        #expect(!onTheCalendar.contains { $0.id == "undated" })
    }

    /// But Today still never raises a finished thing. The two surfaces read the
    /// same items and disagree on purpose.
    @Test
    func aCompletedItemStillNeverReachesToday() {
        let day = FieldSampleData.date(2025, 8, 14)
        let context = FieldTodaySelector.Context(
            now: day,
            identity: FieldSampleData.identity,
            partners: [],
            lifeItems: [item("done", dueOn: day, isDone: true)],
            clusters: [],
            horizons: [],
            heldTopics: [],
            standingRules: []
        )

        #expect(FieldTodaySelector.rank(context).isEmpty)
    }
}

// MARK: - Becoming a horizon

@MainActor
struct FieldPromotionTests {
    private func trip(_ id: String, _ title: String) -> LifeItem {
        LifeItem(
            id: id,
            title: title,
            category: .trips,
            owner: .shared,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
    }

    private func context(
        lifeItems: [LifeItem],
        horizons: [FieldHorizon] = [],
        held: [FieldHeldTopic] = []
    ) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: FieldSampleData.today,
            identity: FieldSampleData.identity,
            partners: [],
            lifeItems: lifeItems,
            clusters: [],
            horizons: horizons,
            heldTopics: held,
            standingRules: []
        )
    }

    /// Once is a passing remark. Asking about a passing remark is the app
    /// manufacturing a conversation.
    @Test
    func oneMentionIsNotWorthAsking() {
        let proposal = FieldPromotion.proposal(
            context(lifeItems: [trip("a", "Japan in the fall")])
        )
        #expect(proposal == nil)
    }

    @Test
    func twiceIsWorthAsking() {
        let proposal = FieldPromotion.proposal(
            context(lifeItems: [
                trip("a", "Japan in the fall"),
                trip("b", "Japan — the Kyoto leg"),
            ])
        )
        #expect(proposal?.subject == "Japan")
        #expect(proposal?.question.choices.count == 2)
        #expect(proposal?.itemIDs.sorted() == ["a", "b"])
    }

    /// A thing with a date is already a plan. Asking whether you plan to do it
    /// would be absurd.
    @Test
    func datedThingsAreNeverProposed() {
        func dated(_ id: String) -> LifeItem {
            var item = trip(id, "Japan in the fall")
            item.category = .care
            item.dueOn = FieldSampleData.date(2025, 9, 1)
            return item
        }

        #expect(
            FieldPromotion.proposal(
                context(lifeItems: [dated("a"), dated("b")])
            ) == nil
        )
    }

    /// Answering yes builds the horizon out of the items — and leaves every
    /// one of them exactly where it was. A horizon points at Life; it does not
    /// empty it.
    @Test
    func answeringYesCreatesAHorizonAndMovesNothing() {
        var state = FieldState.seed
        state.horizons = []
        state.lifeItems = [
            trip("a", "Lisbon, maybe"),
            trip("b", "Lisbon in June"),
        ]
        let store = FieldStore(state: state)

        guard let proposal = FieldPromotion.proposal(
            context(lifeItems: state.lifeItems)
        ), let yes = proposal.affirmative else {
            Issue.record("expected a proposal for Lisbon")
            return
        }

        store.answer(proposal.question, with: yes)

        #expect(store.state.horizons.count == 1)
        #expect(store.state.horizons.first?.title == "Lisbon")
        #expect(store.state.horizons.first?.isPrimary == true)
        #expect(
            store.state.horizons.first?.linkedLifeItemIDs.sorted() == ["a", "b"]
        )
        // The whole point: they are still in Life.
        #expect(store.state.lifeItems.count == 2)
        #expect(store.state.lifeItems.allSatisfy { $0.category == .trips })
        #expect(
            store.state.evidence.first?.horizonID
                == store.state.horizons.first?.id
        )
    }

    /// "Not this year" is a real answer with a real consequence: the app stops
    /// asking. Timing is most of tact.
    @Test
    func answeringNoHoldsTheTopicAndBuildsNothing() {
        var state = FieldState.seed
        state.horizons = []
        state.lifeItems = [
            trip("a", "Lisbon, maybe"),
            trip("b", "Lisbon in June"),
        ]
        let store = FieldStore(state: state)

        guard let proposal = FieldPromotion.proposal(
            context(lifeItems: state.lifeItems)
        ), let no = proposal.question.choices.last else {
            Issue.record("expected a proposal for Lisbon")
            return
        }

        store.answer(proposal.question, with: no)

        #expect(store.state.horizons.isEmpty)
        // Settled rather than held. "Not this year" is an answer, and the app
        // owes it the same finality it owes a yes — a held topic is one the
        // app is still sitting on, and this is not that.
        #expect(store.state.heldTopics.contains { $0.wasDismissed })
        #expect(!store.state.heldTopics.contains { !$0.isSettled })
        // And it does not come back tomorrow.
        #expect(
            FieldPromotion.proposal(
                context(
                    lifeItems: store.state.lifeItems,
                    held: store.state.heldTopics
                )
            ) == nil
        )
    }

    /// A subject that already has a horizon has already been answered.
    @Test
    func anExistingHorizonIsNotProposedAgain() {
        let horizon = FieldHorizon(
            id: "japan",
            title: "Japan,",
            window: nil,
            owner: .shared,
            isPrimary: true,
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: [],
            openQuestion: nil
        )

        #expect(
            FieldPromotion.proposal(
                context(
                    lifeItems: [
                        trip("a", "Japan in the fall"),
                        trip("b", "Japan — the Kyoto leg"),
                    ],
                    horizons: [horizon]
                )
            ) == nil
        )
    }
}

// MARK: - Joining an occasion

@MainActor
struct FieldOccasionTests {
    /// The visit itself: dated, about a person, belonging to nothing yet.
    private func visit(
        id: String = "visit",
        _ title: String = "Ryan's dad is in town",
        on day: Date = FieldSampleData.date(2025, 8, 15)
    ) -> LifeItem {
        LifeItem(
            id: id,
            title: title,
            category: .home,
            owner: .shared,
            dueOn: day,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
    }

    /// A loose thought, undated and unattached.
    private func loose(_ id: String, _ title: String) -> LifeItem {
        LifeItem(
            id: id,
            title: title,
            category: .food,
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

    private func context(
        lifeItems: [LifeItem],
        clusters: [FieldCluster] = [],
        held: [FieldHeldTopic] = []
    ) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: FieldSampleData.today,
            identity: FieldSampleData.identity,
            partners: [],
            lifeItems: lifeItems,
            clusters: clusters,
            horizons: [],
            heldTopics: held,
            standingRules: []
        )
    }

    /// The whole feature, in one case: a visit, a thought that only refers to
    /// the person, and one question about whether they go together.
    @Test
    func aPronounIsReadAgainstTheOnlyPersonComing() {
        let proposal = FieldOccasion.proposal(
            context(lifeItems: [
                visit(),
                loose("coffee", "The coffee he likes"),
            ])
        )

        #expect(proposal?.itemID == "coffee")
        #expect(proposal?.clusterID == nil)
        #expect(proposal?.anchorItemID == "visit")
        #expect(proposal?.evidence == .referred(pronoun: "he"))
        #expect(proposal?.question.choices.count == 2)
    }

    /// The guard the whole rule rests on. Two people coming and "he" could be
    /// either — so the app says nothing rather than filing one man's coffee
    /// under the other man's visit.
    @Test
    func aPronounIsNotGuessedAtWhenTwoPeopleAreComing() {
        let other = visit(
            id: "other",
            "Dylan's mother is in town",
            on: FieldSampleData.date(2025, 8, 18)
        )

        #expect(
            FieldOccasion.proposal(
                context(lifeItems: [
                    visit(),
                    other,
                    loose("coffee", "The coffee he likes"),
                ])
            ) == nil
        )
    }

    /// Naming the person removes the ambiguity, so the same two occasions are
    /// no longer a reason to stay quiet.
    @Test
    func namingThePersonIsUnambiguousEvenWithTwoOccasions() {
        let other = visit(
            id: "other",
            "Dylan's mother is in town",
            on: FieldSampleData.date(2025, 8, 18)
        )

        let proposal = FieldOccasion.proposal(
            context(lifeItems: [
                visit(),
                other,
                loose("coffee", "Coffee for Ryan's dad"),
            ])
        )

        #expect(proposal?.itemID == "coffee")
        #expect(proposal?.anchorItemID == "visit")
        #expect(proposal?.evidence == .named("ryan's dad"))
    }

    /// Whole words only. Without that rule "there" contains "her" and the app
    /// confidently relates a thought about nothing.
    @Test
    func pronounsInsideOtherWordsAreNotPronouns() {
        #expect(
            FieldOccasion.proposal(
                context(lifeItems: [
                    visit(),
                    loose("shelf", "Put the shelf brackets in there"),
                ])
            ) == nil
        )
    }

    /// Beyond the window a dated thing is a plan, not an occasion — otherwise
    /// everything mentioned between now and then gets swept into it.
    @Test
    func somethingMonthsAwayDoesNotPullThingsIn() {
        #expect(
            FieldOccasion.proposal(
                context(lifeItems: [
                    visit(on: FieldSampleData.date(2025, 12, 24)),
                    loose("coffee", "The coffee he likes"),
                ])
            ) == nil
        )
    }

    /// Yes forms the occasion, puts both things in it — and moves neither of
    /// them. The same promise a promotion makes.
    @Test
    func answeringYesFormsTheOccasionAndMovesNothing() {
        var state = FieldState.seed
        state.clusters = []
        state.horizons = []
        state.lifeItems = [visit(), loose("coffee", "The coffee he likes")]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        guard let proposal = FieldOccasion.proposal(
            context(lifeItems: state.lifeItems)
        ), let yes = proposal.affirmative else {
            Issue.record("expected an occasion proposal")
            return
        }
        store.answer(proposal.question, with: yes)

        #expect(store.state.clusters.count == 1)
        let cluster = store.state.clusters[0]
        #expect(cluster.anchorDate != nil)

        // Both in the occasion, including the visit that named it.
        let members = Set(cluster.items(from: store.state.lifeItems).map(\.id))
        #expect(members == ["visit", "coffee"])

        // And nothing moved: same category, same owner, still in Life.
        let coffee = store.state.lifeItems.first { $0.id == "coffee" }
        #expect(coffee?.category == .food)
        #expect(coffee?.owner == .a)
        #expect(store.state.lifeItems.count == 2)
    }

    /// No is an answer, not a postponement — and the app does not ask again.
    @Test
    func answeringNoKeepsThemApartAndStopsAsking() {
        var state = FieldState.seed
        state.clusters = []
        state.horizons = []
        state.lifeItems = [visit(), loose("coffee", "The coffee he likes")]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        guard let proposal = FieldOccasion.proposal(
            context(lifeItems: state.lifeItems)
        ), let no = proposal.question.choices.last else {
            Issue.record("expected an occasion proposal")
            return
        }
        store.answer(proposal.question, with: no)

        #expect(store.state.clusters.isEmpty)
        #expect(store.state.lifeItems.allSatisfy { $0.clusterID == nil })
        #expect(store.state.heldTopics.contains { $0.wasDismissed })

        // The claim being made on screen, asserted: it does not come back.
        #expect(
            FieldOccasion.proposal(
                context(
                    lifeItems: store.state.lifeItems,
                    held: store.state.heldTopics
                )
            ) == nil
        )
    }

    /// An occasion that already exists gains the item rather than being
    /// rebuilt beside itself.
    @Test
    func anExistingOccasionIsJoinedRatherThanDuplicated() {
        let cluster = FieldCluster(
            id: "dad",
            title: "Before your dad lands",
            rationale: "",
            tint: .a,
            timeframe: "FRI",
            anchorDate: FieldSampleData.date(2025, 8, 15)
        )
        var state = FieldState.seed
        state.clusters = [cluster]
        state.horizons = []
        state.lifeItems = [loose("coffee", "The coffee he likes")]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        guard let proposal = FieldOccasion.proposal(
            context(lifeItems: state.lifeItems, clusters: [cluster])
        ), let yes = proposal.affirmative else {
            Issue.record("expected an occasion proposal")
            return
        }
        #expect(proposal.clusterID == "dad")

        store.answer(proposal.question, with: yes)

        #expect(store.state.clusters.count == 1)
        #expect(
            store.state.lifeItems.first { $0.id == "coffee" }?.clusterID
                == "dad"
        )
    }

    /// The occasion's own anchor is never offered as a thing to file into it.
    @Test
    func theVisitIsNotProposedAgainstItself() {
        let proposal = FieldOccasion.proposal(
            context(lifeItems: [visit()])
        )
        #expect(proposal == nil)
    }

    /// The rule must stay silent on the sample couple.
    ///
    /// Not a detail: every gallery screen, every preview and every zone UI
    /// test reads that state, and a new thing Today is willing to say would
    /// change all of them at once. Silence here is the evidence that this
    /// feature only speaks when it has been given something to speak about —
    /// which is the same standard `FieldCaptureSuggestions` is held to.
    @Test
    func theSampleCoupleIsGivenNothingToAnswer() {
        let seeded = FieldTodaySelector.Context(
            now: FieldSampleData.today,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: FieldSampleData.lifeItems,
            clusters: FieldSampleData.clusters,
            horizons: FieldSampleData.horizons,
            heldTopics: [],
            standingRules: []
        )
        #expect(FieldOccasion.proposal(seeded) == nil)
    }
}

// MARK: - This week, and a room that got big

@MainActor
struct FieldTimelyTests {
    private func context(
        lifeItems: [LifeItem] = FieldSampleData.lifeItems,
        clusters: [FieldCluster] = FieldSampleData.clusters
    ) -> FieldTodaySelector.Context {
        FieldTodaySelector.Context(
            now: FieldSampleData.today,
            identity: FieldSampleData.identity,
            partners: FieldSampleData.partners,
            lifeItems: lifeItems,
            clusters: clusters,
            horizons: [],
            heldTopics: [],
            standingRules: []
        )
    }

    @Test
    func thisWeekIsGroupedByOccasionAndStaysShort() {
        let nudges = FieldTimely.nudges(context())
        #expect(!nudges.isEmpty)
        #expect(nudges.count <= FieldTimely.limit)
        // An occasion names itself and the thing it is waiting on, in that
        // thing's own words — the app never invents an errand.
        for nudge in nudges {
            #expect(!nudge.occasion.isEmpty)
        }
    }

    /// Nothing dated, nothing said. An empty heading over an empty week is the
    /// app talking to fill the silence.
    @Test
    func aWeekWithNothingDatedSaysNothing() {
        let undated = FieldSampleData.mentioned
        #expect(FieldTimely.nudges(context(lifeItems: undated, clusters: [])).isEmpty)
    }

    /// Undated things stay quiet forever — this is the whole of what the
    /// Ours/Life split used to buy, now falling out of the ranking itself.
    @Test
    func anUndatedItemNeverReachesTheSurface() {
        for item in FieldSampleData.mentioned {
            let ranked = FieldTodaySelector.rank(context(lifeItems: [item], clusters: []))
            for candidate in ranked {
                #expect(
                    candidate.priority < FieldTodaySelector.surfacingThreshold,
                    "\(item.title) could become the one thing"
                )
            }
        }
    }

    /// A room only groups when it is big *and* there is something honest to
    /// group by. Invented headings are worse than none.
    @Test
    func aRoomGroupsOnlyWhenItIsBig() {
        func film(_ id: String, _ title: String) -> LifeItem {
            LifeItem(
                id: id,
                title: title,
                category: .watchlist,
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

        let few = (0..<4).map { film("f\($0)", "Film \($0)") }
        #expect(FieldGrouping.groups(few, context: context(lifeItems: few)).isEmpty)

        let many = (0..<6).map { film("f\($0)", "Film \($0)") }
            + (0..<4).map { film("s\($0)", "The Bear, season \($0)") }
        let groups = FieldGrouping.groups(many, context: context(lifeItems: many))
        #expect(groups.count == 2)
        #expect(groups.map(\.heading) == ["An evening", "Something longer"])
        #expect(groups.flatMap(\.items).count == many.count)
    }
}

// MARK: - Changing a filed thing
//
// Filing was one-way until these existed: a receipt could be corrected before
// it was sent, and after that an item's word and its day were fixed forever.
// What is asserted here is the part that is not a matter of taste — that a
// move teaches the classifier, that a date cannot survive a move into a
// category which does not carry dates, and that the app keeps its promise
// about the calendar it does not own.

@MainActor
struct FieldItemEditingTests {
    /// The seeded couple's grocery item: Food, dated, with a cut-off.
    private let dated = "groceries"

    @Test
    func removingTakesItOffEveryScreen() {
        let store = FieldStore()
        #expect(store.state.lifeItems.contains { $0.id == dated })

        store.remove(dated)

        #expect(!store.state.lifeItems.contains { $0.id == dated })
    }

    /// An upgrade preserves the read-only boundary for rows left by calendar
    /// builds that predate private intake.
    @Test
    func legacyExternalRowsAreRefused() {
        let imported = LifeItem(
            id: "cal:ABC-123",
            title: "Dentist",
            // Legacy rows were never a category of their own.
            category: .notes,
            owner: .shared,
            dueOn: FieldSampleData.today,
            closesAt: nil,
            clusterID: nil,
            source: .imported,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        )
        var seeded = FieldState.seed
        seeded.lifeItems.append(imported)
        let store = FieldStore(state: seeded)

        store.remove(imported.id)
        store.refile(imported.id, to: .home)
        store.redate(imported.id, to: nil)

        let after = store.state.lifeItems.first { $0.id == imported.id }
        #expect(after == imported)
    }

    /// Moving something by hand is the clearest signal the app ever gets about
    /// where this shape of thing belongs. Dropping it would make the same
    /// mistake again next week.
    @Test
    func movingSomethingTeachesTheClassifier() {
        let store = FieldStore()
        let before = store.state.corrections.count

        store.refile(dated, to: .home)

        #expect(store.state.corrections.count == before + 1)
        let correction = store.state.corrections.last
        #expect(correction?.original == .food)
        #expect(correction?.corrected == .home)
        #expect(
            store.state.lifeItems.first { $0.id == self.dated }?.category
                == .home
        )
    }

    /// Moving into the same category is not a correction, and recording one
    /// would teach the classifier a lesson nobody meant to give it.
    @Test
    func movingNowhereRecordsNothing() {
        let store = FieldStore()
        let before = store.state.corrections.count

        store.refile(dated, to: .food)

        #expect(store.state.corrections.count == before)
    }

    /// A film is not due on Thursday. `LifeCategory.dateless` is the rule, and
    /// `FieldClassifier.correct` applies it to a receipt — a move has to apply
    /// it to a filed item too, or the date survives into a category that
    /// cannot express one.
    @Test
    func movingIntoADatelessCategoryDropsTheDay() {
        let store = FieldStore()
        #expect(store.state.lifeItems.first { $0.id == dated }?.dueOn != nil)

        store.refile(dated, to: .watchlist)

        let item = store.state.lifeItems.first { $0.id == dated }
        #expect(item?.dueOn == nil)
        #expect(item?.closesAt == nil)
    }

    /// Taking the date off has to take the cut-off with it. A window that
    /// closes at 9pm on no particular day is not a thing, and leaving it
    /// behind would keep the item at the top of Today with nothing behind it —
    /// `LifeItem.pressure(now:)` floors a `closesAt` at 0.85 regardless of
    /// `dueOn`.
    @Test
    func clearingTheDateClearsTheCutOff() {
        let store = FieldStore()

        store.redate(dated, to: nil)

        let item = store.state.lifeItems.first { $0.id == dated }
        #expect(item?.dueOn == nil)
        #expect(item?.closesAt == nil)
        #expect(item?.pressure(now: store.now) == 0.08)
    }

    /// A date is stored as the start of its day, so two items set to "today"
    /// from different hours land on the same calendar cell.
    @Test
    func aNewDateIsAnchoredToTheStartOfItsDay() {
        let store = FieldStore()
        let calendar = Calendar.gregorianUS

        store.redate(dated, to: store.now)

        let dueOn = store.state.lifeItems.first { $0.id == dated }?.dueOn
        #expect(dueOn == calendar.startOfDay(for: store.now))
    }

    /// Dating something that cannot carry a date is refused rather than
    /// silently accepted — the same refusal `toggleForToday` makes.
    @Test
    func adatelessCategoryCannotBeDated() {
        let store = FieldStore()
        guard let film = store.state.lifeItems.first(
            where: { $0.category == .watchlist }
        ) else {
            Issue.record("expected the seeded couple to have a watchlist")
            return
        }

        store.redate(film.id, to: store.now)

        #expect(store.state.lifeItems.first { $0.id == film.id }?.dueOn == nil)
    }

    /// A name the couple supplies, not one the app offered. Refused rather
    /// than mangled when it is not a heading.
    @Test
    func movingToANamedCategory() {
        let store = FieldStore()

        #expect(store.refile(dated, toNewCategory: "garden") == LifeCategory(named: "garden"))
        #expect(
            store.state.lifeItems.first { $0.id == self.dated }?.category.word
                == "Garden"
        )

        #expect(
            store.refile(dated, toNewCategory: "the whole of everything else")
                == nil
        )
    }
}

// MARK: - Getting rid of a group
//
// The two halves of this are different in kind, and the tests are grouped to
// keep that visible.
//
// Deleting a *grown* group needs no new concept: categories are derived from
// the items that carry them, so moving the items out is the deletion.
// Renaming is the same act with a different destination.
//
// Putting a *built-in* away is the first time a category is stored anywhere.
// Everything asserted about it is about keeping that a display fact — the
// classifier, Today, and search must all go on seeing a group that is no
// longer drawn, or "put away" has quietly become "muted" and things people
// wrote down stop reaching them.

@MainActor
struct FieldGroupTests {
    /// A category with three things in it, one of them finished, plus a dated
    /// one — enough to catch every rule `moveGroup` applies.
    private func storeWithAGrownGroup() -> FieldStore {
        var state = FieldState.empty(
            nameA: "Ryan",
            nameB: "Dylan",
            now: FieldSampleData.today
        )
        let filters = LifeCategory(rawValue: "airfilters")
        state.lifeItems = [
            LifeItem(
                id: "f1",
                title: "Order the HEPA filter",
                category: filters,
                owner: .a,
                dueOn: FieldSampleData.today,
                source: .captured,
                isTimeCritical: false,
                isDone: false
            ),
            LifeItem(
                id: "f2",
                title: "Check the bedroom one",
                category: filters,
                owner: .b,
                source: .captured,
                isTimeCritical: false,
                isDone: false
            ),
            LifeItem(
                id: "f3",
                title: "Replaced the kitchen one",
                category: filters,
                owner: .a,
                source: .captured,
                isTimeCritical: false,
                isDone: true
            ),
            LifeItem(
                id: "c1",
                title: "Book the vet",
                category: .care,
                owner: .a,
                source: .captured,
                isTimeCritical: false,
                isDone: false
            ),
        ]
        return FieldStore(state: state, now: FieldSampleData.today)
    }

    private var filters: LifeCategory { LifeCategory(rawValue: "airfilters") }

    // MARK: Emptying is deleting

    /// The whole of "delete a grown group". Nothing else had to be built.
    @Test
    func movingAGroupDissolvesIt() {
        let store = storeWithAGrownGroup()
        #expect(store.lifeCategories.contains(filters))

        let moved = store.moveGroup(filters, to: .home)

        #expect(moved == 3)
        #expect(
            !store.lifeCategories.contains(filters),
            "the word survived its last item"
        )
        #expect(store.openItems(in: .home).count == 2)
    }

    /// A finished errand left behind would keep a deleted group alive the
    /// moment somebody reopened it — the couple's tidy-up coming back weeks
    /// later carrying one item.
    @Test
    func movingAGroupCarriesFinishedThingsToo() {
        let store = storeWithAGrownGroup()

        store.moveGroup(filters, to: .home)

        let done = store.state.lifeItems.first { $0.id == "f3" }
        #expect(done?.category == .home)
        #expect(done?.isDone == true)
    }

    /// The decision this whole feature turns on. `refile` records a correction
    /// because moving *one* thing is a lesson; thirty from a single gesture is
    /// thirty lessons nobody gave, and the next month of filing would be
    /// shaped by a tidy-up.
    @Test
    func movingAGroupTeachesTheClassifierNothing() {
        let store = storeWithAGrownGroup()
        let before = store.state.corrections.count

        store.moveGroup(filters, to: .home)

        #expect(store.state.corrections.count == before)
    }

    /// The same rule `refile` applies, applied in bulk: a film is not due on
    /// Thursday.
    @Test
    func movingAGroupIntoADatelessOneDropsTheDates() {
        let store = storeWithAGrownGroup()
        #expect(store.state.lifeItems.first { $0.id == "f1" }?.dueOn != nil)

        store.moveGroup(filters, to: .watchlist)

        let item = store.state.lifeItems.first { $0.id == "f1" }
        #expect(item?.dueOn == nil)
        #expect(item?.closesAt == nil)
    }

    /// Renaming is the same write. Refused rather than mangled when the name
    /// is not a heading — and refusing must leave the group exactly as it was,
    /// not half-moved.
    @Test
    func renamingAGroupKeepsEverythingInIt() {
        let store = storeWithAGrownGroup()

        let renamed = store.moveGroup(filters, toNewCategory: "filters")
        #expect(renamed == LifeCategory(named: "filters"))
        #expect(store.state.lifeItems.filter {
            $0.category == LifeCategory(rawValue: "filters")
        }.count == 3)
        #expect(!store.lifeCategories.contains(self.filters))

        #expect(
            store.moveGroup(
                LifeCategory(rawValue: "filters"),
                toNewCategory: "the whole of everything else"
            ) == nil
        )
        #expect(store.state.lifeItems.filter {
            $0.category == LifeCategory(rawValue: "filters")
        }.count == 3)
    }

    /// The sheet names a number before anybody commits to it, so that number
    /// has to be the set the move actually touches. An imported calendar event
    /// sits in a category and does not travel — the app does not own somebody
    /// else's calendar — and a sheet offering to move four things while moving
    /// three is the app miscounting a couple's own list back to them.
    @Test
    func theCountOnOfferIsTheCountThatMoves() {
        var state = FieldState.empty(
            nameA: "Ryan",
            nameB: "Dylan",
            now: FieldSampleData.today
        )
        state.lifeItems = [
            LifeItem(
                id: "f1",
                title: "Order the HEPA filter",
                category: filters,
                owner: .a,
                source: .captured,
                isTimeCritical: false,
                isDone: false
            ),
            LifeItem(
                id: "cal:standing-desk",
                title: "Delivery window",
                category: filters,
                owner: .a,
                source: .captured,
                isTimeCritical: false,
                isDone: false
            ),
        ]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        #expect(store.movableCount(in: filters) == 1)
        #expect(store.moveGroup(filters, to: .home) == 1)
        #expect(
            store.state.lifeItems.first { $0.id == "cal:standing-desk" }?
                .category == self.filters,
            "a legacy external row moved categories"
        )
    }

    /// A group move changes no title, so a fingerprint of titles alone would
    /// leave both the source and the destination describing lists they no
    /// longer hold — and the stale sentence would survive every relaunch.
    @Test
    func movingAGroupInvalidatesTheSubtitles() {
        let store = storeWithAGrownGroup()
        let before = store.subtitleRefreshKey

        store.moveGroup(filters, to: .home)

        #expect(store.subtitleRefreshKey != before)
    }

    // MARK: Putting a built-in away

    @Test
    func puttingAGroupAwayTakesItOffLifeAndNowhereElse() {
        let store = storeWithAGrownGroup()
        #expect(store.putAway(.money))

        #expect(!store.categoryOrder.contains(.money))
        #expect(!store.visibleCategories.contains(.money))
        // The sibling, not a filter on it. Everything that decides *where a
        // thing belongs* still sees every category.
        #expect(store.lifeCategories.contains(.money))
        #expect(store.putAwayCategories == [.money])
        #expect(store.isPutAway(.money))
    }

    /// A container never sets its contents down with it. Care has an open item
    /// here, so the whole act is refused rather than half-done.
    @Test
    func aGroupWithThingsInItCannotBePutAway() {
        let store = storeWithAGrownGroup()

        #expect(store.putAway(.care) == false)
        #expect(store.visibleCategories.contains(.care))
        #expect(store.state.hiddenCategories.isEmpty)
    }

    /// A grown category is deleted by being emptied. Hiding one would leave
    /// its items filed under a word that exists nowhere on screen.
    @Test
    func aGrownGroupCannotBePutAway() {
        let store = storeWithAGrownGroup()

        #expect(store.putAway(filters) == false)
        #expect(store.state.hiddenCategories.isEmpty)
    }

    /// The guard that stands in for the CHECK constraint the migration
    /// deliberately does not have. A row naming a grown category — stale, hand
    /// edited, or from a future bug — must be inert rather than able to take a
    /// live list off the screen while its contents go on falling due.
    @Test
    func aStoredHideOfAGrownGroupIsIgnored() {
        var state = FieldState.empty(
            nameA: "Ryan",
            nameB: "Dylan",
            now: FieldSampleData.today
        )
        state.lifeItems = [
            LifeItem(
                id: "f1",
                title: "Order the HEPA filter",
                category: LifeCategory(rawValue: "airfilters"),
                owner: .a,
                source: .captured,
                isTimeCritical: false,
                isDone: false
            ),
        ]
        state.hiddenCategories = ["airfilters"]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        #expect(store.visibleCategories.contains(self.filters))
        #expect(store.putAwayCategories.isEmpty)
    }

    @Test
    func bringingAGroupBackPutsTheWordBack() {
        let store = storeWithAGrownGroup()
        store.putAway(.money)

        store.bringBack(.money)

        #expect(store.visibleCategories.contains(.money))
        #expect(store.putAwayCategories.isEmpty)
    }

    // MARK: What a hidden group must go on doing

    /// The line between "put away" and "muted". Today reads items and has no
    /// notion of a category at all — this is here so that stays true, because
    /// the day somebody filters Today by `visibleCategories` a vet appointment
    /// disappears.
    @Test
    func todayStillSurfacesThingsFromAGroupThatIsPutAway() {
        var state = FieldState.empty(
            nameA: "Ryan",
            nameB: "Dylan",
            now: FieldSampleData.today
        )
        state.lifeItems = [
            LifeItem(
                id: "m1",
                title: "Pay the rent",
                category: .money,
                owner: .a,
                dueOn: FieldSampleData.today,
                source: .captured,
                isTimeCritical: true,
                isDone: false
            ),
        ]
        // Written straight into state: `putAway` refuses while the item is
        // there, and it is the item that has to still reach them.
        state.hiddenCategories = ["money"]
        let store = FieldStore(state: state, now: FieldSampleData.today)

        #expect(!store.visibleCategories.contains(.money))
        #expect(
            store.todayCandidates.contains {
                if case .life(let item) = $0.origin { return item.id == "m1" }
                return false
            },
            "putting a group away stopped its items reaching Today"
        )
    }

    /// Filing one thing into a put-away group brings it back too, and the
    /// route matters: `refile` takes any category, so this is what a partner's
    /// move arriving over realtime does. A heading standing over something is
    /// not away.
    @Test
    func refilingOneThingIntoAGroupThatIsPutAwayBringsItBack() {
        let store = storeWithAGrownGroup()
        store.putAway(.money)

        store.refile("f1", to: .money)

        #expect(!store.isPutAway(.money))
        #expect(store.visibleCategories.contains(.money))
    }

    /// The picker is presentation, so it follows Life. The way back to a
    /// put-away group is the row at the foot of Life, not a chip that offers
    /// it as though it were an ordinary destination.
    @Test
    func theCorrectionPickerDoesNotOfferAGroupThatIsPutAway() {
        let store = storeWithAGrownGroup()
        store.putAway(.money)

        #expect(!store.correctionCategories.contains(.money))
    }

    // MARK: Coming back

    @Test
    func sendingSomethingIntoAGroupThatIsPutAwayBringsItBack() {
        let store = storeWithAGrownGroup()
        store.putAway(.money)

        store.captureDraft = "pay the rent"
        store.submitCapture()
        guard var receipt = store.lastReceipt else {
            Issue.record("expected a receipt")
            return
        }
        receipt.category = .money
        store.lastReceipt = receipt

        // Reading the receipt changes nothing. The group is still away right
        // up until the moment the thing is actually filed into it.
        #expect(store.isPutAway(.money))

        store.send()

        #expect(!store.isPutAway(.money))
        #expect(store.lastRevival == .money)
        #expect(store.visibleCategories.contains(.money))
    }

    /// The consequence of putting revival in `send` rather than in `classify`.
    /// Somebody who reads "sending this will bring Care back" and decides they
    /// meant somewhere else has changed their mind about the capture, not
    /// about the group.
    @Test
    func correctingAwayFromAGroupThatIsPutAwayLeavesItPutAway() {
        let store = storeWithAGrownGroup()
        store.putAway(.money)

        store.captureDraft = "pay the rent"
        store.submitCapture()
        guard var receipt = store.lastReceipt else {
            Issue.record("expected a receipt")
            return
        }
        receipt.category = .money
        store.lastReceipt = receipt

        store.beginCorrection()
        store.correct(to: .home)
        store.send()

        #expect(store.isPutAway(.money))
        #expect(store.lastRevival == nil)
        #expect(!store.visibleCategories.contains(.money))
    }

    /// Moving a whole group into one that was put away brings it back for the
    /// same reason a capture does: a heading standing over things is not away.
    @Test
    func movingAGroupIntoOneThatIsPutAwayBringsItBack() {
        let store = storeWithAGrownGroup()
        store.putAway(.money)

        store.moveGroup(filters, to: .money)

        #expect(!store.isPutAway(.money))
        #expect(store.visibleCategories.contains(.money))
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
