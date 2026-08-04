//
//  FieldCalendarSurface.swift
//  WE
//
//  The calendar — pull down on Life.
//
//  A calendar is not a list of things. It is a *view* of everything that has a
//  date, whatever list the thing came from — so Calendar is not one of Life's
//  category words and owns nothing. Filing something here is impossible,
//  because there is nothing here to file into. Nothing on this screen is
//  stored: the month is drawn from `store.state.lifeItems` and, when the
//  couple has connected one, their real calendar.
//
//  It replaced the Reminders takeover, which used to live behind this gesture.
//  That screen's occasions were the better half of it and moved up to the top
//  of Life, where they can be seen without a gesture at all.
//
//  Drawn in the app's own language: hairlines, no boxes, no fills, no chips. A
//  day carrying something is marked with a dot in the owner's colour, which is
//  the same mark the rest of the app uses to say whose a thing is.
//

import SwiftUI

struct FieldCalendarSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: FieldStore

    /// Which month is shown, as an offset from the month containing `now`.
    @State private var monthOffset = 0
    @State private var selectedDay: Date?
    /// The agenda row somebody tapped. Presented from here rather than from
    /// the shell: this surface covers the shell, so a sheet mounted underneath
    /// it would open behind the takeover.
    @State private var openItem: FieldItemReference?

    private let calendar = Calendar.gregorianUS

    var body: some View {
        ZStack {
            FieldPalette.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                weekdayRow
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                monthGrid

                agenda
                    .padding(.top, FieldMetrics.sectionGap)

                Spacer(minLength: 0)

                footer
            }
            .padding(.top, FieldMetrics.screenTop)
            .padding(.horizontal, FieldMetrics.takeoverSide)
            .padding(.bottom, FieldMetrics.takeoverBottom)
        }
        .animation(.fieldZone(reduceMotion), value: monthOffset)
        .animation(.fieldZone(reduceMotion), value: selectedDay)
        // Swipe sideways for the next month; either way vertically to leave.
        // Down is how it arrived, so down puts it back — and up is what a hand
        // does to push a full-screen thing away. Both mean the same here, and
        // guessing which one somebody will reach for is a bet with no upside.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.height) > 110,
                       abs(value.translation.width) < 80 {
                        store.closeCalendar()
                    } else if value.translation.width < -60 {
                        monthOffset += 1
                    } else if value.translation.width > 60 {
                        monthOffset -= 1
                    }
                }
        )
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
                .environment(store)
        }
        .accessibilityIdentifier("field.calendar")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            FieldLabel(
                DateFormatter.fieldMonthYear.string(from: shownMonth).uppercased()
            )

            Spacer()

            Text("\(datedOnThePage.count) DATED")
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.headerMeta))
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.recessive))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The month
    //
    // Six rows of seven, so the grid does not change height between months —
    // a calendar that jumps as you page through it reads as unstable, and this
    // screen is meant to be the calm answer to "when is that".

    private var monthGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { weekday in
                        dayCell(gridDate(week: week, weekday: weekday))
                            .frame(maxWidth: .infinity)
                    }
                }
                .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
            }
        }
        .overlay(alignment: .bottom) { FieldRuleLine(color: FieldRule.row) }
    }

    private func dayCell(_ date: Date) -> some View {
        let inMonth = calendar.isDate(date, equalTo: shownMonth, toGranularity: .month)
        let isToday = calendar.isDate(date, inSameDayAs: store.now)
        let items = items(on: date)
        let isSelected = selectedDay.map {
            calendar.isDate($0, inSameDayAs: date)
        } ?? false

        return Button {
            selectedDay = isSelected ? nil : date
        } label: {
            VStack(spacing: 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(FieldType.dateCount)
                    .foregroundStyle(
                        inMonth
                            ? (isToday ? .fieldInk(.headline) : .fieldInk(.legend))
                            : .fieldInk(.recessive)
                    )

                // One dot per day, in the colour of whoever the day belongs
                // to. Never a count: a number of things on a Tuesday is a
                // workload, and this app does not render workloads.
                //
                // A day with nothing left open is still a marked day — it just
                // stops asking for attention.
                if let owner = leadingOwner(of: items) {
                    FieldDot(
                        owner: owner,
                        identity: store.identity,
                        size: FieldDotSize.inlinePair,
                        baselineNudge: 0,
                        opacity: items.allSatisfy(\.isDone) ? 0.4 : 1
                    )
                } else {
                    Color.clear.frame(height: FieldDotSize.inlinePair)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Rectangle().fill(FieldPalette.ink.opacity(0.07))
                } else if isToday {
                    Rectangle().fill(FieldPalette.ink.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, items: items))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Shared when both are involved, otherwise whoever's day it mostly is.
    private func leadingOwner(of items: [LifeItem]) -> FieldOwner? {
        guard let first = items.first else { return nil }
        let owners = Set(items.map(\.owner))
        return owners.count > 1 ? .shared : first.owner
    }

    // MARK: The day

    @ViewBuilder
    private var agenda: some View {
        let day = selectedDay ?? store.now
        let items = items(on: day)

        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(
                DateFormatter.fieldDayMonth.string(from: day).uppercased(),
                color: .fieldInk(.monoLabelQuiet)
            )

            if items.isEmpty {
                // A real state, and the one to be pleased about.
                Text(
                    calendar.isDate(day, inSameDayAs: store.now)
                        ? "Nothing today."
                        : "Nothing that day."
                )
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.monoLabel))
            } else {
                ForEach(items) { item in
                    // Tapping opens the thing itself. The calendar borrows
                    // items rather than holding them, so this is the same
                    // sheet the category room opens — moving something here
                    // moves it there, because there is only one of it.
                    Button {
                        openItem = FieldItemReference(id: item.id)
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            FieldDot(
                                owner: item.owner,
                                identity: store.identity,
                                size: FieldDotSize.list,
                                baselineNudge: 6,
                                opacity: item.isDone ? 0.45 : 1
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                // Done is a quieter ink, never a strikethrough
                                // and never a removal. The page still reads
                                // "that is behind you" without pretending it
                                // never happened.
                                Text(item.title)
                                    .font(FieldType.listItem)
                                    .foregroundStyle(
                                        item.isDone
                                            ? .fieldInk(.quietListItem)
                                            : .fieldInk(.headline)
                                    )
                                    .fixedSize(horizontal: false, vertical: true)

                                // Where it lives when you go looking for it.
                                Text(item.category.word.uppercased())
                                    .font(FieldType.subLabel)
                                    .tracking(FieldTracking.subLabel)
                                    .foregroundStyle(.fieldInk(.recessive))
                            }

                            Spacer(minLength: 8)

                            if let closesAt = item.closesAt {
                                Text(
                                    DateFormatter.fieldClock
                                        .string(from: closesAt)
                                )
                                .font(FieldType.dateCount)
                                .tracking(FieldTracking.dateCount)
                                .foregroundStyle(.fieldInk(.dateCount))
                            }
                        }
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        FieldRuleLine(color: FieldRule.row)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens this, to move it or take it off")
                    .accessibilityIdentifier("field.calendar.row")
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                monthOffset = 0
                selectedDay = nil
            } label: {
                Text("TODAY")
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    .foregroundStyle(.fieldInk(.legend))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("field.calendar.today")

            Spacer()

            Button {
                store.closeCalendar()
            } label: {
                Text("DONE ✕")
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    .foregroundStyle(.fieldInk(.legend))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .accessibilityIdentifier("field.calendar.done")
        }
    }

    // MARK: Reading the month

    private var shownMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: store.now)
            ?? store.now
    }

    /// The first cell is the Sunday on or before the first of the month, so
    /// the grid always starts on a week boundary.
    private func gridDate(week: Int, weekday: Int) -> Date {
        let components = calendar.dateComponents([.year, .month], from: shownMonth)
        let first = calendar.date(from: components) ?? shownMonth
        let leading = calendar.component(.weekday, from: first) - 1
        let offset = week * 7 + weekday - leading
        return calendar.date(byAdding: .day, value: offset, to: first) ?? first
    }

    /// Everything with a date, wherever it came from — a Life item somebody
    /// filed, or an event from the calendar they connected.
    private func items(on date: Date) -> [LifeItem] {
        dated.filter { item in
            guard let dueOn = item.dueOn else { return false }
            return calendar.isDate(dueOn, inSameDayAs: date)
        }
        .sorted { left, right in
            switch (left.closesAt, right.closesAt) {
            case let (l?, r?): return l < r
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// Everything with a date on it, done or not.
    ///
    /// A calendar is a record of when things are and were. A party you went to
    /// did not stop having happened at 2pm on Saturday because you ticked it
    /// off, and filtering completed items out here applied to-do logic to the
    /// one surface in the app that is not a to-do list. Done items render
    /// quietly instead — see `isBehind`.
    ///
    /// Today is unaffected: `FieldTodaySelector.rank` drops completed items on
    /// its own, so nothing finished can resurface as something that needs you.
    private var dated: [LifeItem] {
        store.state.lifeItems.filter { $0.dueOn != nil }
    }

    /// What the header counts: the six weeks actually drawn, not the calendar
    /// month. Derived from the same `gridDate` the grid uses, so the number
    /// and the dots can never disagree — which they did, reading "0 DATED"
    /// with a dot plainly visible on a trailing day of the next month.
    private var datedOnThePage: [LifeItem] {
        let first = calendar.startOfDay(for: gridDate(week: 0, weekday: 0))
        let last = calendar.startOfDay(for: gridDate(week: 5, weekday: 6))

        return dated.filter {
            guard let dueOn = $0.dueOn else { return false }
            let day = calendar.startOfDay(for: dueOn)
            return day >= first && day <= last
        }
    }

    private var weekdaySymbols: [String] {
        ["S", "M", "T", "W", "T", "F", "S"]
    }

    private func accessibilityLabel(
        for date: Date,
        items: [LifeItem]
    ) -> String {
        let day = DateFormatter.fieldDayMonth.string(from: date)
        guard !items.isEmpty else { return "\(day), nothing" }
        return "\(day), \(items.count) — \(items.map(\.title).joined(separator: ", "))"
    }
}

#Preview {
    let store = FieldStore()
    store.openCalendar()
    return FieldCalendarSurface(store: store).environment(store)
}
