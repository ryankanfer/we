import SwiftUI

struct LifeView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsAdd = false
    @State private var editing: Responsibility?

    let onProfile: () -> Void

    var body: some View {
        ZStack {
            WarmEditorialBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ProductHeader(
                        eyebrow: "What we carry",
                        title: "Life",
                        profileName: session.snapshot?.profile.name ?? "You",
                        onProfile: onProfile
                    )

                    if active.isEmpty {
                        EditorialEmptyState(
                            symbol: "hands.and.sparkles",
                            title: "Nothing is assigned yet.",
                            message: "Add a responsibility when naming who carries it would make life feel lighter.",
                            actionTitle: session.canMutate ? "Add a responsibility" : nil,
                            action: { showsAdd = true }
                        )
                    } else {
                        ForEach(ResponsibilityOwner.allCases, id: \.self) { owner in
                            let items = active.filter { $0.owner == owner }
                            if !items.isEmpty {
                                responsibilitySection(owner.title, items: items)
                            }
                        }
                    }

                    if !completed.isEmpty {
                        responsibilitySection("Completed", items: completed, completed: true)
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
    }

    private var active: [Responsibility] { session.responsibilities.filter { $0.status == .active } }
    private var completed: [Responsibility] { session.responsibilities.filter { $0.status == .completed } }

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
            .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.weHeadline)
                    .strikethrough(item.status == .completed)
                if let note = item.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(Color("WEFaint"))
                }
                Text(item.owner.title)
                    .font(.caption)
                    .foregroundStyle(Color("WEBurgundy"))
            }
            .padding(.vertical, 10)
            Spacer(minLength: 4)
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Archive", systemImage: "archivebox") { onStatus(.archived) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .disabled(!session.canMutate)
            .accessibilityLabel("More actions for \(item.title)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 64)
    }
}

private struct ResponsibilityEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    var responsibility: Responsibility?

    @State private var title: String
    @State private var note: String
    @State private var owner: ResponsibilityOwner

    init(responsibility: Responsibility? = nil) {
        self.responsibility = responsibility
        _title = State(initialValue: responsibility?.title ?? "")
        _note = State(initialValue: responsibility?.note ?? "")
        _owner = State(initialValue: responsibility?.owner ?? .together)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Responsibility") {
                    TextField("What needs carrying?", text: $title)
                    TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section("Who carries it") {
                    Picker("Owner", selection: $owner) {
                        ForEach(ResponsibilityOwner.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                SessionMessageView()
            }
            .navigationTitle(responsibility == nil ? "New responsibility" : "Edit responsibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.canMutate)
                }
            }
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
