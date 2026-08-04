//
//  YoursSurface.swift
//  WE
//
//  The personal space, and what it deliberately is not.
//
//  CIRCLE.md §7: "The most distinctive version of this does *not* open onto a
//  reverse-chronological journal. A product that visually celebrates
//  accumulation while claiming to resist it is telling on itself."
//
//  So the order on this screen is an argument. Writing comes first, because
//  that is what the space is for. One returned entry comes second, if one has
//  been presented, and never more than one. Held is a drawer somebody opens,
//  not a section that greets them. Living entries are reachable and
//  unemphasised. There is no feed, no count, no inbox, no streak, no overdue
//  state, and no guilt language anywhere — and the absence of each of those is
//  a decision rather than an omission.
//
//  Returns are discovered here rather than announced (§9). There is no push
//  notification for them and there must not be one: "Something in Yours is
//  ready for you" on a lock screen, on a phone lying face up on a shared
//  counter, tells a partner that something private matured today.
//

import SwiftUI

struct YoursSurface: View {
    @State private var store: YoursStore
    @Environment(\.dismiss) private var dismiss

    /// The entry whose "let go" is being confirmed, if any.
    @State private var releasing: YoursEntry?
    @State private var releasingOffer: YoursPreparedOffer?
    @State private var editing: YoursEntry?
    @State private var showsSnoozeConfirmation = false
    @State private var showsTeaching = false

