//
//  WELook.swift
//  WE
//
//  The pieces the whole app is drawn with now: two lights, glass, and type
//  that arrives. Small on purpose, so every screen reaches for the same
//  three things instead of inventing its own.
//

import SwiftUI

// MARK: - Glass

extension View {
    /// iOS 26 glass, in the app's shapes. On paper it frosts; on the dark
    /// ground it catches the two lights underneath. Reduce Transparency is
    /// honoured by the system glass itself.
    func weGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}

// MARK: - The two lights

/// Where the two people's lights sit. Every screen picks one; the lights
/// travel between poses, which is most of the app's motion.
enum WELightsPose: Equatable, Sendable {
    /// The app icon, exactly: two large lights overlapping in the middle.
    /// Only the splash uses it, so tapping the icon and the app opening
    /// read as one continuous move.
    case icon
    /// Far apart at the bottom corners. Before anything has happened.
    case apart
    /// Drawn toward each other. The resting state of a shared screen.
    case near
    /// Close, rising a little. Something was just added.
    case lifted
    /// One light only: yours. Only me.
    case alone
    /// One warm light in the middle. Agreement.
    case merged
    /// Spread wide and low, for long reading surfaces like Life.
    case wide
    /// Leaning toward each other without touching. One of you has said yes
    /// and the other has not answered yet.
    case leaning
    /// Their light going out. Only for the screen after a partner leaves.
    case parting

    fileprivate var a: UnitPoint {
        switch self {
        case .icon: UnitPoint(x: 0.38, y: 0.54)
        case .apart: UnitPoint(x: 0.12, y: 1.06)
        case .near: UnitPoint(x: 0.34, y: 1.04)
        case .lifted: UnitPoint(x: 0.42, y: 0.94)
        case .alone: UnitPoint(x: 0.5, y: 1.02)
        case .merged: UnitPoint(x: 0.5, y: 0.78)
        case .wide: UnitPoint(x: 0.08, y: 1.1)
        case .leaning: UnitPoint(x: 0.4, y: 1.0)
        case .parting: UnitPoint(x: 0.34, y: 1.04)
        }
    }

    fileprivate var b: UnitPoint {
        switch self {
        case .icon: UnitPoint(x: 0.62, y: 0.52)
        case .apart: UnitPoint(x: 0.88, y: 1.06)
        case .near: UnitPoint(x: 0.66, y: 1.04)
        case .lifted: UnitPoint(x: 0.58, y: 0.96)
        case .alone: UnitPoint(x: 0.62, y: 1.08)
        case .merged: UnitPoint(x: 0.5, y: 0.78)
        case .wide: UnitPoint(x: 0.92, y: 1.1)
        case .leaning: UnitPoint(x: 0.6, y: 1.0)
        case .parting: UnitPoint(x: 0.7, y: 1.12)
        }
    }

    fileprivate var scale: CGFloat {
        switch self {
        case .merged: 1.35
        case .icon: 1.25
        case .lifted: 1.1
        case .wide: 0.9
        default: 1
        }
    }

    fileprivate var showsB: Bool { self != .alone && self != .parting }
}

/// Two soft lights in the two people's colours, at the bottom of the screen.
///
/// The grammar, everywhere in the app: `personA` is the viewer's own light,
/// `personB` is their partner's, and the overlap is what they share. The
/// lights only ever react to something that happened between the two of
/// them. They never measure, compare, or keep score.
///
/// THE SENTENCE TEST. Every behaviour of these lights must be captionable
/// as one sentence about the relationship: "Dylan is here." "This is only
/// yours." "You decided together." If a movement cannot be captioned that
/// way it is decoration, and it does not ship. That is why they do not
/// idly breathe, and why Today and Life share one resting pose.
///
/// On the dark ground they are light coming up from below the glass. On
/// paper the same colours soak in like ink, multiplied rather than added,
/// which is the argument `WelcomeBloom` already makes.
struct WELights: View {
    var identity: FieldIdentity
    var pose: WELightsPose
    /// Both lights swell once. Something new landed in Life.
    var pulse: Int = 0
    /// Only your light swells. Something is waiting for you.
    var pulseMine: Int = 0
    /// Only their light swells. They were just here.
    var pulseTheirs: Int = 0
    /// The two lights meet in the middle for a moment, then settle back.
    /// Kept for agreement: the one time they fully overlap.
    var merge: Int = 0
    /// Draws a faint ring where their light will be, before they exist.
    var showsTheirPlace: Bool = false

    @Environment(\.weCanvas) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var swell = false
    @State private var swellMine = false
    @State private var swellTheirs = false
    @State private var merging = false

    private var strength: Double { canvas.isDark ? 0.62 : 0.34 }
    private var shown: WELightsPose { merging ? .merged : pose }

