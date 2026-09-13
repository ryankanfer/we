import SwiftUI

struct FieldLifeZone: View {
    @Environment(FieldStore.self) private var store
    @State private var filter = LifeFilter.plans
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
        .fullScreenCover(isPresented: $shareInboxIsOpen) { WEArtifactsView().environment(store) }
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

    private var header: some View {
        HStack(alignment: .center) {
            Text("Life").font(FieldType.hero)
            Spacer()
            Button { store.openSearch() } label: {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Search Life")
            .accessibilityIdentifier("field.life.search")
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
