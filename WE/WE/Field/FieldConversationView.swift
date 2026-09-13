import SwiftUI

struct FieldConversationView: View {
    @Environment(FieldStore.self) private var store
    @State private var focusedContext: FieldChatContext?
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var history: [FieldChatMessage] = []
    @State private var decisionsOnly = false
    @State private var query = ""
    @State private var loading = false
    @State private var hasEarlier = true
    @State private var atBottom = true
    @State private var settings = false
    @State private var contextPicker = false
    @State private var contextQuery = ""
    @State private var keeping: FieldChatMessage?
    @State private var proposing: FieldChatMessage?
    @State private var openedItem: FieldItemReference?
    @State private var openedGoal: FieldItemReference?
    @State private var notice: FieldGoalSuggestion?
    @State private var dismissedTopics: Set<String> = []
    @State private var suggestions: [FieldGoalSuggestion] = []
    @FocusState private var writing: Bool
    init(initialContext: FieldChatContext? = nil) {
        _focusedContext = State(initialValue: initialContext)
    }

    private var preference: FieldChatPreference? { store.state.chatPreferences?.first { $0.owner == store.speaker } }
    private var noticesAllowed: Bool {
        FieldConversationPolicy.noticesAllowed(store.state.chatPreferences ?? []) && !session.v2State.signalConsents.contains { $0.signal == .sharedPlans && !$0.isEnabled }
    }
    private var dismissalKey: String { "we.chat.dismissed." + (session.user?.id ?? "demo") + "." + (session.snapshot?.membership?.coupleID ?? "demo") }
    private var upcoming: LifeItem? {
        let contexts = store.chatMessages.compactMap(\.context)
        let goalIDs = Set(contexts.filter { $0.kind == "goal" }.map(\.id))
        let ids = Set(contexts.filter { $0.kind == "life" }.map(\.id) + store.state.horizons.filter { goalIDs.contains($0.id) }.flatMap(\.linkedLifeItemIDs) + store.chatMessages.map(\.id))
        return store.state.lifeItems.filter {
            guard $0.isSharedPresence, !$0.isDone, ids.contains($0.id), let date = $0.dueOn else { return false }
            return date >= Calendar.current.startOfDay(for: Date()) && date < Date().addingTimeInterval(3 * 86400)
        }.sorted { ($0.dueOn ?? .distantFuture) < ($1.dueOn ?? .distantFuture) }.first
    }
    private var allMessages: [FieldChatMessage] {
        var merged = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in store.chatMessages { merged[message.id] = message }
        return merged.values.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }
    private var messages: [FieldChatMessage] {
        allMessages.filter { message in
            if let focusedContext, !store.conversationMessage(message, relatesTo: focusedContext) { return false }
            return (!decisionsOnly || (message.decision && message.confirmed)) && (query.isEmpty || message.body.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if focusedContext == nil, noticesAllowed, let suggestion = suggestions.first(where: { !dismissedTopics.contains($0.id) }), !decisionsOnly {
                            HStack(alignment: .top) {
                                Button { notice = suggestion } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Taking shape").font(.system(.caption, weight: .medium))
                                        Text(suggestion.title).font(FieldType.captureWriting)
                                        Text("From \(suggestion.items.count) things you’ve shared. Review together.").font(.system(.caption))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                Button { dismissedTopics.insert(suggestion.id); UserDefaults.standard.set(Array(dismissedTopics), forKey: dismissalKey) } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }.accessibilityLabel("Just chatting, dismiss this suggestion")
                            }.padding(16).background(WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if focusedContext == nil, noticesAllowed, let upcoming, !decisionsOnly {
                            Button { openedItem = .init(id: upcoming.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Coming up · " + (upcoming.dueOn?.formatted(.dateTime.month(.abbreviated).day()) ?? "")).font(.system(.caption))
                                        Text(upcoming.title).font(.system(.subheadline))
                                    }
                                    Spacer(); Image(systemName: "arrow.up.right")
                                }.padding(16)
                            }.buttonStyle(.plain)
                        }
                        if hasEarlier {
                            Button(loading ? "Loading…" : "Load earlier messages") { Task { await loadEarlier() } }
                                .font(.system(.caption)).frame(maxWidth: .infinity, minHeight: 44).disabled(loading)
                        }
                        if messages.isEmpty && !loading {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(decisionsOnly ? "What you decide, kept together." : focusedContext != nil ? "A place to talk about this." : "A little space for you two.").font(FieldType.pageHeadline)
                                Text(decisionsOnly ? "Propose a decision from a message. It appears here after your partner confirms it." : "Send a link and it’s kept in Life. Bring a plan or a shared hope into the conversation. A next step is always your choice.").font(.system(.body)).foregroundStyle(.fieldInk(.reasoning))
                            }.padding(.vertical, 30)
                        }
                        ForEach(messages) { message in messageRow(message).id(message.id) }
                        Color.clear.frame(height: 1).id("bottom").onAppear { atBottom = true }.onDisappear { atBottom = false }
                    }.padding(.horizontal, 22).padding(.vertical, 20)
                }.scrollDismissesKeyboard(.interactively)
                .onChange(of: store.chatMessages.last?.id) { _, _ in
                    if atBottom || store.chatMessages.last?.sender == store.speaker { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }.frame(minHeight: 0, maxHeight: .infinity)
            if let error = store.conversationError ?? store.itemSaveError {
                Text(error).font(.system(.caption)).padding(.horizontal, 22).foregroundStyle(.fieldInk(.headline))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !decisionsOnly { composer }
        }
        .background(WECanvas.cream.bg.ignoresSafeArea()).environment(\.weCanvas, .cream).preferredColorScheme(.light)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .task {
            dismissedTopics = Set(UserDefaults.standard.stringArray(forKey: dismissalKey) ?? [])
            hasEarlier = store.chatMessages.count >= 100
            await markRead()
        }
        .task(id: decisionsOnly) {
            if decisionsOnly { loading = true; history = await store.earlierChat(before: nil, decisionsOnly: true); hasEarlier = history.count >= 100; loading = false }
            else { history = []; hasEarlier = store.chatMessages.count >= 100 }
        }
        .task(id: store.chatMessages.last?.id) { await markRead() }
        .task(id: store.chatMessages.hashValue ^ noticesAllowed.hashValue) {
            suggestions = noticesAllowed ? FieldGoalSuggestions.suggestions(items: FieldConversationPolicy.evidence(store.chatMessages), goals: store.state.horizons) : []
        }
        .sheet(isPresented: $settings) { settingsSheet }
        .sheet(isPresented: $contextPicker) { contextSheet }
        .sheet(item: $keeping) { FieldKeepChatSheet(message: $0).environment(store) }
        .sheet(item: $proposing) { FieldDecisionDraft(message: $0).environment(store) }
        .sheet(item: $openedItem) { FieldItemSheet(itemID: $0.id).environment(store) }
        .sheet(item: $openedGoal) { FieldGoalRoom(goalID: $0.id).environment(store).environmentObject(session) }
        .sheet(item: $notice) { FieldChatGoalDraft(suggestion: $0).environment(store) }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(typeSize.isAccessibilitySize ? "Chat" : "Between you two")
                    .font(typeSize.isAccessibilitySize ? .system(.headline) : FieldType.captureWriting)
                    .accessibilityLabel("Between you two")
                Spacer()
                Button { settings = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 22)).frame(width: 44, height: 44) }.accessibilityLabel("Conversation settings")
                Button("Done") { dismiss() }.font(.system(.subheadline)).frame(minHeight: 44).accessibilityIdentifier("field.chat.done")
            }
            if !writing || !typeSize.isAccessibilitySize {
                if typeSize.isAccessibilitySize {
                    ScrollView(.horizontal, showsIndicators: false) { conversationTabs }
                        .fixedSize(horizontal: false, vertical: true)
                } else { conversationTabs }
            }
            if let context = focusedContext {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.kind == "goal" ? "From Us" : "From Life")
                            .font(.system(.caption, weight: .medium)).foregroundStyle(.fieldInk(.reasoning))
                        Text(store.chatContextTitle(context) ?? "Original item unavailable")
                            .font(.system(.subheadline, weight: .medium)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button("Show all") { focusedContext = nil; Task { await markRead() } }
                        .font(.system(.subheadline)).frame(minHeight: 44)
                        .accessibilityIdentifier("field.chat.showAll")
                }
                .padding(.top, 4)
            }
            if decisionsOnly { TextField("Find a decision in loaded messages", text: $query).font(.system(.subheadline)) }
        }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)
        .foregroundStyle(.fieldInk(.headline))
    }
    private var conversationTabs: some View {
        HStack(spacing: 24) {
            tab("Conversation", selected: !decisionsOnly) { decisionsOnly = false }
            tab("Decisions", selected: decisionsOnly) { decisionsOnly = true }
        }
    }
    private func tab(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).font(.system(.subheadline, weight: selected ? .semibold : .regular)).fixedSize(horizontal: true, vertical: false).padding(.vertical, 10)
            .overlay(alignment: .bottom) { if selected { Rectangle().frame(height: 1) } } }.buttonStyle(.plain)
    }
    private func messageRow(_ message: FieldChatMessage) -> some View {
        let mine = message.sender == store.speaker
        return HStack {
            if mine { Spacer(minLength: 34) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.identity.name(for: message.sender)).font(.system(.caption, weight: .medium))
                    Spacer(minLength: 12)
                    Text(message.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(.caption))
                }.foregroundStyle(.fieldInk(.reasoning))
                if let context = message.context {
                    Button {
                        if context.kind == "goal" { openedGoal = .init(id: context.id) } else { openedItem = .init(id: context.id) }
                    } label: { Label(store.chatContextTitle(context) ?? "Original item unavailable", systemImage: "arrow.up.right").font(.system(.caption)) }
                        .disabled(store.chatContextTitle(context) == nil)
                }
                if message.decision { Text(message.confirmed ? "Decided together" : "Proposed decision").font(.system(.caption, weight: .semibold)) }
                if !message.textWithoutLinks.isEmpty {
                    Text(message.textWithoutLinks).font(.system(.body)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(message.urls, id: \.absoluteString) { url in
                    sharedLink(url, message: message)
                }
                if message.decision && !message.confirmed && !mine {
                    Button("That’s what we decided") { Task { await store.confirmConversationDecision(message) } }.font(.system(.subheadline, weight: .medium)).frame(minHeight: 44)
                }
                HStack {
                    if mine && store.canReportDelivery {
                        switch store.deliveryState(for: message.id) {
                        case .savedLocally: Text("Waiting to send").font(.system(.caption2))
                        case .needsAttention: Button("Retry sending") { Task { await store.retryDelivery(for: message.id) } }.font(.system(.caption))
                        case .shared: Text("Sent").font(.system(.caption2))
                        }
                    }
                    Spacer()
                    Menu {
                        if store.state.lifeItems.contains(where: { $0.id == message.id }) {
                            Button("Open saved item in Life") { openedItem = .init(id: message.id) }
                        }
                        Button(message.urls.isEmpty ? "Keep in Life / make a plan" : "Make a plan from this") { keeping = message }
                        if !message.decision { Button("Propose a decision") { proposing = message } }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("Message actions")
                }
            }.padding(16)
                .background(mine ? store.identity.color(for: store.speaker, on: .cream).opacity(0.09) : WECanvas.cream.bgElevated, in: RoundedRectangle(cornerRadius: 18))
            if !mine { Spacer(minLength: 34) }
        }.foregroundStyle(.fieldInk(.headline))
    }
    private func sharedLink(_ url: URL, message: FieldChatMessage) -> some View {
        let saved = store.savedConversationLink(url)
        return VStack(alignment: .leading, spacing: 0) {
            Link(destination: url) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "link").font(.system(size: 20)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(url.host() ?? "Open link").font(.system(.subheadline, weight: .medium))
                        if !url.path.isEmpty && url.path != "/" {
                            Text(url.path.removingPercentEncoding ?? url.path)
                                .font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning)).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right").font(.system(.caption))
                }
                .frame(minHeight: 44, alignment: .leading).padding(.vertical, 8)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let saved {
                FieldRuleLine(color: FieldRule.row)
                HStack(spacing: 0) {
                    Button { openedItem = .init(id: saved.id) } label: {
                        Label {
                            Text(savedLinkStatus(saved)).font(.system(.subheadline))
                        } icon: {
                            Image(systemName: "bookmark").font(.system(size: 18))
                        }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("field.chat.savedLink")
                    if store.canReportDelivery && store.deliveryState(for: saved.id) == .needsAttention {
                        Button("Retry") { Task { await store.retryDelivery(for: saved.id) } }
                            .font(.system(.subheadline)).frame(minWidth: 44, minHeight: 44)
                    }
                    if FieldItemPurpose.resolve(saved) == .reference {
                        Menu {
                            Button("Remove from Saved", role: .destructive) { _ = store.remove(saved.id) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Saved link options")
                    }
                }
            } else {
                Button { _ = store.keepConversationLink(url, from: message) } label: {
                    Label("Keep in Life", systemImage: "bookmark")
                        .font(.system(.subheadline)).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func savedLinkStatus(_ item: LifeItem) -> String {
        guard store.canReportDelivery else { return "Saved in Life" }
        switch store.deliveryState(for: item.id) {
        case .shared: return "Saved in Life"
        case .savedLocally: return "Saved in Life · syncing"
        case .needsAttention: return "Saved on this phone"
        }
    }

    private var composer: some View {
        @Bindable var store = store
        let draftURLs = FieldConversationLinks.urls(in: store.conversationDraft)
        return VStack(alignment: .leading, spacing: 8) {
            if !draftURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if typeSize.isAccessibilitySize {
                        Text(draftURLs.count == 1 ? "Link → Life when sent" : "\(draftURLs.count) links → Life when sent")
                            .font(.system(.caption)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "link")
                            Text(draftURLs.first?.host() ?? "Link").lineLimit(1)
                            if draftURLs.count > 1 { Text("+\(draftURLs.count - 1)") }
                            Spacer(minLength: 0)
                        }.font(.system(.subheadline, weight: .medium))
                        Text(draftURLs.count == 1 ? "Kept in Life when you send" : "All \(draftURLs.count) links kept in Life when you send")
                            .font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
                    }
                }.padding(.horizontal, 14).padding(.top, 8)
                .accessibilityIdentifier("field.chat.linkPreview")
            }
            if let context = store.conversationContext, context != focusedContext {
                HStack {
                    Label(store.chatContextTitle(context) ?? "Item unavailable", systemImage: "paperclip").font(.system(.caption)).lineLimit(1)
                    Spacer()
                    Button { store.conversationContext = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Remove attached context")
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button { contextPicker = true } label: { Image(systemName: "plus").font(.system(size: 22)).frame(width: 44, height: 48) }.accessibilityLabel("Bring a Life item or Us goal")
                TextField(typeSize.isAccessibilitySize ? "Message…" : "Say something, share a link…", text: $store.conversationDraft, axis: .vertical)
                    .font(.system(.body)).lineLimit(1...(typeSize.isAccessibilitySize ? 2 : 5)).focused($writing).padding(.vertical, 14)
                    .accessibilityIdentifier("field.chat.input")
                Button {
                    if store.sendConversation(store.conversationDraft, context: store.conversationContext ?? focusedContext) { store.conversationDraft = ""; store.conversationContext = nil; writing = false }
                } label: { Image(systemName: "arrow.up").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: Circle()) }
                    .disabled(store.conversationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.conversationDraft.count > 4000)
                    .accessibilityLabel("Send message").accessibilityIdentifier("field.chat.send")
            }
            if store.conversationDraft.count > 3800 { Text("\(store.conversationDraft.count) / 4,000").font(.system(.caption)) }
        }.padding(.horizontal, 12).padding(.vertical, 10).background(.regularMaterial)
        .foregroundStyle(.fieldInk(.headline))
    }
    private var settingsSheet: some View {
        FieldChatPage(title: "A little help from WE") {
            Text("Your conversation stays yours.").font(FieldType.pageHeadline)
            Text("When you both opt in, WE can notice recurring possibilities in shared messages. Suggestions stay outside the conversation. Nothing is saved as a plan without your choice.").font(.system(.body))
            Toggle("Notice possibilities in our chat", isOn: Binding(get: { preference?.notices ?? false }, set: { value in Task { await store.updateChatPreference(notices: value) } }))
            Text(noticesAllowed ? "You’ve both enabled suggestions." : "Suggestions stay off until both of you enable them.").font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
            Toggle("Message notifications", isOn: Binding(get: { preference?.notifications ?? true }, set: { value in Task { await store.updateChatPreference(notices: preference?.notices ?? false, notifications: value) } }))
            Text("Messages appear live while WE is open. Background notifications are not available in this beta yet.").font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
            Text("This version recognizes recurring topics on your device. Private writing is never included. No read receipts or online-status tracking.").font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
            if let error = store.conversationError { Text(error) }
        }
    }
    private var contextSheet: some View {
        let goals = store.state.horizons.filter { contextQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(contextQuery) }
        let items = store.state.lifeItems.filter {
            $0.isSharedPresence && !$0.isDone && !$0.id.hasPrefix("cal:") && (contextQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(contextQuery))
        }
        return FieldChatPage(title: "Bring it into the conversation") {
            Text("A plan, a possibility, something you’ve kept. Give your conversation a place to return to.")
                .font(.system(.body)).foregroundStyle(.fieldInk(.reasoning))
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                TextField("Find something in Us or Life", text: $contextQuery)
                    .accessibilityLabel("Find something in Us or Life")
            }.font(.system(.body)).padding(.vertical, 12)
            FieldRuleLine(color: FieldRule.row)
            if !goals.isEmpty {
                Text("From Us").font(FieldType.weLifeSection)
                ForEach(goals) { goal in
                    contextRow(goal.title, subtitle: "Shared goal", context: .init(kind: "goal", id: goal.id))
                }
            }
            if !items.isEmpty {
                Text("From Life").font(FieldType.weLifeSection)
                ForEach(items) { item in
                    contextRow(item.title, subtitle: item.sourceURL?.host() ?? "Shared in Life", context: .init(kind: "life", id: item.id))
                }
            }
            if goals.isEmpty && items.isEmpty {
                Text(contextQuery.isEmpty ? "Your shared plans and saved ideas will appear here. You can start by sending a link." : "Nothing matches yet. Try another word.")
                    .font(.system(.body)).foregroundStyle(.fieldInk(.reasoning))
            }
        }
    }
    private func contextRow(_ title: String, subtitle: String, context: FieldChatContext) -> some View {
        Button {
            store.conversationContext = context
            contextPicker = false
            contextQuery = ""
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(.body)).lineLimit(2)
                    Text(subtitle).font(.system(.subheadline)).foregroundStyle(.fieldInk(.reasoning))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus").font(.system(.body))
            }.frame(minHeight: 44).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func loadEarlier() async {
        loading = true
        let page = await store.earlierChat(before: allMessages.first?.id, decisionsOnly: decisionsOnly)
        history.append(contentsOf: page); hasEarlier = page.count >= 100; loading = false
    }
    private func markRead() async {
        guard focusedContext == nil, store.chatUnread else { return }
        await store.updateChatPreference(notices: preference?.notices ?? false, readAt: Date())
    }
}

private struct FieldKeepChatSheet: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let message: FieldChatMessage
    @State private var title = ""
    @State private var task = false
    @State private var dated = false
    @State private var date = Date()
    var body: some View {
        FieldChatPage(title: "Keep what matters") {
            TextField("A name for this", text: $title, axis: .vertical).font(FieldType.pageHeadline)
            Toggle("Make this a next step", isOn: $task)
            if task {
                Toggle("Give it a date", isOn: $dated)
                if dated { DatePicker("When", selection: $date, displayedComponents: .date) }
            }
            Text("Shared in Life, with the original message and link attached. No one is assigned automatically.").font(.system(.subheadline))
            Button(task ? "Save plan to Life" : "Keep in Life") {
                if store.keepConversation(message, title: title, asTask: task, dueOn: task && dated ? date : nil) { dismiss() }
            }.buttonStyle(FieldChatPrimaryStyle()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 240)
            if let error = store.itemSaveError { Text(error).font(.system(.subheadline)) }
        }.onAppear {
            title = String((message.textWithoutLinks.isEmpty ? message.firstURL.map(FieldConversationLinks.title) ?? message.body : message.textWithoutLinks).prefix(120))
            task = !message.urls.isEmpty
        }
    }
}
private struct FieldDecisionDraft: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let message: FieldChatMessage
    @State private var text = ""
    var body: some View {
        FieldChatPage(title: "What did you decide?") {
            TextField("Put the decision in your own words", text: $text, axis: .vertical).font(FieldType.captureWriting).lineLimit(3...8)
            Text("Your partner will confirm this before it appears in Decisions. The original message remains in the conversation.").font(.system(.subheadline))
            Button("Propose this decision") {
                if store.sendConversation(text, context: message.context, decision: true, sourceID: message.id) { dismiss() }
            }.buttonStyle(FieldChatPrimaryStyle()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000)
        }.onAppear { text = message.body }
    }
}
private struct FieldChatGoalDraft: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let suggestion: FieldGoalSuggestion
    @State private var title = ""
    var body: some View {
        FieldChatPage(title: "A possibility for Us") {
            TextField("Goal", text: $title).font(FieldType.pageHeadline)
            Text("These messages may belong together. You decide.").font(.system(.subheadline))
            ForEach(suggestion.items) { Text($0.title).font(.system(.body)) }
            Button(suggestion.existingGoalID == nil ? "Add to Exploring" : "Connect to the existing goal") {
                if store.keepChatGoal(suggestion, title: title) { dismiss() }
            }.buttonStyle(FieldChatPrimaryStyle()).disabled(title.isEmpty || title.count > 120)
        }.onAppear { title = suggestion.title }
    }
}
private struct FieldChatPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            HStack { Text(title).font(.system(.subheadline, weight: .medium)); Spacer(); Button("Done") { dismiss() }.frame(minHeight: 44) }
            content
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
        .background(WECanvas.cream.bg.ignoresSafeArea()).foregroundStyle(.fieldInk(.headline))
        .environment(\.weCanvas, .cream).preferredColorScheme(.light).presentationDetents([.large])
    }
}
private struct FieldChatPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, weight: .medium)).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(WECanvas.cream.bgElevated).background(WECanvas.cream.ink, in: RoundedRectangle(cornerRadius: 12))
            .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
    }
}
