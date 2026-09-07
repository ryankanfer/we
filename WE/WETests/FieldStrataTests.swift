import Foundation
import Testing
@testable import WE

/// Life's four bands (§15b), and the collapse that is "the app's main
/// adaptive behaviour" (§16a).
///
/// These assert the *rule*, not the rendering. What separates the bands on
/// screen is structure — rows, then a run of subjects, then a bare count — and
/// that is the view's business. What matters here is that a thing lands in
/// exactly one band, and in the right one.
struct FieldStrataTests {
    private static let now = FieldSampleData.date(2025, 8, 13)

    private static func item(
        _ id: String,
        title: String = "Something",
        category: LifeCategory = .care,
        dueOn: Date? = nil,
        closesAt: Date? = nil,
        isTimeCritical: Bool = false,
        isDone: Bool = false,
        reachedOutAt: Date? = nil
    ) -> LifeItem {
        LifeItem(
            id: id,
            title: title,
            category: category,
            owner: .a,
            dueOn: dueOn,
            closesAt: closesAt,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: isTimeCritical,
            isDone: isDone,
            reachedOutAt: reachedOutAt
        )
    }

    private static func day(_ offset: Int) -> Date {
        Calendar.gregorianUS.date(byAdding: .day, value: offset, to: now)!
    }

    // MARK: What lands where

    @Test
    func aDatedThingInsideTheWeekIsThisWeek() {
        for offset in [0, 1, 6, 7] {
            let band = FieldStrata.band(
                for: Self.item("x", dueOn: Self.day(offset)),
                now: Self.now
            )
            #expect(band == .thisWeek, "day \(offset) should be this week")
        }
    }

    /// A date further out than the week is not yet asking for anything. It is
    /// deliberately *not* "fading" — fading is about a date that has passed.
    @Test
    func aDateBeyondTheWeekIsNoHurryRatherThanFading() {
        let band = FieldStrata.band(
            for: Self.item("x", dueOn: Self.day(30)),
            now: Self.now
        )
        #expect(band == .noHurry)
    }

    /// Recently overdue still presses. This is the difference between an app
    /// that reminds you and one that nags: the thing does not leave the top
    /// band the moment its date slips.
    @Test
    func recentlyOverdueStillPresses() {
        for offset in [-1, -13, -14] {
            let band = FieldStrata.band(
                for: Self.item("x", dueOn: Self.day(offset)),
                now: Self.now
            )
            #expect(band == .thisWeek, "day \(offset) should still press")
        }
    }

    /// "The air filter has been two months over and nothing broke — that is
    /// upkeep, not an emergency." The app stops asking rather than asking
    /// louder, which is the same judgement `LifeItem.pressure` already makes.
    @Test
    func longOverdueFadesRatherThanEscalating() {
        let band = FieldStrata.band(
            for: Self.item("x", dueOn: Self.day(-60)),
            now: Self.now
        )
        #expect(band == .fading)
    }

    /// Fading is decided before the verb is read. Otherwise a thing written in
    /// March and never done would still be reported as something a plumber is
    /// actively getting to.
    @Test
    func aLongOverdueOutwardActFadesRatherThanWaiting() {
        let band = FieldStrata.band(
            for: Self.item("x", title: "Call the plumber", dueOn: Self.day(-60)),
            now: Self.now
        )
        #expect(band == .fading)
    }

