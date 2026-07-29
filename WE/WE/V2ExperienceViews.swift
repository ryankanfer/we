import SwiftUI

struct HorizonGlimpse: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsPlanEditor = false

    var body: some View {
        Button {
            showsPlanEditor = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sun.horizon.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(personalHue.atmosphereColor)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.06), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Something coming up?")
                        .font(.weHeadline)
                        .foregroundStyle(.white)

                    Text("Keep a plan or possibility in view.")
                        .font(.weSubheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28, height: 44)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(WEPressableCardStyle())
        .disabled(!session.canMutate)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .accessibilityLabel("Add something ahead")
        .accessibilityHint(
            "Opens one editor for a shared plan or possibility"
        )
        .sheet(isPresented: $showsPlanEditor) {
            PlanEditor()
        }
        .accessibilityIdentifier("horizonGlimpse")
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }
}

struct ContextualSuggestionCard: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsReview = false
    let suggestion: ContextualSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.evidence.context.uppercased())
                .font(.weMeta)
                .tracking(1.4)
                .foregroundStyle(personalHue.atmosphereColor)

            Text(suggestion.title)
                .font(.weTitle)
                .foregroundStyle(.white)

            Text(suggestion.evidence.reason)
                .font(.weSubheadline)
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 10) {
                Button("Review and add") {
                    showsReview = true
                }
                .buttonStyle(.borderedProminent)
                .tint(personalHue.controlColor)
                .disabled(!session.canMutate)

                Button("Not useful") {
                    Task {
                        await session.dismissContextualSuggestion(
                            id: suggestion.id
                        )
                    }
                }
                .buttonStyle(WESecondaryButtonStyle(tintColor: .white.opacity(0.78)))
                .disabled(!session.canMutate)
            }
            .frame(minHeight: 44)

            DisclosureGroup("Why WE suggested this") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(suggestion.provenance.rule)
                    ForEach(suggestion.evidence.sharedInputs) { source in
                        Label(source.label, systemImage: "link")
                    }
                    Text("Uses shared data only.")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 8)
            }
            .tint(.white.opacity(0.68))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            personalHue.color.opacity(0.13),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(personalHue.color.opacity(0.3), lineWidth: 1)
        }
        .sheet(isPresented: $showsReview) {
            SuggestionReviewSheet(suggestion: suggestion)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contextualSuggestion")
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }
}

private struct SuggestionReviewSheet: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note = ""
    @State private var owner: ResponsibilityOwner = .together
    @State private var includesDate: Bool
    @State private var date: Date
    let suggestion: ContextualSuggestion

    init(suggestion: ContextualSuggestion) {
        self.suggestion = suggestion
        _title = State(initialValue: suggestion.proposedResponsibilityTitle)
        let inferred = suggestion.proposedScheduledOn.flatMap {
            DateFormatter.weDay.date(from: $0)
        }
        _includesDate = State(initialValue: inferred != nil)
        _date = State(initialValue: inferred ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    TextField("Title", text: $title)
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(2 ... 4)

                    LabeledContent("Destination", value: "Shared Life")
                    Picker("Held by", selection: $owner) {
                        Text("Together").tag(ResponsibilityOwner.together)
                        Text("Me").tag(ResponsibilityOwner.me)
                        Text(session.partnerName)
                            .tag(ResponsibilityOwner.partner)
                    }

                    LabeledContent(
                        "Related plan",
                        value: relatedPlanTitle
                    )

                    Toggle("Add a date", isOn: $includesDate)
                    if includesDate {
                        DatePicker(
                            "Before the plan",
                            selection: $date,
                            displayedComponents: .date
                        )
                    }
                }

                Section("What produced this") {
                    Text(suggestion.evidence.reason)
                    ForEach(suggestion.provenance.references) { reference in
                        Label(reference.label, systemImage: "link")
                    }
                    Label(
                        "No private reflections or unrevealed answers",
                        systemImage: "lock.shield"
                    )
                }

                Section {
                    Button("Add to shared list") {
                        Task {
                            await session.confirmContextualSuggestion(
                                SuggestionConfirmation(
                                    suggestionID: suggestion.id,
                                    title: title,
                                    note: note.nilIfEmpty,
                                    owner: owner,
                                    scheduledOn: includesDate
                                        ? DateFormatter.weDay.string(from: date)
                                        : nil
                                )
                            )
                            if session.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || !session.canMutate
                    )
                }

                SessionMessageView()
            }
            .navigationTitle("Review shared care")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var relatedPlanTitle: String {
        session.plans.first {
            $0.id == suggestion.relatedPlanID
        }?.title ?? suggestion.evidence.context
    }
}

