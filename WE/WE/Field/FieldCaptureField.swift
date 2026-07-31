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
    @Environment(FieldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var caretIsVisible = false

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
            } else {
                samplePhrases(store: store)
                    .padding(.top, 14)
            }

            caughtThisWeek
                .padding(.top, FieldMetrics.sectionGap)
        }
        .animation(.fieldZone(reduceMotion), value: store.lastReceipt)
        .animation(.fieldZone(reduceMotion), value: store.correctingReceipt)
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
                    Text("japan in the fall maybe")
                        .font(FieldType.captureInput)
                        .foregroundStyle(.fieldInk(.monoLabel))
                }

                TextField("", text: $store.captureDraft, axis: .vertical)
                    .font(FieldType.captureInput)
                    .foregroundStyle(.fieldInk(.headline))
                    .tint(store.identity.personA.color)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { store.submitCapture() }
                    .accessibilityLabel("Tell WE anything")
                    .accessibilityIdentifier("field.capture.input")
            }

            if store.captureDraft.isEmpty {
                caret
            } else {
                Button {
                    store.submitCapture()
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
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
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
        let destinationColor = receipt.accent == .shared
            ? store.identity.personB.color
            : accent

        return FieldCard(accent: accent) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    FieldLabel(
                        receipt.wasCorrected ? "Moved to" : "Filed to",
                        color: .fieldInk(.monoLabelQuiet)
                    )

                    Spacer()

                    Text(receipt.destination.label)
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(destinationColor)
                }

                Text(receipt.reasoning)
                    .font(FieldType.receiptReasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.65, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)

                // Send is the affirmative and carries the filled style,
                // because it is the moment the thing actually crosses into
                // the shared space. Correcting first costs nothing, which is
                // why it is the quiet one.
                HStack(spacing: 11) {
                    Button("Send") { store.send() }
                        .buttonStyle(FieldFilledButtonStyle())
                        .accessibilityIdentifier("field.receipt.send")
                        .accessibilityHint(
                            "Files it to \(receipt.destination.label)"
                        )

                    Button("Wrong place") { store.beginCorrection() }
                        .buttonStyle(FieldQuietButtonStyle())
                        .accessibilityIdentifier("field.receipt.wrong")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Filed to \(receipt.destination.label). \(receipt.reasoning)"
        )
    }

    /// One tap to a corrected destination. Not a picker wheel, not a sheet —
    /// the handoff is explicit that the correction is a single tap.
    private var correctionPicker: some View {
        FieldCard(accent: FieldPalette.ink.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 13) {
                FieldLabel("Where should it go?", color: .fieldInk(.monoLabelQuiet))

                FieldFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(correctionOptions, id: \.label) { destination in
                        Button {
                            store.correct(to: destination)
                        } label: {
                            Text(destination.label)
                                .font(FieldType.dateCount)
                                .tracking(FieldTracking.dateCount)
                                .foregroundStyle(.fieldInk(.legend))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .overlay {
                                    Capsule().stroke(
                                        FieldRule.secondaryButton,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var correctionOptions: [FieldDestination] {
        guard let current = store.correctingReceipt?.destination else {
            return FieldDestination.allCases
        }
        return FieldDestination.allCases.filter { $0.label != current.label }
    }

    // MARK: The demo affordance
    //
    // The four canonical inputs, which double as the classifier's few-shot
    // examples. They disappear the moment a real receipt exists.

    private func samplePhrases(store: FieldStore) -> some View {
        @Bindable var store = store

        return FieldFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(FieldSampleData.canonicalInputs, id: \.self) { phrase in
                Button {
                    store.captureDraft = phrase
                    store.submitCapture()
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try: \(phrase)")
            }
        }
    }

    // MARK: Caught this week

    private var caughtThisWeek: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel("Caught this week · \(store.state.captures.count)")

            FieldFlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(store.state.captures) { capture in
                    chip(capture)
                }
            }
        }
    }

    private func chip(_ capture: FieldCapture) -> some View {
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
