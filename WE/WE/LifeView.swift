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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ProductHeader(
                        eyebrow: "What we carry",
                        title: "Life",
                        profileName: session.snapshot?.profile.name ?? "You",
                        onProfile: onProfile
                    )
                    .weArrival()

                    if !active.isEmpty {
                        carryDistributionBar
                            .weArrival(order: 1)

                        filterCapsuleBar
                            .weArrival(order: 2)
                    }

                    if active.isEmpty {
                        EditorialEmptyState(
                            symbol: "hands.and.sparkles",
                            title: "Nothing is assigned yet.",
                            message: "Add a responsibility when naming who carries it would make life feel lighter.",
                            actionTitle: session.canMutate ? "Add a responsibility" : nil,
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
                                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .weState) {
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
                                responsibilitySection(ownerSectionTitle(owner), items: items)
                                    .weArrival(order: index + 4)
                            }
                        }
                    }

                    if !completed.isEmpty && selectedFilter == .all {
                        responsibilitySection("Completed", items: completed, completed: true)
                            .weArrival(order: 8)
                    }
                    SessionMessageView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Life")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsAdd = true } label: { Image(systemName: "plus") }
                    .disabled(!session.canMutate)
                    .accessibilityLabel("Add responsibility")
            }
        }
        .sheet(isPresented: $showsAdd) { ResponsibilityEditor() }
        .sheet(item: $editing) { ResponsibilityEditor(responsibility: $0) }
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .weState,
            value: active.map(\.id)
        )
    }

    private var active: [Responsibility] { session.responsibilities.filter { $0.status == .active } }
    private var completed: [Responsibility] { session.responsibilities.filter { $0.status == .completed } }

    private var filteredActive: [Responsibility] {
        switch selectedFilter {
        case .all: active
        case .me: active.filter { $0.owner == .me }
        case .partner: active.filter { $0.owner == .partner }
        case .together: active.filter { $0.owner == .together }
        }
    }

    private var filterCapsuleBar: some View {
        HStack(spacing: 6) {
            ForEach(FilterOption.allCases) { option in
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .weState) {
                        selectedFilter = option
                    }
                } label: {
                    Text(filterLabel(option))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedFilter == option ? Color("WEInk") : Color("WEFaint"))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background {
                            if selectedFilter == option {
                                Capsule()
                                    .fill(Color("WECard"))
                                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedFilter == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.04), in: Capsule())
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }

    private var carryDistributionBar: some View {
        let total = Double(max(active.count, 1))
        let meCount = Double(active.filter { $0.owner == .me }.count)
        let partnerCount = Double(active.filter { $0.owner == .partner }.count)
        let togetherCount = Double(active.filter { $0.owner == .together }.count)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HOW THE LOAD IS HELD")
                    .font(.weCaption)
                    .foregroundStyle(Color("WEFaint"))
                Spacer()
                Text("\(active.count) ACTIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color("WEFaint"))
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    if meCount > 0 {
                        Rectangle()
                            .fill(personalHue.controlColor)
                            .frame(width: max((meCount / total) * geo.size.width - 1, 4))
                    }
                    if togetherCount > 0 {
                        Rectangle()
                            .fill(Color("WEBurgundy"))
                            .frame(width: max((togetherCount / total) * geo.size.width - 1, 4))
                    }
                    if partnerCount > 0 {
                        Rectangle()
                            .fill(partnerHue.controlColor)
                            .frame(width: max((partnerCount / total) * geo.size.width - 1, 4))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                distributionKey("You", count: Int(meCount), color: personalHue.controlColor)
                distributionKey("Together", count: Int(togetherCount), color: Color("WEBurgundy"))
                distributionKey(partnerName, count: Int(partnerCount), color: partnerHue.controlColor)
            }
        }
        .padding(14)
        .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How the load is held")
        .accessibilityValue(
            "You \(Int(meCount)), together \(Int(togetherCount)), \(partnerName) \(Int(partnerCount))"
        )
    }

    private func distributionKey(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(count)")
                .font(.caption2)
                .foregroundStyle(Color("WEFaint"))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func filterLabel(_ option: FilterOption) -> String {
        option == .partner ? partnerName : option.rawValue
    }

    private var emptyFilterPhrase: String {
        switch selectedFilter {
        case .all: "here"
        case .me: "carried by you"
        case .partner: "carried by \(partnerName)"
        case .together: "carried together"
        }
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

    private func ownerSectionTitle(_ owner: ResponsibilityOwner) -> String {
        switch owner {
        case .me: "Carried by You"
        case .partner: "Carried by \(partnerName)"
        case .together: "Carried Together"
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

    private func responsibilitySection(_ title: String, items: [Responsibility], completed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductSectionHeader(title: title, detail: "\(items.count)")
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
            .background(
                Color("WECard"),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
        }
    }
}

private struct ResponsibilityRow: View {
    @EnvironmentObject private var session: AppSession
    let item: Responsibility
    let onEdit: () -> Void
    let onStatus: (SharedItemStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                onStatus(item.status == .completed ? .active : .completed)
            } label: {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.status == .completed ? Color("WEBurgundy") : Color("WEFaint"))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!session.canMutate)
            .accessibilityLabel(
                item.status == .completed
                    ? "Mark \(item.title) active"
                    : "Mark \(item.title) complete"
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.weHeadline)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? Color("WEFaint") : Color("WEInk"))

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
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Archive", systemImage: "archivebox") { onStatus(.archived) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color("WEFaint"))
            }
            .disabled(!session.canMutate)
            .accessibilityLabel("More actions for \(item.title)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 64)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onStatus(item.status == .completed ? .active : .completed)
            } label: {
                Label(
                    item.status == .completed ? "Activate" : "Complete",
                    systemImage: item.status == .completed ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(item.status == .completed ? Color.gray : Color("WEBurgundy"))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onStatus(.archived)
            } label: {
                Label("Archive", systemImage: "archivebox")
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
        "Groceries",
        "Bills & Utilities",
        "Home Maintenance",
        "Travel Booking",
        "Dinner & Meals"
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
                        Text(responsibility == nil ? "New responsibility" : "Edit responsibility")
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
                        // Title & Note Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RESPONSIBILITY")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(alignment: .leading, spacing: 10) {
                                TextField("What needs carrying?", text: $title)
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

                        // Quick Suggestions
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
                            Text("WHO CARRIES IT")
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

                        // Action Button
                        Button("Save Responsibility") { save() }
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
        case .me: "Carried primarily on your side. Visible to your partner."
        case .partner: "Assigned to your partner. Visible on their Life list."
        case .together: "Shared responsibility owned jointly by both of you."
        }
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
