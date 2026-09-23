//
//  FieldItemSheet.swift
//  WE
//
//  One filed thing, and the three things you can do to it.
//
//  Filing used to be one-way. A receipt could be corrected before it was sent,
//  and after that an item's word and its day were fixed forever — so a typo, a
//  thing filed under the wrong heading, or a plan that was cancelled stayed on
//  the page until somebody ticked it off as though it had happened.
//
//  This is the surface that fixes that, and it is one surface rather than two
//  because the category room and the calendar are asking the same question
//  about the same object. Reached by tapping a row in either.
//
//  It asks nothing the app can answer itself: no confirm on a move, because a
//  move is reversible in the same gesture; a confirmation on the removal,
//  because that one is not.
//

import SwiftUI

/// The row somebody tapped, as something `.sheet(item:)` will accept.
///
/// An id rather than the `LifeItem` itself, deliberately: the sheet mutates
/// the item on every control, and a value captured at presentation would go
/// stale the moment it did.
struct FieldItemReference: Identifiable, Hashable {
    let id: String
}

struct FieldItemSheet: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let itemID: String

    @State private var asksToRemove = false
    @State private var isPickingDay = false
    @State private var asksToShare = false

    /// Read live from the store rather than captured at presentation. Every
    /// control here mutates the item, and a copy taken when the sheet opened
    /// would render the state before the tap.
    private var item: LifeItem? {
        store.state.lifeItems.first { $0.id == itemID }
    }

    @State private var showsChat = false

    var body: some View {
        ZStack {
            WECanvas.cream.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if let item {
                    VStack(alignment: .leading, spacing: 0) {
                        header(item)
                            .padding(.bottom, FieldMetrics.sectionGap)

                        delivery
                        if WEFeatureFlags.shareInboxEnabled { WEPlanAttachments(planID: itemID).environment(store) }

                        whoSees(item)
                            .padding(.bottom, FieldMetrics.sectionGap)

                        if let error = store.itemSaveError {
                            Text(error).font(FieldType.body)
                                .padding(.bottom, 20)
                                .accessibilityIdentifier("field.item.saveError")
                        }

                        if item.sourceURL != nil { FieldItemHelp(item: item, sourceOnly: true) }

                        FieldItemActionPanel(item: item)
                            .id(itemID)

                        FieldItemHelp(item: item)

                        if FieldItemPurpose.resolve(item) != .reference {
                            when(item)
                                .padding(.bottom, 24)
                        }

                        if FieldItemPurpose.resolve(item) == .task {
                            Button("Mark complete") { store.complete(itemID) }
                                .buttonStyle(FieldWorkspacePrimaryStyle())
                                .padding(.bottom, 28)
                                .disabled(item.isDone)
                                .accessibilityIdentifier("field.item.complete")
                        }

                        if item.isSharedPresence {
                            Button("Discuss this together") { store.conversationContext = .init(kind: "life", id: item.id); showsChat = true }
                                .buttonStyle(FieldWorkspacePrimaryStyle()).padding(.bottom, 24)
                        }
                        standing(item)

                        DisclosureGroup("Organize this item") {
                            whereItLives(item)
                                .padding(.top, 16)
                        }
                        .font(.system(.body, weight: .medium))
                        .padding(.bottom, 28)

                        removeIt
                    }
                    .padding(.top, 72)
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.bottom, 60)
                }
            }
        }
        .overlay(alignment: .topTrailing) { doneButton }
        .sheet(item: Binding(
            get: { store.pendingOutreach },
            set: { if $0 == nil { store.dismissOutreach() } }
        )) { request in
            FieldOutreachConfirmation(request: request).environment(store)
        }
        .sheet(isPresented: $showsChat) { FieldConversationView(initialContext: .init(kind: "life", id: itemID)).environment(store) }
        .preferredColorScheme(.light)
        .environment(\.weCanvas, WECanvas.cream)
        .animation(.fieldZone(reduceMotion), value: item?.category)
        .animation(.fieldZone(reduceMotion), value: item?.dueOn)
        .animation(.fieldZone(reduceMotion), value: isPickingDay)
        // The item can leave from underneath this — the partner completes it,
        // or removing it succeeds. A sheet over nothing is not a state.
        .onChange(of: item == nil) { _, gone in
            if gone { dismiss() }
        }
        .onChange(of: item?.isDone) { _, done in
            if done == true { dismiss() }
        }
        .confirmationDialog(
            "Remove this?",
            isPresented: $asksToRemove,
            titleVisibility: .visible
        ) {
            Button("Remove it", role: .destructive) {
                if store.remove(itemID) { dismiss() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(
                item?.visibility == .private
                    ? "It goes from every screen, and there is no undo."
                    : "It goes for both of you, from every screen, and there "
                        + "is no undo."
            )
        }
        // Asked once, because this is the one change here that cannot be
        // taken back: the database lets a private thing become shared and
        // nothing the other way.
        .confirmationDialog(
            "Share with \(store.partnerName)?",
            isPresented: $asksToShare,
            titleVisibility: .visible
        ) {
            Button("Share it") { store.share(itemID) }
                .accessibilityIdentifier("field.item.share.confirm")
            Button("Keep it to myself", role: .cancel) {}
        } message: {
            Text(
                "\(store.partnerName) will be able to see it from now on. "
                    + "It can't be made private again."
            )
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.fieldInk(.legend))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityIdentifier("field.item.done")
    }

    // MARK: The thing itself

    private func header(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.category.word).font(.system(.subheadline, weight: .medium))

            HStack(alignment: .top, spacing: 11) {
                FieldDot(
                    owner: item.owner,
                    isPrivate: item.visibility == .private,
                    identity: store.identity,
                    size: FieldDotSize.prominentList,
                    baselineNudge: 8
                )

                Text(item.title)
                    .font(FieldType.hero)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            WEPrivacyLabel(text: store.privacyLabel(for: item))
            Text(whose(item))
                .font(.system(.footnote))
                .foregroundStyle(.fieldInk(.reasoning))
        }
    }

    private func whose(_ item: LifeItem) -> String {
        let owner = store.identity.name(for: item.owner)
        guard let dueOn = item.dueOn else { return owner }
        return "\(owner) · \(DateFormatter.fieldDayMonth.string(from: dueOn))"
    }

    // MARK: Whether the other phone has it

    /// Where this item's writing has got to, in one line.
    ///
    /// All three states are drawn, including the ordinary one. Drawing nothing
    /// when a write has landed reads as "shared" only to somebody who already
    /// knows that is the convention; to everybody else it is indistinguishable
    /// from a screen that has no opinion, which is the ambiguity this is here
    /// to remove.
    ///
    /// It says where the writing is, never why the network is unhappy: an
    /// error code is a fact about infrastructure, and the person is being
    /// asked one question, which is whether to try again.
    ///
    /// It also says nothing about who can *see* the item. Delivery and
    /// visibility are different facts, and an earlier draft of this copy read
    /// "Shared. They can see this.", which would tell somebody looking at a
    /// private item that their partner could read it because a row reached the
    /// server. Whether a thing is private is answered by `visibility`, on the
    /// item, and nowhere near this.
    @ViewBuilder
    private var delivery: some View {
        if store.canReportDelivery {
            deliveryLine
        }
    }

    @ViewBuilder
    private var deliveryLine: some View {
        switch store.deliveryState(for: itemID) {
        case .shared:
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                Text("Saved beyond this phone.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.delivery.shared")

        case .savedLocally:
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                Text("Saved on this phone only, for now.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.delivery.local")

        case .needsAttention:
            VStack(alignment: .leading, spacing: 14) {
                FieldRuleLine()

                Text("Saved on this phone only. It has not got any further yet.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Button {
                    Task { await store.retryDelivery(for: itemID) }
                } label: {
                    Text("Try again")
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.headline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field.item.delivery.retry")
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.delivery.blocked")
        }
    }

    // MARK: Where it stands
    //
    // Two facts Life sorts on that were previously invisible here, which is
    // how the sorting became unarguable-with. A person who could see "waiting
    // on someone else" on the Life screen had no way to find out *why* the app
    // thought so, and no way to say otherwise.

    @ViewBuilder
    private func standing(_ item: LifeItem) -> some View {
        if item.isAwaitingSomeoneElse {
            VStack(alignment: .leading, spacing: 14) {
                FieldRuleLine()

                Text("You said you'd reached out. Life is holding it as "
                     + "somebody else's move.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                // The way back. A voicemail nobody returned is not somebody
                // else having the next move for the rest of the year, and the
                // only person who can say so is the one who left it.
                Button {
                    store.reclaimOutreach(itemID)
                } label: {
                    Text("It's still on me")
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.headline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field.item.reclaim")
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.waiting")
        } else if FieldStrata.windowHasClosed(item, now: store.now) {
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                // Stated, not silently absorbed. The window is gone; whether
                // the thing still matters is not the app's call, and the two
                // controls that settle it — the date, and Remove it — are
                // already on this page.
                Text("That window has closed.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.windowClosed")
        }
    }

    // MARK: Who sees it

    /// Always said, never implied. A shared thing names who else can see it;
    /// a private one says so plainly and offers the one way it can change.
    private func whoSees(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldRuleLine()

            if item.visibility == .private {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(FieldType.subLabel)
                        .accessibilityHidden(true)
                    Text("Only you can see this.")
                        .font(FieldType.body)
                }
                .foregroundStyle(.fieldInk(.headline))
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("field.item.private")

                Button("Share with \(store.partnerName)") {
                    asksToShare = true
                }
                .buttonStyle(FieldQuietButtonStyle())
                .accessibilityIdentifier("field.item.share")
            } else {
                Text("\(store.partnerName) can see this.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .padding(.top, 18)
                    .accessibilityIdentifier("field.item.shared")
            }
        }
    }

    // MARK: Where it lives

    private func whereItLives(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldCategoryPicker(
                options: store.correctionCategories,
                choose: { store.refile(itemID, to: $0) },
                name: { store.refile(itemID, toNewCategory: $0) },
                title: "Where it lives",
                selected: item.category,
                selectedTint: store.identity.color(for: item.owner, on: .cream)
            )
            .padding(.top, 18)
        }
    }

    // MARK: When
    //
    // A date is the whole of what makes an item rank, surface, and fall due —
    // see `LifeItem.pressure(now:)`. So this is not a detail field: it is the
    // control that moves something on and off the calendar and out of Today.

    private func when(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("When", ink: .labelQuiet)
                .padding(.top, 18)
                .padding(.bottom, 13)

            if isPickingDay {
                dayPicker(item)
            } else {
                FieldFlowLayout(spacing: 8, lineSpacing: 8) {
                    FieldChip(
                        "TODAY",
                        isSelected: isOn(item, offsetFromToday: 0),
                        tint: store.identity.color(for: item.owner, on: .cream)
                    ) {
                        store.redate(itemID, to: store.now)
                    }
                    .accessibilityIdentifier("field.item.today")

                    FieldChip(
                        "TOMORROW",
                        isSelected: isOn(item, offsetFromToday: 1),
                        tint: store.identity.color(for: item.owner, on: .cream)
                    ) {
                        store.redate(itemID, to: tomorrow)
                    }

                    FieldChip("PICK A DAY") { isPickingDay = true }
                        .accessibilityIdentifier("field.item.pickDay")

                    // Only offered when there is a date to take off. "No date"
                    // beside a thing that never had one is a control that does
                    // nothing, which is how a page starts feeling like a form.
                    if item.dueOn != nil {
                        FieldChip("NO DATE") { store.redate(itemID, to: nil) }
                            .accessibilityIdentifier("field.item.noDate")
                    }
                }
            }
        }
    }

    private func dayPicker(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            DatePicker(
                "The day",
                selection: Binding(
                    get: { item.dueOn ?? store.now },
                    set: { store.redate(itemID, to: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(store.identity.color(for: item.owner, on: .cream))
            .accessibilityIdentifier("field.item.dayPicker")

            Button("Back to the days") { isPickingDay = false }
                .buttonStyle(FieldQuietButtonStyle())
        }
    }

    private func isOn(_ item: LifeItem, offsetFromToday days: Int) -> Bool {
        guard let dueOn = item.dueOn,
              let day = Calendar.gregorianUS.date(
                  byAdding: .day,
                  value: days,
                  to: store.now
              )
        else { return false }
        return Calendar.gregorianUS.isDate(dueOn, inSameDayAs: day)
    }

    private var tomorrow: Date {
        Calendar.gregorianUS.date(byAdding: .day, value: 1, to: store.now)
            ?? store.now
    }

    // MARK: Removing it

    private var removeIt: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            Button("Remove it") { asksToRemove = true }
                .buttonStyle(FieldQuietButtonStyle())
                .padding(.top, 8)
                .accessibilityHint(
                    "Removes this for both of you. There is no undo."
                )
                .accessibilityIdentifier("field.item.remove")
        }
    }

}

#Preview {
    let store = FieldStore()
    return FieldItemSheet(
        itemID: store.state.lifeItems.first?.id ?? ""
    )
    .environment(store)
}

/// Working with an item comes before organising it.
private struct FieldItemActionPanel: View {
    @Environment(FieldStore.self) private var store
    let item: LifeItem
    @State private var decision = ""
    @State private var note = ""
    @State private var shareText = ""
    @State private var savedMessage: String?
    @State private var isResolving = false

    private var purpose: FieldItemPurpose { FieldItemPurpose.resolve(item) }
    private var contactAct: FieldAct? {
        let act = FieldTodaySelector.primaryAct(for: item)
        return [.call, .message, .email, .book].contains(act) ? act : nil
    }
    private var options: [String] {
        if item.category == .food { return ["Cook at home", "Go out", "Order in"] }
        return []
    }
    private var sharing: String {
        item.isSharedPresence ? "Saved on this shared item, visible to both of you." : "Saved on this private item."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark")
                    .font(.system(.subheadline, weight: .medium))
                    .accessibilityIdentifier("field.item.action.saved")
            }

            if purpose == .decision {
                Text("Choose a direction.")
                    .font(FieldType.pageHeadline)
                if !options.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(options, id: \.self) { option in
                            Button { decision = option } label: {
                                HStack {
                                    Text(option).font(FieldType.captureWriting)
                                    Spacer()
                                    Image(systemName: decision == option ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .light))
                                }
                                .padding(.vertical, 17)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(decision == option ? .isSelected : [])
                            .accessibilityIdentifier("field.item.decision.option")
                            FieldRuleLine(color: FieldRule.watching)
                        }
                    }
                }
                TextField("Make it specific, or write another choice", text: $decision, axis: .vertical)
                    .font(FieldType.body)
                    .lineLimit(2...5)
                    .padding(16)
                    .background(WECanvas.cream.bg, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("field.item.decision.choice")
                Text(sharing).font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
                Button("Save decision") {
                    if store.saveDecision(on: item.id, choice: decision) {
                        savedMessage = "Decision saved. Your plan is ready."
                        decision = ""
                    }
                }
                .buttonStyle(FieldWorkspacePrimaryStyle())
                .disabled(decision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || decision.count > 240)
                .accessibilityIdentifier("field.item.decision.save")
            } else {
                if item.title.lowercased().hasPrefix("send ") {
                    TextField("Write the list or message to share", text: $shareText, axis: .vertical)
                        .font(FieldType.body)
                        .lineLimit(4...10)
                        .padding(16)
                        .background(WECanvas.cream.bg, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("field.item.action.shareDraft")
                    ShareLink(item: shareText) {
                        Label("Choose where to share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(FieldWorkspacePrimaryStyle())
                    .disabled(shareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("field.item.action.share")
                } else if let act = contactAct {
                    Button(isResolving ? "Finding the destination…" : FieldItemPurpose.actionLabel(item)) {
                        isResolving = true
                        Task {
                            await store.begin(act, for: item.id)
                            isResolving = false
                        }
                    }
                    .buttonStyle(FieldWorkspacePrimaryStyle())
                    .disabled(isResolving)
                    .accessibilityIdentifier("field.item.action.begin")
                }

                DisclosureGroup(item.sourceURL != nil ? "Thoughts to share" : purpose == .reference ? "Add a note" : "Write the next step") {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField(item.sourceURL != nil ? "What caught your eye? What would you like to talk about?" : "What would help you move this forward?", text: $note, axis: .vertical)
                            .font(FieldType.body)
                            .lineLimit(3...8)
                            .padding(14)
                            .background(WECanvas.cream.bg, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("field.item.action.note")
                        Text(sharing).font(.system(.footnote)).foregroundStyle(.fieldInk(.reasoning))
                        Button("Save note") {
                            if store.saveNextStep(on: item.id, note: note) {
                                note = ""
                                savedMessage = "Note saved."
                            }
                        }
                        .buttonStyle(FieldWorkspacePrimaryStyle())
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 1000)
                        .accessibilityIdentifier("field.item.action.saveNote")
                    }
                    .padding(.top, 12)
                }
                .font(.system(.body, weight: .medium))
            }
        }
        .foregroundStyle(.fieldInk(.headline))
        .padding(.bottom, 28)
    }
}

private struct FieldWorkspacePrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .foregroundStyle(WECanvas.cream.bgElevated)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(WECanvas.cream.ink.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
