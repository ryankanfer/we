import SwiftUI

struct AheadView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsAdd = false
    @State private var editing: PlanItem?
    let onProfile: () -> Void

    var body: some View {
        ZStack {
            WarmEditorialBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ProductHeader(
                        eyebrow: "What is coming",
                        title: "Ahead",
                        profileName: session.snapshot?.profile.name ?? "You",
                        onProfile: onProfile
                    )

                    if active.isEmpty {
                        EditorialEmptyState(
                            symbol: "arrow.forward.circle",
                            title: "Nothing is waiting ahead.",
                            message: "Add a plan with a date, or keep it unscheduled until the shape is clearer.",
                            actionTitle: session.canMutate ? "Add a plan" : nil,
                            action: { showsAdd = true }
                        )
                    } else {
                        if !scheduled.isEmpty { planSection("Scheduled", plans: scheduled) }
                        if !unscheduled.isEmpty { planSection("Unscheduled", plans: unscheduled) }
                    }
                    if !completed.isEmpty { planSection("Completed", plans: completed) }
                    SessionMessageView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Ahead")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsAdd = true } label: { Image(systemName: "plus") }
                    .disabled(!session.canMutate)
                    .accessibilityLabel("Add plan")
            }
        }
        .sheet(isPresented: $showsAdd) { PlanEditor() }
        .sheet(item: $editing) { PlanEditor(plan: $0) }
    }

    private var active: [PlanItem] { session.plans.filter { $0.status == .active } }
    private var scheduled: [PlanItem] { active.filter { $0.scheduledOn != nil }.sorted { ($0.scheduledOn ?? "") < ($1.scheduledOn ?? "") } }
    private var unscheduled: [PlanItem] { active.filter { $0.scheduledOn == nil } }
    private var completed: [PlanItem] { session.plans.filter { $0.status == .completed } }

    private func planSection(_ title: String, plans: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductSectionHeader(title: title, detail: "\(plans.count)")
            VStack(spacing: 0) {
                ForEach(plans) { plan in
                    PlanRow(
                        plan: plan,
                        onEdit: { editing = plan },
                        onStatus: { status in Task { await session.setPlanStatus(id: plan.id, status: status) } }
                    )
                    if plan.id != plans.last?.id { Divider().padding(.leading, 18) }
                }
            }
            .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct PlanRow: View {
    @EnvironmentObject private var session: AppSession
    let plan: PlanItem
    let onEdit: () -> Void
    let onStatus: (SharedItemStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { onStatus(plan.status == .completed ? .active : .completed) } label: {
                Image(systemName: plan.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(plan.status == .completed ? Color("WEBurgundy") : Color("WEFaint"))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!session.canMutate)
            .accessibilityLabel(
                plan.status == .completed
                    ? "Mark \(plan.title) active"
                    : "Mark \(plan.title) complete"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(plan.title).font(.weHeadline).strikethrough(plan.status == .completed)
                if let note = plan.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(Color("WEFaint")) }
                if let date = PlanDate.date(plan.scheduledOn) {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption).foregroundStyle(Color("WEBurgundy"))
                } else if plan.status == .active {
                    Text("WHEN IT FITS").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Color("WEFaint"))
                }
            }
            .padding(.vertical, 10)
            Spacer(minLength: 4)
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Archive", systemImage: "archivebox") { onStatus(.archived) }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .disabled(!session.canMutate)
            .accessibilityLabel("More actions for \(plan.title)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 64)
    }
}

private struct PlanEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    var plan: PlanItem?

    @State private var title: String
    @State private var note: String
    @State private var isScheduled: Bool
    @State private var date: Date

    init(plan: PlanItem? = nil) {
        self.plan = plan
        _title = State(initialValue: plan?.title ?? "")
        _note = State(initialValue: plan?.note ?? "")
        _isScheduled = State(initialValue: plan?.scheduledOn != nil)
        _date = State(initialValue: PlanDate.date(plan?.scheduledOn) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("What is ahead?", text: $title)
                    TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section("Timing") {
                    Toggle("Set a date", isOn: $isScheduled)
                    if isScheduled { DatePicker("Date", selection: $date, displayedComponents: .date) }
                }
                SessionMessageView()
            }
            .navigationTitle(plan == nil ? "New plan" : "Edit plan")
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
        let input = PlanInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            scheduledOn: isScheduled ? PlanDate.string(date) : nil
        )
        Task {
            if let plan { await session.updatePlan(id: plan.id, input: input) }
            else { await session.createPlan(input) }
            if session.errorMessage == nil { dismiss() }
        }
    }
}

enum PlanDate {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateFormatter.wePlanDate.date(from: value)
    }

    static func string(_ date: Date) -> String { DateFormatter.wePlanDate.string(from: date) }
}

private extension DateFormatter {
    static let wePlanDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    NavigationStack { AheadView(onProfile: {}) }
        .environmentObject(AppSession(repository: PreviewRepository()))
}
