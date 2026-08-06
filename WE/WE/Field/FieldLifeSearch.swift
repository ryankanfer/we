//
//  FieldLifeSearch.swift
//  WE
//
//  Search — pull down on Life.
//
//  Life carries single large words and never enumerates a category. That is the
//  whole reason it stays calm, and the price of it is that something written
//  down six weeks ago can only be reached by remembering where it was filed.
//  Remembering where you filed a thing is the exact work this app exists to
//  take off two people.
//
//  So: one field, and everything either of them has ever written down. Not a
//  filter over Life — a different question entirely. Life asks "what is going
//  on"; this asks "where did that go".
//
//  It owns nothing, in the same way the calendar owns nothing: every row is a
//  borrowed `LifeItem`, tapping one opens the same `FieldItemSheet` the
//  category room opens, and closing this changes nothing about anything.
//
//  Done items are included, and deliberately. Half the reason to search for a
//  thing is to find out whether it was ever dealt with, and a search that
//  silently omits the answer to that reads as "you never wrote it down".
//

import SwiftUI

struct FieldLifeSearch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: FieldStore

    @State private var query = ""
    /// The row somebody tapped. Presented from here rather than from the
    /// shell: this surface covers the shell, so a sheet mounted underneath it
    /// would open behind the takeover — the same reason
    /// `FieldCalendarSurface` holds its own.
    @State private var openItem: FieldItemReference?
    @FocusState private var isTyping: Bool

    var body: some View {
        ZStack {
            FieldPalette.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                field

                results
                    .padding(.top, FieldMetrics.sectionGap)

                Spacer(minLength: 0)

                footer
            }
            .padding(.top, FieldMetrics.screenTop)
            .padding(.horizontal, FieldMetrics.takeoverSide)
            .padding(.bottom, FieldMetrics.takeoverBottom)
        }
        .animation(.fieldZone(reduceMotion), value: matches.count)
        // Up or down to leave, matching the calendar. Down is how it arrived,
        // so down puts it back; up is what a hand does to push a full-screen
        // thing away. Sideways is left alone — there are no pages here.
        //
        // `minimumDistance: 30` so a drag inside the field's own text
        // selection is never mistaken for a dismissal.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.height) > 110,
                          abs(value.translation.width) < 80
                    else { return }
                    close()
                }
        )
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
                .environment(store)
        }
        // The keyboard, without anybody having to ask for it. Search is the one
        // surface in this app where arriving and wanting to type are the same
        // act — nobody pulls this down to look at it.
        .onAppear { isTyping = true }
        // Stays a container.
        //
        // Without this the identifier below collapses the whole surface into
        // one element — VoiceOver announced the entire screen as a single
        // button labelled "Done", and the field, every result, and the count
        // were simply not there. It showed up first as a test unable to find
        // the search field, which is exactly what a person with the rotor
        // would have experienced.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.search")
    }

    // MARK: The field

    private var field: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel("Find", color: .fieldInk(.monoLabelQuiet))

            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(FieldType.categoryWord)
                .foregroundStyle(.fieldInk(.headline))
                .tint(store.identity.color(for: store.speaker))
                .focused($isTyping)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search everything you've written down")
                .accessibilityIdentifier("field.search.field")

            FieldRuleLine()
        }
    }

    // MARK: The results

    @ViewBuilder
    private var results: some View {
        if trimmedQuery.isEmpty {
            // Not an empty state and not an invitation — the field above is
            // already the invitation. Saying "start typing" under a focused
            // cursor is the app narrating what a person is already doing.
            EmptyView()
        } else if matches.isEmpty {
            Text("Nothing written down about that.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.monoLabel))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matches) { item in
                        row(item)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func row(_ item: LifeItem) -> some View {
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
                    // Done is a quieter ink, never a strikethrough and never a
                    // removal — the same rule the calendar's agenda follows.
                    Text(item.title)
                        .font(FieldType.listItem)
                        .foregroundStyle(
                            item.isDone
                                ? .fieldInk(.quietListItem)
                                : .fieldInk(.headline)
                        )
                        .fixedSize(horizontal: false, vertical: true)

                    // The answer to the question that brought somebody here.
                    Text(item.category.word.uppercased())
                        .font(FieldType.subLabel)
                        .tracking(FieldTracking.subLabel)
                        .foregroundStyle(.fieldInk(.recessive))
                }

                Spacer(minLength: 8)

                if item.isDone {
                    Text("DONE")
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.recessive))
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
        .accessibilityIdentifier("field.search.row")
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if !matches.isEmpty {
                Text("\(matches.count) FOUND")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))
            }

            Spacer()

            Button {
                close()
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
            .accessibilityIdentifier("field.search.done")
        }
    }

    // MARK: Reading

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything matching, open before done, each half newest first.
    ///
    /// `localizedStandardContains` rather than `lowercased().contains`: it is
    /// case *and* diacritic insensitive and it is the comparison the rest of
    /// the system uses, so "cafe" finds "Café" the way a person expects and
    /// the way Spotlight already taught them.
    ///
    /// Matches `detail` as well as `title`, because the second line is where
    /// the specifics go — a filter size, a room, a name — and those are
    /// precisely the words somebody comes here holding.
    private var matches: [LifeItem] {
        let needle = trimmedQuery
        guard !needle.isEmpty else { return [] }

        let found = store.state.lifeItems.filter { item in
            item.title.localizedStandardContains(needle)
                || (item.detail?.localizedStandardContains(needle) ?? false)
        }

        // Open first. Somebody searching for a thing is usually about to do
        // something about it, and a screen that leads with what is already
        // behind them answers a question nobody asked.
        return found.filter { !$0.isDone } + found.filter(\.isDone)
    }

    private func close() {
        isTyping = false
        store.closeSearch()
    }
}

#Preview {
    FieldZoneShell(store: FieldStore())
}
