//
//  CaptureIntentTests.swift
//  WETests
//
//  The walkthrough's sentences, exactly as typed. A plan is never turned into
//  a search, a date somebody typed is never thrown away, and a dated trip is
//  three readings of one row: Trips, the calendar, and Us.
//

import Foundation
import Testing
@testable import WE

@MainActor private let calendar = Calendar.gregorianUS

/// Wednesday, August 13, 2025.
@MainActor private let now = FieldSampleData.today

@MainActor private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    FieldSampleData.date(year, month, day)
}

// MARK: - Save or search

@MainActor
struct CaptureLookupIntentTests {
    @Test
    func remindMeToIsSavedNotSearched() {
        #expect(!FieldLookupEngine.isLookup("remind me to call mom tomorrow"))
        #expect(!FieldLookupEngine.isLookup("Remind me to book the vet"))
    }

    @Test
    func remindMeWhatIsStillASearch() {
        #expect(FieldLookupEngine.isLookup("remind me what we got dad"))
        #expect(FieldLookupEngine.isLookup("remind me when the lease ends"))
        #expect(FieldLookupEngine.isLookup("what did we decide about tahoe"))
        #expect(FieldLookupEngine.isLookup("find the hotel we liked"))
    }

    /// Something to do, on a day, is a plan however it opens.
    @Test
    func anErrandOnADayIsNeverASearch() {
        #expect(!FieldLookupEngine.isLookup("find a sitter for saturday"))
        #expect(!FieldLookupEngine.isLookup("find a sitter nov 1"))
    }

    @Test
    func remindMeToCallMomTomorrowLandsOnTomorrow() {
        let receipt = FieldClassifier.classify(
            "remind me to call mom tomorrow",
            context: classifierContext
        )
        #expect(receipt.category == .care)
        #expect(receipt.title == "Call mom")
        #expect(receipt.dueOn.map { calendar.isDate($0, inSameDayAs: day(2025, 8, 14)) } == true)
    }
}

// MARK: - Written-out dates

@MainActor
struct FieldNamedDateTests {
    @Test
    func aSpanWithAHyphen() {
        let result = FieldPhrasing.tidy("Bermuda nov 1-5", now: now)
        #expect(result.title == "Bermuda")
        #expect(result.dueOn == day(2025, 11, 1))
        #expect(result.endsOn == day(2025, 11, 5))
    }

    @Test
    func aSpanInWords() {
        let result = FieldPhrasing.tidy("Bermuda from november 1st to 5th", now: now)
        #expect(result.title == "Bermuda")
        #expect(result.dueOn == day(2025, 11, 1))
        #expect(result.endsOn == day(2025, 11, 5))
    }

    @Test
    func aSpanAcrossMonths() {
        let result = FieldPhrasing.tidy("lisbon nov 28 to dec 3", now: now)
        #expect(result.title == "Lisbon")
        #expect(result.dueOn == day(2025, 11, 28))
        #expect(result.endsOn == day(2025, 12, 3))
    }

    @Test
    func aNumericSpan() {
        let result = FieldPhrasing.tidy("Tulum 11/1-11/5", now: now)
        #expect(result.title == "Tulum")
        #expect(result.dueOn == day(2025, 11, 1))
        #expect(result.endsOn == day(2025, 11, 5))
    }

    @Test
    func aSingleDayHasNoEnd() {
        let result = FieldPhrasing.tidy("dinner with the Parks oct 18", now: now)
        #expect(result.title == "Dinner with the Parks")
        #expect(result.dueOn == day(2025, 10, 18))
        #expect(result.endsOn == nil)
    }

    @Test
    func anOrdinalIsThisMonthOrNext() {
        #expect(FieldPhrasing.tidy("pay rent on the 1st", now: now).dueOn == day(2025, 9, 1))
        #expect(FieldPhrasing.tidy("pay rent on the 1st", now: now).title == "Pay rent")
        #expect(FieldPhrasing.tidy("haircut the 20th", now: now).dueOn == day(2025, 8, 20))
    }

    /// Nobody plans a trip for last February.
    @Test
    func aDateThatHasPassedIsNextYears() {
        let result = FieldPhrasing.tidy("ski trip feb 3 to 8", now: now)
        #expect(result.dueOn == day(2026, 2, 3))
        #expect(result.endsOn == day(2026, 2, 8))
    }

    @Test
    func aWrittenDateBeatsAWeekday() {
        let result = FieldPhrasing.tidy("dinner fri nov 7", now: now)
        #expect(result.dueOn == day(2025, 11, 7))
        #expect(result.title == "Dinner")
    }

