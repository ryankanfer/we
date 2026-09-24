//
//  FieldChatComposer.swift
//  WE
//
//  What the + opens: one line in the day's conversation.
//
//  It replaced a capture sheet with a receipt card, a correction picker and a
//  second, separate "Only Me" link above the writing area. Here there is only
//  what a message needs — the words, who will see them, and send. Where the
//  thing went, and changing it, is WE's reply in the conversation, not a form
//  to fill in before it is allowed to leave.
//
//  Who sees it is the app's own mark: two circles are the two of you, one
//  circle is you alone. "Us" is the default every time the sheet opens, and
//  the line under it names the partner, so nobody has to guess what "shared"
//  means. A question about what is already written down is a private
//  look-up whichever way the switch is set.
//

import SwiftUI

struct FieldChatComposer: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weCanvas) private var canvas
    @FocusState private var focused: Bool

    @State private var text = ""
    @State private var justMe = false

    /// Called after something is added or looked up, so the caller can show
    /// the conversation where it landed.
    var onSent: () -> Void = {}

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLookup: Bool { FieldLookupEngine.isLookup(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Say something…", text: $text, axis: .vertical)
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(.fieldInk(.headline))
                    .lineLimit(1...6)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(canvas.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        if justMe && !isLookup {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(canvas.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    .accessibilityIdentifier("field.composer.text")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(trimmed.isEmpty ? .fieldInk(.legend) : .fieldInk(.headline))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .accessibilityLabel(isLookup ? "Ask" : "Send")
                .accessibilityIdentifier("field.composer.send")
            }

            HStack(spacing: 10) {
                audienceSwitch
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(.fieldInk(.legend))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, FieldMetrics.screenSide)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .onAppear { focused = true }
    }

    /// Two circles, or one. Tapping switches.
    private var audienceSwitch: some View {
        Button {
            justMe.toggle()
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .strokeBorder(store.identity.color(for: store.speaker), lineWidth: 1.4)
                        .frame(width: 16, height: 16)
                        .offset(x: justMe ? 0 : -5)
                    if !justMe {
                        Circle()
                            .strokeBorder(store.identity.color(for: store.speaker == .a ? .b : .a), lineWidth: 1.4)
                            .frame(width: 16, height: 16)
                            .offset(x: 5)
                    }
                }
                .frame(width: 28, height: 18)
                Text(justMe ? "Just me" : "Us")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.fieldInk(.headline))
            }
            .padding(.leading, 6)
            .padding(.trailing, 11)
            .frame(minHeight: 32)
            .overlay { Capsule().strokeBorder(canvas.ink.opacity(0.2), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLookup)
        .opacity(isLookup ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.2), value: justMe)
        .accessibilityLabel("Who can see this")
        .accessibilityValue(justMe ? "Just me" : "Both of us")
        .accessibilityHint("Switches between both of you and just you")
        .accessibilityIdentifier("field.composer.audience")
    }

    private var footnote: String {
        if isLookup { return "Asking WE. Only you see this." }
        return justMe
            ? "Only you and WE. \(store.partnerName) won't see this."
            : "\(store.partnerName) will see this."
    }

    private func send() {
        let words = trimmed
        guard !words.isEmpty else { return }

        if isLookup {
            store.lookUp(words)
        } else {
            store.captureDraft = words
            store.submitCapture()
            if justMe { store.togglePrivate() }
            store.send()
        }
        text = ""
        onSent()
        dismiss()
    }
}