struct PresenceControl: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(PresenceMode.allCases, id: \.self) { mode in
                let isSelected = mode == session.presenceMode
                Button {
                    Task { await session.setPresence(mode) }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(modeTint(for: mode).opacity(
                                    isSelected ? 0.22 : 0.055
                                ))
                                .frame(width: 38, height: 38)

                            Circle()
                                .stroke(
                                    modeTint(for: mode).opacity(
                                        isSelected ? 0.92 : 0.34
                                    ),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                                .frame(width: 38, height: 38)

                            Image(systemName: presenceSymbol(for: mode))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    isSelected
                                        ? Color.weInk
                                        : Color.weInkTertiary
                                )
                        }
                        .shadow(
                            color: modeTint(for: mode).opacity(
                                isSelected ? 0.46 : 0
                            ),
                            radius: 12
                        )

                        Text(mode.title)
                            .font(.weMeta)
                            .foregroundStyle(
                                isSelected
                                    ? Color.weInk
                                    : Color.weInkTertiary
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint(mode.detail)
            }
        }
        .animation(
            reduceMotion ? nil : .weQuick,
            value: session.presenceMode
        )
        .sensoryFeedback(.selection, trigger: session.presenceMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Relationship Presence Mode")
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private func modeTint(for mode: PresenceMode) -> Color {
        switch mode {
        case .apart:
            personalHue.atmosphereColor
        case .together:
            personalHue.controlColor
        case .away:
            relationshipPartnerHue(session).atmosphereColor
        }
    }

    private func presenceSymbol(for mode: PresenceMode) -> String {
        switch mode {
        case .apart: "circle.dotted"
        case .together: "person.2.fill"
        case .away: "airplane"
        }
    }
}

struct ThreadPullHandle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull: CGFloat = 0
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    Circle().fill(Color("WEBurgundy")).frame(width: 9, height: 9)
                    Circle().fill(Color("WESage")).frame(width: 9, height: 9)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.72))
            .frame(width: 54, height: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .offset(y: pull)
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged {
                    pull = max(0, min(52, $0.translation.height))
                }
                .onEnded { _ in
                    if pull >= 34 { onOpen() }
                    withAnimation(reduceMotion ? nil : .weState) {
                        pull = 0
                    }
                }
        )
        .accessibilityLabel("Open the Thread")
        .accessibilityHint("Shows everything WE has held together")
        .accessibilityAction(named: "Open the Thread", onOpen)
    }
}

struct ThreadView: View {
    private enum Filter: String, CaseIterable {
        case everything = "Everything"
        case apart = "Held while apart"
    }

    @EnvironmentObject private var session: AppSession
    @State private var filter: Filter = .everything
    @State private var selectedEvidence: ThreadEvidence?
    let onClose: (() -> Void)?
    let onProfile: (() -> Void)?

    init(
        onClose: (() -> Void)? = nil,
        onProfile: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onProfile = onProfile
    }