    @Test
    func thingsThatAreNotDatesAreLeftAlone() {
        let flour = FieldPhrasing.tidy("1/2 cup flour", now: now)
        #expect(flour.dueOn == nil)
        #expect(flour.title == "1/2 cup flour")

        let people = FieldPhrasing.tidy("table for 2-3 people", now: now)
        #expect(people.dueOn == nil)
        #expect(people.title == "Table for 2-3 people")

        #expect(FieldPhrasing.tidy("maybe we march", now: now).dueOn == nil)
        #expect(FieldPhrasing.tidy("concert feb 31", now: now).dueOn == nil)
    }

    @Test
    func spansAreSaidBackPlainly() {
        #expect(FieldPhrasing.spanLabel(day(2025, 11, 1), day(2025, 11, 5)) == "Nov 1 to 5")
        #expect(FieldPhrasing.spanLabel(day(2025, 11, 28), day(2025, 12, 3)) == "Nov 28 to Dec 3")
        #expect(FieldPhrasing.spanLabel(day(2025, 11, 1), nil) == "Nov 1")
    }
}

// MARK: - Where it goes

@MainActor
struct FieldDatedRoutingTests {
    @Test
    func bermudaWithDatesIsATrip() {
        let receipt = FieldClassifier.classify("Bermuda nov 1-5", context: classifierContext)
        #expect(receipt.category == .trips)
        #expect(receipt.dueOn == day(2025, 11, 1))
        #expect(receipt.endsOn == day(2025, 11, 5))
        #expect(receipt.reasoning.contains("Nov 1 to 5"))
    }

    @Test
    func aFilmIsStillAFilm() {
        #expect(FieldClassifier.classify("Past Lives", context: classifierContext).category == .watchlist)
    }

    /// Travel is Trips, not a second list beside it.
    @Test
    func aFlightIsATrip() {
        let receipt = FieldClassifier.classify("flight to lisbon dec 3", context: classifierContext)
        #expect(receipt.category == .trips)
        #expect(receipt.dueOn == day(2025, 12, 3))
    }

    /// The note Ryan wanted on the calendar: an event with no list of its own.
    @Test
    func aDatedEventLandsOnTheCalendar() {
        let receipt = FieldClassifier.classify("Parks gala oct 18", context: classifierContext)
        #expect(receipt.category == .notes)
        #expect(receipt.dueOn == day(2025, 10, 18))
    }

    @Test
    func aDatedDinnerKeepsItsDay() {
        let receipt = FieldClassifier.classify("dinner with the Parks oct 18", context: classifierContext)
        #expect(receipt.category == .food)
        #expect(receipt.dueOn == day(2025, 10, 18))
    }

    @Test
    func movingIntoTripsKeepsTheSpan() {
        let receipt = FieldClassifier.classify("Bermuda nov 1-5", context: classifierContext)
        var wrong = receipt
        wrong.category = .watchlist
        wrong.dueOn = nil
        wrong.endsOn = nil
        let moved = FieldClassifier.correct(wrong, to: .trips, context: classifierContext).receipt
        #expect(moved.dueOn == day(2025, 11, 1))
        #expect(moved.endsOn == day(2025, 11, 5))
    }
}

// MARK: - Trips, calendar and Us

@MainActor
struct FieldDatedTripTests {
    private func capture(_ text: String, privately: Bool = false) -> (FieldStore, LifeItem?) {
        let store = FieldStore()
        store.captureDraft = text
        store.submitCapture()
        if privately { store.togglePrivate() }
        let id = store.lastReceipt?.id
        store.send()
        return (store, store.state.lifeItems.first { $0.id == id })
    }

    @Test
    func aDatedTripCarriesItsSpan() {
        let (_, item) = capture("Bermuda nov 1-5")
        #expect(item?.category == .trips)
        #expect(item?.timing?.startDay == "2025-11-01")
        #expect(item?.timing?.endDay == "2025-11-05")
        #expect(item?.objectTiming?.includes(day(2025, 11, 3), calendar: calendar) == true)
        #expect(item.map(FieldItemPurpose.resolve) == .plan)
    }

    @Test
    func aSharedDatedTripIsAHorizon() {
        let (store, item) = capture("Bermuda nov 1-5")
        let horizon = store.tripHorizons.first { $0.linkedLifeItemIDs == [item?.id ?? ""] }
        #expect(horizon?.title == "Bermuda")
        #expect(horizon?.window == "Nov 1 to 5")
        #expect(horizon?.targetDate == day(2025, 11, 1))
        #expect(store.horizons.contains { $0.id == horizon?.id })
        // Derived, never stored.
        #expect(!store.state.horizons.contains { $0.id == horizon?.id })
    }

