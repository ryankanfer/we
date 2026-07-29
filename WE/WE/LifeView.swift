import SwiftUI

struct LifeView: View {
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case me = "Me"
        case partner = "Partner"
        case together = "Together"

        var id: String { rawValue }
    }

    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAdd = false
    @State private var editing: Responsibility?
    @State private var selectedFilter: FilterOption = .all

    let onProfile: () -> Void

    var body: some View {
        ZStack {
            WarmEditorialBackground()
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        lifeRhythmFocusScene(
                            minHeight: max(viewport.size.height, 620)
                        )
                        .weArrival()

                        lifeLibrary
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsAdd) { ResponsibilityEditor() }
        .sheet(item: $editing) { ResponsibilityEditor(responsibility: $0) }
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .weState,
            value: active.map(\.id)
        )
    }

    private var header: some View {
        WEEditorialScreenHeader(
            title: "Life",
            profileName: session.snapshot?.profile.name ?? "You",
            actionSystemImage: "plus",
            actionAccessibilityLabel: "Name some care",
            actionEnabled: session.canMutate,
            onAction: { showsAdd = true },
            onProfile: onProfile
        )
    }

    @ViewBuilder
    private var lifeLibrary: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LIFE")
                    .font(.weMeta)
                    .tracking(1.8)
                    .foregroundStyle(Color.weInkTertiary)
                Text("Everything else you are carrying")
                    .font(.weTitle)
                    .foregroundStyle(Color.weInk)
            }

            HandoffInbox()
                .weArrival(order: 2)

            if !active.isEmpty {
                carePromise
                    .weArrival(order: 1)

                filterCapsuleBar
                    .weArrival(order: 2)
            }

            if active.isEmpty {
                EditorialEmptyState(
                    symbol: "hands.and.sparkles",
                    title: "Nothing needs naming right now.",
                    message: "Name a piece of care when making it visible would help life feel lighter.",
                    actionTitle: session.canMutate ? "Name some care" : nil,
                    action: { showsAdd = true }
                )
                .weArrival(order: 3)
            } else if filteredActive.isEmpty {
                EditorialEmptyState(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "Nothing is \(emptyFilterPhrase).",
                    message: "The rest of what you carry is still here.",
                    actionTitle: "Show everything",
                    action: {
                        withAnimation(
                            reduceMotion
                                ? .easeOut(duration: 0.16)
                                : .weState
                        ) {
                            selectedFilter = .all
                        }
                    }
                )
                .weArrival(order: 3)
            } else {
                ForEach(
                    Array(ResponsibilityOwner.allCases.enumerated()),
                    id: \.element
                ) { index, owner in
                    let items = filteredActive.filter { $0.owner == owner }
                    if !items.isEmpty {
                        responsibilitySection(
                            ownerSectionTitle(owner),
                            items: items
                        )
                        .weArrival(order: index + 4)
                    }
                }
            }

            if !lifeStream.isEmpty && selectedFilter == .all {
                lifeStreamSection
                    .weArrival(order: 8)
            }

            SessionMessageView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 36)
        .background(Color.weCanvas)
    }

    private var active: [Responsibility] { session.responsibilities.filter { $0.status == .active } }
    private var activePlans: [PlanItem] {
        session.plans
            .filter { $0.status == .active }
            .sorted { ($0.scheduledOn ?? "9999") < ($1.scheduledOn ?? "9999") }
    }
    private var completedCare: [Responsibility] {
        session.responsibilities.filter { $0.status == .completed }
    }

    private var rememberedHorizons: [PlanItem] {
        session.plans.filter { $0.status == .completed }
    }

    private var lifeStream: [LifeStreamEntry] {
        let care = completedCare.map {
            LifeStreamEntry(
                id: "care-\($0.id)",
                title: $0.title,
                detail: "Care found its place",
                symbol: "hands.sparkles.fill",
                timestamp: $0.completedAt ?? $0.updatedAt
            )
        }
        let horizons = rememberedHorizons.map {
            LifeStreamEntry(
                id: "horizon-\($0.id)",
                title: $0.title,
                detail: "A shared moment",
                symbol: "sparkles",
                timestamp: $0.completedAt ?? $0.updatedAt
            )
        }
        return (care + horizons).sorted { $0.timestamp > $1.timestamp }
    }

    private var filteredActive: [Responsibility] {
        switch selectedFilter {
        case .all: active
        case .me: active.filter { $0.owner == .me }
        case .partner: active.filter { $0.owner == .partner }
        case .together: active.filter { $0.owner == .together }
        }
    }

    private func lifeRhythmFocusScene(minHeight: CGFloat) -> some View {
        WECinematicFocusScene(
            artwork: .confluence,
            minHeight: minHeight,
            intensity: 0.88
        ) {
            VStack(alignment: .leading, spacing: 0) {
                header

                weekStrip
                    .padding(.top, 18)

                Spacer(minLength: 42)

                VStack(alignment: .leading, spacing: 9) {
                    Text(lifeFocusEyebrow)
                        .font(.weMeta)
                        .tracking(1.8)
                        .foregroundStyle(personalHue.controlColor)

                    Text(lifeFocusTitle)
                        .font(.weLargeTitle)
                        .foregroundStyle(Color.weInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(lifeFocusDetail)
                        .font(.weSubheadline)
                        .foregroundStyle(Color.weInkSecondary)
                        .frame(maxWidth: 330, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 24)

                NavigationLink {
                    AheadView(onProfile: onProfile)
                } label: {
                    HStack(spacing: 10) {
                        Text("Open shared horizons")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.weInk)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open shared horizons")
                .accessibilityHint("Shows shared plans and possibilities")
                .accessibilityIdentifier("life.openHorizons")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 76)
        }
    }

    private var lifeFocusEyebrow: String {
        if !activePlans.isEmpty { return "NEXT HORIZON" }
        if !active.isEmpty { return "CARE IN VIEW" }
        return "OUR RHYTHM"
    }

    private var lifeFocusTitle: String {
        if let plan = activePlans.first {
            return plan.title
        }
        if let item = active.first {
            return item.title
        }
        return "Nothing is asking for a place yet."
    }

    private var lifeFocusDetail: String {
        if let plan = activePlans.first {
            return PlanDate.relativeDescription(plan.scheduledOn)
                ?? "Still forming"
        }
        if let item = active.first {
            return rhythmOwner(item.owner)
        }
        return "Plans and shared care will gather here when they come into view."
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Calendar.current.date(
                    byAdding: .day,
                    value: offset,
                    to: Date()
                ) ?? Date()

                VStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.weMeta)
                        .foregroundStyle(Color.weInkTertiary)
                    Text(date.formatted(.dateTime.day()))
                        .font(.caption.weight(offset == 0 ? .bold : .medium))
                        .foregroundStyle(
                            offset == 0 ? Color.weInk : Color.weInkSecondary
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            offset == 0
                                ? personalHue.controlColor.opacity(0.34)
                                : .clear,
                            in: Circle()
                        )
                        .overlay {
                            if offset == 0 {
                                Circle().stroke(
                                    personalHue.controlColor.opacity(0.7),
                                    lineWidth: 1
                                )
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The next seven days, starting today")
    }

    private func rhythmRow(
        symbol: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.weHeadline)
                    .foregroundStyle(Color.weInk)
                    .lineLimit(1)
                Text(detail)
                    .font(.weMeta)
                    .foregroundStyle(Color.weInkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rhythmOwner(_ owner: ResponsibilityOwner) -> String {
        switch owner {
        case .me: "On your side"
        case .partner: "With \(partnerName)"
        case .together: "Held together"
        }
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var filterCapsuleBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(FilterOption.allCases) { option in
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .weState) {
                            selectedFilter = option
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(filterLabel(option))
                                .font(.weMeta)
                                .foregroundStyle(
                                    selectedFilter == option
                                        ? personalHue.controlColor
                                        : Color.weInkTertiary
                                )

                            Capsule()
                                .fill(personalHue.controlColor)
                                .frame(width: 18, height: 1.5)
                                .opacity(selectedFilter == option ? 1 : 0)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedFilter == option ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }

    private var carePromise: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CARE, NOT ASSIGNMENTS")
                .font(.weMeta)
                .tracking(1.4)
                .foregroundStyle(personalHue.controlColor)
            Text("Naming care keeps it from becoming invisible. It is not a score of who does more.")
                .font(.weSubheadline)
                .foregroundStyle(Color.weInkSecondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.weHairline)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func filterLabel(_ option: FilterOption) -> String {
        switch option {
        case .all: "All care"
        case .me: "My side"
        case .partner: partnerName
        case .together: "Together"
        }
    }

    private var emptyFilterPhrase: String {
        switch selectedFilter {
        case .all: "here"
        case .me: "on your side"
        case .partner: "on \(partnerName)’s side"
        case .together: "held together"
        }
    }

    private func ownerSectionTitle(_ owner: ResponsibilityOwner) -> String {
        switch owner {
        case .me: "On Your Side"
        case .partner: "On \(partnerName)’s Side"
        case .together: "Held Together"
        }
    }

    private var partnerName: String {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return "Partner"
        }
        return partner.name
    }

    private func responsibilitySection(_ title: String, items: [Responsibility]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductSectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    ResponsibilityRow(
                        item: item,
                        onEdit: { editing = item },
                        onStatus: { status in Task { await session.setResponsibilityStatus(id: item.id, status: status) } }
                    )
                    if item.id != items.last?.id { Divider().padding(.leading, 18) }
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.weHairline)
                    .frame(height: 0.5)
            }
        }
    }

    private var lifeStreamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductSectionHeader(
                title: "Life Stream",
                detail: "What found its place"
            )

            VStack(spacing: 0) {
                ForEach(lifeStream) { entry in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: entry.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color("WEBurgundy"))
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.weHeadline)
                                .foregroundStyle(Color("WEInk"))
                            Text(entry.detail)
                                .font(.subheadline)
                                .foregroundStyle(Color("WEFaint"))
                        }
                        .padding(.vertical, 10)

                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 64)
                    .accessibilityElement(children: .combine)

                    if entry.id != lifeStream.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.weHairline)
                    .frame(height: 0.5)
            }
        }
    }
}