    var body: some View {
        ZStack {
            Color.weCanvas.ignoresSafeArea()

            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        usFocusScene(
                            minHeight: max(viewport.size.height, 620)
                        )
                        .weArrival()

                        threadLibrary
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbarBackground(Color.weCanvas, for: .navigationBar)
        .sheet(item: $selectedEvidence) {
            EvidenceSheet(
                title: $0.title,
                references: $0.references
            )
        }
    }

    private func usFocusScene(minHeight: CGFloat) -> some View {
        WECinematicFocusScene(
            artwork: .horizon,
            minHeight: minHeight,
            focalPoint: .bottom,
            intensity: 0.96
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if let onClose {
                    HStack {
                        Text("WE")
                            .font(.weMeta)
                            .tracking(1.8)
                            .foregroundStyle(Color.weInkTertiary)

                        Spacer()

                        Button("Close", action: onClose)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.weInkSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                } else if let onProfile {
                    WEEditorialScreenHeader(
                        title: "Us",
                        profileName: session.snapshot?.profile.name ?? "You",
                        onProfile: onProfile
                    )
                } else {
                    Text("WE")
                        .font(.weMeta)
                        .tracking(1.8)
                        .foregroundStyle(Color.weInkTertiary)

                    Text("Us")
                        .font(.weLargeTitle)
                        .foregroundStyle(Color.weInk)
                        .padding(.top, 2)
                }

                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 10) {
                    Text("OUR MEMORY")
                        .font(.weMeta)
                        .tracking(1.8)
                        .foregroundStyle(Color.weInkTertiary)

                    Text(heroTitle)
                        .font(.weLargeTitle)
                        .foregroundStyle(Color.weInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(heroDetail)
                        .font(.weSubheadline)
                        .foregroundStyle(Color.weInkSecondary)
                        .frame(maxWidth: 330, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 24)

                HStack(spacing: 8) {
                    Text("What you hold together")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.weInkSecondary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 76)
        }
    }

    @ViewBuilder
    private var threadLibrary: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnchorsSection()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THREAD")
                        .font(.weMeta)
                        .tracking(1.8)
                        .foregroundStyle(Color.weInkTertiary)
                    Text("What you have held together")
                        .font(.weTitle)
                        .foregroundStyle(Color.weInk)
                }

                Spacer()

                if !session.relationshipEvents.isEmpty {
                    Text("\(session.relationshipEvents.count)")
                        .font(.weMeta)
                        .foregroundStyle(Color.weInkTertiary)
                }
            }
            .padding(.top, 28)

            if session.relationshipEvents.isEmpty {
                WECinematicPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The memory has not been made yet.")
                            .font(.weTitle)
                            .foregroundStyle(Color.weInk)
                        Text("Moments you both choose to close will gather here, quietly and in order.")
                            .font(.weSubheadline)
                            .foregroundStyle(Color.weInkSecondary)
                    }
                }
                .padding(.top, 14)
            } else {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.self) { item in
                        Button(item.rawValue) { filter = item }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                filter == item
                                    ? Color.weInk
                                    : Color.weInkTertiary
                            )
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(
                                filter == item
                                    ? Color.weSurfaceRaised
                                    : Color.clear,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(Color.weHairline)
                            }
                    }
                }
                .padding(.top, 18)
            }

            ForEach(groupedEvents, id: \.month) { group in
                monthHeader(group.month)
                    .padding(.top, 24)
                ForEach(group.events) { event in
                    threadRow(event)
                }
            }

            ForEach(session.seasons.reversed()) { season in
                NavigationLink {
                    SeasonDetailView(season: season)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A SEASON IS READY")
                            .font(.weCaption)
                            .tracking(1.6)
                            .foregroundStyle(Color("WEBurgundySoft"))
                        Text(season.title)
                            .font(.weTitle)
                            .foregroundStyle(.white)
                        Text("Read the season")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Text("WE keeps nothing either of you did not choose to close.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.34))
                .padding(.top, 18)
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 44)
        .background(Color.weCanvas)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var heroTitle: String {
        if let anchor = session.anchors.first(where: \.isActive) {
            return anchor.title
        }
        if let season = session.seasons.last {
            return season.title
        }
        return "Everything between you has somewhere to belong."
    }

    private var heroDetail: String {
        if session.relationshipEvents.isEmpty {
            return "The first shared memory will appear after you close something together."
        }
        return threadSummary
    }

    private var visibleEvents: [RelationshipEvent] {
        let sorted = session.relationshipEvents.sorted {
            $0.occurredAt > $1.occurredAt
        }
        guard filter == .apart else { return sorted }
        return sorted.filter { event in
            event.provenance.contains {
                $0.label.localizedCaseInsensitiveContains("apart")
            }
        }
    }

    private var groupedEvents: [(month: String, events: [RelationshipEvent])] {
        var order: [String] = []
        var groups: [String: [RelationshipEvent]] = [:]
        for event in visibleEvents {
            let month = eventMonth(event)
            if groups[month] == nil { order.append(month) }
            groups[month, default: []].append(event)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private var threadSummary: String {
        "\(session.relationshipEvents.count) things closed together, in the order you held them."
    }

    private func monthHeader(_ month: String) -> some View {
        HStack(spacing: 10) {
            Text(month.uppercased())
                .font(.weCaption)
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.4))
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
    }

    private func threadRow(_ event: RelationshipEvent) -> some View {
        Button {
            selectedEvidence = ThreadEvidence(
                id: event.id,
                title: event.title,
                references: event.provenance
            )
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(eventDay(event))
                    .font(.weBody)
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 28, alignment: .leading)

                HStack(spacing: 0) {
                    Circle().fill(personalHue.color).frame(width: 8, height: 8)
                    Circle()
                        .fill(relationshipPartnerHue(session).color)
                        .frame(width: 8, height: 8)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(eventKicker(event))
                        .font(.weCaption)
                        .tracking(1.4)
                        .foregroundStyle(
                            event.type == .mutualResolution
                                ? Color("WEBurgundySoft")
                                : .white.opacity(0.46)
                        )
                    Text(event.title)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.white)
                    Text(event.type.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.075)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the shared evidence for this entry")
    }

    private func eventDate(_ event: RelationshipEvent) -> Date? {
        ISO8601DateFormatter.we.date(from: event.occurredAt)
            ?? ISO8601DateFormatter.weFlexible.date(from: event.occurredAt)
    }

    private func eventMonth(_ event: RelationshipEvent) -> String {
        eventDate(event)?.formatted(.dateTime.month(.wide).year())
            ?? "Shared"
    }

    private func eventDay(_ event: RelationshipEvent) -> String {
        eventDate(event)?.formatted(.dateTime.day()) ?? "—"
    }

    private func eventKicker(_ event: RelationshipEvent) -> String {
        switch event.type {
        case .mutualResolution: "MUTUAL RESOLUTION"
        case .responsibilityCompleted, .handoffAccepted: "CARE SETTLED"
        case .planCompleted: "A PLAN KEPT"
        case .sharedMomentOpened: "A SHARED MOMENT"
        }
    }
}

private struct ThreadEvidence: Identifiable {
    let id: String
    let title: String
    let references: [ProvenanceReference]
}

private struct SeasonDetailView: View {
    @EnvironmentObject private var session: AppSession
    let season: Season

    var body: some View {
        ZStack {
            Color.weCanvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SEASON \(season.sequence) · WITH \(session.partnerName.uppercased())")
                        .font(.weCaption)
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.48))
                    Text(season.title)
                        .font(.weLargeTitle)
                        .foregroundStyle(.white)
                        .padding(.top, 10)
                    Text(season.summary)
                        .font(.weBody)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 12)

                    HStack(spacing: 10) {
                        seasonCount("\(events.count)", "CLOSED\nTOGETHER")
                        seasonCount("\(care.count)", "CARE\nSETTLED")
                        seasonCount("\(mutual.count)", "MUTUAL\nREVEALS")
                    }
                    .padding(.top, 24)

                    seasonSection("WHAT YOU HELD", events: mutual)
                    seasonSection("WHAT YOU LET GO", events: care)

                    Text("Every line above comes from a shared event both of you could see.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.top, 28)
                }
                .padding(24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("The Season")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var events: [RelationshipEvent] {
        session.relationshipEvents.filter { season.eventIDs.contains($0.id) }
    }
    private var mutual: [RelationshipEvent] {
        events.filter { $0.type == .mutualResolution || $0.type == .sharedMomentOpened }
    }
    private var care: [RelationshipEvent] {
        events.filter { $0.type == .responsibilityCompleted || $0.type == .handoffAccepted }
    }

    private func seasonCount(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.weLargeTitle).foregroundStyle(.white)
            Text(label)
                .font(.weCaption)
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.44))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)) }
    }

    @ViewBuilder
    private func seasonSection(
        _ title: String,
        events: [RelationshipEvent]
    ) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.weCaption)
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.44))
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.weTitle).foregroundStyle(.white)
                        Text(event.type.title)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.44))
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                    }
                }
            }
            .padding(.top, 28)
        }
    }
}

