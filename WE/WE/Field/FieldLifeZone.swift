import SwiftUI

struct FieldLifeZone: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession
    @State private var filter = LifeFilter.plans
    /// Goals, which used to live in Us. Life is everything now.
    @State private var goalsAreOpen = false
    @State private var openGoal: FieldItemReference?
    @State private var openItem: FieldItemReference?
    @State private var putAwayIsOpen = false
    @State private var shareInboxIsOpen = false
    @State private var recoveryIsOpen = false
    @State private var intelligence = WEIntelligenceStore.shared

    private enum LifeFilter: String, CaseIterable {
        case plans = "Plans", saved = "Saved"
    }

    private var items: [LifeItem] { store.lifeStrata.all }
    private var decisions: [LifeItem] {
        items.filter { FieldItemPurpose.resolve($0) == .decision && !$0.isAwaitingSomeoneElse }
    }
    private var saved: [LifeItem] {
        items.filter { (FieldItemPurpose.resolve($0) == .reference || $0.sourceURL != nil) && !$0.isAwaitingSomeoneElse }
    }
    private var tasks: [LifeItem] {
        items.filter { FieldItemPurpose.resolve($0) == .task && !$0.isAwaitingSomeoneElse }
    }
    private var upcoming: [LifeItem] {
        let ids = Set(store.lifeStrata.thisWeek.map(\.id))
        return tasks.filter { ids.contains($0.id) }
    }
    private var later: [LifeItem] {
        let ids = Set(upcoming.map(\.id))
        return tasks.filter { !ids.contains($0.id) }
    }

    var body: some View {
        FieldZoneScaffold(zone: .life, showsZoneLabel: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                searchHero
                whereWereHeaded
                if WEFeatureFlags.shareInboxEnabled {
                    fromElsewhere
                    if !intelligence.issues.isEmpty || store.deliveryStates.values.contains(.needsAttention) {
                        Button("Needs attention", systemImage: "exclamationmark.circle") { recoveryIsOpen = true }
                            .font(.subheadline).frame(minHeight: 44)
                            .accessibilityIdentifier("intelligence.recovery")
                    }
                }
                filters
                if items.isEmpty {
                    Text("A place for the plans, choices and ideas you want to keep.")
                        .font(FieldType.pageHeadline)
                        .foregroundStyle(.fieldInk(.reasoning))
                } else {
                    contents
                }
                if !store.putAwayCategories.isEmpty {
                    Button("Put-away collections · \(store.putAwayCategories.count)") { putAwayIsOpen = true }
                        .font(FieldType.body)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("field.life.putAway")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.fieldInk(.headline))
        }
        .sheet(item: $openItem) { FieldItemSheet(itemID: $0.id).environment(store) }
        .sheet(isPresented: $recoveryIsOpen) { WERecoveryCenter().environment(store) }
        .sheet(isPresented: $putAwayIsOpen) { FieldPutAwaySheet().environment(store) }
        .sheet(isPresented: $goalsAreOpen) {
            FieldGoalsSurface().environment(store).environmentObject(session)
        }
        .sheet(item: $openGoal) {
            FieldGoalRoom(goalID: $0.id).environment(store).environmentObject(session)
        }
        .fullScreenCover(isPresented: $shareInboxIsOpen) { WEArtifactsView().environment(store) }
    }

    /// Goals — the long view — at the top of Life, above this week's plans,
    /// so everything below reads in its light. A line of goals rather than a
    /// card at the bottom of a long list, where it was found last if at all.
    /// Each goal opens itself; "See all" opens the full goals room, where a
    /// new one can be made.
    private var whereWereHeaded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where we're headed")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.fieldInk(.reasoning))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all") { goalsAreOpen = true }
                    .font(.system(.subheadline))
                    .foregroundStyle(.fieldInk(.headline))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("field.life.goals")
            }

            if store.state.horizons.isEmpty {
                Text("Goals you both choose will live here.")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(.fieldInk(.legend))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(goals) { goal in
                            Button {
                                openGoal = FieldItemReference(id: goal.id)
                            } label: {
                                Text(goal.title.trimmingCharacters(in: CharacterSet(charactersIn: ", ")))
                                    .font(.system(size: 17, design: .serif))
                                    .foregroundStyle(.fieldInk(.headline))
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(WECanvas.cream.bgElevated, in: Capsule())
                                    .overlay {
                                        if goal.isPrimary {
                                            Capsule().strokeBorder(WECanvas.cream.ink.opacity(0.35), lineWidth: 1)
                                        }
                                    }
                            }
                            .accessibilityHint("Opens this goal")
                            .accessibilityIdentifier("field.life.goal")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// The primary goal first, then the rest in the order they were made.
    private var goals: [FieldHorizon] {
        store.state.horizons.filter(\.isPrimary) + store.state.horizons.filter { !$0.isPrimary }
    }

    private var fromElsewhere: some View {
        Button { shareInboxIsOpen = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 23, weight: .light))
                VStack(alignment: .leading, spacing: 6) {
                    Text("From elsewhere").font(FieldType.weLifeSection)
                    Text("Save a thought, image, or link. Only Me until you share.")
                        .font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
            }
            .padding(20)
            .background(WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .accessibilityHint("Review links saved through the Share Sheet")
        .accessibilityIdentifier("field.life.fromElsewhere")
    }

    // MARK: Search, in the middle

    /// Life opens on a question. Most of the time somebody comes to Life to
    /// find one thing — the wine for Dad, the passport date — so the box for
    /// that sits in the middle of the first screen, and everything else is
    /// one scroll down.
    private var searchHero: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text("What are you looking for?")
                .font(.system(size: 24, design: .serif))
                .foregroundStyle(.fieldInk(.headline))
                .multilineTextAlignment(.center)

            Button { store.openSearch() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                    FieldSearchHint(examples: searchExamples)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .background(WECanvas.cream.bgElevated, in: Capsule())
                .overlay { Capsule().strokeBorder(WECanvas.cream.ink.opacity(0.28), lineWidth: 1) }
                .contentShape(Capsule())
            }
            .accessibilityLabel("Search Life")
            .accessibilityIdentifier("field.life.search")

            if !searchSuggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(searchSuggestions, id: \.self) { word in
                        Button { store.openSearch(word) } label: {
                            Text(word)
                                .font(.system(size: 14))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .overlay { Capsule().strokeBorder(WECanvas.cream.ink.opacity(0.18), lineWidth: 1) }
                                .contentShape(Capsule())
                        }
                        .accessibilityLabel("Search \(word)")
                    }
                }
            }
            Spacer(minLength: 0)
            if !items.isEmpty {
                Label("Everything below", systemImage: "chevron.down")
                    .font(.system(size: 13))
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical) { height, _ in height * 0.62 }
    }

    /// Real things from Life, cycled in the empty box, so it shows what it
    /// can find rather than saying "Search".
    private var searchExamples: [String] {
        let titles = items.filter { !$0.isDone }.prefix(6).map { $0.title.lowercased() }
        return titles.isEmpty ? ["the wine for dad"] : Array(titles)
    }

    /// The groups you actually have things in, most first.
    private var searchSuggestions: [String] {
        Dictionary(grouping: items.filter { !$0.isDone }, by: \.category)
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map { $0.key.word }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Life").font(FieldType.hero)
            Spacer()
            Button { store.openCalendar() } label: {
                Image(systemName: "calendar").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Calendar")
            .accessibilityIdentifier("field.life.calendar")
        }
        .font(.system(size: 20, weight: .regular))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(LifeFilter.allCases, id: \.self) { value in
                    Button { filter = value } label: {
                        Text(value.rawValue)
                            .font(.system(.subheadline, weight: filter == value ? .semibold : .regular))
                            .foregroundStyle(filter == value ? .fieldInk(.headline) : .fieldInk(.reasoning))
                            .padding(.bottom, 12)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) {
                                if filter == value {
                                    Rectangle().fill(WECanvas.cream.ink).frame(height: 2)
                                }
                            }
                    }
                    .accessibilityAddTraits(filter == value ? .isSelected : [])
                    .accessibilityIdentifier("field.life.filter.\(value)")
                }
            }
        }
        .overlay(alignment: .bottom) { FieldRuleLine(color: FieldRule.row) }
    }

    @ViewBuilder private var contents: some View {
        switch filter {
        case .plans:
            Text("The things you’re deciding and doing.")
                .font(FieldType.body).foregroundStyle(.fieldInk(.reasoning))
            if decisions.isEmpty && tasks.isEmpty && !items.contains(where: \.isAwaitingSomeoneElse) {
                emptyFilter("Nothing needs a next step right now.")
            }
            section("Needs a decision", subtitle: "Turn an open question into a plan.", items: decisions)
            section("Up next", subtitle: nil, items: upcoming)
            section("Waiting", subtitle: "A reply or someone else’s next move.", items: items.filter(\.isAwaitingSomeoneElse))
            section("Later", subtitle: nil, items: later)
        case .saved:
            Text("Links you send each other, and ideas worth keeping.")
                .font(FieldType.body).foregroundStyle(.fieldInk(.reasoning))
            if saved.isEmpty { emptyFilter("Keep something you want to come back to together.") }
            section("Links to revisit", subtitle: "Open the original. Keep your thoughts alongside it.", items: saved.filter { $0.sourceURL != nil })
            section("Ideas to keep", subtitle: nil, items: saved.filter { $0.sourceURL == nil })
        }
    }

    private func emptyFilter(_ text: String) -> some View {
        Text(text).font(FieldType.captureWriting).foregroundStyle(.fieldInk(.reasoning)).padding(.vertical, 24)
    }

    @ViewBuilder private func section(_ title: String, subtitle: String?, items: [LifeItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(FieldType.weLifeSection)
                    Spacer()
                    Text("\(items.count)").font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
                }
                if let subtitle {
                    Text(subtitle).font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
                }
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id { FieldRuleLine(color: FieldRule.watching) }
                    }
                }
            }
        }
    }

    private func row(_ item: LifeItem) -> some View {
        Button { openItem = FieldItemReference(id: item.id) } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    WEPrivacyLabel(text: store.privacyLabel(for: item))
                    Text(item.title)
                        .font(.system(.body, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        FieldDot(owner: item.owner, identity: store.identity, size: 6, baselineNudge: 0)
                        Text(filter == .saved ? (item.sourceURL?.host ?? item.category.word) : (item.dueOn.map(dateLabel) ?? item.category.word))
                        Text("·")
                        Text(FieldItemPurpose.resolve(item) == .decision ? "Choose a direction" : store.identity.name(for: item.owner))
                    }
                    .font(.system(.caption))
                    .foregroundStyle(.fieldInk(.reasoning))
                }
                Spacer(minLength: 0)
                Image(systemName: filter == .saved && item.sourceURL != nil ? "link" : "arrow.up.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.fieldInk(.reasoning))
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(item.title)
        .accessibilityHint(FieldItemPurpose.actionLabel(item))
        .accessibilityIdentifier("field.life.item")
    }

    private func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.gregorianUS
        if calendar.isDate(date, inSameDayAs: store.now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: store.now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return DateFormatter.fieldDayMonth.string(from: date)
    }
}

extension FieldType {
    static var weLifeSection: Font { .system(.title3, design: .serif, weight: .regular) }
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

/// The placeholder in Life's search box: one real thing at a time, changing
/// every few seconds. Still under Reduce Motion, which gets the first one.
private struct FieldSearchHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let examples: [String]
    @State private var index = 0

    var body: some View {
        Text("\(examples[index % max(examples.count, 1)])…")
            .font(.system(size: 17, design: .serif))
            .foregroundStyle(.fieldInk(.legend))
            .lineLimit(1)
            .id(index)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .task(id: examples) {
                guard !reduceMotion, examples.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: 0.4)) { index += 1 }
                }
            }
    }
}