private struct LifeStreamEntry: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let timestamp: String
}

private struct ResponsibilityRow: View {
    @EnvironmentObject private var session: AppSession
    let item: Responsibility
    let onEdit: () -> Void
    let onStatus: (SharedItemStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hands.sparkles.fill")
                .font(.title3)
                .foregroundStyle(Color("WEBurgundy"))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.weHeadline)
                    .foregroundStyle(Color("WEInk"))

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Color("WEFaint"))
                }

                ResponsibilityOwnerChip(owner: item.owner)
            }
            .padding(.vertical, 10)

            Spacer(minLength: 4)

            Menu {
                Button("Shape this care", systemImage: "pencil", action: onEdit)
                if let partnerID {
                    Button(
                        "Offer to \(session.partnerName)",
                        systemImage: "arrow.right"
                    ) {
                        Task {
                            await session.offerHandoff(
                                responsibilityID: item.id,
                                toProfileID: partnerID
                            )
                        }
                    }
                }
                Button("Settle into the Life Stream", systemImage: "sparkles") {
                    onStatus(.completed)
                }
                Button("Let it go", systemImage: "archivebox") {
                    onStatus(.archived)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color("WEFaint"))
            }
            .disabled(!session.canMutate)
            .accessibilityLabel("Actions for \(item.title)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 64)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onStatus(.completed)
            } label: {
                Label(
                    "Settle for now",
                    systemImage: "sparkles"
                )
            }
            .tint(Color("WEBurgundy"))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onStatus(.archived)
            } label: {
                Label("Let it go", systemImage: "archivebox")
            }
            .tint(.red)

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color.gray)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: item.status)
        .animation(.weState, value: item.status)
    }

    private var partnerID: String? {
        session.snapshot?.members.first {
            $0.id != session.user?.id
        }?.id
    }
}

