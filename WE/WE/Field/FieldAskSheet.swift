//
//  FieldAskSheet.swift
//  WE
//
//  Ask WE: a question about what is already written down.
//
//  It used to be answered inside Today, as an exchange, which made a private
//  look up read like a message to somebody. It lives here now, on its own
//  surface, and Today is never written into. The rules are the look up's own
//  (`FieldLookupEngine`): answered only with records this person can already
//  see, held in memory on this phone, never filed and never sent.
//

import SwiftUI

struct FieldAskSheet: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var question = ""
    @State private var openItem: FieldItemReference?

    private var trimmed: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field
                        .padding(.bottom, 10)

                    Label("Only you see this. Nothing here is saved.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.fieldInk(.legend))
                        .padding(.bottom, FieldMetrics.sectionGap)

                    if store.lookups.isEmpty {
                        Text("Ask about anything either of you kept. “What did we get for dad?” “Where's the hotel we liked?”")
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(store.lookups.reversed())) { lookup in
                            answer(lookup)
                                .padding(.bottom, 28)
                        }
                    }
                }
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WECanvas.surface.bg.ignoresSafeArea())
            .navigationTitle("Ask WE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("field.ask.done")
                }
            }
        }
        .onAppear { if store.lookups.isEmpty { focused = true } }
        .sheet(item: $openItem) { FieldItemSheet(itemID: $0.id).environment(store) }
        .accessibilityIdentifier("field.ask")
    }

    private var field: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.fieldInk(.legend))
                .accessibilityHidden(true)
            TextField("What did we decide about…", text: $question, axis: .vertical)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(.fieldInk(.headline))
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(ask)
                .accessibilityIdentifier("field.ask.input")
            if !trimmed.isEmpty {
                Button("Ask", action: ask)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.fieldInk(.headline))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("field.ask.submit")
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { FieldRuleLine() }
    }

    private func ask() {
        guard !trimmed.isEmpty else { return }
        store.lookUp(trimmed)
        question = ""
    }

    // MARK: One answer

    private func answer(_ lookup: FieldLookup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lookup.question)
                .font(FieldType.listItemLarge)
                .foregroundStyle(.fieldInk(.headline))
                .fixedSize(horizontal: false, vertical: true)

            Text(lookup.foundNothing ? FieldDayCopy.nothingFound : FieldDayCopy.found)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(lookup.decisionIDs, id: \.self) { id in
                    if let message = store.chatMessages.first(where: { $0.id == id }) {
                        row(
                            FieldDayCopy.decided(message.context.flatMap(store.chatContextTitle) ?? message.body),
                            systemImage: "checkmark.circle"
                        )
                    }
                }
                ForEach(lookup.itemIDs, id: \.self) { id in
                    if let item = store.state.lifeItems.first(where: { $0.id == id }) {
                        Button { openItem = FieldItemReference(id: id) } label: {
                            row(
                                item.title + (item.isDone ? ", done" : ""),
                                detail: item.category.word,
                                systemImage: "chevron.right",
                                trailing: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens it")
                        .accessibilityIdentifier("field.ask.item")
                    }
                }
                ForEach(lookup.earlierMessageIDs, id: \.self) { id in
                    if let message = store.chatMessages.first(where: { $0.id == id }) {
                        row("From an earlier conversation: “\(message.body)”", systemImage: "quote.opening")
                    }
                }
            }

            // The one way a question leaves this phone: on purpose, as a
            // shared thing to talk about. Named so nobody does it by accident.
            Button(FieldDayCopy.saveForUs) {
                store.saveLookupForUs(lookup)
            }
            .font(FieldType.reasoning)
            .buttonStyle(.plain)
            .underline()
            .foregroundStyle(.fieldInk(.legend))
            .frame(minHeight: 44)
            .accessibilityHint("Shares this question with \(store.partnerName)")
            .accessibilityIdentifier("field.ask.save")
        }
        .accessibilityElement(children: .contain)
    }

    private func row(
        _ text: String,
        detail: String? = nil,
        systemImage: String,
        trailing: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if !trailing {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.fieldInk(.legend))
                }
            }
            Spacer(minLength: 8)
            if trailing {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { FieldRuleLine(color: FieldRule.row) }
    }
}
