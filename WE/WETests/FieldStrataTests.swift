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
        isDone: Bool = false
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
            isTimeCritical: false,
            isDone: isDone
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

    /// The next move is in somebody else's hands.
    @Test
    func anUndatedOutwardActWaitsOnSomeoneElse() {
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
                band == .waitingOnSomeoneElse,
                "\"\(title)\" puts the next move elsewhere"
            )
        }
    }

    /// Paying and ordering are ours to finish, so they are not waiting on
    /// anyone. This mirrors `FieldLookupPolicy.leavesItToUs`, deliberately —
    /// the two must not drift.
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
