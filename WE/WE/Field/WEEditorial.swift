//
//  WEEditorial.swift
//  WE
//
//  The two components "Type Holds the Room" needs before any surface can be
//  converted: display type that sizes itself, and an action that is a sentence
//  rather than a rectangle.
//

import SwiftUI

// MARK: - Display type

/// A thought set at display scale, sized to the room it is given.
///
/// A hero is a hero because it owns the viewport, so its size cannot be a
/// constant: the same token has to set a two word horizon and a nine word one
/// without either wrapping into a wall. The width is measured and handed to
/// `WEDisplayScale`, which is where the curve lives.
struct WEDisplayText: View {
    enum Role {
        /// One per screen, and never more.
        case hero
        /// A major question or a secondary horizon.
        case majorQuestion
    }

    let text: String
    var role: Role = .hero
    var alignment: TextAlignment = .leading

    init(
        _ text: String,
        role: Role = .hero,
        alignment: TextAlignment = .leading
    ) {
        self.text = text
        self.role = role
        self.alignment = alignment
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Seeded to the reference device's text column so the first frame is
    /// already close, rather than snapping after layout.
    @State private var width: CGFloat =
        FieldMetrics.referenceDevice.width - FieldMetrics.usSide * 2

    private var size: CGFloat {
        switch role {
        case .hero:
            WEDisplayScale.hero(text, width: width, typeSize: typeSize)
        case .majorQuestion:
            WEDisplayScale.majorQuestion(text, width: width, typeSize: typeSize)
        }
    }

    var body: some View {
        Text(text)
            .font(
                role == .hero
                    ? FieldType.hero(size)
                    : FieldType.majorQuestion(size)
            )
            .foregroundStyle(.fieldInk(.headline))
            // Display line height is tight, but never so tight that ascenders
            // and descenders collide between lines.
            .fieldLineHeight(1.04, size: size)
            // Belt and braces under the width bound: an unbreakable string
            // longer than the arithmetic expects shrinks rather than clips.
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                alignment: alignment == .center ? .center : .leading
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WEDisplayWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
            .onPreferenceChange(WEDisplayWidthKey.self) { measured in
                if measured > 0, abs(measured - width) > 0.5 {
                    width = measured
                }
            }
    }
}

private struct WEDisplayWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

// MARK: - The editorial action

/// An action that reads as a sentence.
///
/// "Prefer plain text actions over filled rectangles." The boxed button was
/// doing two jobs — saying the word and drawing a target — and only the first
/// belongs on the page. The target is still forty four points; it is simply
/// no longer visible.
///
/// Selection is carried by ink weight *and* a colour trace, never by colour
/// alone: the rule under a chosen action is the only thing that changes shape.
struct WEEditorialAction: View {
    @Environment(\.weCanvas) private var canvas
    let title: String
    var isSelected = false
    /// The person whose choice this is, when the choice belongs to someone.
    var tint: Color?
    var action: () -> Void

    init(
        _ title: String,
        isSelected: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FieldType.listItemLarge)
                .foregroundStyle(
                    isSelected ? .fieldInk(.headline) : .fieldInk(.cardProse)
                )
                .padding(.vertical, 12)
                .frame(minHeight: 44, alignment: .leading)
                .overlay(alignment: .bottomLeading) { trace }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A hairline under every action, thickening and taking colour under the
    /// chosen one. Weight carries the state where colour is unavailable.
    private var trace: some View {
        Rectangle()
            .fill(
                isSelected
                    ? (tint ?? canvas.ink).opacity(0.85)
                    : FieldRule.row.color(on: canvas)
            )
            .frame(width: isSelected ? 34 : 18, height: isSelected ? 2 : 1)
    }
}
