//
//  FieldCaptureField.swift
//  WE
//
//  "Tell WE anything" — the single input in the app. Option 5a.
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
    /// What the field says before this couple has said anything.
    ///
    /// An instruction, not an example. It names the one thing the field does
    /// and asks for nothing in particular, which is the only honest thing to
    /// say to somebody the app has never met.
    static let coldPlaceholder = "Anything. I'll work out where it goes."

    @Environment(FieldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var caretIsVisible = false
    /// Collapsed by default. The chips are a reassurance that nothing was
    /// dropped, not a list anybody works from — and Today is the one screen
    /// that must not accumulate.
    @State private var caughtIsOpen = false
    /// The chip somebody tapped. A capture carries the id of the thing it
    /// filed, so the proof-of-catch is also the way back to it.
    @State private var openItem: FieldItemReference?

    var body: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Tell WE anything")
                .padding(.top, 20)
                .padding(.bottom, 14)

            field(store: store)

            if let receipt = store.lastReceipt {
                if store.correctingReceipt != nil {
                    correctionPicker
                        .padding(.top, 14)
                } else {
                    receiptCard(receipt)
                        .padding(.top, 14)
                }
            } else if let revived = store.lastRevival {
                revivalNote(revived)
                    .padding(.top, 14)
            } else {
                samplePhrases(store: store)
                    .padding(.top, 14)
            }

            caughtThisWeek
                .padding(.top, FieldMetrics.sectionGap)
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
                Button("Done") { isFocused = false }
                    .accessibilityIdentifier("field.capture.dismiss")

                Spacer()

                if !store.captureDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    Button("File it") { submit() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("field.capture.submitKeyboard")
                }
            }
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
        store.submitCapture()
        isFocused = false
    }

    // MARK: The field
    //
    // 15pt vertical / 16pt horizontal padding, ink .06 fill, 1pt ink .16
    // border, 3pt radius. An 8pt blend dot, then the text, then a 1.5 × 19pt
    // caret pulsing at 1.4s.

    private func field(store: FieldStore) -> some View {
        @Bindable var store = store

        return HStack(alignment: .center, spacing: 11) {
            Circle()
                .fill(store.identity.blend())
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if store.captureDraft.isEmpty && !isFocused {
                    // The placeholder is a suggestion too, and the same one
                    // the first pill offers — the field demonstrates itself
                    // with something true about this week.
                    //
                    // Before there is a week to read, it falls back to an
                    // instruction rather than to the demo phrases. A
                    // placeholder cannot be tapped into the draft, so this is
                    // the one place a cold field can say what it is for
                    // without putting words in somebody's mouth.
                    Text(store.captureSuggestions.first ?? Self.coldPlaceholder)
                        .font(FieldType.captureInput)
                        .foregroundStyle(.fieldInk(.monoLabel))
                }

                TextField("", text: $store.captureDraft, axis: .vertical)
                    .font(FieldType.captureInput)
                    .foregroundStyle(.fieldInk(.headline))
                    .tint(store.identity.personA.color)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    .accessibilityLabel("Tell WE anything")
                    .accessibilityIdentifier("field.capture.input")
            }
            // Keep the broad focus affordance off the enclosing HStack. A tap
            // gesture on that ancestor wins hit testing over the trailing
            // submit Button, leaving "File it" visible to accessibility but
            // impossible to activate.
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            if store.captureDraft.isEmpty {
                caret
            } else {
                Button {
                    submit()
                } label: {
                    Text("→")
                        .font(.system(size: 17))
                        .foregroundStyle(.fieldInk(.legend))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("File it")
                .accessibilityIdentifier("field.capture.submit")
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 16)
        .background(FieldPalette.ink.opacity(0.06))
        .overlay {
            RoundedRectangle(
                cornerRadius: FieldMetrics.cardRadius,
                style: .continuous
            )
            .stroke(FieldRule.primary, lineWidth: 1)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: FieldMetrics.cardRadius,
                style: .continuous
            )
        )
    }

    private var caret: some View {
        Rectangle()
            .fill(FieldPalette.ink)
            .frame(width: 1.5, height: 19)
            .opacity(reduceMotion ? 0.7 : (caretIsVisible ? 1 : 0.15))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.4).repeatForever(
                        autoreverses: true
                    ),
                value: caretIsVisible
            )
            .onAppear { caretIsVisible = true }
            .accessibilityHidden(true)
    }

    // MARK: The receipt
    //
    // ink .05 fill with a 2pt left border in the destination's colour.

    private func receiptCard(_ receipt: FieldReceipt) -> some View {
        let accent = store.identity.color(for: receipt.accent)

        return FieldCard(accent: accent) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    FieldLabel(
                        receipt.wasCorrected ? "Moved to" : "Filed to",
                        color: .fieldInk(.monoLabelQuiet)
                    )

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

                Text(receipt.reasoning)
                    .font(FieldType.receiptReasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.65, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)

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

                // Send is the affirmative and carries the filled style,
                // because it is the moment the thing actually crosses into
                // the shared space. The other two cost nothing and change
                // nothing yet, which is why they are the quiet ones.
                HStack(spacing: 11) {
                    Button("Send") { store.send() }
                        .buttonStyle(FieldFilledButtonStyle())
                        .accessibilityIdentifier("field.receipt.send")
                        .accessibilityHint(
                            "Files it to \(receipt.category.label)"
                        )

                    // Only where a date is not a lie. The confirmation is the
                    // TODAY chip that appears above — the app shows what it is
                    // about to do rather than announcing that it did it.
                    if receipt.category.carriesDates {
                        Button(isForToday(receipt) ? "Not today" : "For today") {
                            store.toggleForToday()
                        }
                        .buttonStyle(FieldQuietButtonStyle())
                        .accessibilityIdentifier("field.receipt.today")
                        .accessibilityHint(
                            isForToday(receipt)
                                ? "Takes the date back off"
                                : "Puts it on today"
                        )
                    }

                    Button("Wrong place") { store.beginCorrection() }
                        .buttonStyle(FieldQuietButtonStyle())
                        .accessibilityIdentifier("field.receipt.wrong")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Filed to \(receipt.category.label). \(receipt.reasoning)"
        )
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
                        .tracking(FieldTracking.button)
                        .foregroundStyle(.fieldInk(.monoLabel))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .overlay {
                            Capsule().stroke(FieldRule.row, lineWidth: 1)
                        }
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

        VStack(alignment: .leading, spacing: 14) {
            Button {
                caughtIsOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    FieldLabel("Caught this week · \(count)")

                    if count > 0 {
                        Text(caughtIsOpen ? "−" : "+")
                            .font(FieldType.subLabel)
                            .foregroundStyle(.fieldInk(.recessive))
                    }

                    Spacer()
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
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
