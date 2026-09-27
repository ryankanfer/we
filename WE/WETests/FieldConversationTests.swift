import Foundation
import Testing
@testable import WE

@MainActor
struct FieldConversationTests {
    func empty() -> FieldState { .empty(nameA: "Alex", nameB: "Sam", now: Date()) }
    @Test func messageOutboxSurvivesRelaunchAndDoesNotDuplicate() async throws {
        let disk = FieldOutboxStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let partition = FieldOutboxPartition(userID: "test", coupleID: "test")
        let server = FieldMemoryBackend(state: empty())
        let queue = FieldOutbox(wrapping: server, partition: partition, store: disk)
        let message = FieldChatMessage(body: "Shall we go to Japan?", sender: .a)
        try queue.stage([.sendChat(message)])
        let restored = FieldOutbox(wrapping: server, partition: partition, store: disk)
        #expect(restored.pending.count == 1)
        try await restored.flush()
        try await server.sendChat(message)
        #expect(try await server.load().conversation?.count == 1)
        #expect(restored.pending.isEmpty)
    }
    @Test func invalidAndPrivateContextCannotSend() {
        var state = empty()
        state.lifeItems = [LifeItem(id: "secret", title: "Private", category: .notes, owner: .a, dueOn: nil, closesAt: nil, clusterID: nil, source: .captured, detail: nil, isTimeCritical: false, isDone: false, visibility: .private)]
        let store = FieldStore(state: state)
        #expect(!store.sendConversation("  ", context: nil))
        #expect(!store.sendConversation(String(repeating: "a", count: 4001), context: nil))
        let context = FieldChatContext(kind: "life", id: "secret")
        #expect(store.chatContextTitle(context) == nil)
        let didSend = store.sendConversation("Discuss", context: context)
        #expect(didSend == false)
        #expect(store.chatMessages.isEmpty)
    }
    @Test func suggestionsRequireBothExplicitChoices() {
        #expect(!FieldConversationPolicy.noticesAllowed([]))
        #expect(!FieldConversationPolicy.noticesAllowed([.init(owner: .a, notices: true)]))
        #expect(!FieldConversationPolicy.noticesAllowed([.init(owner: .a, notices: true), .init(owner: .b, notices: false)]))
        #expect(FieldConversationPolicy.noticesAllowed([.init(owner: .a, notices: true), .init(owner: .b, notices: true)]))
    }
    @Test func proposedDecisionCannotConfirmItself() async {
        let store = FieldStore(state: empty())
        #expect(store.sendConversation("Spring in Japan", context: nil, decision: true))
        await store.confirmConversationDecision(store.chatMessages[0])
        #expect(!store.chatMessages[0].confirmed)
    }
    @Test func keepingALinkPreservesSourceAndTaskIntent() {
        let store = FieldStore(state: empty())
        let message = FieldChatMessage(body: "Compare this https://example.com/trip", sender: .a)
        #expect(store.keepConversation(message, title: "Compare flight options", asTask: true, dueOn: nil))
        #expect(store.state.lifeItems[0].sourceURL?.absoluteString == "https://example.com/trip")
        #expect(FieldItemPurpose.resolve(store.state.lifeItems[0]) == .task)
        #expect(store.state.lifeItems[0].owner == .shared)
        #expect(store.state.lifeItems[0].detail?.contains(message.body) == true)
    }
    @Test func repeatedSharedDiscussionCanBecomeGoalWithoutAutoCommitment() {
        var state = empty()
        state.chatPreferences = [.init(owner: .a, notices: true), .init(owner: .b, notices: true)]
        state.conversation = ["Go to Japan next year?", "Flights to Tokyo look good", "Visit Kyoto in spring"].map { .init(body: $0, sender: .a) }
        let store = FieldStore(state: state)
        let suggestions = FieldGoalSuggestions.suggestions(items: FieldConversationPolicy.evidence(store.chatMessages), goals: [])
        #expect(!suggestions.isEmpty)
        #expect(store.keepChatGoal(suggestions[0], title: "Japan together"))
        #expect(store.state.horizons[0].goalPlan?.isBuilding == false)
        #expect(store.state.horizons[0].linkedLifeItemIDs.count == 3)
        #expect(FieldGoalSuggestions.suggestions(items: FieldConversationPolicy.evidence(store.chatMessages), goals: store.state.horizons).isEmpty)
    }
    @Test func unsafeURLDoesNotBecomeLink() {
        #expect(FieldChatMessage(body: "javascript:alert(1)", sender: .a).firstURL == nil)
    }
    @Test func sentLinksBecomeReferencesWithoutTurningDiscussionIntoTasks() throws {
        let store = FieldStore(state: empty())
        store.conversationDraft = "Book these? https://example.com/hotel https://example.org/flight"
        #expect(store.state.lifeItems.isEmpty)
        #expect(store.sendConversation(store.conversationDraft, context: nil))
        #expect(store.state.lifeItems.count == 2)
        #expect(store.state.lifeItems.allSatisfy { FieldItemPurpose.resolve($0) == .reference && $0.dueOn == nil && $0.owner == .shared })
        #expect(store.state.lifeItems.allSatisfy { $0.detail?.contains(store.conversationDraft) == true })
        #expect(store.chatMessages[0].urls.count == 2)
        #expect(store.chatMessages[0].textWithoutLinks == "Book these?")
    }

