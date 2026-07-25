import SwiftUI

struct AheadView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .weArrival()

                    if active.isEmpty {
                        EditorialEmptyState(
                            symbol: "arrow.forward.circle",
                            title: "Nothing is waiting ahead.",
                            message: "Add a plan with a date, or keep it unscheduled until the shape is clearer.",
                            actionTitle: session.canMutate ? "Add a plan" : nil,
                            action: { showsAdd = true }
                        )
                        .weArrival(order: 1)
                    } else {
                        if let nextPlan = scheduled.first {
                            nextMilestoneCard(nextPlan)
                                .weArrival(order: 1)
                        }

                        if !remainingScheduled.isEmpty {
                            planSection("Later", plans: remainingScheduled)
                                .weArrival(order: 2)
                        }
                        if !unscheduled.isEmpty {
                            planSection("Unscheduled", plans: unscheduled)
                                .weArrival(order: 3)
                        }
                    }
                    if !completed.isEmpty {
                        planSection("Completed", plans: completed)
                            .weArrival(order: 4)
                    }
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
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .weState,
            value: active.map(\.id)
        )
    }

    private var active: [PlanItem] { session.plans.filter { $0.status == .active } }
    private var scheduled: [PlanItem] { active.filter { $0.scheduledOn != nil }.sorted { ($0.scheduledOn ?? "") < ($1.scheduledOn ?? "") } }
    private var remainingScheduled: [PlanItem] { Array(scheduled.dropFirst()) }
    private var unscheduled: [PlanItem] { active.filter { $0.scheduledOn == nil } }
    private var completed: [PlanItem] { session.plans.filter { $0.status == .completed } }

    private func nextMilestoneCard(_ plan: PlanItem) -> some View {
        Button {
            editing = plan
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("NEXT UP", systemImage: "calendar.badge.clock")
                        .font(.weCaption)
                        .foregroundStyle(Color("WEBurgundy"))
                    Spacer()
                    if let relativeText = PlanDate.relativeDescription(plan.scheduledOn) {
                        Text(relativeText.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(Color("WEBurgundy"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color("WEBurgundy").opacity(0.12), in: Capsule())
                    }
                }

                Text(plan.title)
                    .font(.weTitle)
                    .foregroundStyle(Color("WEInk"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let note = plan.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Color("WEFaint"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color("WECard"),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color("WEBurgundy").opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(WEPressableCardStyle())
        .accessibilityHint("Opens this plan for editing")
    }

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

            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title)
                    .font(.weHeadline)
                    .strikethrough(plan.status == .completed)
                    .foregroundStyle(plan.status == .completed ? Color("WEFaint") : Color("WEInk"))

                if let note = plan.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Color("WEFaint"))
                }

                if let relativeText = PlanDate.relativeDescription(plan.scheduledOn) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(relativeText)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(personalHue.controlColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(personalHue.color.opacity(0.12), in: Capsule())
                } else if plan.status == .active {
                    Text("WHEN IT FITS")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Color("WEFaint"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.04), in: Capsule())
                }
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
            .accessibilityLabel("More actions for \(plan.title)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 64)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onStatus(plan.status == .completed ? .active : .completed)
            } label: {
                Label(
                    plan.status == .completed ? "Activate" : "Complete",
                    systemImage: plan.status == .completed ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(plan.status == .completed ? Color.gray : Color("WEBurgundy"))
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
        .sensoryFeedback(.impact(weight: .light), trigger: plan.status)
        .animation(.weState, value: plan.status)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
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
        ZStack {
            WarmEditorialBackground()

            VStack(spacing: 0) {
                // Header Bar
                HStack(alignment: .center) {
                    Button("Cancel") { dismiss() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color("WEBurgundy"))
                        .frame(minHeight: 44)

                    Spacer()

                    VStack(spacing: 2) {
                        Text("WHAT IS AHEAD")
                            .font(.weCaption)
                            .foregroundStyle(Color("WEFaint"))
                        Text(plan == nil ? "New plan" : "Edit plan")
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
                        // Plan Details Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PLAN DETAILS")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(alignment: .leading, spacing: 10) {
                                TextField("What is ahead?", text: $title)
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

                        // Timing Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TIMING")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(spacing: 14) {
                                Toggle(isOn: $isScheduled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Set a date")
                                            .font(.weHeadline)
                                            .foregroundStyle(Color("WEInk"))
                                        Text(isScheduled ? "Scheduled ahead" : "When it fits")
                                            .font(.caption)
                                            .foregroundStyle(Color("WEFaint"))
                                    }
                                }
                                .tint(Color("WEBurgundy"))

                                if isScheduled {
                                    Divider()

                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("QUICK PRESETS")
                                            .font(.caption2.weight(.semibold))
                                            .tracking(1)
                                            .foregroundStyle(Color("WEFaint"))

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                presetButton("Today", days: 0)
                                                presetButton("Tomorrow", days: 1)
                                                presetButton("This Saturday", targetDay: .saturday)
                                                presetButton("Next Week", days: 7)
                                            }
                                        }

                                        DatePicker("Date", selection: $date, displayedComponents: .date)
                                            .font(.weBody)
                                            .tint(Color("WEBurgundy"))
                                    }
                                }
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

                        // Action button at bottom for clear feedback
                        Button("Save Plan") { save() }
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

    private func presetButton(_ label: String, days: Int) -> some View {
        Button(label) {
            isScheduled = true
            date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        }
        .buttonStyle(.bordered)
        .tint(Color("WEBurgundy"))
        .buttonBorderShape(.capsule)
        .font(.caption.weight(.medium))
    }

    private func presetButton(_ label: String, targetDay: Weekday) -> some View {
        Button(label) {
            isScheduled = true
            date = nextWeekday(targetDay)
        }
        .buttonStyle(.bordered)
        .tint(Color("WEBurgundy"))
        .buttonBorderShape(.capsule)
        .font(.caption.weight(.medium))
    }

    private enum Weekday: Int {
        case saturday = 7
    }

    private func nextWeekday(_ weekday: Weekday) -> Date {
        let calendar = Calendar.current
        let today = Date()
        let currentComponent = calendar.component(.weekday, from: today)
        var daysAhead = weekday.rawValue - currentComponent
        if daysAhead <= 0 { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
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

    static func relativeDescription(_ value: String?) -> String? {
        guard let date = date(value) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date))
        if let days = components.day, days > 1 && days <= 6 {
            return "In \(days) days"
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }
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