    /// Us is shared furniture. A private trip is on its owner's calendar only.
    @Test
    func anOnlyMeTripIsNotAHorizon() {
        let (store, item) = capture("Bermuda nov 1-5", privately: true)
        #expect(item?.visibility == .private)
        #expect(item?.objectTiming?.includes(day(2025, 11, 3), calendar: calendar) == true)
        #expect(!store.tripHorizons.contains { $0.linkedLifeItemIDs.contains(item?.id ?? "") })
    }

    @Test
    func movingTheTripMovesEverythingAndKeepsItsLength() {
        let (store, item) = capture("Bermuda nov 1-5")
        guard let id = item?.id else { Issue.record("not filed"); return }
        store.redate(id, to: day(2025, 11, 10))
        let moved = store.state.lifeItems.first { $0.id == id }
        #expect(moved?.timing?.startDay == "2025-11-10")
        #expect(moved?.timing?.endDay == "2025-11-14")
        #expect(store.tripHorizons.first { $0.linkedLifeItemIDs == [id] }?.window == "Nov 10 to 14")
    }

    @Test
    func removingTheTripRemovesTheHorizon() {
        let (store, item) = capture("Bermuda nov 1-5")
        guard let id = item?.id else { Issue.record("not filed"); return }
        #expect(store.remove(id))
        #expect(!store.tripHorizons.contains { $0.linkedLifeItemIDs.contains(id) })
    }

    /// A horizon somebody already shaped around the trip wins.
    @Test
    func aShapedHorizonIsNotDuplicated() {
        var trip = LifeItem(
            id: "bermuda", title: "Bermuda", category: .trips, owner: .a,
            dueOn: day(2025, 11, 1), closesAt: nil, clusterID: nil,
            source: .captured, detail: nil, isTimeCritical: false, isDone: false
        )
        trip.timing = WEObjectTiming(precision: .day, startDay: "2025-11-01", endDay: "2025-11-05")
        var state = FieldState.seed
        state.lifeItems.append(trip)
        #expect(FieldStore(state: state).tripHorizons.contains { $0.linkedLifeItemIDs == ["bermuda"] })

        state.horizons.append(
            FieldHorizon(
                id: "shaped", title: "Bermuda", window: nil, owner: .shared,
                isPrimary: false, thesis: nil, targetDate: nil,
                linkedLifeItemIDs: ["bermuda"], openQuestion: nil
            )
        )
        let store = FieldStore(state: state)
        #expect(!store.tripHorizons.contains { $0.linkedLifeItemIDs.contains("bermuda") })
        #expect(store.horizons.filter { $0.linkedLifeItemIDs.contains("bermuda") }.count == 1)
    }

    /// Once the last day has gone by, it leaves Us. The trip stays in Trips.
    @Test
    func aFinishedTripLeavesUs() {
        var trip = LifeItem(
            id: "maine", title: "Maine", category: .trips, owner: .a,
            dueOn: day(2025, 8, 1), closesAt: nil, clusterID: nil,
            source: .captured, detail: nil, isTimeCritical: false, isDone: false
        )
        trip.timing = WEObjectTiming(precision: .day, startDay: "2025-08-01", endDay: "2025-08-05")
        var state = FieldState.seed
        state.lifeItems.append(trip)
        let store = FieldStore(state: state)
        #expect(!store.tripHorizons.contains { $0.linkedLifeItemIDs.contains("maine") })
        #expect(store.state.lifeItems.contains { $0.id == "maine" })
    }

    @Test
    func anUndatedTripIsStillAskedAbout() {
        let (_, item) = capture("Japan someday maybe")
        #expect(item?.category == .trips)
        #expect(item?.objectTiming == nil)
        #expect(item.map(FieldItemPurpose.resolve) == .reference)
    }

    @Test
    func theComposerSaysTheDayBackBeforeSending() {
        let store = FieldStore()
        #expect(store.previewWhen(for: "Bermuda nov 1-5", in: .trips) == "Nov 1 to 5")
        #expect(store.previewWhen(for: "Bermuda nov 1-5", in: .watchlist) == nil)
        #expect(store.previewWhen(for: "Bermuda", in: .trips) == nil)
    }
}

@MainActor
private var classifierContext: FieldClassifier.Context {
    FieldClassifier.Context(
        identity: FieldSampleData.identity,
        speaker: .a,
        now: now,
        lifeItems: FieldSampleData.lifeItems,
        horizons: FieldSampleData.horizons,
        rhythms: FieldSampleData.rhythms,
        corrections: [],
        partners: FieldSampleData.partners
    )
}