private struct ResponsibilityOwnerChip: View {
    @EnvironmentObject private var session: AppSession
    let owner: ResponsibilityOwner

    var body: some View {
        HStack(spacing: 5) {
            if owner == .together {
                WEMark(
                    style: .micro,
                    showsWordmark: false,
                    personalHue: personalHue,
                    partnerHue: partnerHue,
                    accessibilityText: "Together"
                )
            } else {
                Circle()
                    .fill(chipColor)
                    .frame(width: 8, height: 8)
            }
            Text(chipLabel)
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(chipColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(chipColor.opacity(0.12), in: Capsule())
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return .partnerDefault
        }
        return WEHue(partner.hue)
    }

    private var chipColor: Color {
        switch owner {
        case .me: personalHue.controlColor
        case .partner: partnerHue.controlColor
        case .together: Color("WEBurgundy")
        }
    }

    private var chipLabel: String {
        switch owner {
        case .me: "ME"
        case .partner: partnerName.uppercased()
        case .together: "TOGETHER"
        }
    }

    private var partnerName: String {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return "PARTNER"
        }
        return partner.name
    }
}

private struct ResponsibilityEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    var responsibility: Responsibility?

    @State private var title: String
    @State private var note: String
    @State private var owner: ResponsibilityOwner

    private let suggestions = [
        "Keep groceries flowing",
        "Stay ahead of shared bills",
        "Hold home maintenance",
        "Shape the next trip",
        "Make weeknight meals easier"
    ]

    init(responsibility: Responsibility? = nil) {
        self.responsibility = responsibility
        _title = State(initialValue: responsibility?.title ?? "")
        _note = State(initialValue: responsibility?.note ?? "")
        _owner = State(initialValue: responsibility?.owner ?? .together)
    }

    var body: some View {
        ZStack {
            WarmEditorialBackground()

            VStack(spacing: 0) {
                // Custom Top Navigation Header
                HStack(alignment: .center) {
                    Button("Cancel") { dismiss() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color("WEBurgundy"))
                        .frame(minHeight: 44)

                    Spacer()

                    VStack(spacing: 2) {
                        Text("WHAT WE CARRY")
                            .font(.weCaption)
                            .foregroundStyle(Color("WEFaint"))
                        Text(responsibility == nil ? "Name some care" : "Shape this care")
                            .font(.weTitle)
                            .foregroundStyle(Color("WEInk"))
                    }

                    Spacer()

                    Button("Save") { save() }
                        .font(.body.weight(.bold))
                        .foregroundStyle(isSaveDisabled ? Color("WEFaint") : Color("WEBurgundy"))
                        .disabled(isSaveDisabled)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("THE CARE")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(alignment: .leading, spacing: 10) {
                                TextField("What would feel lighter if it were named?", text: $title)
                                    .font(.weHeadline)
                                    .foregroundStyle(Color("WEInk"))

                                Divider()

                                TextField("Optional note or detail…", text: $note, axis: .vertical)
                                    .lineLimit(2...5)
                                    .font(.weBody)
                                    .foregroundStyle(Color("WEInk"))
                            }
                            .padding(16)
                            .background(
                                Color("WECard"),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                        }

                        if title.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("QUICK SUGGESTIONS")
                                    .font(.weCaption)
                                    .foregroundStyle(Color("WEFaint"))

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(suggestions, id: \.self) { item in
                                            Button(item) {
                                                withAnimation(.weState) {
                                                    title = item
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(Color("WEBurgundy"))
                                            .buttonBorderShape(.capsule)
                                            .font(.caption.weight(.medium))
                                        }
                                    }
                                }
                            }
                        }

                        // Ownership Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WHERE IT IS HELD")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Owner", selection: $owner) {
                                    ForEach(ResponsibilityOwner.allCases, id: \.self) {
                                        Text($0.title).tag($0)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Text(ownerDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(Color("WEFaint"))
                            }
                            .padding(16)
                            .background(
                                Color("WECard"),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                        }

                        SessionMessageView()

                        Button(responsibility == nil ? "Hold This Care" : "Save Changes") {
                            save()
                        }
                            .buttonStyle(WEPrimaryButtonStyle())
                            .disabled(isSaveDisabled)
                            .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.canMutate
    }

    private var ownerDescription: String {
        switch owner {
        case .me: "Held mainly on your side, with shared visibility."
        case .partner: "Held mainly on \(partnerName)’s side, without turning it into an assignment."
        case .together: "Held in the space you share."
        }
    }

    private var partnerName: String {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return "your partner"
        }
        return partner.name
    }

    private func save() {
        let input = ResponsibilityInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            owner: owner
        )
        Task {
            if let responsibility { await session.updateResponsibility(id: responsibility.id, input: input) }
            else { await session.createResponsibility(input) }
            if session.errorMessage == nil { dismiss() }
        }
    }
}

extension ResponsibilityOwner {
    var title: String {
        switch self { case .me: "Me"; case .partner: "Partner"; case .together: "Together" }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    NavigationStack { LifeView(onProfile: {}) }
        .environmentObject(AppSession(repository: PreviewRepository()))
}
