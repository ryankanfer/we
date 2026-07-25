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
                        eyebrow: "Shared horizons",
                        title: "Ahead",
                        profileName: session.snapshot?.profile.name ?? "You",
                        onProfile: onProfile
                    )
                    .weArrival()

                    if let privateChoiceRecord {
                        privateChoiceCard(privateChoiceRecord)
                            .weArrival(order: 1)
                    }

                    if active.isEmpty {
                        EditorialEmptyState(
                            symbol: "sun.horizon",
                            title: "The horizon is open.",
                            message: "Hold an intention with a day, or let its timing keep forming.",
                            actionTitle: session.canMutate ? "Hold an intention" : nil,
                            action: { showsAdd = true }
                        )
                        .weArrival(order: 2)
                    } else {
                        if let nextPlan = scheduled.first {
                            nextMilestoneCard(nextPlan)
                                .weArrival(order: 2)
                        }

                        if !remainingScheduled.isEmpty {
                            planSection("Further out", plans: remainingScheduled)
                                .weArrival(order: 3)
                        }
                        if !unscheduled.isEmpty {
                            planSection("Still forming", plans: unscheduled)
                                .weArrival(order: 4)
                        }
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
                    .accessibilityLabel("Hold a new intention")
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
    private var privateChoiceRecord: InsightRecord? {
        session.insightRecords.first {
            $0.insight.kind == .logistical
                && session.projection(for: $0)?.phase != .resolved
        }
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private func privateChoiceCard(_ record: InsightRecord) -> some View {
        NavigationLink {
            InsightDetailView(insightID: record.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .font(.title3)
                    .foregroundStyle(personalHue.controlColor)
                    .frame(width: 44, height: 44)
                    .background(
                        personalHue.color.opacity(0.12),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 7) {
                    Text("CHOOSE PRIVATELY")
                        .font(.weCaption)
                        .tracking(1.2)
                        .foregroundStyle(Color("WEBurgundy"))
                    Text(record.insight.title)
                        .font(.weHeadline)
                        .foregroundStyle(Color("WEInk"))
                    Text("WE opens only a mutual match. A preference that does not match stays unspoken.")
                        .font(.subheadline)
                        .foregroundStyle(Color("WEFaint"))
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color("WEFaint"))
                    .frame(minHeight: 44)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color("WECard"),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(personalHue.color.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(WEPressableCardStyle())
        .accessibilityHint("Opens a private preference round")
    }

    private func nextMilestoneCard(_ plan: PlanItem) -> some View {
        Button {
            editing = plan
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("COMING INTO VIEW", systemImage: "sun.horizon.fill")
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
        .accessibilityHint("Opens this intention for editing")
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
            Image(systemName: plan.scheduledOn == nil ? "sparkles" : "sun.horizon.fill")
                .font(.title3)
                .foregroundStyle(personalHue.controlColor)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title)
                    .font(.weHeadline)
                    .foregroundStyle(Color("WEInk"))

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
                } else {
                    Text("TIMING STILL OPEN")
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
                Button("Shape this intention", systemImage: "pencil", action: onEdit)
                Button("Move into the Life Stream", systemImage: "sparkles") {
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
            .accessibilityLabel("Actions for \(plan.title)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 64)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onStatus(.completed)
            } label: {
                Label(
                    "Move to Life Stream",
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
                        Text(plan == nil ? "New intention" : "Shape intention")
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
                            Text("THE HORIZON")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(alignment: .leading, spacing: 10) {
                                TextField("What are you hoping toward?", text: $title)
                                    .font(.weHeadline)
                                    .foregroundStyle(Color("WEInk"))

                                Divider()

                                TextField("A feeling, possibility, or useful detail…", text: $note, axis: .vertical)
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

                        VStack(alignment: .leading, spacing: 12) {
                            Text("TIMING")
                                .font(.weCaption)
                                .foregroundStyle(Color("WEFaint"))

                            VStack(spacing: 14) {
                                Toggle(isOn: $isScheduled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Hold a day")
                                            .font(.weHeadline)
                                            .foregroundStyle(Color("WEInk"))
                                        Text(isScheduled ? "Coming into view" : "Let timing stay open")
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

                        Button(plan == nil ? "Hold This Intention" : "Save Changes") {
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
