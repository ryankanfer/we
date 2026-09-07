//
//  FieldLifeZone.swift
//  WE
//
//  Life — strata. Options 15b and 16a.
//
//  The page used to open on eight category words, which is a filing cabinet
//  with the drawers labelled. V2 §2 forbids that outright — "never subject
//  categories as the top-level sort" — and replaces it with four bands that
//  answer a different question: not *what kind of thing is this* but *how much
//  is it asking of us right now*.
//
//  The bands are fixed and their order never changes. What changes is how much
//  of each is on screen, because **each band is a different kind of object**:
//  rows in full, then rows tightened, then a run of subject words, then a bare
//  count. That progression is the page's whole argument. A thing does not get
//  quieter here by being written in fainter ink — it gets quieter by being
//  described in less detail, until at the bottom the app will tell you how
//  many there are and nothing else.
//
//  It has to work that way. §3 asked for the bands to separate by ink as well
//  — 100 / 72 / 40 / 24 — and on the near-black ground those bottom two score
//  3.35:1 and 1.91:1, both under WCAG AA, in 9pt labels where the large-text
//  allowance does not apply. `FieldInk` now floors at AA, so the ink barely
//  moves across the bottom half of this page and the structure carries it
//  instead. See `FieldStrata` for the sorting rule and the measurements.
//
//  Under about five open items the bands disappear altogether and the page
//  becomes a plain list at 30px — §16a's "main adaptive behaviour", driven by
//  count rather than by any screen size. A couple with four things to do
//  should not be handed a filing system with four drawers, three of them
//  empty.
//
//  Two rooms still sit behind the page and neither is a band. The calendar is
//  every dated thing at once; search is everything written down at all. Both
//  say so in words, for the reason the way into Yours already taught: a room
//  reachable only by a gesture is a room most people never open.
//

import SwiftUI

struct FieldLifeZone: View {
    @Environment(FieldStore.self) private var store
    @State private var isAtTop = true
    /// Which category room is open. Local `@State`, not store state: a
    /// hand-built `Binding` over an `@Observable` property does not drive
    /// `.sheet(item:)` reliably, and this is ephemeral to the screen anyway.
    @State private var openCategory: LifeCategory?
    /// Which item is open, to move it or take it off.
    @State private var openItem: FieldItemReference?
    /// Whether the list of groups the couple has set down is open.
    @State private var putAwayIsOpen = false
    /// Private Share Sheet drafts. Feature-gated until the full local and
    /// server release path has passed together.
    @State private var shareInboxIsOpen = false

    var body: some View {
        let strata = store.lifeStrata

        FieldZoneScaffold(zone: .life) {
            VStack(alignment: .leading, spacing: 0) {
                if strata.isEmpty {
                    emptyState
                } else if strata.isCollapsed {
                    sparseList(strata)
                } else {
                    bands(strata)
                }

                fromElsewhere
                    .padding(.top, FieldMetrics.sectionGapLoose)

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
        // Pull down anywhere on Life. Simultaneous so it never fights the
        // vertical scroll, and a drag of 24pt or more is not a tap, so it
        // cannot fire together with a row.
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
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
                .environment(store)
        }
        .sheet(isPresented: $putAwayIsOpen) {
            FieldPutAwaySheet()
                .environment(store)
        }
        .fullScreenCover(isPresented: $shareInboxIsOpen) {
            ShareInboxView()
                .environment(store)
        }
        // Keyed on the items, not on appearance: revisiting Life should not
        // re-run the model, and adding something should.
        .task(id: store.subtitleRefreshKey) {
            await store.refreshSubtitles()
        }
    }

    // MARK: - Nothing at all
    //
    // A real state, not a failure — and the app does not suggest filling it.

    private var emptyState: some View {
        Text("Your saved thoughts will be here. Add something in Today, or use Search to find it again.")
            .font(FieldType.pageHeadline)
            .foregroundStyle(.fieldInk(.headline))
            .fieldLineHeight(1.16, size: 32)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, FieldMetrics.sectionGap)
    }

