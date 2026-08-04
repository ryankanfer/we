//
//  FieldCategoryPicker.swift
//  WE
//
//  "Where should it go?" — one control, two callers.
//
//  This was the correction picker inside `FieldCaptureField`, which is the
//  only place a destination could be changed: before a receipt was sent. Now
//  that a filed item can be moved too (`FieldItemSheet`), the same question is
//  asked in two places and there is no version of this the two should disagree
//  about — the tap target, the naming rules, and the sentence that comes back
//  when a name is refused are all part of one behaviour.
//
//  A row of chips, never a picker wheel and never a sheet: the handoff is
//  explicit that the correction is a single tap.
//

import SwiftUI

struct FieldCategoryPicker: View {
    /// The destinations to offer. A filed item's current destination stays in
    /// this set so the picker can answer "where is it now?" before asking the
    /// person to choose somewhere else.
    let options: [LifeCategory]
    /// A destination was tapped.
    let choose: (LifeCategory) -> Void
    /// A name was typed. Returns the category it became, or `nil` when the
    /// name is not a heading — the picker says so rather than substituting one.
    let name: (String) -> LifeCategory?
    /// Rendered as "Never mind" beside the title. Opening this is not a
    /// commitment to move anything.
    var cancel: (() -> Void)?
    var title = "Where should it go?"
    /// Present only when the picker describes an already-filed item. The
    /// current place is filled rather than removed from the list.
    var selected: LifeCategory?
    var selectedTint: Color?

    /// Naming rather than picking. Local, because nothing has been decided
    /// until it is committed and an abandoned half-typed word is not state the
    /// app should remember.
    @State private var isNaming = false
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var isNamingFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                FieldLabel(title, color: .fieldInk(.monoLabelQuiet))

                Spacer()

                if let cancel {
                    Button("Never mind") {
                        reset()
                        cancel()
                    }
                    .buttonStyle(FieldQuietButtonStyle())
                    .accessibilityIdentifier("field.receipt.cancelCorrection")
                }
            }

            if isNaming {
                namingField
            } else {
                FieldFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(options) { category in
                        FieldChip(
                            category.word,
                            isSelected: category == selected,
                            tint: category == selected ? selectedTint : nil
                        ) {
                            choose(category)
                        }
                        .accessibilityValue(
                            category == selected ? "Current location" : ""
                        )
                        .accessibilityHint(
                            category == selected
                                ? "Already filed here"
                                : "Moves it here"
                        )
                        .accessibilityIdentifier(
                            category == selected
                                ? "field.item.currentCategory"
                                : "field.correction.option"
                        )
                    }

                    FieldChip("+ NEW") {
                        draft = ""
                        error = nil
                        isNaming = true
                        isNamingFocused = true
                    }
                    .accessibilityLabel("Somewhere new")
                    .accessibilityIdentifier("field.correction.new")
                }
            }
        }
    }

    /// Naming one. A category is a word you can put above a list, so this is a
    /// single line and it refuses a sentence rather than truncating one.
    private var namingField: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                TextField("Name it", text: $draft)
                    .font(FieldType.captureInput)
                    .foregroundStyle(.fieldInk(.headline))
                    .tint(FieldIdentity.seed.personA.color)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNamingFocused)
                    .onSubmit { commit() }
                    .accessibilityLabel("New category name")
                    .accessibilityIdentifier("field.correction.newName")

                Button("File it") { commit() }
                    .buttonStyle(FieldFilledButtonStyle())
                    .disabled(
                        draft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                    .accessibilityIdentifier("field.correction.newCommit")
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(FieldPalette.ink.opacity(0.06))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )

            Text(
                error
                    ?? "One or two words. It becomes a list in Life, and I'll "
                    + "file this shape of thing there from now on."
            )
            .font(FieldType.receiptReasoning)
            .foregroundStyle(
                error == nil
                    ? .fieldInk(.reasoning)
                    : FieldIdentity.seed.personA.color
            )
            .fieldLineHeight(1.65, size: 13.5)
            .fixedSize(horizontal: false, vertical: true)

            Button("Back to the list") {
                isNaming = false
                isNamingFocused = false
                error = nil
            }
            .buttonStyle(FieldQuietButtonStyle())
            .accessibilityIdentifier("field.correction.newBack")
        }
    }

    /// Refused rather than mangled. `LifeCategory(named:)` already knows what a
    /// heading can be — three letters to eighteen, one or two words, never a
    /// reserved one — and the message says which rule was broken in the app's
    /// own voice rather than restating a validator.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard name(trimmed) != nil else {
            error = "That won't work as a heading — one or two words, and not "
                + "\"calendar\". Try the word you'd say out loud."
            return
        }
        reset()
    }

    private func reset() {
        isNaming = false
        isNamingFocused = false
        draft = ""
        error = nil
    }
}
