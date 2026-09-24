import SwiftUI

struct FieldGoalsSurface: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession
    @State private var editing: FieldHorizon?
    @State private var opened: FieldItemReference?
    @State private var reviewed: FieldGoalSuggestion?
    @State private var showsConversation = false
    @State private var suggestions: [FieldGoalSuggestion] = []
    @State private var dismissed: [String: Double] = [:]
    private var dismissalKey: String { "we.us.suggestions." + (session.snapshot?.membership?.coupleID ?? "demo") + "." + (session.user?.id ?? "demo") }
    private var canSuggest: Bool {
        !session.v2State.signalConsents.contains { $0.signal == .sharedPlans && !$0.isEnabled }
    }
    private var visibleSuggestions: [FieldGoalSuggestion] {
        (canSuggest ? suggestions : []).filter { guard let until = dismissed[$0.id] else { return true }; return until >= 0 && until < Date().timeIntervalSince1970 }
    }
    private func isBuilding(_ goal: FieldHorizon) -> Bool {
        if let plan = goal.goalPlan { return plan.isBuilding }
        return session.snapshot?.journeys.contains { $0.horizonID == goal.id && $0.status == .active } == true
    }
    private var building: [FieldHorizon] { store.state.horizons.filter(isBuilding) }
    private var exploring: [FieldHorizon] { store.state.horizons.filter { !isBuilding($0) } }

    var body: some View {
        FieldZoneScaffold(zone: .life, showsZoneLabel: false) {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("Us").font(FieldType.hero)
                    Spacer()
                    Button { editing = newGoal() } label: { Image(systemName: "plus").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: Circle()) }
                        .accessibilityLabel("Explore a goal").accessibilityIdentifier("field.us.goal.create")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("A life, imagined\ntogether.").font(FieldType.pageHeadline)
                    Text("Trips, a place of your own, the bigger things.\nStart with a possibility.")
                        .font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning)).lineSpacing(3)
                }.padding(.bottom, 10)
                if let suggestion = visibleSuggestions.first {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Taking shape").font(.system(.subheadline, weight: .medium))
                        Text(suggestion.existingGoalID == nil ? suggestion.title : "More for " + suggestion.title)
                            .font(FieldType.captureWriting)
                        Text("Connected through \(suggestion.items.count) shared items in Life.")
                            .font(FieldType.body).foregroundStyle(.fieldInk(.reasoning))
                        Button("See what connects them") { reviewed = suggestion }.buttonStyle(FieldGoalPrimaryStyle())
                        HStack {
                            Button("Not now") { dismiss(suggestion, until: Date().addingTimeInterval(14 * 86400).timeIntervalSince1970) }
                            Spacer()
                            Button("Don’t suggest this") { dismiss(suggestion, until: -1) }
                        }.font(.system(.footnote)).frame(minHeight: 44)
                    }.padding(22).background(WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("field.us.goal.suggestion")
                }
                group("Building together", detail: "Goals you’ve both chosen to pursue.", goals: building)
                group("Exploring", detail: "Possibilities to shape before you commit.", goals: exploring)
                if store.state.horizons.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("What could be next for you two?").font(FieldType.captureWriting)
                        Button("Explore a goal") { editing = newGoal() }.buttonStyle(FieldGoalPrimaryStyle())
                        Text("A trip. A home. A dog. Or something only you two have in mind.").font(FieldType.body)
                    }
                }
                FieldCorrectionSummary()
                    .padding(.top, FieldMetrics.sectionGap)
                Button("Our shared conversations") { showsConversation = true }
                    .font(FieldType.body).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(.fieldInk(.headline))
        }
        .sheet(item: $editing) { FieldGoalEditor(goal: $0).environment(store) }
        .sheet(item: $opened) { FieldGoalRoom(goalID: $0.id).environment(store) }
        .sheet(item: $reviewed) { FieldGoalSuggestionReview(suggestion: $0).environment(store) }
         .sheet(isPresented: $showsConversation) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showsConversation = false }.padding(20) }
                SharedJourneyUsSurface().environment(store).environmentObject(session)
            }.background(WECanvas.cream.bg).environment(\.weCanvas, .cream).preferredColorScheme(.light)
        }
        .task(id: dismissalKey) { dismissed = UserDefaults.standard.dictionary(forKey: dismissalKey) as? [String: Double] ?? [:] }
        .task(id: store.state.lifeItems.hashValue ^ store.state.horizons.hashValue ^ canSuggest.hashValue) {
            suggestions = canSuggest ? FieldGoalSuggestions.suggestions(items: store.state.lifeItems, goals: store.state.horizons) : []
        }
    }
    private func dismiss(_ suggestion: FieldGoalSuggestion, until: Double) {
        dismissed[suggestion.id] = until
        UserDefaults.standard.set(dismissed, forKey: dismissalKey)
    }
    @ViewBuilder private func group(_ title: String, detail: String, goals: [FieldHorizon]) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(FieldType.weLifeSection)
                Text(detail).font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
                ForEach(goals) { goal in
                    Button { opened = .init(id: goal.id) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(goal.title).font(FieldType.captureWriting); Spacer(); Image(systemName: "arrow.up.right") }
                            if let thesis = goal.thesis, !thesis.isEmpty { Text(thesis).font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning)).lineLimit(2) }
                            if let plan = goal.goalPlan, plan.target > 0 {
                                Text("\(plan.saved.formatted(.currency(code: plan.currency))) of \(plan.target.formatted(.currency(code: plan.currency)))")
                                    .font(.system(.subheadline))
                                ProgressView(value: min(plan.saved / plan.target, 1)).tint(WECanvas.cream.ink)
                            } else if let window = goal.window, !window.isEmpty { Text(window).font(.system(.subheadline)) }
                        }.padding(.vertical, 18).padding(.horizontal, isBuilding(goal) ? 20 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            if isBuilding(goal) { RoundedRectangle(cornerRadius: 18).fill(WECanvas.cream.bgElevated) }
                        }
                        .overlay(alignment: .top) {
                            if !isBuilding(goal) { Rectangle().fill(WECanvas.cream.ink.opacity(0.12)).frame(height: 0.5) }
                        }
                    }.accessibilityIdentifier("field.us.goal.open")
                }
            }
        }
    }
    private func newGoal() -> FieldHorizon {
        FieldHorizon(goalPlan: FieldGoalPlan(), id: UUID().uuidString, title: "", window: nil, owner: .shared, isPrimary: false, thesis: nil, targetDate: nil, linkedLifeItemIDs: [], openQuestion: nil)
    }
}