    init(store: YoursStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    compose

                    if let returned = store.returned {
                        returnCard(returned)
                    } else if let offer = store.returnedOffer {
                        offerCard(offer)
                    }

                    living
                    heldDrawer
                }
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.top, 30)
                .padding(.bottom, 80)
            }

            closeButton
        }
        .preferredColorScheme(.dark)
        .task {
            await store.open()
            // The second and last time the word is ever shown. §2: a symbol
            // can become wordless after it is learned, not before.
            showsTeaching = store.shouldTeachOnFirstEntry
        }
        .task { await store.drainDestroyQueue() }
        .sheet(isPresented: $showsTeaching) {
            YoursTeachingSheet {
                showsTeaching = false
                Task { await store.markTaught(.firstEntry) }
            }
        }
        .sheet(item: $releasing) { entry in
            YoursReleaseSheet { reason in
                releasing = nil
                Task { await store.letGo(entry, reason: reason) }
            }
        }
        .sheet(item: $releasingOffer) { offer in
            YoursReleaseSheet { reason in
                releasingOffer = nil
                Task { await store.letOfferGo(offer, reason: reason) }
            }
        }
        .sheet(item: $store.preparingOffer) { entry in
            YoursOfferComposer(entry: entry) { title, question, options in
                Task {
                    await store.prepareOffer(
                        from: entry,
                        title: title,
                        question: question,
                        options: options
                    )
                }
            }
        }
        .sheet(item: $editing) { entry in
            YoursHeldEditSheet(entry: entry) { decision, body in
                editing = nil
                Task {
                    switch decision {
                    case .updateHeld:
                        await store.updateHeld(entry, body: body)
                    case .letThisReturn:
                        await store.letThisReturn(entry, body: body)
                    }
                }
            }
        }
    }

    // MARK: Writing

    private var compose: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(YoursCopy.compose)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))

            TextEditor(text: $store.draft)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.headline))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(12)
                .background(FieldPalette.ink.opacity(0.05))
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityIdentifier("yours.compose")

            // §8's save detail: the return and the outer bound, stated once,
            // at the moment of saving. Both dates, exactly, because forgetting
            // is invisible to the partner and completely legible to the owner
            // — and then never again as a countdown on the entry itself.
            if let saved = store.justSaved {
                VStack(alignment: .leading, spacing: 6) {
                    Text(YoursCopy.saved)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.headline))

                    Text(
                        YoursDates.saveDetail(
                            readyAt: saved.readyAt,
                            unseenDeleteAt: saved.unseenDeleteAt,
                            now: store.now
                        )
                    )
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.legend))
                }
                .accessibilityIdentifier("yours.saved")
                .onTapGesture { store.dismissSaveConfirmation() }
            }

            if !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 12) {
                    Button("Save") {
                        Task { await store.save() }
                    }
                    .buttonStyle(FieldOutlinedButtonStyle())

                    // §3: available from the first save, and visually
                    // secondary here. Somebody who knows on day one that a
                    // thing is permanent should not have to wait eighteen
                    // weeks to say so.
                    Button(YoursCopy.keepIndefinitely) {
                        Task { await store.saveAndHold() }
                    }
                    .buttonStyle(FieldQuietButtonStyle())
                }
            }
        }
    }

    // MARK: The return

    private func returnCard(_ entry: YoursEntry) -> some View {
        FieldCard {
            VStack(alignment: .leading, spacing: 18) {
                Text(YoursCopy.returnQuestion)
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))

                Text(entry.body)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.quietListItem))

                // Two questions, and which one is asked is the only thing the
                // renewal count is ever used for. It is not rendered, here or
                // anywhere.
                if entry.isSecondReturn {
                    secondReturnActions(entry)
                } else {
                    firstReturnActions(entry)
                }
            }
        }
        .accessibilityIdentifier("yours.return")
    }

    private func firstReturnActions(_ entry: YoursEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(YoursCopy.keepForNow) {
                Task { await store.keepForNow(entry) }
            }
            .buttonStyle(FieldOutlinedButtonStyle())

            Button(YoursCopy.keepIndefinitely) {
                Task { await store.hold(entry) }
            }
            .buttonStyle(FieldQuietButtonStyle())

            if entry.canSnooze {
                Button(YoursCopy.snooze) {
                    showsSnoozeConfirmation = true
                }
                .buttonStyle(FieldQuietButtonStyle())
                .confirmationDialog(
                    snoozeSentence(entry),
                    isPresented: $showsSnoozeConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(YoursCopy.snooze) {
                        Task { await store.snooze(entry) }
                    }
                }
            }

            Button(YoursCopy.letGo) { releasing = entry }
                .buttonStyle(FieldQuietButtonStyle())
        }
    }

    /// §3's three options, in order, with **no default and no pre-selection**.
    /// A pre-selected answer to "should this continue" is the system having an
    /// opinion about somebody's private writing.
    private func secondReturnActions(_ entry: YoursEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(YoursCopy.keepOnlyForMe) {
                Task { await store.hold(entry) }
            }
            .buttonStyle(FieldOutlinedButtonStyle())

            Button(YoursCopy.prepareAnOffer) {
                store.beginPreparingOffer(from: entry)
            }
            .buttonStyle(FieldQuietButtonStyle())

            Button(YoursCopy.letItGo) { releasing = entry }
                .buttonStyle(FieldQuietButtonStyle())
        }
    }

    /// Both dates, stated before the week is granted. This is the one window
    /// that can run out while nobody is looking, so consent for that outcome
    /// is obtained here or not at all.
    private func snoozeSentence(_ entry: YoursEntry) -> String {
        let returnsOn = store.now.addingTimeInterval(7 * 86_400)
        return YoursDates.snoozeConfirmation(
            returnsOn: returnsOn,
            letGoOn: returnsOn.addingTimeInterval(7 * 86_400)
        )
    }

    // MARK: A prepared offer, come back

    private func offerCard(_ offer: YoursPreparedOffer) -> some View {
        FieldCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(offer.title)
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))

                Text(offer.question)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.quietListItem))

                // Two options and no third. If it did not cross in two weeks,
                // the preparation was the work.
                Button(YoursCopy.send) {
                    Task { await store.send(offer) }
                }
                .buttonStyle(FieldOutlinedButtonStyle())

                Button(YoursCopy.letItGo) { releasingOffer = offer }
                    .buttonStyle(FieldQuietButtonStyle())
            }
        }
    }

    // MARK: Living

    /// Reachable, unemphasised, and not a feed.
    ///
    /// The mark beside each entry is the only status it carries — outline
    /// while living, lightening across the final week. No date, no countdown,
    /// no ordering by anything but when it was written.
    private var living: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.snapshot.living.isEmpty, store.returned == nil {
                Text(YoursCopy.empty)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityIdentifier("yours.empty")
            }

            ForEach(store.snapshot.living) { entry in
                HStack(alignment: .top, spacing: 12) {
                    YoursMark(
                        style: .micro,
                        presence: presence(for: entry),
                        hue: .fieldInk(.headline)
                    )
                    .padding(.top, 2)

                    Text(entry.body)
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.quietListItem))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func presence(for entry: YoursEntry) -> YoursMark.Presence {
        if entry.state == .held { return .held }
        if entry.state == .presented { return .returned }
        if let progress = YoursDates.nearingProgress(
            readyAt: entry.readyAt,
            now: store.now
        ) {
            return .nearing(progress)
        }
        return .living
    }

    // MARK: Held

    /// A drawer, opened deliberately.
    ///
    /// There is no cap on it and no count of it, permanently. A cap turns
    /// deliberate permanence into a storage quota, and at the limit the
    /// product would be pressuring somebody to rank or delete private
    /// material. Held may accumulate; that is acceptable, because its defining
    /// property is that every item in it entered deliberately.
    private var heldDrawer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.snapshot.held.isEmpty {
                Button {
                    store.showsHeldDrawer.toggle()
                } label: {
                    Text(YoursCopy.heldDrawer)
                        .font(FieldType.sectionLabel)
                        .foregroundStyle(.fieldInk(.monoLabel))
                }
                .buttonStyle(.plain)
                // §4: owner-initiated, never a prompt and never a scheduled
                // audit. The drawer is labelled with the noun and the action
                // lives in the hint, so nothing on screen ever asks somebody
                // to go through what they have kept.
                .accessibilityHint(YoursCopy.reviewHeld)
                .accessibilityIdentifier("yours.held")

                if store.showsHeldDrawer {
                    ForEach(store.snapshot.held) { entry in
                        FieldCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(entry.body)
                                    .font(FieldType.listItem)
                                    .foregroundStyle(.fieldInk(.headline))

                                Button(YoursCopy.letThisReturn) {
                                    Task { await store.letThisReturn(entry) }
                                }
                                .buttonStyle(FieldQuietButtonStyle())

                                Button(YoursCopy.letGoNow) { releasing = entry }
                                    .buttonStyle(FieldQuietButtonStyle())

                                Button("Edit") { editing = entry }
                                    .buttonStyle(FieldQuietButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.fieldInk(.monoLabel))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 12)
        .accessibilityLabel("Close")
    }
}

