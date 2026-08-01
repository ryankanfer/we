//
//  FieldLifeZone.swift
//  WE
//
//  Life — "run life". Option 3a.
//
//  Everything that keeps the week moving, and never the first thing you see.
//
//  "Life must stay this calm. An early version put the full Reminders list
//  inline and it swamped the page." Nothing on this screen enumerates a
//  category. It carries two things: **this week**, which is the handful of
//  dated things grouped by occasion, and **the categories**, which are single
//  large words.
//
//  Pulling down opens the calendar — every dated thing at once, whatever list
//  it came from. A calendar is not a category and never was one.
//

import SwiftUI

struct FieldLifeZone: View {
    @Environment(FieldStore.self) private var store
    @State private var isAtTop = true
    /// Which category room is open. Local `@State`, not store state: a
    /// hand-built `Binding` over an `@Observable` property does not drive
    /// `.sheet(item:)` reliably, and this is ephemeral to the screen anyway.
    @State private var openCategory: LifeCategory?

    var body: some View {
        FieldZoneScaffold(zone: .life) {
            VStack(alignment: .leading, spacing: 0) {
                thisWeek
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                categories
            }
        }
        .overlay(alignment: .top) {
            pullAffordance
                .padding(.top, FieldMetrics.screenTop)
                .padding(.trailing, FieldMetrics.screenSide)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(true)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= geometry.contentInsets.top + 1
        } action: { _, atTop in
            isAtTop = atTop
        }
        // Pull down anywhere on Life. The gesture is simultaneous so it never
        // fights the vertical scroll — it only fires from the top.
        //
        // It does not fight the category buttons either: a drag of 24pt or
        // more is not a tap, so the two cannot both fire.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard isAtTop,
                          value.translation.height > 90,
                          abs(value.translation.width) < 60
                    else { return }
                    store.openCalendar()
                }
        )
        .sheet(item: $openCategory) { category in
            FieldCategoryRoom(category: category)
                .environment(store)
        }
        // Keyed on the items, not on appearance: revisiting Life should not
        // re-run the model, and adding something should.
        .task(id: store.subtitleRefreshKey) {
            await store.refreshSubtitles()
        }
    }

    // MARK: This week
    //
    // Grouped by occasion, never by category or date: "categories are a filing
    // system; occasions are how people actually think." This is where the
    // Reminders takeover's content went when the pull-down became the
    // calendar.
    //
    // It renders nothing at all when nothing is dated. An empty heading over
    // an empty week is the app talking to fill the silence.

    @ViewBuilder
    private var thisWeek: some View {
        let nudges = store.thisWeek

        if !nudges.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                FieldLabel("This week")
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 15) {
                    ForEach(nudges) { nudge in
                        nudgeRow(nudge)
                    }
                }
                .padding(.bottom, 20)

                FieldRuleLine()
            }
        }
    }

    private func nudgeRow(_ nudge: FieldTimely.Nudge) -> some View {
        HStack(alignment: .top, spacing: 11) {
            FieldDot(
                owner: nudge.tint,
                identity: store.identity,
                size: FieldDotSize.list,
                baselineNudge: 7
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(nudge.occasion)
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.25, size: 18)
                    .fixedSize(horizontal: false, vertical: true)

                // The thing the occasion is waiting on, in its own words. The
                // app does not invent an errand — it repeats the one somebody
                // already wrote down.
                if let ask = nudge.ask {
                    Text(ask)
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let dueOn = nudge.dueOn {
                Text(dayLabel(dueOn))
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.dateCount))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [nudge.occasion, nudge.ask].compactMap { $0 }
                .joined(separator: ". ")
        )
    }

    /// "TODAY", "TOMORROW", then the weekday, then the date. Nothing in this
    /// section is more than ten days out, so it never needs a year.
    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.gregorianUS
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: store.now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case ..<0: return "OVERDUE"
        case 0: return "TODAY"
        case 1: return "TOMORROW"
        case 2...6: return DateFormatter.fieldWeekday
            .string(from: date).uppercased()
        default: return DateFormatter.fieldDayMonth
            .string(from: date).uppercased()
        }
    }

    // MARK: The categories
    //
    // Ordered by attention needed, not alphabetically or by a fixed taxonomy.

    private var categories: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
            ForEach(store.categoryOrder) { category in
                categoryRow(category)
            }
        }
    }

    /// Tapping a category word opens its room.
    ///
    /// A plain `Button` so the row looks exactly as it did — no highlight, no
    /// chevron, nothing added to the page. Life stays a set of words; the
    /// detail is behind them.
    private func categoryRow(_ category: LifeCategory) -> some View {
        Button {
            openCategory = category
        } label: {
            categoryLabel(category)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(category.word)")
    }

    private func categoryLabel(_ category: LifeCategory) -> some View {
        let count = store.openItems(in: category).count
        let pressured = store.isPressured(category)
        let hasNothingPressing = !pressured && count == 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(category.word)
                    .font(FieldType.categoryWord)
                    .foregroundStyle(
                        pressured || count > 0
                            ? .fieldInk(.headline)
                            : .fieldInk(.reasoning)
                    )

                if count > 0 {
                    Text("\(count)")
                        .font(FieldType.zoneLabel)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(
                            pressured
                                ? store.identity.personA.color
                                : .fieldInk(.dateCount)
                        )
                }
            }

            Text(store.subtitle(for: category))
                .font(FieldType.body)
                .foregroundStyle(
                    hasNothingPressing
                        ? .fieldInk(.monoLabel)
                        : .fieldInk(.categorySummary)
                )
                .fieldLineHeight(1.5, size: 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            count > 0
                ? "\(category.word), \(count) items. \(store.summary(for: category))"
                : "\(category.word). \(store.summary(for: category))"
        )
        .accessibilityIdentifier("field.life.\(category.rawValue)")
    }

    // MARK: The entry affordance

    private var pullAffordance: some View {
        Button {
            store.openCalendar()
        } label: {
            Text("↓ PULL FOR CALENDAR")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.recessive))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendar")
        .accessibilityHint("Opens the month, and everything with a date on it")
        .accessibilityIdentifier("field.life.calendar")
    }
}

#Preview {
    FieldZoneShell(store: FieldStore())
}