private struct FieldGoalSuggestionReview: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let suggestion: FieldGoalSuggestion
    @State private var editing: FieldHorizon?
    @State private var item: FieldItemReference?
    var body: some View {
        FieldGoalPage(title: "A possibility for Us") {
            Text(suggestion.title).font(FieldType.pageHeadline)
            Text("These shared items may belong together. You decide whether they do.").font(FieldType.body)
            ForEach(suggestion.items) { evidence in
                Button { item = .init(id: evidence.id) } label: {
                    HStack { Text(evidence.title); Spacer(); Image(systemName: "arrow.up.right") }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            if let id = suggestion.existingGoalID {
                Button("Add these to the existing goal") {
                    guard var goal = store.state.horizons.first(where: { $0.id == id }) else { return }
                    goal.linkedLifeItemIDs = Array(Set(goal.linkedLifeItemIDs + suggestion.items.map(\.id))).sorted()
                    if store.saveGoal(goal) { dismiss() }
                }.buttonStyle(FieldGoalPrimaryStyle())
            } else {
                Button("Shape this possibility") {
                    var plan = FieldGoalPlan(); plan.kind = suggestion.kind
                    editing = FieldHorizon(goalPlan: plan, id: UUID().uuidString, title: suggestion.title, window: nil, owner: .shared, isPrimary: false, thesis: nil, targetDate: nil, linkedLifeItemIDs: suggestion.items.map(\.id), openQuestion: nil)
                }.buttonStyle(FieldGoalPrimaryStyle())
            }
        }
        .sheet(item: $item) { FieldItemSheet(itemID: $0.id).environment(store) }
        .sheet(item: $editing, onDismiss: {
            if store.state.horizons.contains(where: { Set(suggestion.items.map(\.id)).isSubset(of: Set($0.linkedLifeItemIDs)) }) { dismiss() }
        }) { FieldGoalEditor(goal: $0).environment(store) }
    }
}

private struct FieldGoalEditor: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: FieldHorizon
    @State private var goal: FieldHorizon
    @State private var plan: FieldGoalPlan
    @State private var reason: String
    @State private var window: String
    @State private var editError: String?
    init(goal: FieldHorizon) {
        original = goal
        _goal = State(initialValue: goal); _plan = State(initialValue: goal.goalPlan ?? .init())
        _reason = State(initialValue: goal.thesis ?? ""); _window = State(initialValue: goal.window ?? "")
    }
    var body: some View {
        FieldGoalPage(title: original.title.isEmpty ? "Explore a goal" : "Shape your goal") {
            TextField("What are you imagining?", text: $goal.title, axis: .vertical).font(FieldType.pageHeadline).lineLimit(1...3)
                .padding(.vertical, 12)
                .accessibilityIdentifier("field.us.goal.title")
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("A little about it").font(.system(.subheadline, weight: .medium))
                    Spacer()
                    Picker("Kind of goal", selection: $plan.kind) { ForEach(FieldGoalKind.allCases) { Text($0.rawValue).tag($0) } }
                        .tint(WECanvas.cream.ink)
                }
                goalInput("Why it matters") {
                    TextField("What would this mean for you two?", text: $reason, axis: .vertical).lineLimit(2...5)
                }
                goalInput("A time in mind · optional") {
                    TextField("Next spring, in a few years, someday…", text: $window)
                }
                if plan.kind == .savings || plan.kind == .trip {
                    goalInput(plan.kind == .trip ? "Trip budget · optional" : "Savings target · optional") {
                        HStack {
                            TextField("Amount", value: $plan.target, format: .number).keyboardType(.decimalPad)
                            Picker("Currency", selection: $plan.currency) { ForEach(["USD", "GBP", "EUR", "CAD", "AUD", "JPY"], id: \.self) { Text($0).tag($0) } }.tint(WECanvas.cream.ink)
                        }
                    }
                    Text("Track savings manually here. Bank connections are planned.").font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
                }
            }.padding(20).background(WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 18))
            Text("Start in Exploring. Build it together when you’re both ready.")
                .font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning)).lineSpacing(3)
            if !original.title.isEmpty, original.goalPlan?.isBuilding == true {
                Text("A change to your purpose, timing, or target asks you both to agree again.").font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
            }
            if let editError { Text(editError).font(.system(.subheadline)) }
            Button(original.title.isEmpty ? "Add to Exploring" : "Save goal") {
                if let latest = store.state.horizons.first(where: { $0.id == goal.id }) {
                    guard latest.goalPlan?.revision == original.goalPlan?.revision,
                          latest.title == original.title, latest.thesis == original.thesis,
                          latest.window == original.window else {
                        editError = "This goal changed while you were editing. Close and reopen it to see the latest version."
                        return
                    }
                    if let current = latest.goalPlan {
                        plan.saved = current.saved; plan.notes = current.notes
                        plan.milestones = current.milestones; plan.approvedOwners = current.approvedOwners
                    }
                    goal.linkedLifeItemIDs = latest.linkedLifeItemIDs
                }
                goal.title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if original.title != goal.title || (original.thesis ?? "") != reason || (original.window ?? "") != window || original.goalPlan?.target != plan.target || original.goalPlan?.kind != plan.kind || original.goalPlan?.currency != plan.currency {
                    plan.revision = UUID().uuidString; plan.approvedOwners = []
                }
                goal.thesis = reason; goal.window = window.isEmpty ? nil : window; goal.goalPlan = plan
                if store.saveGoal(goal) { dismiss() }
            }.buttonStyle(FieldGoalPrimaryStyle()).disabled(goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.title.count > 120 || !plan.valid)
                .accessibilityIdentifier("field.us.goal.save")
        }
    }
    private func goalInput<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label).font(.system(.caption, weight: .medium)).foregroundStyle(.fieldInk(.reasoning))
            content().font(.system(.body))
        }
    }

}

