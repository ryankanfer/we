//
//  FieldChatComposer.swift
//  WE
//
//  What the + opens: a card in the middle of the screen, over whatever you
//  were looking at.
//
//  It replaced a capture sheet with a receipt card, a correction picker and a
//  second, separate "Only me" link above the writing area, and then a sheet
//  from the bottom. Here there is only what a message needs — the words, a
//  link if there is one, who will see it, and send. Where the thing went,
//  and changing it, is WE's reply in the conversation, not a form to fill in
//  before it is allowed to leave.
//
//  A link is handed over, not typed around. The link button pastes whatever
//  was copied (through the system paste button, so there is no "allow
//  paste" prompt), and a link typed or pasted into the words is lifted out
//  the same way. The card reads it — title, site, picture — and says where
//  it will go before it goes. That read is on this phone; see
//  `FieldLinkReader`.
//
//  Who sees it is the app's own mark: two circles are the two of you, one
//  circle is you alone. "Us" is the default every time the card opens, and
//  the line under it names the partner, so nobody has to guess what "shared"
//  means. A question about what is already written down is a private
//  look-up whichever way the switch is set.
//

import SwiftUI

struct FieldChatComposer: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.weCanvas) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    @State private var text = ""
    @State private var justMe = false
    @State private var link: FieldLinkReader?

    /// Closes the card without sending.
    var onClose: () -> Void = {}
    /// Called after something is added or looked up, so the caller can show
    /// the conversation where it landed.
    var onSent: () -> Void = {}

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A link makes it something to keep, never a question to WE.
    private var isLookup: Bool { link == nil && FieldLookupEngine.isLookup(trimmed) }

    private var canSend: Bool { !trimmed.isEmpty || link != nil }

    /// What will be filed: the words, or the page's title when there are none.
    private var wordsToFile: String {
        trimmed.isEmpty ? (link?.fallbackWords ?? "") : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(link == nil ? "Say something…" : "Add a note, or send as is", text: $text, axis: .vertical)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(.fieldInk(.headline))
                .lineLimit(1...6)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .onChange(of: text) { _, new in liftLink(from: new) }
                .accessibilityIdentifier("field.composer.text")

            if let link {
                linkCard(link)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            }

            if let destination = destinationLine {
                Text(destination)
                    .font(.system(size: 12))
                    .foregroundStyle(.fieldInk(.legend))
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("field.composer.destination")
            }

            HStack(spacing: 10) {
                pasteLink
                audienceSwitch
                Spacer(minLength: 0)
                sendButton
            }

            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(.fieldInk(.legend))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(canvas.bgElevated, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    canvas.ink.opacity(justMe && !isLookup ? 0.35 : 0.1),
                    style: StrokeStyle(lineWidth: 1, dash: justMe && !isLookup ? [5, 4] : [])
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: link?.phase)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: link == nil)
        .onAppear { focused = true }
        .onDisappear { link?.cancel() }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    // MARK: The link

    private func linkCard(_ link: FieldLinkReader) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(canvas.ink.opacity(0.06))
                if let image = link.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if link.phase == .reading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "link").foregroundStyle(.fieldInk(.legend))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(link.phase == .reading ? "Reading…" : (link.title ?? link.site))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(link.phase == .reading ? .fieldInk(.legend) : .fieldInk(.headline))
                    .lineLimit(2)
                Text(link.site)
                    .font(.system(size: 12))
                    .foregroundStyle(.fieldInk(.legend))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                link.cancel()
                self.link = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.fieldInk(.legend))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove link")
        }
        .padding(10)
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(canvas.ink.opacity(0.12), lineWidth: 1) }
        .accessibilityIdentifier("field.composer.link")
    }

    /// The system paste button: no "allow paste" prompt, because the person
    /// pressing it is the permission.
    private var pasteLink: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let url = strings.lazy.compactMap(FieldLinkReader.firstLink(in:)).first else { return }
            Task { @MainActor in attach(url) }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(canvas.bgDeep)
        .foregroundStyle(.fieldInk(.headline))
        .accessibilityLabel("Paste a link")
        .accessibilityIdentifier("field.composer.paste")
    }

    /// A link typed or pasted into the words becomes the link card, and
    /// leaves the words.
    private func liftLink(from new: String) {
        guard link == nil, let url = FieldLinkReader.firstLink(in: new) else { return }
        let absolute = url.absoluteString
        if new.contains(absolute) {
            text = new.replacingOccurrences(of: absolute, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        attach(url)
    }

    private func attach(_ url: URL) {
        link?.cancel()
        let reader = FieldLinkReader(url: url)
        link = reader
        Task { await reader.read() }
    }

    private var destinationLine: String? {
        guard !isLookup, link?.phase != .reading,
              let category = store.previewDestination(for: wordsToFile, link: link?.url)
        else { return nil }
        return "Goes to \(category.word)"
    }

    // MARK: Who sees it, and send

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
                Text(justMe ? "Only me" : "Both of us")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.fieldInk(.headline))
            }
            .padding(.leading, 6)
            .padding(.trailing, 11)
            .frame(minHeight: 36)
            .overlay { Capsule().strokeBorder(canvas.ink.opacity(0.2), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLookup)
        .opacity(isLookup ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.2), value: justMe)
        .accessibilityLabel("Who can see this")
        .accessibilityValue(justMe ? "Only me" : "Both of us")
        .accessibilityHint("Switches between both of you and just you")
        .accessibilityIdentifier("field.composer.audience")
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canSend ? AnyShapeStyle(canvas.bgElevated) : AnyShapeStyle(.fieldInk(.legend)))
                .frame(width: 44, height: 44)
                .background(canSend ? canvas.ink : canvas.ink.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel(isLookup ? "Ask" : "Send")
        .accessibilityIdentifier("field.composer.send")
    }

    private var footnote: String {
        if isLookup { return "Asking WE. Only you see this." }
        return justMe
            ? "Only you and WE. \(store.partnerName) won't see this."
            : "\(store.partnerName) will see this."
    }

    private func send() {
        guard canSend else { return }

        if isLookup {
            store.lookUp(trimmed)
        } else {
            store.captureDraft = wordsToFile
            store.submitCapture()
            store.attachLink(link?.url)
            if justMe { store.togglePrivate() }
            store.send()
        }
        text = ""
        link = nil
        onSent()
    }
}

/// The + card and the dimmed screen behind it. Tapping outside closes it.
struct FieldComposerOverlay: View {
    @Binding var isPresented: Bool
    var onSent: () -> Void

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)

                FieldChatComposer(
                    onClose: { isPresented = false },
                    onSent: {
                        isPresented = false
                        onSent()
                    }
                )
                .padding(.horizontal, 16)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.18), value: isPresented)
    }
}