struct SeasonReadyCard: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("A season is ready", systemImage: "circle.hexagongrid.fill")
                .font(.weCaption)
                .tracking(1.15)
                .textCase(.uppercase)
            Text("Six weeks of shared moments have formed something you can look back on.")
                .font(.weBody)
            Button("Create this season") {
                Task { await session.createReadySeason() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("WEBurgundy"))
            .disabled(!session.canMutate)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color("WEBurgundy").opacity(0.24),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seasonReady")
    }
}

private struct EvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let references: [ProvenanceReference]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title)
                        .font(.weTitle)
                }
                Section("Shared evidence") {
                    ForEach(references) { reference in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reference.label)
                            Text(reference.kind.rawValue.replacingOccurrences(
                                of: "_",
                                with: " "
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Label(
                        "Every line is traceable to shared events.",
                        systemImage: "checkmark.shield"
                    )
                }
            }
            .navigationTitle("Why this surfaced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SignalConsentView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        List {
            Section {
                Text("WE notices only shared signals both people allow. Private reflection is outside the intelligence layer.")
            }

            ForEach(SignalKind.allCases, id: \.self) { signal in
                Toggle(
                    isOn: Binding(
                        get: { enabled(signal) },
                        set: { value in
                            Task {
                                await session.setSignalConsent(
                                    signal,
                                    enabled: value
                                )
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.title)
                        Text(signal.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(
                    signal.isPermanentlyDisabled || !session.canMutate
                )
                .accessibilityHint(signal.detail)
            }
        }
        .navigationTitle("How WE notices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func enabled(_ signal: SignalKind) -> Bool {
        guard !signal.isPermanentlyDisabled else { return false }
        return session.v2State.signalConsents.first {
            $0.profileID == session.user?.id && $0.signal == signal
        }?.isEnabled ?? true
    }
}

struct ModeSettingsView: View {
    @EnvironmentObject private var host: SessionHost
    @State private var confirmsReset = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: modeBinding) {
                    ForEach(AppMode.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(
                    host.mode == .actual
                        ? "Actual uses your live relationship and Supabase."
                        : "Simulation is local to this device and never writes to Supabase."
                )
            }

            if host.mode == .simulation {
                Section("Viewer") {
                    Picker("Viewing as", selection: viewerBinding) {
                        ForEach(SimulationViewer.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Reset scenario", role: .destructive) {
                        confirmsReset = true
                    }
                }
            }
        }
        .navigationTitle("Mode")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset the shared simulation?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset simulation", role: .destructive) {
                Task { await host.resetSimulation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ryan and Dylan will both return to the starting scenario.")
        }
    }

    private var modeBinding: Binding<AppMode> {
        Binding(
            get: { host.mode },
            set: { value in Task { await host.setMode(value) } }
        )
    }

    private var viewerBinding: Binding<SimulationViewer> {
        Binding(
            get: { host.viewer },
            set: { value in Task { await host.setViewer(value) } }
        )
    }
}

struct SimulationMarker: View {
    @EnvironmentObject private var host: SessionHost

    var body: some View {
        if host.mode == .simulation {
            HStack(spacing: 6) {
                Image(systemName: "testtube.2")
                Text("Simulation · \(host.viewer.title)")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                Color.weCanvas.opacity(0.86),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(.white.opacity(0.12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("simulationMarker")
        }
    }
}

struct AnchorsSection: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANCHOR")
                        .font(.weMeta)
                        .tracking(1.8)
                        .foregroundStyle(Color.weInkTertiary)
                    Text("What brings you back")
                        .font(.weTitle)
                        .foregroundStyle(Color.weInk)
                }

                Spacer()

                Button {
                    showsEditor = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.weInkSecondary)
                        .frame(width: 44, height: 44)
                }
                .disabled(!session.canMutate)
                .accessibilityLabel("Add an Anchor")
            }

            if activeAnchors.isEmpty {
                Text("A small shared rhythm can live here without becoming a task.")
                    .font(.weSubheadline)
                    .foregroundStyle(Color.weInkSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(activeAnchors) { anchor in
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(Color("WESage"))
                            .frame(width: 7, height: 7)
                            .padding(.top, 8)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(anchor.title)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Color.weInk)
                            if let note = anchor.note {
                                Text(note)
                                    .font(.weSubheadline)
                                    .foregroundStyle(Color.weInkSecondary)
                            }
                        }

                        Spacer()

                        Menu {
                            Button("Let this rest") {
                                Task {
                                    await session.setAnchorActive(
                                        id: anchor.id,
                                        isActive: false
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(Color.weInkTertiary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.weHairline)
                            .frame(height: 0.5)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            AnchorEditor()
        }
    }

    private var activeAnchors: [Anchor] {
        session.anchors.filter(\.isActive)
    }
}

struct HandoffInbox: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if !offers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ProductSectionHeader(title: "Care offered to you")
                ForEach(offers) { offer in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(responsibilityTitle(offer))
                            .font(.weHeadline)
                        Text("You can take this on, or let the offer rest. A decline does not become a score.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Take this on") {
                                Task {
                                    await session.respondToHandoff(
                                        id: offer.id,
                                        accept: true
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color("WESage"))

                            Button("Not now") {
                                Task {
                                    await session.respondToHandoff(
                                        id: offer.id,
                                        accept: false
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .background(
                        .white.opacity(0.07),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }
            }
        }
    }

    private var offers: [ResponsibilityHandoff] {
        session.handoffs.filter {
            $0.toProfileID == session.user?.id && $0.status == .offered
        }
    }

    private func responsibilityTitle(
        _ handoff: ResponsibilityHandoff
    ) -> String {
        session.responsibilities.first {
            $0.id == handoff.responsibilityID
        }?.title ?? "Shared care"
    }
}

private struct AnchorEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var cadence: AnchorCadence = .weekly

    var body: some View {
        NavigationStack {
            Form {
                TextField("Anchor", text: $title)
                TextField("Optional note", text: $note, axis: .vertical)
                Picker("Rhythm", selection: $cadence) {
                    ForEach(AnchorCadence.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }
            .navigationTitle("Add an Anchor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await session.createAnchor(
                                AnchorInput(
                                    title: title,
                                    note: note.nilIfEmpty,
                                    cadence: cadence
                                )
                            )
                            if session.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || !session.canMutate
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ApproachButton: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsEditor = false
    let plan: PlanItem

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            Label("Approach", systemImage: "arrow.trianglehead.merge")
                .font(.caption.weight(.semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showsEditor) {
            ApproachEditor(plan: plan)
        }
    }
}

struct ApproachEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var approach: ApproachKind = .gently
    @State private var note = ""
    let plan: PlanItem

    var body: some View {
        NavigationStack {
            Form {
                Section(plan.title) {
                    Picker("How should you approach it?", selection: $approach) {
                        ForEach(ApproachKind.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    TextField(
                        "Optional private note",
                        text: $note,
                        axis: .vertical
                    )
                }

                if let partnerApproach {
                    Section("\(session.partnerName)’s approach") {
                        LabeledContent(
                            "How",
                            value: partnerApproach.approach.title
                        )
                        if let note = partnerApproach.note {
                            Text(note)
                        }
                        Label(
                            "Opened because both of you named an approach",
                            systemImage: "person.2.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Label(
                            "Held privately until both of you name an approach",
                            systemImage: "lock"
                        )
                    }
                }
            }
            .navigationTitle("Approach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await session.setApproach(
                                planID: plan.id,
                                approach: approach,
                                note: note.nilIfEmpty
                            )
                            if session.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(!session.canMutate)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard let myApproach else { return }
            approach = myApproach.approach
            note = myApproach.note ?? ""
        }
    }

    private var myApproach: PlanApproach? {
        session.v2State.approaches.first {
            $0.planID == plan.id && $0.profileID == session.user?.id
        }
    }

    private var partnerApproach: PlanApproach? {
        session.v2State.approaches.first {
            $0.planID == plan.id
                && $0.profileID != session.user?.id
                && $0.revealedAt != nil
        }
    }
}

struct PassThePhoneView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var currentAnswer = ""
    @State private var firstAnswer = ""
    @State private var sharedSummary = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                if step < 2 {
                    Text(step == 0 ? "For you" : "Pass to \(session.partnerName)")
                        .font(.weLargeTitle)
                    Text("What would help tonight feel cared for?")
                        .font(.weTitle)
                    TextEditor(text: $currentAnswer)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(
                            .white.opacity(0.07),
                            in: RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                        .accessibilityLabel("Private answer")
                    Text("This answer stays on this phone and is cleared after the shared line is made.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(step == 0 ? "Hold and pass" : "Make one shared line") {
                        advance()
                    }
                    .buttonStyle(WEPrimaryButtonStyle())
                    .disabled(currentAnswer.nilIfEmpty == nil)
                } else {
                    Text("One thing to carry together")
                        .font(.weLargeTitle)
                    Text(sharedSummary)
                        .font(.weTitle)
                    Label(
                        "Individual answers were cleared",
                        systemImage: "checkmark.shield"
                    )
                    .foregroundStyle(.secondary)
                    Button("Done") { dismiss() }
                        .buttonStyle(WEPrimaryButtonStyle())
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Pass the phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        clearAnswers()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if step == 0 {
            firstAnswer = currentAnswer
            currentAnswer = ""
            step = 1
        } else {
            sharedSummary = "Make room for care, then choose the smallest next step together."
            clearAnswers()
            step = 2
        }
    }

    private func clearAnswers() {
        firstAnswer = ""
        currentAnswer = ""
    }
}
