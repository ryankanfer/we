//
//  FieldCaptureField.swift
//  WE
//
//  "Say something" — the single input in the app. Option 5a.
//
//  The user never has to know where anything goes. They type; the model
//  classifies; the receipt says where it went and why; one tap corrects it.
//
//  The prototype faked this with four canned phrases behind buttons. Here it
//  is a live text input whose contents are classified — the sample phrases
//  survive only as a demo affordance, and they are the classifier's few-shot
//  set.
//

import SwiftUI

struct FieldCaptureField: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    /// Collapsed by default. The chips are a reassurance that nothing was
    /// dropped, not a list anybody works from — and Today is the one screen
    /// that must not accumulate.
    @State private var caughtIsOpen = false
    /// The chip somebody tapped. A capture carries the id of the thing it
    /// filed, so the proof-of-catch is also the way back to it.
    @State private var openItem: FieldItemReference?
    @State private var savedItemID: String?
    private var completion: FieldCaptureCompletion? {
        let items = WEIntelligenceCapabilities.isPreview ? store.state.lifeItems : store.intelligenceEligibleLifeItems
        return FieldCaptureCompletion.match(store.captureDraft, titles: items.filter(\.isSharedPresence).map(\.title))
    }
    private func acceptCompletion() {
        guard let completion else { return }
        store.captureDraft = completion.text
    }

    var isWalkthrough = false
    var compact = false
    var onSaved: (String) -> Void = { _ in }
    var onRetrieved: (String) -> Void = { _ in }
    /// Called when what was typed was a question for WE rather than a thing
    /// to add — the caller closes the sheet so the answer is seen in Today.
    var onLookedUp: () -> Void = {}

    init(savedItemID: String? = nil, isWalkthrough: Bool = false, compact: Bool = false,
         onSaved: @escaping (String) -> Void = { _ in },
         onRetrieved: @escaping (String) -> Void = { _ in },
         onLookedUp: @escaping () -> Void = {}) {
        self.isWalkthrough = isWalkthrough
        self.compact = compact
        _savedItemID = State(initialValue: savedItemID)
        self.onSaved = onSaved
        self.onRetrieved = onRetrieved
        self.onLookedUp = onLookedUp
    }

    var body: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            if !isWalkthrough && !compact {
                Text("What is on your mind?")
                    .font(FieldType.pageHeadline)
                    .foregroundStyle(.fieldInk(.headline))
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }

            if !isWalkthrough || store.lastReceipt == nil {
                field(store: store)
            }

            if let error = store.captureSaveError ?? store.draftSaveError {
                Text(error).font(FieldType.body).foregroundStyle(.fieldInk(.headline))
                    .accessibilityIdentifier("field.capture.saveError")
            }

            if let receipt = store.lastReceipt {
                if store.correctingReceipt != nil {
                    correctionPicker
                        .padding(.top, 14)
                } else {
                    receiptCard(receipt)
                        .padding(.top, 14)
                }
            } else if let id = savedItemID, let item = store.state.lifeItems.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.canReportDelivery ? deliveryDescription(id) : "Saved in this example.")
                        .font(FieldType.body)
                    Button("Open in Life") {
                        store.go(to: .life)
                        openItem = FieldItemReference(id: item.id)
                        onRetrieved(item.id)
                    }
                    .buttonStyle(FieldFilledButtonStyle())
                    .accessibilityIdentifier("field.capture.retrieve")
                }
                .padding(.top, 20)
            } else if let revived = store.lastRevival {
                revivalNote(revived)
                    .padding(.top, 14)
            } else if !isWalkthrough && !compact {
                samplePhrases(store: store)
                    .padding(.top, 14)
            }

            if !isWalkthrough && !compact {
                caughtThisWeek
                    .padding(.top, FieldMetrics.sectionGap)
            }
        }
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
        }
        .animation(.fieldZone(reduceMotion), value: store.lastReceipt)
        .animation(.fieldZone(reduceMotion), value: store.lastRevival)
        .animation(.fieldZone(reduceMotion), value: store.correctingReceipt)
        .animation(.fieldZone(reduceMotion), value: caughtIsOpen)
        // The field is multi-line, so Return inserts a newline rather than
        // submitting — which left the keyboard with no way out at all. This is
        // the way out, and it is also the second place the thing can be filed.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button { isFocused = false } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                    .accessibilityLabel("Hide keyboard")
                    .accessibilityIdentifier("field.capture.dismiss")

                Spacer()

                if !store.captureDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    Button("Review") { submit() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("field.capture.submitKeyboard")
                }
            }
        }
    }

    private func saveReceipt() {
        savedItemID = store.lastReceipt?.id
        store.send()
        if store.lastReceipt == nil, let id = savedItemID { onSaved(id) }
    }

    private func deliveryDescription(_ id: String) -> String {
        switch store.deliveryState(for: id) {
        case .shared: "Saved and synced. Shared in Life."
        case .savedLocally: "Saved on this phone. Waiting to sync."
        case .needsAttention: "Saved on this phone. Open the item to retry syncing."
        }
    }

    // MARK: A group coming back
    //
    // The other half of the warning on the receipt. That one is in the future
    // tense and appears before Send; this is the past tense and appears after
    // it, so a word returning to Life is never something the couple has to
    // work out for themselves.
    //
    // Three words and no control. There is nothing to undo here — the item
    // they just filed is in the group, and putting it away again would file
    // that item under a heading nobody can see. The way back is the row at the
    // foot of Life, once the group is empty again.

    private func revivalNote(_ category: LifeCategory) -> some View {
        Text("\(category.word) is back.")
            .font(FieldType.receiptReasoning)
            .foregroundStyle(.fieldInk(.reasoning))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("field.receipt.revived")
            // Cleared by the view that shows it, because it is a sentence and
            // not a state: it has been read by the time the couple types the
            // next thing, and it must not still be there tomorrow morning.
            .task(id: category) {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                store.lastRevival = nil
            }
    }

    /// Classify, then step back. The receipt is the thing to read next, and it
    /// cannot be read from behind a keyboard.
    private func submit() {
        let text = store.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // "What did we get for dad?" is asked of WE, privately, and answered
        // with links in Today. Nothing is filed and nothing is shared. Never
        // in the walkthrough, which must not touch a real account.
        if !isWalkthrough, FieldLookupEngine.isLookup(text) {
            store.lookUp(text)
            store.captureDraft = ""
            isFocused = false
            onLookedUp()
            return
        }
        store.submitCapture()
        isFocused = false
    }

    // MARK: The writing paper

    private func field(store: FieldStore) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 20) {
            ZStack(alignment: .topLeading) {
                if store.captureDraft.isEmpty {
                    Text("A thought, a plan, something to remember…")
                        .font(FieldType.captureWriting)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $store.captureDraft)
                    .font(FieldType.captureWriting)
                    .lineSpacing(5)
                    .foregroundStyle(completion == nil ? FieldInk.headline.color(on: .cream) : Color.clear)
                    .tint(WECanvas.cream.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: compact ? 110 : 150, maxHeight: 220)
                    .focused($isFocused)
                    .accessibilityLabel("Say something")
                    .accessibilityIdentifier("field.capture.input")
                if let completion {
                    (Text(store.captureDraft).foregroundColor(FieldInk.headline.color(on: .cream)) +
                     Text(String(completion.text.dropFirst(store.captureDraft.count))).italic().foregroundColor(FieldInk.reasoning.color(on: .cream)))
                        .font(FieldType.captureWriting).lineSpacing(5)
                        .padding(.horizontal, 5).padding(.top, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityRespondsToUserInteraction(false)

            if let completion {
                Button(action: acceptCompletion) {
                    Text("Swipe right to accept · or tap")
                        .font(.caption).foregroundStyle(.fieldInk(.reasoning))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Accept completion: " + completion.text)
                    .accessibilityIdentifier("field.capture.completion")
                    .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                        if value.translation.width > 60 && abs(value.translation.height) < 40 { acceptCompletion() }
                    })
                DisclosureGroup("Why this?") { Text(completion.reason).font(.footnote) }
            }
            HStack(alignment: .center, spacing: 16) {
                Text("A little less to carry.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button { submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(WECanvas.cream.ink)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .disabled(store.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(store.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Review thought")
                .accessibilityIdentifier("field.capture.submit")
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(WECanvas.cream.ink.opacity(0.08), lineWidth: 0.5)
                .accessibilityHidden(true)
        }
        .shadow(color: WECanvas.cream.ink.opacity(0.06), radius: 20, x: 0, y: 8)
        .environment(\.weCanvas, .cream)
    }

    // MARK: The receipt
    //
    // ink .05 fill with a 2pt left border in the destination's colour.

    private func receiptCard(_ receipt: FieldReceipt) -> some View {
        let accent = store.identity.color(for: receipt.accent, on: .cream)

        return FieldCard(accent: accent) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text(receipt.wasCorrected ? "Move to" : "Save to")
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.headline))

                    Spacer()

                    Text(receipt.category.label)
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(accent)

                    // The way out. Nothing has been written yet, so leaving
                    // costs nothing and needs no confirmation — but until
                    // this existed the only ways past a receipt were to send
                    // it or to type over it, and neither is "no".
                    Button {
                        store.dismissReceipt()
                    } label: {
                        Text("✕")
                            .font(FieldType.subLabel)
                            .foregroundStyle(.fieldInk(.recessive))
                            // 44 square, which is the minimum a thumb is
                            // owed. The mark itself stays small — the target
                            // is what has to be generous, not the glyph.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.trailing, -12)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Never mind")
                    .accessibilityHint("Drops it without filing it")
                    .accessibilityIdentifier("field.receipt.dismiss")
                }

                // What is actually about to be filed, when that is not what
                // was typed. Shown before the reasoning, because a person who
                // said "reminder to call mom sunday" needs to see that it
                // became "Call mom, Sunday" *and* be able to disagree with it
                // — silently rewriting someone's words is the worst version
                // of this feature.
                if receipt.wasRephrased || receipt.dueOn != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(receipt.title)
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.headline))
                            .fixedSize(horizontal: false, vertical: true)

                        if let dueOn = receipt.dueOn {
                            Text(dayWord(dueOn).uppercased())
                                .font(FieldType.dateCount)
                                .tracking(FieldTracking.dateCount)
                                .foregroundStyle(.fieldInk(.dateCount))
                        }
                    }
                }

                if receipt.category.carriesDates {
                    HStack(spacing: 12) {
                        if receipt.dueOn != nil {
                            DatePicker("Date", selection: Binding(
                                get: { store.lastReceipt?.dueOn ?? store.now },
                                set: { store.lastReceipt?.dueOn = $0 }
                            ), displayedComponents: .date)
                            .font(FieldType.body)
                            .accessibilityIdentifier("field.receipt.date")
                        }
                        receiptTodayButton(receipt)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                DisclosureGroup("Why here?") {
                    Text(receipt.reasoning)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))

                // Said before the fact, in the future tense, because nothing
                // has happened yet — the group comes back on Send and not on
                // reading this. Correcting the destination below leaves it
                // exactly where they put it.
                //
                // Neither partner is named. Either of them may have set the
                // group down, and telling somebody they did something they did
                // not is worse than saying nothing about who did.
                if store.isPutAway(receipt.category) {
                    Text(
                        "\(receipt.category.word) is currently put away. "
                            + "Sending this will bring it back."
                    )
                    .font(FieldType.receiptReasoning)
                    .foregroundStyle(accent)
                    .fieldLineHeight(1.65, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("field.receipt.revival")
                }

                // Who will see it, said before it is saved, and changeable here.
                // Private is a property of the thing, not a separate room.
                privacyToggle(receipt)

                receiptActions
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var receiptActions: some View {
        VStack(spacing: 8) {
            Button { saveReceipt() } label: {
                Text(isWalkthrough ? "Save example" : "Save to Life")
                    .font(FieldType.button)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(WECanvas.cream.ink)
            .accessibilityIdentifier("field.receipt.send")
            .accessibilityHint(
                store.lastReceipt?.isPrivate == true ? "Saves this just for you" : "Saves this where both of you can see it"
            )

            Button("Change category") { store.beginCorrection() }
                .font(FieldType.button)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .foregroundStyle(.fieldInk(.legend))
                .accessibilityIdentifier("field.receipt.wrong")
        }
    }

    /// "Only me". A property of this one thing, chosen before it leaves the
    /// phone — not a place to go and not a mode to be in.
    ///
    /// Off by default, so filing stays what it has always been: shared. When
    /// it is on, the line says who will not see it, by name, because "private"
    /// on its own leaves somebody guessing from whom.
    private func privacyToggle(_ receipt: FieldReceipt) -> some View {
        Button {
            store.togglePrivate()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: receipt.isPrivate ? "lock.fill" : "lock.open")
                    .font(FieldType.subLabel)
                    .accessibilityHidden(true)
                Text(
                    receipt.isPrivate
                        ? "Only me. \(store.partnerName) won't see this."
                        : "Only me"
                )
                .font(FieldType.receiptReasoning)
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(
                receipt.isPrivate
                    ? .fieldInk(.headline)
                    : .fieldInk(.labelQuiet)
            )
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Only me")
        .accessibilityValue(receipt.isPrivate ? "On" : "Off")
        .accessibilityHint(
            receipt.isPrivate
                ? "\(store.partnerName) won't see this"
                : "Keeps this from \(store.partnerName)"
        )
        .accessibilityAddTraits(receipt.isPrivate ? .isSelected : [])
        .accessibilityIdentifier("field.receipt.private")
    }

    /// "Today", "Tomorrow", or the weekday. A date beside a one-line title
    /// should read the way the person said it, not as 3 Aug 2026.
    private func dayWord(_ date: Date) -> String {
        let calendar = Calendar.gregorianUS
        if calendar.isDate(date, inSameDayAs: store.now) { return "Today" }
        if let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: store.now)
        ), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return DateFormatter.fieldWeekday.string(from: date)
    }

    private func isForToday(_ receipt: FieldReceipt) -> Bool {
        guard let dueOn = receipt.dueOn else { return false }
        return Calendar.gregorianUS.isDate(dueOn, inSameDayAs: store.now)
    }

    private func receiptTodayButton(_ receipt: FieldReceipt) -> some View {
        let forToday = isForToday(receipt)
        return Button(forToday ? "Clear date" : "Today") {
            store.toggleForToday()
        }
        .buttonStyle(FieldQuietButtonStyle())
        .accessibilityIdentifier("field.receipt.today")
        .accessibilityHint(
            forToday ? "Takes the date back off" : "Puts it on today"
        )
    }

    /// One tap to a corrected destination. Not a picker wheel, not a sheet —
    /// the handoff is explicit that the correction is a single tap.
    ///
    /// Two things the first version left out. The app grows categories on its
    /// own and is deliberately shy about it, so "somewhere else entirely" has
    /// to be an option a person can name themselves — otherwise the only
    /// answer to a wrong heading is a differently wrong one. And opening this
    /// is not a commitment: "Never mind" puts the receipt back untouched.
    private var correctionPicker: some View {
        FieldCard(accent: FieldPalette.ink.opacity(0.22)) {
            FieldCategoryPicker(
                options: correctionOptions,
                choose: { store.correct(to: $0) },
                name: { store.correct(toNewCategory: $0) },
                cancel: { store.cancelCorrection() }
            )
        }
        // A new correction gets a new picker, so a half-typed heading from a
        // previous one is never sitting there waiting.
        .id(store.correctingReceipt?.id ?? "no-correction")
    }

    /// Every category that currently exists, including ones the app grew — a
    /// thing must be movable into one of those as easily as into a given one.
    private var correctionOptions: [LifeCategory] {
        guard let current = store.correctingReceipt?.category else {
            return store.correctionCategories
        }
        return store.correctionCategories.filter { $0 != current }
    }

    // MARK: What to say
    //
    // Read from this couple's week — a stretch someone is about to leave for,
    // a rhythm that has slipped, an occasion with nothing bought for it. The
    // four canned phrases remain only for a couple with nothing to read yet;
    // see `FieldCaptureSuggestions`. They disappear the moment a real receipt
    // exists.

    private func samplePhrases(store: FieldStore) -> some View {
        @Bindable var store = store

        return FieldFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(store.captureSuggestions, id: \.self) { phrase in
                Button {
                    store.captureDraft = phrase
                    submit()
                } label: {
                    Text(phrase)
                        .font(FieldType.button)
                        .foregroundStyle(.fieldInk(.label))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        // Keep the compact capsule while giving the button the
                        // full iOS touch target around it.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try: \(phrase)")
                // Addressable without knowing the words. The pills are read
                // from this couple's own week now, so no test can name one in
                // advance — which is the point of them.
                .accessibilityIdentifier("field.capture.suggestion")
            }
        }
    }

    // MARK: Caught this week

    /// Collapsed to its own label, which already carries the only number that
    /// matters. Opening it is a deliberate act — the count is the reassurance,
    /// and the chips are the proof you ask for when you doubt it.
    @ViewBuilder
    private var caughtThisWeek: some View {
        let caught = store.capturesThisWeek
        let count = caught.count

        if count > 0 {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    caughtIsOpen.toggle()
                } label: {
                    HStack(spacing: 8) {
                        FieldLabel("Caught this week · \(count)")

                        Text(caughtIsOpen ? "−" : "+")
                            .font(FieldType.subLabel)
                            .foregroundStyle(.fieldInk(.recessive))

                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Caught this week, \(count)")
                .accessibilityHint(caughtIsOpen ? "Collapses the list" : "Shows the list")
                .accessibilityIdentifier("field.caught.toggle")

                if caughtIsOpen {
                    FieldFlowLayout(spacing: 7, lineSpacing: 7) {
                        ForEach(caught) { capture in
                            chip(capture)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// The chip, and the way back to what it filed.
    ///
    /// A capture is stamped with the receipt's id, which is the id of the item
    /// that was filed — so the chip already knew where its thing lives and was
    /// simply refusing to say. Tapping opens that item where the category room
    /// and the calendar open it, which is the one surface that can answer
    /// "where did this go" and let you move it if the answer is wrong.
    ///
    /// Inert when the item is gone, which is now the rare case rather than the
    /// ordinary one: removing a filed thing takes its capture with it, so a
    /// dead chip is only a capture from before that was true, or one whose
    /// item left in the instant between a partner's delete and the reload. A
    /// chip that opens an empty sheet is worse than one that does nothing.
    @ViewBuilder
    private func chip(_ capture: FieldCapture) -> some View {
        let filed = store.state.lifeItems.contains { $0.id == capture.id }

        if filed {
            Button {
                openItem = FieldItemReference(id: capture.id)
            } label: {
                chipBody(capture)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens where it was filed")
            .accessibilityIdentifier("field.caught.chip")
        } else {
            chipBody(capture)
        }
    }

    private func chipBody(_ capture: FieldCapture) -> some View {
        HStack(spacing: 6) {
            FieldDot(
                owner: capture.owner,
                isPrivate: capture.visibility == .private,
                identity: store.identity,
                size: FieldDotSize.chip,
                baselineNudge: 0
            )

            Text(capture.text)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(.fieldInk(.legend))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            if capture.owner == .shared {
                Capsule().fill(store.identity.sharedChipTint)
            } else {
                Capsule().fill(store.identity.chipTint(for: capture.owner))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(capture.text), \(store.identity.name(for: capture.owner))"
        )
    }
}

// MARK: - A wrapping row
//
// The chips wrap. SwiftUI has no flow container, so this is the smallest one
// that behaves: it measures each subview at its ideal size and breaks the line
// when the next one would overflow.

struct FieldFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(
            width: maxWidth == .infinity ? x : maxWidth,
            height: y + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Finishing a word from a title already saved in shared Life. Three
/// letters first, and never a suffix that is not really there.
struct FieldCaptureCompletion: Equatable {
    let text: String
    let reason: String
    static func match(_ input: String, titles: [String]) -> Self? {
        guard input.count >= 3, input == input.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let matches = Set(titles).filter { $0.count <= 240 && $0.count > input.count && $0.lowercased().hasPrefix(input.lowercased()) }
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        guard let text = matches.first else { return nil }
        return .init(text: input + text.dropFirst(input.count), reason: "From a title already saved in your shared Life.")
    }
}