    // MARK: - The sparse page (16a)
    //
    // Five things or fewer and the page stops organising itself. No headings,
    // no bands, no rules between the rows — just the things, large, with air
    // around them. The 38pt gap is most of what makes this read as calm rather
    // than as a page that failed to load.

    private func sparseList(_ strata: FieldStrata.Result) -> some View {
        VStack(alignment: .leading, spacing: 38) {
            ForEach(strata.all) { item in
                Button {
                    openItem = FieldItemReference(id: item.id)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        FieldDot(
                            owner: item.owner,
                            identity: store.identity,
                            size: FieldDotSize.prominentList,
                            baselineNudge: 13
                        )

                        Text(item.title)
                            .font(FieldType.listItemSparse)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.12, size: 30)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityHint("Opens this, to move it or take it off")
                .accessibilityIdentifier("field.life.item")
            }
        }
        .padding(.top, FieldMetrics.sectionGap)
    }

    // MARK: - The four bands (15b)

    @ViewBuilder
    private func bands(_ strata: FieldStrata.Result) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(FieldStrata.Band.allCases, id: \.self) { band in
                let items = strata.items(in: band)

                // A heading over an empty band is the app talking to fill the
                // silence. Absent bands are simply absent.
                if !items.isEmpty {
                    bandHeader(band)

                    switch band {
                    case .thisWeek:
                        rows(items, prominent: true)
                    case .waitingOnSomeoneElse:
                        rows(items, prominent: false)
                    case .noHurry:
                        rows(items, prominent: false)
                    case .fading:
                        rows(items, prominent: false)
                    }
                }
            }
        }
    }

    private func bandHeader(_ band: FieldStrata.Band) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine(color: rule(for: band))

            FieldLabel(band.heading, ink: ink(for: band))
                .padding(.top, 18)
                .padding(.bottom, 16)
        }
        .padding(.top, band == .thisWeek ? 0 : FieldMetrics.sectionGapLoose)
    }

    /// The rule thins with each band — half of what separates them now that
    /// the ink cannot.
    private func rule(for band: FieldStrata.Band) -> FieldRuleStyle {
        switch band {
        case .thisWeek: FieldRule.strataThisWeek
        case .waitingOnSomeoneElse: FieldRule.strataWaiting
        case .noHurry: FieldRule.strataNoHurry
        case .fading: FieldRule.strataFading
        }
    }

    /// What is left of §3's ink ramp after the AA floor. The top two bands
    /// still separate; the bottom two are within a few thousandths and lean on
    /// structure instead.
    private func ink(for band: FieldStrata.Band) -> FieldInk {
        switch band {
        case .thisWeek: .headline
        case .waitingOnSomeoneElse: .legend
        case .noHurry: .metadataProse
        case .fading: .recessive
        }
    }

    // MARK: Bands one and two — rows

    private func rows(
        _ items: [LifeItem],
        prominent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: prominent ? 15 : 11) {
            ForEach(items) { item in
                Button {
                    openItem = FieldItemReference(id: item.id)
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        FieldDot(
                            owner: item.owner,
                            identity: store.identity,
                            size: FieldDotSize.list,
                            baselineNudge: prominent ? 7 : 6
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(
                                    prominent
                                        ? FieldType.listItemLarge
                                        : FieldType.listItem
                                )
                                .foregroundStyle(
                                    .fieldInk(
                                        prominent ? .headline : .legend
                                    )
                                )
                                .fieldLineHeight(1.25, size: prominent ? 18 : 15.5)
                                .fixedSize(horizontal: false, vertical: true)

                            // Only the top band explains itself. Repeating a
                            // reason down every row turns the page into an
                            // argument, and the lower bands are not arguing.
                            if prominent, let detail = item.detail {
                                Text(detail)
                                    .font(FieldType.reasoning)
                                    .foregroundStyle(.fieldInk(.reasoning))
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                        }

                        Spacer(minLength: 8)

                        if let dueOn = item.dueOn {
                            Text(dayLabel(dueOn))
                                .font(FieldType.dateCount)
                                .tracking(FieldTracking.dateCount)
                                .foregroundStyle(.fieldInk(.dateCount))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Not `.accessibilityElement(children: .combine)`. A Button is
                // already an accessibility element, and combining after
                // `.buttonStyle` wraps it in a second one — a button inside a
                // button, read twice. See `FieldCategoryRoom` for the same
                // note and the tree that showed it.
                .accessibilityLabel(
                    [item.title, prominent ? item.detail : nil]
                        .compactMap { $0 }
                        .joined(separator: ". ")
                )
                .accessibilityHint("Opens this, to move it or take it off")
                .accessibilityIdentifier("field.life.item")
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: Band three — a run of subjects
    //
    // Not rows. The things in this band are not asking for anything, so
    // listing them one per line would give each the same weight as something
    // that is. What the page says instead is which *subjects* have quiet
    // things in them, run together as a line of words.
    //
    // This is also the one place a category still appears on Life, and it is
    // deliberately inside a band rather than above one: a subject is how you
    // reach a room, not how the page is sorted.

    private func subjectRun(_ items: [LifeItem]) -> some View {
        let subjects = FieldStrata.subjects(in: items)

        return FieldFlowLayout(spacing: 0, lineSpacing: 8) {
            ForEach(Array(subjects.enumerated()), id: \.element) { index, subject in
                Button {
                    openCategory = subject
                } label: {
                    (
                        Text(subject.word)
                            .foregroundStyle(.fieldInk(.metadataProse))
                            + Text(
                                index == subjects.count - 1 ? "" : "  ·  "
                            )
                            .foregroundStyle(.fieldInk(.recessive))
                    )
                    .font(FieldType.listItem)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subject.word)
                .accessibilityHint("Opens \(subject.word)")
                .accessibilityIdentifier("field.life.\(subject.rawValue)")
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: Band four — a count, and nothing else
    //
    // No titles. Naming them would be the app pointing at things it has just
    // finished deciding not to ask about, which is the shape of a guilt list.
    // The count is honest and the sentence stops there.

    private func fadingCount(_ items: [LifeItem]) -> some View {
        Text(
            items.count == 1
                ? "One thing has gone quiet."
                : "\(items.count.spelled.capitalized) things have gone quiet."
        )
        .font(FieldType.body)
        .foregroundStyle(.fieldInk(.recessive))
        .fieldLineHeight(1.5, size: 14.5)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 20)
        .accessibilityIdentifier("field.life.fading")
    }

    // MARK: - The rest of the page

    @ViewBuilder
    private var fromElsewhere: some View {
        if WEFeatureFlags.shareInboxEnabled {
            Button {
                shareInboxIsOpen = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("From elsewhere")
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(.headline))

                    Text("PRIVATE")
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.dateCount))

                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                FieldRuleLine(color: FieldRule.row)
            }
            .accessibilityHint(
                "Opens private drafts kept from the Share Sheet"
            )
            .accessibilityIdentifier("field.life.fromElsewhere")
        }
    }

    /// One name for the two routes in — the control above and the pull — so
    /// that anything either of them ever has to do is written once.
    private func openSearch() {
        store.openSearch()
    }

    /// "TODAY", "TOMORROW", then the weekday, then the date. Nothing in the
    /// banded rows is more than ten days out, so it never needs a year.
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

    // MARK: What has been set down
    //
    // Renders nothing at all until something is put away, which is almost
    // always. A permanent "0 groups put away" would be a heading over nothing.
    //
    // It exists so that nothing on this page is ever simply gone. A group the
    // couple set down is still theirs and still findable.

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
                        .foregroundStyle(.fieldInk(.label))

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
    // Two rooms behind this screen, and both say so in words. The pull is an
    // accelerator for the hand that knows it, and neither room depends on
    // anybody having learned one.

    private var pullAffordance: some View {
        HStack(spacing: 18) {
            affordance(
                "Search",
                hint: "Finds anything either of you has written down",
                id: "field.life.search"
            ) {
                openSearch()
            }

            affordance(
                "Calendar",
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
            WECanvas.cream.bgElevated.ignoresSafeArea()

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
        .preferredColorScheme(.light)
        .environment(\.weCanvas, WECanvas.cream)
        // Closes itself once the last one is back, because the row that opens
        // it has gone by then and there would be nothing here to look at.
        .onChange(of: store.putAwayCategories.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
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