    var body: some View {
        if reduceTransparency {
            Color.clear.allowsHitTesting(false)
        } else {
            GeometryReader { proxy in
                let size = proxy.size.width * 1.35
                ZStack {
                    if showsTheirPlace && !shown.showsB {
                        Circle()
                            .strokeBorder(
                                identity.personB.color(on: canvas).opacity(0.35),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                            )
                            .frame(width: 120, height: 120)
                            .position(
                                x: proxy.size.width * WELightsPose.near.b.x,
                                y: proxy.size.height * 0.88
                            )
                            .transition(.opacity)
                    }
                    light(identity.personA, at: shown.a, in: proxy.size, size: size)
                        .scaleEffect(swellMine ? 1.18 : 1, anchor: .bottom)
                    light(identity.personB, at: shown.b, in: proxy.size, size: size)
                        .scaleEffect(swellTheirs ? 1.18 : 1, anchor: .bottom)
                        .opacity(shown.showsB ? 1 : 0)
                }
                .scaleEffect(swell ? 1.12 : 1, anchor: .bottom)
                .blendMode(canvas.isDark ? .normal : .multiply)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(
                reduceMotion ? nil
                    : pose == .parting ? .easeInOut(duration: 3.2)
                    : .spring(response: 1.3, dampingFraction: 0.85),
                value: shown
            )
            .onChange(of: pulse) { _, _ in
                swellOnce { swell = $0 }
            }
            .onChange(of: pulseMine) { _, _ in
                swellOnce { swellMine = $0 }
            }
            .onChange(of: pulseTheirs) { _, _ in
                swellOnce { swellTheirs = $0 }
            }
            .onChange(of: merge) { _, _ in
                guard !reduceMotion else { return }
                merging = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { merging = false }
            }
            .accessibilityHidden(true)
        }
    }

    /// Up quickly, down slowly. A breath in, not a flash.
    private func swellOnce(_ set: @escaping (Bool) -> Void) {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { set(true) }
        withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.35)) { set(false) }
    }

    private func light(_ swatch: FieldSwatch, at point: UnitPoint, in bounds: CGSize, size: CGFloat) -> some View {
        let tint = swatch.color(on: canvas)
        return Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(strength), tint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size * shown.scale, height: size * shown.scale)
            .blur(radius: 40)
            .position(x: bounds.width * point.x, y: bounds.height * point.y)
    }
}

// MARK: - Type that arrives

/// A headline that arrives a word at a time, each word lifting out of a
/// blur. Plays when it appears and whenever the text changes. VoiceOver
/// reads it as one sentence, straight away.
struct WEWordReveal: View {
    let text: String
    var font: Font = FieldType.hero
    var tracking: CGFloat = -0.4
    var lineSpacing: CGFloat = 2
    var alignment: HorizontalAlignment = .leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var words: [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    var body: some View {
        WEFlowLayout(spacing: 0, lineSpacing: lineSpacing, alignment: alignment) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word + (index < words.count - 1 ? " " : ""))
                    .font(font)
                    .tracking(tracking)
                    .opacity(shown || reduceMotion ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 10)
                    .blur(radius: shown || reduceMotion ? 0 : 6)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.9)
                            .delay(Double(index) * 0.07 + 0.08),
                        value: shown
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { shown = true }
        .onChange(of: text) { _, _ in
            shown = false
            DispatchQueue.main.async { shown = true }
        }
    }
}

/// Words laid out in lines, wrapping at the proposed width.
struct WEFlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height)),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty,
               rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Arrival

extension View {
    /// Fades and lifts in once, after a delay. For the second and third
    /// things on a screen, after its headline has started to arrive.
    func weArrival(delay: Double = 0.2) -> some View {
        modifier(WEArrival(delay: delay))
    }
}

private struct WEArrival: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.9).delay(delay)) {
                    shown = true
                }
            }
    }
}

// MARK: - The coach

extension View {
    /// A soft ring that breathes around the one control a screen is waiting
    /// on. Only while `active`; gone the moment it has been used.
    func weCoach(_ active: Bool, tint: Color) -> some View {
        modifier(WECoach(active: active, tint: tint))
    }
}

private struct WECoach: ViewModifier {
    let active: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring = false

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.35))
                            .blur(radius: 10)
                            .scaleEffect(ring ? 1.5 : 1.15)
                        Circle()
                            .strokeBorder(tint, lineWidth: 2)
                            .scaleEffect(ring ? 1.45 : 1.05)
                            .opacity(ring ? 0 : 1)
                    }
                    .onAppear {
                        guard !reduceMotion else { return }
                        ring = false
                        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { ring = true }
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - The lights, as a legend

/// The two lights at text size, so a row can say who something belongs to
/// in the same language the screen does. Always captionable: the
/// accessibility label is the sentence.
struct WELightsMark: View {
    enum Reading: Equatable {
        /// "You're both in."
        case together
        /// "One of you said yes."
        case leaning
        /// "Shared, not decided yet."
        case apart
        /// "Only yours."
        case mine
        /// "Theirs."
        case theirs
    }

    /// Viewer oriented: `personA` is the reader's own light.
    var identity: FieldIdentity
    var reading: Reading
    var size: CGFloat = 12

    @Environment(\.weCanvas) private var canvas

    private var gap: CGFloat {
        switch reading {
        case .together: size * 0.45
        case .leaning: size * 1.05
        case .apart: size * 1.6
        case .mine, .theirs: 0
        }
    }

    var body: some View {
        let mine = identity.personA.color(on: canvas)
        let theirs = identity.personB.color(on: canvas)
        ZStack {
            switch reading {
            case .mine:
                Circle().fill(mine).frame(width: size, height: size)
            case .theirs:
                Circle().fill(theirs).frame(width: size, height: size)
            default:
                Circle().fill(mine).frame(width: size, height: size).offset(x: -gap / 2)
                Circle().fill(theirs).frame(width: size, height: size).offset(x: gap / 2)
                    .blendMode(canvas.isDark ? .screen : .multiply)
            }
        }
        .frame(width: size + size * 1.6, height: size)
        .accessibilityElement()
        .accessibilityLabel(sentence)
    }

    private var sentence: String {
        switch reading {
        case .together: "Shared. You're both in."
        case .leaning: "Shared. One of you has said yes."
        case .apart: "Shared, not decided yet."
        case .mine: "Only yours."
        case .theirs: "\(identity.nameB)'s."
        }
    }
}