    /// Writing "call the plumber" down is not calling the plumber.
    ///
    /// This is the assertion that used to say the opposite. The band was
    /// decided by the verb the title happened to contain, so a thing nobody
    /// had done was reported back to the couple as something a third party was
    /// already getting to — the app asserting a fact about the world that
    /// nobody had given it.
    @Test
    func anUnsentOutwardActIsStillOursUntilSomebodySaysOtherwise() {
        for title in [
            "Call the vet",
            "Email the landlord",
            "Book the restaurant",
        ] {
            let band = FieldStrata.band(
                for: Self.item("x", title: title),
                now: Self.now
            )
            #expect(
                band == .noHurry,
                "\"\(title)\" is unsent, so it is still ours"
            )
        }
    }

    /// And this is what does put it there: a person's own confirmation.
    @Test
    func aConfirmedOutreachWaitsOnSomeoneElse() {
        let band = FieldStrata.band(
            for: Self.item(
                "x",
                title: "Call the vet",
                reachedOutAt: Self.day(-1)
            ),
            now: Self.now
        )
        #expect(band == .waitingOnSomeoneElse)
    }

    /// It is the confirmation and not the wording. Something with no outward
    /// verb in it at all still waits once somebody says they reached out, and
    /// the reverse case above still does not.
    @Test
    func confirmedOutreachDoesNotDependOnTheWordsInTheTitle() {
        let band = FieldStrata.band(
            for: Self.item(
                "x",
                title: "The thing about the roof",
                reachedOutAt: Self.day(-1)
            ),
            now: Self.now
        )
        #expect(band == .waitingOnSomeoneElse)
    }

    /// Taking it back returns it to wherever its date puts it. Nothing else
    /// about the item changed, so nothing else about its filing may.
    @Test
    func takingTheOutreachBackReturnsItToUs() {
        var item = Self.item(
            "x",
            title: "Call the vet",
            reachedOutAt: Self.day(-1)
        )
        #expect(FieldStrata.band(for: item, now: Self.now) == .waitingOnSomeoneElse)

        item.reachedOutAt = nil
        #expect(FieldStrata.band(for: item, now: Self.now) == .noHurry)
    }

    /// Paying and ordering were never waiting on anyone, and still are not.
    @Test
    func aThingThatIsOursToDoIsNoHurryNotWaiting() {
        for title in ["Order the air filters", "Pay the water bill", "Steak"] {
            let band = FieldStrata.band(
                for: Self.item("x", title: title),
                now: Self.now
            )
            #expect(band == .noHurry, "\"\(title)\" is ours to finish")
        }
    }

    /// A window closing inside the day is what "this week" means at its
    /// sharpest, and it outranks whatever date sits under it.
    @Test
    func aClosingWindowIsThisWeekWhateverTheDateSaysBeneathIt() {
        let band = FieldStrata.band(
            for: Self.item(
                "x",
                dueOn: Self.day(90),
                closesAt: Self.day(0)
            ),
            now: Self.now
        )
        #expect(band == .thisWeek)
    }

    /// A window that closed is not a window. The comparison here used to be
    /// one-sided, so −500 satisfied it exactly as readily as 2 and a window
    /// that shut a year ago presented itself as still open.
    @Test
    func aWindowThatClosedIsNotReportedAsStillOpen() {
        let item = Self.item("x", closesAt: Self.day(-365))
        #expect(FieldStrata.windowHasClosed(item, now: Self.now))
        #expect(!FieldStrata.windowHasClosed(
            Self.item("y", closesAt: Self.day(0)),
            now: Self.now
        ))
    }

    /// And it is not quietly reduced to a number either. Fading renders as a
    /// bare count; a missed hard commitment counted rather than asked about is
    /// the app deciding on somebody's behalf that it stopped mattering.
    @Test
    func aMissedHardCommitmentStaysInRowsRatherThanFading() {
        for offset in [-1, -15, -365] {
            let band = FieldStrata.band(
                for: Self.item("x", closesAt: Self.day(offset)),
                now: Self.now
            )
            #expect(band == .thisWeek, "a window \(offset) days gone needs a person")
        }
    }

    /// Age alone cannot establish that something stopped mattering. The air
    /// filter fades; a thing its owner marked time-critical does not.
    @Test
    func longOverdueFadesOnlyWhenItWasNeverFixed() {
        #expect(
            FieldStrata.band(
                for: Self.item("upkeep", dueOn: Self.day(-60)),
                now: Self.now
            ) == .fading
        )
        #expect(
            FieldStrata.band(
                for: Self.item(
                    "fixed",
                    dueOn: Self.day(-60),
                    isTimeCritical: true
                ),
                now: Self.now
            ) == .thisWeek
        )
    }

    /// Fading never means done. Whatever band a thing is in, it is still open
    /// and still on the page.
    @Test
    func nothingIsMarkedFinishedByGettingOld() {
        let sorted = FieldStrata.sort(
            [
                Self.item("old", dueOn: Self.day(-60)),
                Self.item("closed", closesAt: Self.day(-90)),
            ],
            now: Self.now
        )
        #expect(sorted.total == 2)
        #expect(sorted.all.allSatisfy { !$0.isDone })
    }

    // MARK: The sort as a whole

    @Test
    func everyOpenItemLandsInExactlyOneBand() {
        let items = [
            Self.item("a", dueOn: Self.day(2)),
            Self.item("b", title: "Call the vet"),
            Self.item("c"),
            Self.item("d", dueOn: Self.day(-60)),
            Self.item("e", dueOn: Self.day(40)),
        ]
        let sorted = FieldStrata.sort(items, now: Self.now)

        #expect(sorted.total == items.count)
        let ids = Set(sorted.all.map(\.id))
        #expect(ids == Set(items.map(\.id)))
    }

    @Test
    func finishedThingsAreNotOnThePageAtAll() {
        let sorted = FieldStrata.sort(
            [
                Self.item("done", dueOn: Self.day(1), isDone: true),
                Self.item("open", dueOn: Self.day(1)),
            ],
            now: Self.now
        )

        #expect(sorted.total == 1)
        #expect(sorted.all.first?.id == "open")
    }

    /// §2 forbids a completed list and an archive. The sort is the only way
    /// onto the page, so this is the assertion that keeps both off it.
    @Test
    func thereIsNoBandThatCollectsFinishedThings() {
        let sorted = FieldStrata.sort(
            (0..<12).map { Self.item("done-\($0)", isDone: true) },
            now: Self.now
        )
        #expect(sorted.isEmpty)
    }

    @Test
    func thisWeekIsOrderedByPressure() {
        let sorted = FieldStrata.sort(
            [
                Self.item("later", dueOn: Self.day(6)),
                Self.item("today", dueOn: Self.day(0)),
                Self.item("soon", dueOn: Self.day(2)),
            ],
            now: Self.now
        )
        #expect(sorted.thisWeek.map(\.id) == ["today", "soon", "later"])
    }

    // MARK: The adaptive collapse

    /// Driven by count, not by a breakpoint — §16a calls this the app's main
    /// adaptive behaviour, and a screen size never enters into it.
    @Test
    func fiveOrFewerThingsCollapseTheBands() {
        for count in 0...FieldStrata.collapseThreshold {
            let sorted = FieldStrata.sort(
                (0..<count).map { Self.item("i-\($0)", dueOn: Self.day(1)) },
                now: Self.now
            )
            #expect(sorted.isCollapsed, "\(count) items should collapse")
        }
    }

    @Test
    func moreThanFiveThingsEarnTheBands() {
        let sorted = FieldStrata.sort(
            (0...FieldStrata.collapseThreshold)
                .map { Self.item("i-\($0)", dueOn: Self.day(1)) },
            now: Self.now
        )
        #expect(!sorted.isCollapsed)
    }

    // MARK: Subjects

    /// The subject run is the one place a category still appears on Life, and
    /// it keeps first-seen order rather than sorting alphabetically — the run
    /// reads as a sentence, not an index.
    @Test
    func subjectsAreUniqueAndKeepTheOrderTheyAppearIn() {
        let subjects = FieldStrata.subjects(in: [
            Self.item("a", category: .food),
            Self.item("b", category: .care),
            Self.item("c", category: .food),
            Self.item("d", category: .home),
        ])
        #expect(subjects == [.food, .care, .home])
    }
}
