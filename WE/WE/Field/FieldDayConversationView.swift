//
//  FieldDayConversationView.swift
//  WE
//
//  The day's conversation, drawn. See `FieldDayConversation` for the rules.
//
//  Three voices, told apart without labels on every line:
//
//    · WE — left, in the serif, on a quiet surface. It speaks in sentences.
//    · You — right, outlined in your colour.
//    · Your partner — left, outlined in their colour, named once per run.
//
//  "Only me" is dashed, wherever it appears, and is never on the partner's
//  screen. No bubble carries a time, a "seen", or a typing indicator.
//

import SwiftUI

struct FieldDayConversationView: View {
    /// The greeting opens the day, above WE's main moment; the thread follows
    /// it. Two parts of one view so they share one voice.
    enum Part { case opening, thread }

    @Environment(FieldStore.self) private var store
    @Environment(\.weCanvas) private var canvas
    let part: Part
    @Binding var openItem: FieldItemReference?
    @Binding var showsDeferral: Bool
    @State private var yesterdayIsOpen = false

    var body: some View {
        switch part {
        case .opening: opening
        case .thread: threadBody
        }
    }

    private var opening: some View {
        let yesterday = FieldDayConversation.yesterdayItemIDs(store: store)
        return weLine(
            greeting + (yesterday.isEmpty ? "" : " " + FieldDayCopy.yesterday(count: yesterday.count)),
            action: yesterday.isEmpty ? nil : ("See them", { yesterdayIsOpen = true })
        )
        .accessibilityIdentifier("field.day.greeting")
        .sheet(isPresented: $yesterdayIsOpen) {
            FieldDayItemList(title: "Yesterday", itemIDs: yesterday)
                .environment(store)
        }
    }

    private var threadBody: some View {
        let thread = FieldDayConversation.thread(store: store)

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(thread) { entry in
                row(entry)
            }

            if !store.heldTopics.isEmpty {
                weLine(
                    FieldDayCopy.holding(count: store.heldTopics.count),
                    action: ("See them", { showsDeferral = true })
                )
                .accessibilityIdentifier("field.day.holding")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        FieldDayCopy.greeting(
            name: store.identity.name(for: store.speaker),
            hour: Calendar.gregorianUS.component(.hour, from: store.now)
        )
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: FieldDayEntry) -> some View {
        switch entry.kind {
        case .greeting(let text):
            weLine(text)
        case .yesterday:
            EmptyView()
        case .capture(let capture, let mine):
            captureBubble(capture, mine: mine)
        case .filed(let itemID):
            filedLine(itemID)
        case .decision(let message):
            decisionLine(message)
        case .lookup(let lookup):
            lookupExchange(lookup)
        case .holding:
            EmptyView()
        }
    }

    // MARK: WE

    private func weLine(
        _ text: String,
        dashed: Bool = false,
        action: (String, () -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(.fieldInk(.headline))
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .font(FieldType.reasoning)
                    .buttonStyle(.plain)
                    .foregroundStyle(.fieldInk(.headline))
                    .underline()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 16, bottomLeadingRadius: 5,
                bottomTrailingRadius: 16, topTrailingRadius: 16
            )
            .fill(canvas.ink.opacity(0.05))
        )
        .overlay {
            if dashed {
                UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 5,
                    bottomTrailingRadius: 16, topTrailingRadius: 16
                )
                .strokeBorder(canvas.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: You and your partner

    private func captureBubble(_ capture: FieldCapture, mine: Bool) -> some View {
        let isPrivate = capture.visibility == .private
        let colour = store.identity.color(for: capture.owner)

        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if isPrivate {
                Label(FieldDayCopy.lookupPrivacy, systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(.fieldInk(.legend))
            } else if !mine {
                Text(store.identity.name(for: capture.owner))
                    .font(.system(size: 11))
                    .foregroundStyle(colour)
            }

            Button {
                openItem = FieldItemReference(id: capture.id)
            } label: {
                Text(capture.text)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .multilineTextAlignment(mine ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: mine ? 16 : 5,
                            bottomTrailingRadius: mine ? 5 : 16,
                            topTrailingRadius: 16
                        )
                        .strokeBorder(
                            isPrivate ? canvas.ink.opacity(0.35) : colour,
                            style: StrokeStyle(lineWidth: 1, dash: isPrivate ? [4, 3] : [])
                        )
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                (mine ? "You: " : "\(store.identity.name(for: capture.owner)): ")
                    + capture.text
                    + (isPrivate ? ". Only you can see this." : "")
            )
            .accessibilityHint("Opens it in Life")
            .accessibilityIdentifier(mine ? "field.day.mine" : "field.day.partner")
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.leading, mine ? 48 : 0)
        .padding(.trailing, mine ? 0 : 48)
    }

    /// WE's reply to one of your own additions: where it went, and the two
    /// things you might want to do next. The partner never sees this line.
    @ViewBuilder
    private func filedLine(_ itemID: String) -> some View {
        if let item = store.state.lifeItems.first(where: { $0.id == itemID }) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(FieldDayCopy.filed(item, dayWord: item.dueOn.map(dayWord)))
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.fieldInk(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("Change") { openItem = FieldItemReference(id: itemID) }
                            .accessibilityIdentifier("field.day.change")
                        if item.isSharedPresence,
                           !store.hasProposedDecision(itemID: itemID),
                           !item.isDone {
                            Button("Decide on this together") {
                                store.proposeDecision(itemID: itemID)
                            }
                            .accessibilityIdentifier("field.day.propose")
                        }
                    }
                    .font(FieldType.reasoning)
                    .buttonStyle(.plain)
                    .foregroundStyle(.fieldInk(.legend))
                    .underline()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 5,
                    bottomTrailingRadius: 16, topTrailingRadius: 16
                )
                .fill(canvas.ink.opacity(0.05))
            )
            .frame(maxWidth: 320, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("field.day.filed")
        }
    }

    // MARK: Decisions

    /// A proposal, then its agreement. "Decided" only once the other person
    /// has confirmed it — never inferred from anything said.
    private func decisionLine(_ message: FieldChatMessage) -> some View {
        let title = message.context.flatMap(store.chatContextTitle) ?? message.body
        let mine = message.sender == store.speaker
        let text = message.confirmed
            ? FieldDayCopy.decided(title)
            : FieldDayCopy.proposal(
                by: mine ? nil : store.identity.name(for: message.sender),
                title: title
            )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: message.confirmed ? "checkmark.circle" : "circle.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !message.confirmed, !mine {
                Button("Agree") {
                    Task { await store.confirmConversationDecision(message) }
                }
                .font(FieldType.reasoning)
                .buttonStyle(.plain)
                .underline()
                .foregroundStyle(.fieldInk(.headline))
                .accessibilityIdentifier("field.day.agree")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(canvas.ink.opacity(0.05))
        )
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(message.confirmed ? "field.day.decided" : "field.day.proposal")
    }

