//
//  FieldStrata.swift
//  WE
//
//  Life, sorted by pressure. Option 15b / 16a.
//
//  V2 §2 gives Life one object — *strata* — and forbids the thing it replaced:
//  "never subject categories as the top-level sort." The old page opened on
//  eight category words, which is a filing cabinet with the drawers labelled.
//  This opens on four bands that answer a different question: not *what kind
//  of thing is this* but *how much is it asking of us right now*.
//
//  The four are fixed, and their order never changes. What changes is how much
//  of each one is on screen, because each band renders as a different kind of
//  object:
//
//  | Band                      | Renders as        | Rule |
//  | ------------------------- | ----------------- | ---- |
//  | This week                 | rows, in full     | .20  |
//  | Waiting on someone else   | rows, tighter     | .14  |
//  | No hurry                  | a run of subjects | .10  |
//  | Fading                    | a count, alone    | .07  |
//
//  The ink was meant to carry this too — 100 / 72 / 40 / 24 per §3 — and it
//  cannot. On the near-black ground, 40% ink scores 3.35:1 and 24% scores
//  1.91:1, both below WCAG AA, and the bands that would have used them are set
//  in 9pt tracked labels where the large-text allowance does not apply. The
//  ramp now floors at AA (see `FieldInk`), so the bottom two bands are within
//  a few thousandths of each other and the *structure* above is what separates
//  them. That is §2's law rather than a workaround: "structure carries
//  purpose."
//
//  ## The adaptive behaviour
//
//  §16a calls this "the app's main adaptive behaviour", and it is driven by
//  **count, not by a breakpoint**: under `collapseThreshold` open items the
//  bands disappear entirely and what is left is a plain list at 30px. A couple
//  with four things to do should not be shown a filing system with four
//  drawers, three of them empty. Headings over almost nothing is the same
//  fault the old `thisWeek` section guarded against, generalised.
//

import Foundation

/// Life's four bands, and the rule that decides which one a thing is in.
enum FieldStrata {
    /// At or below this many open items, the bands collapse into one list.
    ///
    /// §16a says "under about five". Five is the count at which four headings
    /// stop describing the page and start outnumbering it.
    static let collapseThreshold = 5

    /// How long a thing may sit past its date before it stops pressing and
    /// starts fading.
    ///
    /// A fortnight, because `LifeItem.pressure(now:)` already decays an
    /// overdue item rather than escalating it — "the air filter has been two
    /// months over and nothing broke — that is upkeep, not an emergency." This
    /// is the same judgement expressed as a band: the app stops asking rather
    /// than asking louder.
    static let fadesAfterDays = 14

    /// How far ahead "this week" reaches.
    static let thisWeekDays = 7

    enum Band: String, CaseIterable, Hashable, Sendable {
        case thisWeek
        case waitingOnSomeoneElse
        case noHurry
        case fading

        /// The heading, in the app's own words. Sentence case, because these
        /// are things the app is saying rather than labels on a form.
        var heading: String {
            switch self {
            case .thisWeek: "This week"
            case .waitingOnSomeoneElse: "Waiting on someone else"
            case .noHurry: "No hurry"
            case .fading: "Fading"
            }
        }
    }

    struct Result: Hashable, Sendable {
        var thisWeek: [LifeItem] = []
        var waitingOnSomeoneElse: [LifeItem] = []
        var noHurry: [LifeItem] = []
        var fading: [LifeItem] = []

        var total: Int {
            thisWeek.count + waitingOnSomeoneElse.count
                + noHurry.count + fading.count
        }

        var isEmpty: Bool { total == 0 }

        /// Whether the page drops its headings and renders one plain list.
        ///
        /// A property of the result rather than of the view, so the rule lives
        /// beside the bands it collapses and can be asserted directly.
        var isCollapsed: Bool { total <= FieldStrata.collapseThreshold }

        /// Every open item, in band order, for the collapsed rendering.
        var all: [LifeItem] {
            thisWeek + waitingOnSomeoneElse + noHurry + fading
        }

        func items(in band: Band) -> [LifeItem] {
            switch band {
            case .thisWeek: thisWeek
            case .waitingOnSomeoneElse: waitingOnSomeoneElse
            case .noHurry: noHurry
            case .fading: fading
            }
        }
    }

    /// Sort every open item into exactly one band.
    ///
    /// The order of the checks is not the order of the bands on screen, and
    /// the difference matters. Fading is tested *before* the outward acts,
    /// because a thing two months past its date is fading whatever verb its
    /// title happens to contain — otherwise "call the plumber", written in
    /// March and never done, would still be reported as something a plumber is
    /// actively getting to.
    static func sort(
        _ items: [LifeItem],
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Result {
        var result = Result()

        for item in items where !item.isDone {
            switch band(for: item, now: now, calendar: calendar) {
            case .thisWeek: result.thisWeek.append(item)
            case .waitingOnSomeoneElse:
                result.waitingOnSomeoneElse.append(item)
            case .noHurry: result.noHurry.append(item)
            case .fading: result.fading.append(item)
            }
        }

        // Within a band, the same weighting the rest of the app ranks by, so
        // Life and Today cannot disagree about which of two things is louder.
        result.thisWeek.sort {
            $0.pressure(now: now, calendar: calendar)
                > $1.pressure(now: now, calendar: calendar)
        }
        result.waitingOnSomeoneElse.sort {
            $0.pressure(now: now, calendar: calendar)
                > $1.pressure(now: now, calendar: calendar)
        }

        return result
    }

    static func band(
        for item: LifeItem,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Band {
        // A cut-off inside the day is this week by definition — that is what a
        // window closing tonight is — and it outranks the date underneath it.
        if let closesAt = item.closesAt {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: closesAt)
            ).day ?? 0
            if days <= thisWeekDays { return .thisWeek }
        }

        if let dueOn = item.dueOn {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: dueOn)
            ).day ?? 0

            if days < -fadesAfterDays { return .fading }
            if days <= thisWeekDays { return .thisWeek }
            // Dated, but far enough out that nothing is being asked yet.
            return .noHurry
        }

        // Undated. The only remaining question is whether it is ours to do.
        //
        // `leavesItToUs` rather than a second list of verbs here: it is the
        // same distinction the outreach path already draws, and
        // `FieldItemStepsTests` asserts the two agree for every `FieldAct`.
        // Paying a bill and ordering filters are ours; calling, messaging,
        // emailing and booking put the next move in somebody else's hands.
        let act = FieldTodaySelector.primaryAct(for: item)
        return FieldLookupPolicy.leavesItToUs(act)
            ? .noHurry
            : .waitingOnSomeoneElse
    }

    /// The subjects present in a band, in the order they first appear.
    ///
    /// This is what "No hurry" renders instead of rows — the subject words
    /// themselves, run together. It is the one place a category still appears
    /// on Life, and it is deliberately *inside* a band rather than above one:
    /// a subject is how you reach a room, not how the page is sorted.
    static func subjects(in items: [LifeItem]) -> [LifeCategory] {
        var seen: Set<LifeCategory> = []
        return items.compactMap { item in
            seen.insert(item.category).inserted ? item.category : nil
        }
    }
}