// MARK: - Letting go

/// Optional, one tap, dismissible, and it never blocks the release.
///
/// §13's real question is not whether releasing felt good but *why*, and the
/// answer means completely different things depending on what was released. A
/// prepared offer is already partner-directed, so letting one go is
/// avoidance-shaped; free personal writing is a different emotional object
/// entirely. That is why the reasons split into two registers and why the
/// recorded row always carries which kind of thing this was.
///
/// A closed set rather than a text box: §10 forbids raw text reaching
/// analytics, and an open field at the moment of letting go is an interview
/// nobody agreed to.
/// Deliberately knows nothing about what is being released.
///
/// Which kind of thing it was travels with the recorded row instead, set by
/// the RPC that does the destroying — so the two can never be mixed up at the
/// point that matters, and a pooled release rate is not something this screen
/// could produce even by accident.
private struct YoursReleaseSheet: View {
    let onChoose: (YoursReleaseReason?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(YoursCopy.releaseReasonPrompt)
                .font(FieldType.cardTitle)
                .foregroundStyle(.fieldInk(.headline))

            ForEach(YoursReleaseReason.allCases, id: \.self) { reason in
                Button(reason.prompt) { onChoose(reason) }
                    .buttonStyle(FieldOutlinedButtonStyle())
            }

            Button(YoursCopy.releaseReasonDecline) { onChoose(nil) }
                .buttonStyle(FieldQuietButtonStyle())

            Text(YoursCopy.deletionAssurance)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))
        }
        .padding(FieldMetrics.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FieldPalette.bg)
        .presentationDetents([.medium])
    }
}