    // MARK: Look-ups

    private func lookupExchange(_ lookup: FieldLookup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .trailing, spacing: 3) {
                Label(FieldDayCopy.lookupPrivacy, systemImage: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.fieldInk(.legend))
                Text(lookup.question)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(canvas.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)

            VStack(alignment: .leading, spacing: 8) {
                Text(lookup.foundNothing ? FieldDayCopy.nothingFound : FieldDayCopy.found)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(.fieldInk(.headline))

                ForEach(lookup.decisionIDs, id: \.self) { id in
                    if let message = store.chatMessages.first(where: { $0.id == id }) {
                        Text(FieldDayCopy.decided(message.context.flatMap(store.chatContextTitle) ?? message.body))
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.headline))
                    }
                }

                ForEach(lookup.itemIDs, id: \.self) { id in
                    if let item = store.state.lifeItems.first(where: { $0.id == id }) {
                        Button {
                            openItem = FieldItemReference(id: id)
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.title).underline()
                                if item.isDone {
                                    Text("done").foregroundStyle(.fieldInk(.legend))
                                }
                            }
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.headline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("field.day.lookup.item")
                    }
                }

                ForEach(lookup.earlierMessageIDs, id: \.self) { id in
                    if let message = store.chatMessages.first(where: { $0.id == id }) {
                        Text("From your earlier conversation: “\(message.body)”")
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(FieldDayCopy.saveForUs) { store.saveLookupForUs(lookup) }
                    .font(FieldType.reasoning)
                    .buttonStyle(.plain)
                    .underline()
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityIdentifier("field.day.lookup.save")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(canvas.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .frame(maxWidth: 320, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.day.lookup")
    }

    private func dayWord(_ date: Date) -> String {
        let calendar = Calendar.gregorianUS
        if calendar.isDate(date, inSameDayAs: store.now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: store.now)),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - A short list of items

/// Yesterday's additions, opened from the morning line.
struct FieldDayItemList: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let title: String
    let itemIDs: [String]
    @State private var openItem: FieldItemReference?

    var body: some View {
        NavigationStack {
            List(itemIDs, id: \.self) { id in
                if let item = store.state.lifeItems.first(where: { $0.id == id }) {
                    Button {
                        openItem = FieldItemReference(id: id)
                    } label: {
                        HStack {
                            FieldDot(owner: item.owner, isPrivate: item.visibility == .private, identity: store.identity)
                            Text(item.title).foregroundStyle(.fieldInk(.headline))
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { Button("Done") { dismiss() } }
        }
        .sheet(item: $openItem) { FieldItemSheet(itemID: $0.id).environment(store) }
    }
}
