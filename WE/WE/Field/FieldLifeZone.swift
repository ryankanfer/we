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
//  Two rooms sit behind it, and neither is a category. The calendar is every
//  dated thing at once, whatever list it came from. Search is everything
//  written down at all, which is the only way to find a thing without first
//  remembering where it went.
//
//  Both have a word in the corner. The calendar also answers to a second tap
//  on LIFE in the bar; search also answers to pulling this screen down, the
//  way every other list on the phone does.
//

import SwiftUI

struct FieldLifeZone: View {
    @Environment(FieldStore.self) private var store
    @State private var isAtTop = true
    /// Which category room is open. Local `@State`, not store state: a
    /// hand-built `Binding` over an `@Observable` property does not drive
    /// `.sheet(item:)` reliably, and this is ephemeral to the screen anyway.
    @State private var openCategory: LifeCategory?
    /// Whether the list of groups the couple has set down is open.
    @State private var putAwayIsOpen = false

    var body: some View {
        FieldZoneScaffold(zone: .life) {
            VStack(alignment: .leading, spacing: 0) {
                thisWeek
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                categories

                putAwayRow
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
        //
        // This used to open the calendar. The calendar is now behind a second
        // tap on the LIFE word in the bar, where it is visible and reachable
        // without a gesture at all, and the pull that everyone already knows
        // from Mail and the Home Screen means here what it means there.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard isAtTop,
                          value.translation.height > 90,
                          abs(value.translation.width) < 60
                    else { return }
                    openSearch()
                }
        )
        .sheet(item: $openCategory) { category in
            FieldCategoryRoom(category: category)
                .environment(store)
        }
        .sheet(isPresented: $putAwayIsOpen) {
            FieldPutAwaySheet()
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

    /// One name for the two routes in — the control above and the pull — so
    /// that anything either of them ever has to do is written once.
    private func openSearch() {
        store.openSearch()
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
    ///
    /// The long press is an accelerator and never the only route: the same
    /// menu is a visible `•••` in the room one tap behind this word. That is
    /// the rule the SEARCH and CALENDAR words next door were added to keep —
    /// a thing reachable only by a gesture is a thing most people never find.
    private func categoryRow(_ category: LifeCategory) -> some View {
        Button {
            openCategory = category
        } label: {
            categoryLabel(category)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(category.word)")
        .contextMenu {
            Button("Open \(category.word)") { openCategory = category }

            // No "Rename" or "Move everything" here. Both open a sheet, and a
            // sheet raised from a context menu on the page underneath has
            // nowhere honest to put the room this group lives in — so the menu
            // that can change a group stays in the room, where the count it
            // is about is on screen.
            if category.isBuiltIn, store.openItems(in: category).isEmpty {
                Button("Put \(category.word) away") {
                    store.putAway(category)
                }
            }
        }
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

    // MARK: What has been set down
    //
    // Renders nothing at all until something is put away, which is almost
    // always. A permanent "0 groups put away" would be a heading over nothing
    // — the same fault `thisWeek` above guards against.
    //
    // It exists so that nothing on this page is ever simply gone. A group the
    // couple set down is still theirs and still findable, and a design where
    // the only way back was to wait for the app to decide would make a
    // mis-tap unrecoverable.

    @ViewBuilder
    private var putAwayRow: some View {
        let away = store.putAwayCategories

        if !away.isEmpty {
            Button {
                putAwayIsOpen = true
            } label: {
                HStack(spacing: 8) {
                    Text(
                        away.count == 1
                            ? "1 group put away"
                            : "\(away.count) groups put away"
                    )
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.recessive))

                    Text("›")
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.monoLabel))

                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, FieldMetrics.sectionGapLoose)
            .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
            .accessibilityLabel(
                away.count == 1
                    ? "1 group put away"
                    : "\(away.count) groups put away"
            )
            .accessibilityHint("Opens them, to bring any of them back")
            .accessibilityIdentifier("field.life.putAway")
        }
    }

    // MARK: The entry affordances
    //
    // Two rooms behind this screen, and both say so in words.
    //
    // An earlier version put the calendar here and left search to the pull
    // alone, mentioned once by a line that then went away forever. That is the
    // failure the way into Yours already taught: a room reachable only by a
    // gesture, with nothing on screen to find, is a room most people will
    // never open — and unlike Yours, search has no reason to be discreet.
    //
    // So the pull is an accelerator for the hand that knows it, and neither
    // room depends on anybody having learned one.

    private var pullAffordance: some View {
        HStack(spacing: 18) {
            affordance(
                "SEARCH",
                hint: "Finds anything either of you has written down",
                id: "field.life.search"
            ) {
                openSearch()
            }

            affordance(
                "CALENDAR",
                hint: "Opens the month, and everything with a date on it",
                id: "field.life.calendar"
            ) {
                store.openCalendar()
            }
        }
    }

    private func affordance(
        _ word: String,
        hint: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(word)
                .font(FieldType.subLabel)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.recessive))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word.capitalized)
        .accessibilityHint(hint)
        .accessibilityIdentifier(id)
    }
}

// MARK: - The groups that were set down

/// Every put-away group, each with its own way back.
///
/// Individually rather than all at once: a couple who set Watchlist and Money
/// down at different times for different reasons should not have to take both
/// back to get one.
///
/// The copy names no one. Either partner may have put a group away — this is
/// a shared page and a joint setting — and "you put Care away" is a sentence
/// that is wrong half the time and unanswerable when it is.
private struct FieldPutAwaySheet: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel("Put away")

                    Text(
                        "These aren't on Life. Nothing in them was deleted, "
                            + "and anything filed into one brings it back."
                    )
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .padding(.bottom, FieldMetrics.sectionGap)

                    ForEach(store.putAwayCategories) { category in
                        row(category)
                    }
                }
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        // Closes itself once the last one is back, because the row that opens
        // it has gone by then and there would be nothing here to look at.
        .onChange(of: store.putAwayCategories.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        // No identifier on the root, for the reason given on the destination
        // sheet in `FieldCategoryRoom`: it would propagate down over
        // `field.putAway.bringBack` on every row here.
    }

    private func row(_ category: LifeCategory) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(category.word)
                .font(FieldType.listItemLarge)
                .foregroundStyle(.fieldInk(.headline))

            Spacer(minLength: 12)

            Button("Bring back") { store.bringBack(category) }
                .buttonStyle(FieldQuietButtonStyle())
                .accessibilityLabel("Bring \(category.word) back")
                .accessibilityIdentifier("field.putAway.bringBack")
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
    }
}

#Preview {
    FieldZoneShell(store: FieldStore())
}