// MARK: - The second teaching moment

/// The last time the word appears anywhere in the product.
///
/// §2 allows exactly two: one during the Promise, one here. After this the
/// mark carries the meaning alone — no title, no navigation label, no section
/// header, no settings row. This is a bounded exception to the no-word rule
/// and not a loophole to widen: adding a third use is a product decision, not
/// a copy edit.
private struct YoursTeachingSheet: View {
    let onSeen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            YoursMark(style: .display, presence: .living, hue: .fieldInk(.headline))

            Text(YoursCopy.teachingTitle)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))

            Text(YoursCopy.teachingBody)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.quietListItem))

            Text(YoursCopy.outerBoundDisclosure)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))

            Button("Begin", action: onSeen)
                .buttonStyle(FieldOutlinedButtonStyle())
        }
        .padding(FieldMetrics.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FieldPalette.bg)
        .interactiveDismissDisabled()
    }
}

// MARK: - Writing an offer

/// §6. The person writes the exact wording that will cross, and sees it before
/// it does.
///
/// Nothing is prefilled from the entry. A composer that suggested a title
/// derived from private writing would be putting words in somebody's mouth at
/// the one moment the whole design promises it will not — and the frozen
/// artifact this produces is the only thing the partner ever sees.
private struct YoursOfferComposer: View {
    let entry: YoursEntry
    let onPrepare: (String, String, [String]) -> Void

    @State private var title = ""
    @State private var question = ""
    @State private var optionA = ""
    @State private var optionB = ""
    @Environment(\.dismiss) private var dismiss

    private var isComplete: Bool {
        ![title, question, optionA, optionB].contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(YoursCopy.prepareOffer)
                .font(FieldType.cardTitle)
                .foregroundStyle(.fieldInk(.headline))

            field("Title", text: $title)
            field("Question", text: $question)
            field("One answer", text: $optionA)
            field("Another", text: $optionB)

            Button(YoursCopy.prepareOffer) {
                onPrepare(title, question, [optionA, optionB])
                dismiss()
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(!isComplete)

            Button("Cancel") { dismiss() }
                .buttonStyle(FieldQuietButtonStyle())
        }
        .padding(FieldMetrics.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FieldPalette.bg)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FieldType.sectionLabel)
                .foregroundStyle(.fieldInk(.monoLabel))
            TextField("", text: text)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.headline))
                .padding(10)
                .background(FieldPalette.ink.opacity(0.05))
                .clipShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
    }
}

// MARK: - Editing something held

/// §4. New words do not inherit permanence, so this is a question rather than
/// a save. There is no third option that quietly keeps both, and there is no
/// version history: a revision log would be an accumulating, undeletable
/// record of exactly the material this design exists to let go of.
private struct YoursHeldEditSheet: View {
    enum Decision { case updateHeld, letThisReturn }

    let entry: YoursEntry
    let onDecide: (Decision, String) -> Void

    @State private var body_ = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(YoursCopy.heldEditQuestion)
                .font(FieldType.cardTitle)
                .foregroundStyle(.fieldInk(.headline))

            TextEditor(text: $body_)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.headline))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(12)
                .background(FieldPalette.ink.opacity(0.05))
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            Button(YoursCopy.updateHeld) { onDecide(.updateHeld, body_) }
                .buttonStyle(FieldOutlinedButtonStyle())

            Button(YoursCopy.letThisReturn) { onDecide(.letThisReturn, body_) }
                .buttonStyle(FieldQuietButtonStyle())

            Text(YoursCopy.letThisReturnDetail)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))

            Button("Cancel") { dismiss() }
                .buttonStyle(FieldQuietButtonStyle())
        }
        .padding(FieldMetrics.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FieldPalette.bg)
        .onAppear { body_ = entry.body }
    }
}