    @Test func repeatedURLsReuseTheSharedItemAndKeepEveryConversation() throws {
        let store = FieldStore(state: empty())
        #expect(store.sendConversation("First https://example.com https://example.com/", context: nil))
        let item = try #require(store.state.lifeItems.first)
        #expect(store.sendConversation("Another thought https://example.com/", context: nil))
        #expect(store.state.lifeItems == [item])
        let context = FieldChatContext(kind: "life", id: item.id)
        #expect(store.chatMessages.allSatisfy { store.conversationMessage($0, relatesTo: context) })
        #expect(!store.conversationMessage(.init(body: "Unrelated", sender: .b), relatesTo: context))
    }

    @Test func privateSavedLinkIsNeverReusedOrPublished() throws {
        var state = empty()
        state.lifeItems = [LifeItem(id: "private", title: "My private thoughts", category: .notes, owner: .a,
            dueOn: nil, closesAt: nil, clusterID: nil, source: .captured, detail: "Private detail",
            isTimeCritical: false, isDone: false, sourceURL: URL(string: "https://example.com/"), visibility: .private)]
        let original = state.lifeItems[0]
        let store = FieldStore(state: state)
        #expect(store.sendConversation("https://example.com/", context: nil))
        #expect(store.state.lifeItems.count == 2)
        #expect(store.state.lifeItems.first(where: { $0.id == "private" }) == original)
        #expect(store.savedConversationLink(try #require(original.sourceURL))?.isSharedPresence == true)
    }

    @Test func linksAndGoalConnectionsSurviveRelaunchTogether() throws {
        var state = empty()
        let goal = FieldGoalTests().goal()
        state.horizons = [goal]
        let server = FieldMemoryBackend(state: state)
        let disk = FieldOutboxStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let partition = FieldOutboxPartition(userID: "test", coupleID: "test")
        let queue = FieldOutbox(wrapping: server, partition: partition, store: disk)
        let store = FieldStore(state: state, backend: queue)
        #expect(store.sendConversation("Options https://example.com/a https://example.com/b", context: .init(kind: "goal", id: goal.id)))
        let restored = FieldOutbox(wrapping: server, partition: partition, store: disk).replayPending(over: state)
        #expect(restored.conversation?.count == 1)
        #expect(restored.lifeItems.count == 2)
        #expect(Set(restored.horizons[0].linkedLifeItemIDs) == Set(restored.lifeItems.map(\.id)))
        #expect(restored.horizons[0].goalPlan?.isBuilding == false)
    }

    @Test func failedDiskWriteKeepsDraftAndDoesNotPartiallySaveLinks() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("not a directory".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = FieldOutbox(wrapping: FieldMemoryBackend(state: empty()),
            partition: .init(userID: "test", coupleID: "test"), store: .init(directory: file))
        let store = FieldStore(state: empty(), backend: queue)
        store.conversationDraft = "Keep https://example.com/a https://example.com/b"
        #expect(!store.sendConversation(store.conversationDraft, context: nil))
        #expect(!store.conversationDraft.isEmpty)
        #expect(store.state.lifeItems.isEmpty)
        #expect(store.chatMessages.isEmpty)
        #expect(queue.isEmpty)
        #expect(store.conversationError != nil)
    }

    @Test func removingSavedLinkLeavesConversationAndAllowsKeepingItAgain() throws {
        let store = FieldStore(state: empty())
        #expect(store.sendConversation("For later https://example.com/", context: nil))
        let message = try #require(store.chatMessages.first)
        let url = try #require(message.firstURL)
        #expect(store.remove(try #require(store.savedConversationLink(url)).id))
        #expect(store.chatMessages == [message])
        #expect(store.savedConversationLink(url) == nil)
        #expect(store.keepConversationLink(url, from: message))
        #expect(store.keepConversationLink(url, from: message))
        #expect(store.state.lifeItems.count == 1)
    }

    @Test func URLIdentityPreservesMeaningfulQueriesAndFragments() {
        let message = FieldChatMessage(body: "https://example.com/p?a=1 https://example.com/p?a=2 https://example.com/p#one https://example.com/p#two mailto:a@example.com", sender: .a)
        #expect(message.urls.count == 4)
        #expect(FieldChatMessage(body: "👋 https://example.com/a and https://example.com/b", sender: .a).textWithoutLinks == "👋  and")
    }

    @Test func domainNamesNeverBecomeDecisions() {
        let store = FieldStore(state: empty())
        #expect(store.sendConversation("https://choose.com/ https://pick.com/", context: nil))
        #expect(store.state.lifeItems.allSatisfy { FieldItemPurpose.resolve($0) == .reference })
    }

    @Test func newGoalSyncsBeforeItsLinkedConversationAfterCompaction() throws {
        let initial = empty()
        let queue = FieldOutbox(wrapping: FieldMemoryBackend(state: initial),
            partition: .init(userID: "test", coupleID: "test"),
            store: .init(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
        let store = FieldStore(state: initial, backend: queue)
        let goal = FieldGoalTests().goal()
        #expect(store.saveGoal(goal))
        #expect(store.sendConversation("https://example.com/trip", context: .init(kind: "goal", id: goal.id)))
        #expect(store.sendConversation("Another option https://example.com/other", context: .init(kind: "goal", id: goal.id)))
        let goalIndex = try #require(queue.pending.firstIndex { if case .upsertHorizon = $0.mutation { return true }; return false })
        let chatIndex = try #require(queue.pending.firstIndex { if case .sendChat = $0.mutation { return true }; return false })
        let itemIndex = try #require(queue.pending.firstIndex { if case .upsertItem = $0.mutation { return true }; return false })
        #expect(itemIndex < goalIndex)
        #expect(goalIndex < chatIndex)
    }

}
