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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// This person's own hue. It is the only color in the arrival field:
    /// nothing partner-colored appears in a room that belongs to one person.
    ///
    /// Taken from `store.speaker` at the call site, not from `personA` — the
    /// rest of the app can be sloppy about which of the two it means because
    /// most surfaces belong to both of them. This one belongs to exactly one.
    private let hue: Color

    /// The entry whose "let go" is being confirmed, if any.
    @State private var releasing: YoursEntry?
    @State private var releasingOffer: YoursPreparedOffer?
    @State private var editing: YoursEntry?
    @State private var showsSnoozeConfirmation = false
    @State private var showsTeaching = false
    @State private var handledTeachingThisPresentation = false

    /// The one held entry whose writing is currently on screen, if any. One at
    /// a time — opening every card at once is the archive again.
    @State private var openHeld: String?

    /// Set the moment a close begins, so a second tap on ✕ during the ~300ms
    /// exit cannot start a second one — two overlapping `dismiss()` calls pop
    /// whatever is underneath as well.
    @State private var isClosing = false
    @State private var asksToDiscardDraft = false
    @State private var contentIsVisible = false
    @State private var savedWords: String?
    @State private var wordsAreSettling = false
    @FocusState private var composeIsFocused: Bool

    init(
        store: YoursStore,
        hue: Color = .white
    ) {
        _store = State(initialValue: store)
        self.hue = hue
    }

    var body: some View {
        room
            // 14f, the room. The one intentional warm deviation from the
            // ground — §3 — and the warmth is the whole signal: this is the
            // surface with no strip, no mark, and nothing filed or learned.
            .environment(\.weCanvas, .room)
            .onAppear { open() }
        // Every explicit exit is `close()`, so the room never simply vanishes.
        .interactiveDismissDisabled()
        .confirmationDialog("Leave this draft?", isPresented: $asksToDiscardDraft, titleVisibility: .visible) {
            Button("Discard draft and close", role: .destructive) { finishClosing() }
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("These words will not be kept on this phone after you close. Keep this screen open if you want to finish saving them.")
        }
    }

    private var room: some View {
        ZStack {
            personalField

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 34) {
                    if showsTeaching {
                        YoursTeachingRoom {
                            handledTeachingThisPresentation = true
                            showsTeaching = false
                            Task { await store.markTaught(.firstEntry) }
                        }
                    }

                    if let entry = releasing {
                        YoursReleaseRoom { reason in
                            releasing = nil
                            Task { await store.letGo(entry, reason: reason) }
                        }
                    } else if let offer = releasingOffer {
                        YoursReleaseRoom { reason in
                            releasingOffer = nil
                            Task { await store.letOfferGo(offer, reason: reason) }
                        }
                    } else if let entry = store.preparingOffer {
                        YoursOfferComposer(
                            entry: entry,
                            onPrepare: { title, question, options in
                                Task {
                                    await store.prepareOffer(
                                        from: entry,
                                        title: title,
                                        question: question,
                                        options: options
                                    )
                                }
                            },
                            onCancel: { store.cancelPreparingOffer() }
                        )
                    } else if let entry = editing {
                        YoursHeldEditor(
                            entry: entry,
                            onDecide: { decision, body in
                                editing = nil
                                Task {
                                    switch decision {
                                    case .updateHeld:
                                        await store.updateHeld(entry, body: body)
                                    case .letThisReturn:
                                        await store.letThisReturn(entry, body: body)
                                    }
                                }
                            },
                            onCancel: { editing = nil }
                        )
                    } else {
                        stateLedRoom
                    }
                }
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.top, 18)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .opacity(contentIsVisible ? 1 : 0)
            .offset(y: reduceMotion || contentIsVisible ? 0 : 10)
        }
        // §4: "never indexed, never learned from, carries no mark." The room
        // used to carry two — one in this bar and one beside the writing
        // prompt — which is the loudest possible way to describe somewhere
        // private, and a direct contradiction of the note at the top of this
        // file. What is left is a close, and nothing else.
        //
        // No background on the bar either. Painting it opaque cut a hard
        // rectangle across the arrival field, so the one warm surface in the
        // app announced itself with a seam.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                closeButton
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 12)
        }
        // The receipt goes when the next thing is being written.
        //
        // It used to dismiss on tap, which cannot survive an Undo sitting
        // inside it — the tap that meant "take that back" would have been
        // swallowed by the tap that meant "stop telling me". Not a timer
        // either: an Undo that disappears on a clock is a trap, and this is
        // the only window in which a mistake is correctable at all.
        .onChange(of: store.draft) { _, draft in
            guard !draft.isEmpty else { return }
            store.dismissSaveConfirmation()
        }
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { close() }
        .task {
            await store.open()
            guard !handledTeachingThisPresentation else { return }
            // The second and last time the word is ever shown. §2: a symbol
            // can become wordless after it is learned, not before.
            showsTeaching = store.shouldTeachOnFirstEntry
            if !showsTeaching,
               store.returned == nil,
               store.returnedOffer == nil {
                composeIsFocused = true
            }
        }
        .task { await store.drainDestroyQueue() }
    }

    @ViewBuilder
    private var stateLedRoom: some View {
        if let returned = store.returned {
            returnCard(returned)
            compose
        } else if let offer = store.returnedOffer {
            offerCard(offer)
            compose
        } else {
            compose
        }

        emptyLine
        heldDrawer
    }

    @ViewBuilder
    private var personalField: some View {
        if reduceTransparency {
            WECanvas.room.bg.ignoresSafeArea()
        } else {
            ZStack {
                WECanvas.room.bg
                RadialGradient(
                    colors: [
                        hue.opacity(0.18),
                        hue.opacity(0.055),
                        .clear,
                    ],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Writing

    private var compose: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(YoursCopy.compose)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)

            // The room is for writing, and until now it did not look like it.
            // A `TextEditor` with a hidden background and no border renders as
            // nothing at all on an empty draft: the screen was a sentence
            // floating over a void, with the one thing you came here to do
            // invisible. The rule underneath is the whole affordance — a line
            // to write on, which is the oldest possible way to say "here".
            //
            // Warm rather than grey, because this ground is warm and a neutral
            // hairline on it reads as a misprint.
            TextEditor(text: $store.draft)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.55, size: 14.5)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 132)
                .padding(.horizontal, -5)
                .focused($composeIsFocused)
                .accessibilityIdentifier("yours.compose")
                .accessibilityLabel("Private writing")
                .disabled(store.isSaving)
                .background(alignment: .topLeading) {
                    // Not a `TextField` prompt: `TextEditor` has none, and an
                    // overlay that swallowed taps would make the room look
                    // writable and refuse to be written in.
                    if store.draft.isEmpty, savedWords == nil {
                        Text(YoursCopy.composePlaceholder)
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.metadataProse))
                            .allowsHitTesting(false)
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(hue.opacity(composeIsFocused ? 0.42 : 0.20))
                        .frame(height: 1)
                        .animation(
                            reduceMotion ? nil : .weSettle(duration: 0.28),
                            value: composeIsFocused
                        )
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .topLeading) {
                    if let savedWords {
                        Text(savedWords)
                            .font(FieldType.body)
                            .foregroundStyle(hue)
                            .lineLimit(3)
                            .opacity(wordsAreSettling ? 0 : 0.72)
                            .scaleEffect(
                                reduceMotion || !wordsAreSettling ? 1 : 0.16,
                                anchor: .topLeading
                            )
                            .offset(
                                x: reduceMotion ? 0 : (wordsAreSettling ? 214 : 0),
                                y: reduceMotion ? 0 : (wordsAreSettling ? -56 : 0)
                            )
                            .allowsHitTesting(false)
                    }
                }

            // §8's save detail: the return and the outer bound, stated once,
            // at the moment of saving. Both dates, exactly, because forgetting
            // is invisible to the partner and completely legible to the owner
            // — and then never again as a countdown on the entry itself.
            //
            // The receipt carries the whole weight now. With nothing listed on
            // this surface, this is the only time an entry is ever seen
            // between being written and returning, so the dates lead in the
            // reading weight rather than sitting under a paraphrase of them.
            // And it offers the one way back: a mistake caught here would
            // otherwise wait six weeks to become correctable.
            if let saved = store.justSaved {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        YoursDates.saveDetail(
                            readyAt: saved.readyAt,
                            unseenDeleteAt: saved.unseenDeleteAt,
                            now: store.now
                        )
                    )
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))

                    Text(YoursCopy.saved)
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.legend))

                    Button(YoursCopy.undoSave) {
                        Task { await store.undoSave() }
                    }
                    .buttonStyle(FieldQuietButtonStyle())
                    .accessibilityIdentifier("yours.undo")
                }
                .accessibilityIdentifier("yours.saved")
            }

            if let error = store.saveError {
                Text(error)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .accessibilityIdentifier("yours.saveError")
            }

            if !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 12) {
                    Button(store.isSaving ? "Saving…" : "Set it down") {
                        settleWords(holding: false)
                    }
                    .buttonStyle(FieldFilledButtonStyle())
                    .accessibilityIdentifier("yours.setDown")
                    .disabled(store.isSaving)

                    // §3: available from the first save, and visually
                    // secondary here. Somebody who knows on day one that a
                    // thing is permanent should not have to wait eighteen
                    // weeks to say so.
                    Button(YoursCopy.keepIndefinitely) {
                        settleWords(holding: true)
                    }
                    .buttonStyle(FieldQuietButtonStyle())
                    .disabled(store.isSaving)
                }
            }
        }
    }

    private func settleWords(holding: Bool) {
        let words = store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        composeIsFocused = false
        Task {
            if holding { await store.saveAndHold() } else { await store.save() }
            guard store.saveError == nil else { return }
            savedWords = words
            wordsAreSettling = false
            withAnimation(reduceMotion ? .linear(duration: 0.18) : .easeOut(duration: 0.52)) {
                wordsAreSettling = true
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.55))
            savedWords = nil
            wordsAreSettling = false
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

    // MARK: Nothing waiting
    //
    // What used to be here was a list of everything living: each entry's text,
    // with a mark beside it tracking how close it was to returning. It was a
    // feed. Worse, it was a feed of the one kind of writing that is supposed
    // to be put down and left alone — so the surface quietly rewarded coming
    // back to re-read, which is the opposite of "write without deciding what
    // it becomes".
    //
    // "Most recent only" is still a feed with one item in it, and a "Written"
    // drawer is an archive wearing a coat. So: nothing. What you wrote is gone
    // until it returns to you, exactly as promised, and the dated receipt at
    // the moment of saving is what makes that a promise rather than a loss.
    //
    // Three things live on this surface now — compose, whatever returned
    // today, and Held. Held is a control surface for deletion and correction,
    // not somewhere to browse.

    /// The one line, when there is nothing to say.
    @ViewBuilder
    private var emptyLine: some View {
        if store.snapshot.held.isEmpty, store.returned == nil,
           store.returnedOffer == nil, store.justSaved == nil
        {
            Text(YoursCopy.empty)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.legend))
                .accessibilityIdentifier("yours.empty")
        }
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
                        .foregroundStyle(.fieldInk(.label))
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
                        heldCard(entry)
                    }
                }
            }
        }
    }

    /// The way out.
    ///
    /// The frame that positions this used to sit *outside* the `Button`, which
    /// made the button's own layout frame the entire screen while the glyph
    /// drew in the corner — so a tap anywhere on the surface dismissed it, and
    /// as the last child of the `ZStack` it sat over the scroll view. Both the
    /// padding and the hit shape belong inside the label; the *placement*
    /// belongs to an `.overlay` on the root. Same shape as `doneButton` in
    /// `FieldLearningSurfaces`.
    /// One held thing, closed until it is opened.
    ///
    /// The drawer used to render every body in full the moment it opened,
    /// which made Held the browsable archive the rest of this surface just
    /// stopped being. A card is a mark and its actions; the writing appears
    /// when somebody deliberately asks for it, one at a time.
    ///
    /// Still no preview and no truncated first line — a preview is browsing
    /// with worse typography.
    @ViewBuilder
    private func heldCard(_ entry: YoursEntry) -> some View {
        let isOpen = openHeld == entry.id

        FieldCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openHeld = isOpen ? nil : entry.id
                } label: {
                    HStack(spacing: 12) {
                        YoursMark(
                            style: .micro,
                            presence: .held,
                            hue: FieldInk.headline.color(on: .room)
                        )

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOpen ? "Close this" : "Open this")
                .accessibilityIdentifier("yours.held.card")

                if isOpen {
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

    // MARK: - Arrival and departure
    //
    // The personal field exists on the first frame; the room then resolves
    // with only a short translation and opacity change, so entry is a settling
    // rather than a wipe. The mark used to resolve alongside it and no longer
    // does — see the chrome above, and §4.

    private func open() {
        if reduceMotion {
            withAnimation(.linear(duration: 0.16)) {
                contentIsVisible = true
            }
        } else {
            withAnimation(.weSettle(duration: 0.52)) {
                contentIsVisible = true
            }
        }
    }

    /// Shorter than the entrance on purpose: arriving somewhere private feels
    /// like an opening, and leaving feels decided.
    private func close() {
        guard !store.isSaving else { return }
        if !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            asksToDiscardDraft = true
            return
        }
        finishClosing()
    }

    private func finishClosing() {
        guard !isClosing else { return }
        isClosing = true

        let duration = reduceMotion ? 0.14 : 0.3
        withAnimation(
            reduceMotion
                ? .linear(duration: duration)
                : .weSettle(duration: duration)
        ) {
            contentIsVisible = false
        }
        Task {
            try? await Task.sleep(for: .seconds(duration))
            leave()
        }
    }

    /// Dismisses without adding the cover's own transition after ours.
    private func leave() {
        var silent = Transaction()
        silent.disablesAnimations = true
        withTransaction(silent) { dismiss() }
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.fieldInk(.label))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("yours.close")
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
private struct YoursReleaseRoom: View {
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("yours.release")
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
private struct YoursTeachingRoom: View {
    let onSeen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            YoursMark(style: .display, presence: .living, hue: FieldInk.headline.color(on: .room))

            Text(YoursCopy.teachingTitle)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))

            Text(YoursCopy.teachingBody)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.quietListItem))

            Text(YoursCopy.outerBoundDisclosure)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))

            Button("Begin") {
                onSeen()
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .accessibilityIdentifier("yours.teaching.begin")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, 8)
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
    let onCancel: () -> Void

    @State private var title = ""
    @State private var question = ""
    @State private var optionA = ""
    @State private var optionB = ""

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
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(!isComplete)

            Button("Cancel") { onCancel() }
                .buttonStyle(FieldQuietButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FieldType.sectionLabel)
                .foregroundStyle(.fieldInk(.label))
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
private struct YoursHeldEditor: View {
    enum Decision { case updateHeld, letThisReturn }

    let entry: YoursEntry
    let onDecide: (Decision, String) -> Void
    let onCancel: () -> Void

    @State private var body_ = ""

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

            Button("Cancel") { onCancel() }
                .buttonStyle(FieldQuietButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { body_ = entry.body }
    }
}