struct FieldGoalRoom: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession
    let goalID: String
    @State private var editing: FieldHorizon?
    @State private var openItem: FieldItemReference?
    @State private var showsLifePicker = false
    @State private var showsGoalChat = false
    @State private var nextStep = ""
    @State private var milestone = ""
    @State private var note = ""
    @State private var savedAmount: Double = 0
    @State private var approving = false
    private var goal: FieldHorizon? { store.state.horizons.first { $0.id == goalID } }
    private var isBuilding: Bool {
        if let plan = goal?.goalPlan { return plan.isBuilding }
        return session.snapshot?.journeys.contains { $0.horizonID == goalID && $0.status == .active } == true
    }
    var body: some View {
        FieldGoalPage(title: isBuilding ? "Building together" : "Exploring") {
            if let goal {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text(goal.title).font(FieldType.pageHeadline)
                        Spacer()
                        Menu {
                            Button("Shape this goal") { editing = goal }
                            if goal.goalPlan?.approvedOwners.contains(store.speaker) == true {
                                Button("I’d like to keep exploring") { Task { await store.approveGoal(goalID, approved: false) } }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Goal options")
                    }
                    if let reason = goal.thesis, !reason.isEmpty { Text(reason).font(.system(.body)).foregroundStyle(.fieldInk(.reasoning)) }
                    if let window = goal.window, !window.isEmpty { Text(window).font(.system(.subheadline)) }
                }
                if let plan = goal.goalPlan {
                    if !plan.isBuilding {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(plan.approvedOwners.contains(store.speaker) ? "You’re ready. Your partner can choose in their own time." : "Is this something you want to build together?").font(.system(.subheadline))
                            if !plan.approvedOwners.contains(store.speaker) {
                                Button(approving ? "Saving your choice…" : "I’m ready to build this") {
                                    approving = true
                                    Task { await store.approveGoal(goalID); approving = false }
                                }.buttonStyle(FieldGoalPrimaryStyle()).disabled(approving)
                            }
                        }
                    }
                    if plan.target > 0 { budget(plan) }
                    milestones(plan)
                    thoughts(plan)
                } else {
                    Button("Shape this goal") { editing = goal }.buttonStyle(FieldGoalPrimaryStyle())
                }
                Button("Discuss this together") { store.conversationContext = .init(kind: "goal", id: goal.id); showsGoalChat = true }.buttonStyle(FieldGoalPrimaryStyle())
                connections(goal)
            } else {
                Text("This goal is no longer available.").font(FieldType.pageHeadline)
            }
        }
        .onAppear { savedAmount = goal?.goalPlan?.saved ?? 0 }
        .sheet(item: $editing) { FieldGoalEditor(goal: $0).environment(store) }
        .sheet(item: $openItem) { FieldItemSheet(itemID: $0.id).environment(store) }
        .sheet(isPresented: $showsGoalChat) { FieldConversationView(initialContext: .init(kind: "goal", id: goalID)).environment(store) }
        .sheet(isPresented: $showsLifePicker) { FieldGoalLifePicker(goalID: goalID).environment(store) }
    }
    private func budget(_ plan: FieldGoalPlan) -> some View {
        FieldGoalSection {
            Text(plan.kind == .trip ? "Making room for the trip" : "A little closer").font(.system(.subheadline, weight: .medium))
            Text(plan.saved.formatted(.currency(code: plan.currency))).font(FieldType.pageHeadline)
            Text("saved toward \(plan.target.formatted(.currency(code: plan.currency)))").font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
            ProgressView(value: min(plan.saved / plan.target, 1)).tint(WECanvas.cream.ink)
            DisclosureGroup("Update savings") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Saved so far", value: $savedAmount, format: .number).keyboardType(.decimalPad)
                        .accessibilityLabel("Saved so far")
                    Button("Save amount") { update { $0.saved = savedAmount } }.buttonStyle(FieldGoalPrimaryStyle())
                        .disabled(!savedAmount.isFinite || savedAmount < 0)
                }.padding(.top, 12)
            }.font(.system(.subheadline)).tint(WECanvas.cream.ink)
        }
    }
    private func milestones(_ plan: FieldGoalPlan) -> some View {
        FieldGoalSection {
            Text("Milestones & decisions").font(FieldType.weLifeSection)
            if plan.milestones.isEmpty { Text("What would help you move this forward?").font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning)) }
            ForEach(plan.milestones) { step in
                Button { update { p in if let i = p.milestones.firstIndex(where: { $0.id == step.id }) { p.milestones[i].done.toggle() } } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                        Text(step.title).strikethrough(step.done).foregroundStyle(.fieldInk(step.done ? .reasoning : .headline))
                    }.font(.system(.body)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
                .contextMenu {
                    Button("Remove milestone", role: .destructive) { update { $0.milestones.removeAll { $0.id == step.id } } }
                }
            }
            HStack {
                TextField("Add a milestone or question", text: $milestone, axis: .vertical).font(.system(.subheadline))
                Button {
                    if update({ $0.milestones.append(.init(title: milestone.trimmingCharacters(in: .whitespacesAndNewlines))) }) { milestone = "" }
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Add milestone")
                    .disabled(milestone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || milestone.count > 240 || plan.milestones.count >= 40)
            }
        }
    }
    private func thoughts(_ plan: FieldGoalPlan) -> some View {
        FieldGoalSection {
            Text("Thoughts for each other").font(FieldType.weLifeSection)
            if !plan.notes.isEmpty { Text(plan.notes).font(FieldType.body).textSelection(.enabled) }
            TextField("What would you like to share?", text: $note, axis: .vertical).font(.system(.body)).lineLimit(2...6)
            if !note.isEmpty {
                Button("Save thought") {
                    let entry = "\(store.identity.name(for: store.speaker)): \(note)"
                    if update({ $0.notes = [$0.notes, entry].filter { !$0.isEmpty }.joined(separator: "\n\n") }) { note = "" }
                }.buttonStyle(FieldGoalPrimaryStyle()).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count + plan.notes.count > 7800)
            }
        }
    }
    private func connections(_ goal: FieldHorizon) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connected in Life").font(FieldType.weLifeSection)
            ForEach(store.state.lifeItems.filter { $0.isSharedPresence && goal.linkedLifeItemIDs.contains($0.id) }) { item in
                Button { openItem = .init(id: item.id) } label: {
                    HStack { Text(item.title); Spacer(); Image(systemName: item.isDone ? "checkmark" : "arrow.up.right") }.font(.system(.body)).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            Button("Bring something from Life") { showsLifePicker = true }.buttonStyle(FieldQuietButtonStyle())
            TextField("A concrete next step", text: $nextStep, axis: .vertical).font(.system(.body))
            Button("Add next step to Life") { if store.addGoalTask(goalID: goalID, title: nextStep) { nextStep = "" } }
                .buttonStyle(FieldGoalPrimaryStyle()).disabled(nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextStep.count > 240)
            Text("Shared with both of you. Links and next steps stay connected in Life.").font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
        }
    }
    @discardableResult private func update(_ change: (inout FieldGoalPlan) -> Void) -> Bool {
        guard var goal, var plan = goal.goalPlan else { return false }
        change(&plan); goal.goalPlan = plan; return store.saveGoal(goal)
    }
}

