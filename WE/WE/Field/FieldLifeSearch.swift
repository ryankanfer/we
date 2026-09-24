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
    @State private var privateSelection: WEArtifactSelection?
    /// The row somebody tapped. Presented from here rather than from the
    /// shell: this surface covers the shell, so a sheet mounted underneath it
    /// would open behind the takeover — the same reason
    /// `FieldCalendarSurface` holds its own.
    @State private var openItem: FieldItemReference?
    @FocusState private var isTyping: Bool

    var body: some View {
        ZStack {
            WECanvas.cream.bg.ignoresSafeArea()

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
        .onAppear { isTyping = true; if !store.searchSeed.isEmpty { query = store.searchSeed; store.searchSeed = "" }; if WEFeatureFlags.shareInboxEnabled { WEIntelligenceStore.shared.reload() } }
        .sheet(item: $privateSelection) { WEArtifactDetail(id: $0.id).environment(store) }
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
            FieldLabel("Find", ink: .labelQuiet)

            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(FieldType.categoryWord)
                .foregroundStyle(.fieldInk(.headline))
                .tint(store.identity.color(for: store.speaker))
                .focused($isTyping)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search saved items and Life plans")
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
        } else if matches.isEmpty && privateMatches.isEmpty && decisionAnswer == nil {
            Text("No saved items match that search.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.label))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let decisionAnswer {
                        Text(decisionAnswer)
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(.fieldInk(.headline))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WECanvas.cream.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                            .padding(.bottom, 12)
                            .accessibilityIdentifier("field.search.decision")
                    }
                    ForEach(privateMatches) { match in
                        VStack(alignment: .leading, spacing: 8) {
                            Button(match.document.title) { if let id = UUID(uuidString: match.id.id) { privateSelection = .init(id: id) } }
                            WEPrivacyLabel(text: "Only Me")
                            DisclosureGroup("Why this?") { Text(match.reason).font(.footnote) }
                        }.padding(.vertical, 12)
                    }
                    ForEach(matches) { item in
                        row(item)
                        if let result = semanticMatches.first(where: { $0.id.id == item.id }) {
                            DisclosureGroup("Why this?") { Text(result.reason).font(.footnote) }.padding(.bottom, 12)
                        }
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
                    isPrivate: item.visibility == .private,
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
                    WEPrivacyLabel(text: store.privacyLabel(for: item))
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
        // Deliberately not `.accessibilityElement(children: .combine)`: the
        // row is already an accessibility element, because it is a Button.
        // Combining *after* `.buttonStyle` wraps that element in a second
        // one rather than merging it, leaving a button inside a button —
        // VoiceOver reads the row twice, and a query by label matches two.
        // A Button already merges its label's children into one element
        // and reads them in order, which is what this row wants. See
        // `FieldLifeZone.categoryRow`, which combines the *content*
        // inside the label closure instead.
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
    private var semanticMatches: [WESearchMatch] {
        let eligible = store.intelligenceEligibleLifeItems
        return WESemanticSearch.matches(trimmedQuery, eligible: eligible.map {
            .init(id: .init(kind: .lifeItem, id: $0.id), title: $0.title, text: $0.detail ?? "", visibility: $0.objectVisibility)
        })
    }
    private var privateMatches: [WESearchMatch] {
        guard WEFeatureFlags.shareInboxEnabled else { return [] }
        return WESemanticSearch.matches(trimmedQuery, eligible: WEIntelligenceStore.shared.searchDocuments)
    }
    /// What the semantic search found, then anything whose words plainly
    /// contain what was typed — title, note, or the group it is in — so
    /// "food" finds everything in Food and a half-remembered word still
    /// lands. Semantic results keep their order at the top.
    private var matches: [LifeItem] {
        let eligible = store.intelligenceEligibleLifeItems
        let semantic = semanticMatches.compactMap { result in eligible.first { $0.id == result.id.id } }
        // The plain match reads everything already on this person's screen.
        // It is a string compare on the phone, the same as Life listing the
        // items, so it does not wait on the consent semantic search needs.
        let visible = store.state.lifeItems
        let seen = Set(semantic.map(\.id))
        let words = FieldLookupEngine.keywords(in: trimmedQuery)
        guard !words.isEmpty else { return semantic }
        let plain = FieldLookupEngine.rank(
            visible.filter { !seen.contains($0.id) },
            words: words,
            text: { [$0.title, $0.detail ?? "", $0.category.word].joined(separator: " ") },
            limit: 40
        )
        return semantic + plain
    }

    /// A decision you both confirmed that matches, said first and plainly.
    /// Only ever a confirmed one: "decided" is not a word WE guesses.
    private var decisionAnswer: String? {
        let words = FieldLookupEngine.keywords(in: trimmedQuery)
        guard !words.isEmpty else { return nil }
        return FieldLookupEngine.rank(
            store.chatMessages.filter { $0.decision && $0.confirmed },
            words: words,
            text: \.body,
            limit: 1
        ).first.map { FieldDayCopy.decided($0.body) }
    }

    private func close() {
        isTyping = false
        store.closeSearch()
    }
}

#Preview {
    FieldZoneShell(store: FieldStore())
}