private struct FieldGoalSection<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct FieldGoalLifePicker: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: String
    @State private var selected = Set<String>()
    @State private var query = ""
    var body: some View {
        FieldGoalPage(title: "Bring it into this goal") {
            Text("Plans, links & inspiration").font(FieldType.pageHeadline)
            TextField("Find something in Life", text: $query).font(.system(.body))
            let items = store.state.lifeItems.filter { $0.isSharedPresence && !$0.id.hasPrefix("cal:") && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
            if items.isEmpty {
                Text("Shared items saved in Life appear here. Save a link or a thought there, then connect it to this goal.").font(.system(.subheadline))
            }
            ForEach(items) { item in
                Button {
                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                            if let url = item.sourceURL { Text(url.host() ?? "Saved link").font(.system(.caption)).foregroundStyle(.fieldInk(.reasoning)) }
                        }
                    }.font(.system(.body)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
            Button("Save connections") {
                guard var goal = store.state.horizons.first(where: { $0.id == goalID }) else { return }
                let sharedIDs = Set(store.state.lifeItems.filter { $0.isSharedPresence }.map(\.id))
                goal.linkedLifeItemIDs = selected.intersection(sharedIDs).sorted()
                if store.saveGoal(goal) { dismiss() }
            }.buttonStyle(FieldGoalPrimaryStyle())
        }.onAppear { selected = Set(store.state.horizons.first(where: { $0.id == goalID })?.linkedLifeItemIDs ?? []) }
    }
}

private struct FieldGoalPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FieldStore.self) private var store
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(title).font(.system(.subheadline, weight: .medium)); Spacer(); Button("Done") { dismiss() }.frame(minHeight: 44) }
                content
                if let error = store.itemSaveError { Text(error).font(FieldType.body).accessibilityIdentifier("field.us.goal.error") }
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WECanvas.cream.bg.ignoresSafeArea())
        .foregroundStyle(.fieldInk(.headline)).environment(\.weCanvas, .cream).preferredColorScheme(.light)
        .presentationDetents([.large])
    }
}

private struct FieldGoalPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.font(.system(.subheadline, weight: .medium))
            Spacer(minLength: 12)
            Image(systemName: "arrow.right").font(.system(.subheadline, weight: .medium))
        }
        .padding(.horizontal, 18).frame(minHeight: 52)
        .foregroundStyle(WECanvas.cream.bgElevated)
        .background(WECanvas.cream.ink, in: RoundedRectangle(cornerRadius: 12))
        .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
    }
}
