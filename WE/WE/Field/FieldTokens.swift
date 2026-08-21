//
//  FieldTokens.swift
//  WE
//
//  The design system from `design_handoff_we_app/README.md`.
//
//  This is a *separate* token set from DesignSystem.swift. That file describes
//  the cream canvas (#F4EFE5 ink on #17140F) the app shipped through July. The
//  handoff replaces it with a flat, matte, desaturated deep green and two
//  person colours. Both exist side by side only while the zones are migrated;
//  Field* is the destination.
//
//  Every hex, alpha, size, and letter-spacing below is quoted from the handoff
//  and is intended to be exact. `FieldPaletteTests` in WETests/FieldTests.swift
//  asserts the ones that carry meaning — the hexes, the contrast floor, the
//  monotonic ramp, and the depth ordering.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Palette

/// The dark canvas, by its old name.
///
/// This described the single page the app used to have. It now delegates to
/// `WECanvas.dark` rather than holding its own values: two constants for one
/// ground drift, and the drift shows up as a screen that is *nearly* the
/// right black, which is worse than either being wrong.
///
/// Surfaces that could be on either canvas should take `.fieldInk(_:)` or
/// `@Environment(\.weCanvas)` instead. What is left here is the places that
/// are genuinely dark by nature — the inverted button fill, the ceremonial
/// screens — plus the ones not yet converted.
enum FieldPalette {
    /// The app background. Warm ink black. Never a gradient fill.
    static var bg: Color { WECanvas.dark.bg }

    /// Sheets and overlays that sit *above* the page.
    static var bgElevated: Color { WECanvas.dark.bgElevated }

    /// The Reminders full-screen takeover — *below* the page in perceived
    /// depth, which is why it is darker rather than lighter.
    static var bgDeep: Color { WECanvas.dark.bgDeep }

    /// Primary text. A warm off-white. Also the inverted button fill.
    static var ink: Color { WECanvas.dark.ink }

    /// The ink channel as raw components, so alpha ramps stay one source.
    static var inkRGB: (r: Double, g: Double, b: Double) {
        WECanvas.dark.inkRGB
    }
}

// MARK: - The ink alpha ramp
//
// The handoff specifies fifteen steps in order of prominence. They are named
// for their *role*, not their value, so a screen never hard-codes an opacity.

// Declared on `ShapeStyle where Self == Color` rather than on `Color`, so the
// leading-dot form resolves inside `foregroundStyle` and `fill` — those take a
// generic `some ShapeStyle`, and implicit member lookup only reaches static
// members declared on the protocol. `Color.fieldInk(_:)` still works for the
// places that need a concrete Color.
extension ShapeStyle where Self == FieldInkStyle {
    static func fieldInk(_ step: FieldInk) -> FieldInkStyle {
        FieldInkStyle(step: step)
    }
}

/// A ramp step, resolved against whichever canvas the subtree is standing on.
///
/// This used to be a plain `Color`, which meant the ink was decided at the
/// call site and every one of the three hundred odd call sites silently
/// assumed the dark ground. Resolving in the environment instead means a
/// screen states its *role* — headline, reasoning, recessive — and the canvas
/// decides the colour, so moving a surface to cream is one modifier rather
/// than a sweep.
struct FieldInkStyle: ShapeStyle {
    let step: FieldInk

    func resolve(in environment: EnvironmentValues) -> Color {
        let canvas = environment.weCanvas
        return canvas.ink.opacity(canvas.alpha(for: step))
    }
}

extension FieldInk {
    /// The concrete colour, for the few places that genuinely cannot take a
    /// `ShapeStyle` — `tint`, gradient stops, `UIColor` bridging. Prefer
    /// `.fieldInk(_:)` everywhere else so the canvas stays in charge.
    func color(on canvas: WECanvas) -> Color {
        canvas.ink.opacity(canvas.alpha(for: self))
    }
}

enum FieldInk: Double, CaseIterable {
    /// Headlines, primary list items.
    case headline = 1.00
    /// Secondary headings.
    case secondaryHeading = 0.82
    /// List items in a de-emphasised group.
    case quietListItem = 0.75
    /// Legend / definition text.
    case legend = 0.72
    /// Supporting prose in a card.
    case cardProse = 0.68
    /// Reasoning — the "why this, now" voice.
    case reasoning = 0.62
    /// Section subtitles.
    case sectionSubtitle = 0.55
    /// Category summaries.
    case categorySummary = 0.52
    /// Quiet metadata prose.
    case metadataProse = 0.50
    /// De-emphasised list items.
    case deemphasisedItem = 0.45
    /// Mono section labels.
    case monoLabel = 0.40
    /// Mono labels, one step quieter.
    case monoLabelQuiet = 0.38
    /// Right-aligned dates and counts.
    case dateCount = 0.35
    /// Header-right metadata.
    case headerMeta = 0.32
    /// Home indicator, most recessive labels.
    case recessive = 0.30
}

// MARK: - Hairlines

/// Hairlines, as ink at a fixed weight.
///
/// These are ramp steps by another name — the same ink at a lower alpha — so
/// they resolve against the canvas exactly the way `.fieldInk(_:)` does. A
/// rule drawn in dark ink on the cream page is not a faint rule, it is an
/// invisible one, which is why these could not stay constants.
enum FieldRule {
    /// Section dividers, top/bottom of the synthesis block.
    static let primary = FieldRuleStyle(alpha: 0.16)
    /// Rule inside Us sections.
    static let us = FieldRuleStyle(alpha: 0.14)
    /// List-row divider.
    static let row = FieldRuleStyle(alpha: 0.13)
    /// List-row divider inside a tinted cluster card.
    static let rowInCluster = FieldRuleStyle(alpha: 0.11)
    /// Divider inside the "what I'm watching" list.
    static let watching = FieldRuleStyle(alpha: 0.09)
    /// Dashed border — the standing-rule card.
    static let dashed = FieldRuleStyle(alpha: 0.20)
    /// Secondary button border.
    static let secondaryButton = FieldRuleStyle(alpha: 0.25)
    /// The WE mark's ring.
    static let mark = FieldRuleStyle(alpha: 0.50)
}

struct FieldRuleStyle: ShapeStyle {
    let alpha: Double

    func resolve(in environment: EnvironmentValues) -> Color {
        let canvas = environment.weCanvas
        return canvas.ink.opacity(canvas.ruleAlpha(alpha))
    }

    /// For the places that need a concrete `Color` — gradient stops, borders
    /// taken as a value rather than applied as a style.
    func color(on canvas: WECanvas) -> Color {
        canvas.ink.opacity(canvas.ruleAlpha(alpha))
    }
}

// MARK: - Person colour
//
// The handoff requires these to be themeable: onboarding (6f) lets each
// partner pick from four palettes, and "every person-coloured element in the
// app derives from these two choices."

enum FieldPersonPalette: String, CaseIterable, Codable, Sendable {
    case warm
    case cool

    var swatches: [FieldSwatch] {
        switch self {
        case .warm:
            [.burgundy, .rose, .rust, .amber]
        case .cool:
            [.sage, .moss, .teal, .indigo]
        }
    }

    /// The first of each is the default — Ryan gets Clay, Dylan gets Slate.
    var defaultSwatch: FieldSwatch { swatches[0] }
}

/// Pigment: eight hue families, muted and complex rather than bright.
///
/// The old set was eight unrelated swatches at one value each, which meant a
/// colour that worked as edge light on the dark page was invisible as an
/// authorship mark on cream, and the reverse. Measuring that is what turned
/// deep and soft from a second row of swatches into a *role*: the same family
/// resolved for the ground it is standing on.
///
/// Deep and soft are therefore never offered as a choice. Asking somebody to
/// pick between two values of one hue is asking them to decide something they
/// cannot see the consequence of, and one of the two answers would always be
/// wrong on half the app. Sixteen colours exist; nobody is ever shown sixteen
/// swatches.
///
/// Every value here was solved rather than picked, and the gate is in
/// `WEPigmentTests`:
///
///   · soft clears 3:1 on warm ink black and deep clears 3:1 on warm cream,
///     worst case 4.07:1;
///   · every pair of families is at least CIEDE2000 12 apart, worst case
///     12.72, so two people's colours are never nearly the same colour;
///   · four of the twenty eight possible pairs produce a shared blend closer
///     than CIEDE2000 8 to one of its parents. Those are the pairs where
///     "yours, theirs, ours" would read as two colours rather than three, and
///     they are the reason the similar pair rule exists. See `blendIsMuddy`.
enum FieldSwatch: String, CaseIterable, Codable, Sendable, Identifiable {
    // Warm
    case burgundy
    case rose
    case rust
    case amber
    // Cool
    case sage
    case moss
    case teal
    case indigo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .burgundy: "Burgundy"
        case .rose: "Rose"
        case .rust: "Rust"
        case .amber: "Amber"
        case .sage: "Sage"
        case .moss: "Moss"
        case .teal: "Teal"
        case .indigo: "Indigo"
        }
    }

    /// Light coming from under the display edge, on the dark canvas.
    var soft: Color {
        switch self {
        case .burgundy: Color(hex: 0xB4576A)
        case .rose: Color(hex: 0xCF7A70)
        case .rust: Color(hex: 0xBE5A2E)
        case .amber: Color(hex: 0xD9A05B)
        case .sage: Color(hex: 0x8AA98B)
        case .moss: Color(hex: 0x6D8B4E)
        case .teal: Color(hex: 0x5E9A95)
        case .indigo: Color(hex: 0x7E8DBC)
        }
    }

    /// Ink on paper, on the cream canvas. A soft tone here is not a quiet
    /// mark, it is an illegible one.
    var deep: Color {
        switch self {
        case .burgundy: Color(hex: 0x7E2F42)
        case .rose: Color(hex: 0x9C4A45)
        case .rust: Color(hex: 0x8E4526)
        case .amber: Color(hex: 0x8A6220)
        case .sage: Color(hex: 0x4E6B52)
        case .moss: Color(hex: 0x47603A)
        case .teal: Color(hex: 0x2F6360)
        case .indigo: Color(hex: 0x474F80)
        }
    }

    func color(on canvas: WECanvas) -> Color {
        canvas == .cream ? deep : soft
    }

    /// The dark canvas value.
    ///
    /// Kept as a plain property because most of the app is dark and reads
    /// this in contexts that need a concrete `Color` — gradient stops, the
    /// colour field, `UIColor` bridging. A surface that can be on either
    /// ground should call `color(on:)` with the environment's canvas.
    var color: Color { soft }

    var palette: FieldPersonPalette {
        FieldPersonPalette.warm.swatches.contains(self) ? .warm : .cool
    }

    // MARK: Colours that used to exist

    /// Decoding a swatch that is no longer a swatch.
    ///
    /// `FieldSwatch` is `Codable` and persisted, so a removed case is not a
    /// refactor — it is a stored value somebody chose, on a device, that no
    /// longer parses. Clay was a lighter rust and slate a lighter indigo, so
    /// each retired colour lands in the family it was always a variation of
    /// rather than on a default nobody picked.
    ///
    /// Kept as data rather than folded into the initialiser so the mapping
    /// can be asserted directly, and so this and the SQL migration can be
    /// checked against each other.
    static let retired: [String: FieldSwatch] = [
        "clay": .rust,
        "slate": .indigo,
    ]

    /// A swatch as it came back from storage.
    ///
    /// The one door for a persisted string, and the reason it exists is that
    /// `init(rawValue:)` is *not* that door: it returns nil for a retired
    /// name, and every caller that reached for it had a `?? .something`
    /// fallback sitting behind it. That fallback silently turned an old clay
    /// into whatever the default happened to be, which is the migration
    /// failing quietly on the one path that matters — somebody who has been
    /// using the app since before the palette changed.
    ///
    /// Returns nil only for a string from neither the current set nor the
    /// retired one, so callers can still tell "corrupt" from "old".
    init?(stored raw: String) {
        if let known = FieldSwatch(rawValue: raw) {
            self = known
        } else if let moved = FieldSwatch.retired[raw] {
            self = moved
        } else {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // A value from neither the current set nor the retired one is a
        // corrupt record rather than an old one. Falling back beats throwing:
        // refusing to decode an identity would lock somebody out of their own
        // app over a colour.
        self = FieldSwatch(stored: raw) ?? .burgundy
    }

    // MARK: The similar pair rule

    /// Whether these two produce a shared atmosphere that reads as one of
    /// them rather than as a third thing.
    ///
    /// The lesson of the blend is the mechanism: two colours stay distinct
    /// and produce a third. Difference is the mechanism, not a problem to be
    /// resolved. A muddy blend breaks that, so WE offers nearby tonal
    /// variations — and it does so only *after both people commit*, to both
    /// of them at the same instant, revealing nothing about who chose what or
    /// when.
    static func blendIsMuddy(_ a: FieldSwatch, _ b: FieldSwatch) -> Bool {
        muddyPairs.contains(Set([a, b]))
    }

    /// Measured, not guessed. Every pair whose linear light blend sits closer
    /// than CIEDE2000 8 to either parent.
    private static let muddyPairs: Set<Set<FieldSwatch>> = [
        [.burgundy, .rose],
        [.rose, .rust],
        [.sage, .moss],
        [.sage, .teal],
    ]

    /// What to offer when a pair is too close, for one of the two people.
    ///
    /// Nearby rather than opposite: somebody who chose sage wanted a green,
    /// and answering a near collision by offering them burgundy is the app
    /// overruling a choice rather than helping with one.
    var neighbours: [FieldSwatch] {
        switch self {
        case .burgundy: [.rust, .amber]
        case .rose: [.amber, .burgundy]
        case .rust: [.amber, .burgundy]
        case .amber: [.rust, .rose]
        case .sage: [.indigo, .moss]
        case .moss: [.teal, .indigo]
        case .teal: [.indigo, .moss]
        case .indigo: [.teal, .sage]
        }
    }
}

/// Which of the two people — or both — an object belongs to.
///
/// This is the *only* thing person colour is ever allowed to encode. It marks
/// ownership, never volume, effort, or balance.
enum FieldOwner: String, Codable, Hashable, Sendable, CaseIterable {
    case a
    case b
    case shared
}

/// The two chosen swatches, resolved once and read everywhere.
struct FieldIdentity: Hashable, Codable, Sendable {
    var personA: FieldSwatch
    var personB: FieldSwatch
    var nameA: String
    var nameB: String

    // The three questions from 6f. Optional because every one is skippable —
    // a skipped question and an empty answer are different things, and the
    // whole cold start is meant to cost almost nothing.
    var livesTogether: Bool?
    var savingFor: String?
    var looksAfter: String?

    /// Burgundy and sage: the reference pair, and the seeded default.
    ///
    /// Not the only colours, and not a recommendation — they are the pair the
    /// system was measured against, and the one the design was drawn with.
    /// The clay and slate this replaced were the two colours the retired set
    /// happened to list first.
    static let seed = FieldIdentity(
        personA: .burgundy,
        personB: .sage,
        nameA: "Ryan",
        nameB: "Dylan"
    )

    func color(for owner: FieldOwner) -> Color {
        color(for: owner, on: .dark)
    }

    /// A person's colour, resolved for the ground it is drawn on.
    ///
    /// The soft tone is light coming from under a black edge and the deep one
    /// is ink on paper. Drawing an authorship dot on Life in the soft tone
    /// puts a pale mark on pale paper, which is not restraint — it is the
    /// mark being absent.
    func color(for owner: FieldOwner, on canvas: WECanvas) -> Color {
        switch owner {
        case .a: personA.color(on: canvas)
        case .b: personB.color(on: canvas)
        // Callers use `blend` for shared fills; this is the fallback for the
        // places that need a single colour and have nowhere to put a gradient.
        case .shared: personA.color(on: canvas)
        }
    }

    func name(for owner: FieldOwner) -> String {
        switch owner {
        case .a: nameA
        case .b: nameB
        case .shared: "\(nameA) and \(nameB)"
        }
    }

    // MARK: The blend
    //
    // "The gradient means *this belongs to both of you*. It must appear only
    // where something is genuinely shared. Its scarcity is what gives it
    // meaning."
    //
    // Permitted: the intelligence mark, a dot on a jointly-owned item, the
    // shared line in any Us visual, the nav indicator segment, and one hairline
    // under the Today header.
    //
    // Forbidden: as a page background, as a tint wash, or to indicate any
    // quantity, balance, or comparison between the partners.

    func blend(
        _ angle: FieldBlendAngle = .horizontal,
        on canvas: WECanvas = .dark
    ) -> LinearGradient {
        LinearGradient(
            colors: [personA.color(on: canvas), personB.color(on: canvas)],
            startPoint: angle.start,
            endPoint: angle.end
        )
    }

    /// The two-stop tint used behind a shared chip.
    var sharedChipTint: LinearGradient {
        LinearGradient(
            colors: [
                personA.color.opacity(0.12),
                personB.color.opacity(0.12),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func clusterTint(for owner: FieldOwner) -> Color {
        switch owner {
        case .a: personA.color.opacity(0.10)
        case .b: personB.color.opacity(0.09)
        case .shared: FieldPalette.ink.opacity(0.04)
        }
    }

    func clusterBorder(for owner: FieldOwner) -> Color {
        switch owner {
        case .a: personA.color
        case .b: personB.color
        case .shared: FieldPalette.ink.opacity(0.22)
        }
    }

    func chipTint(for owner: FieldOwner) -> Color {
        switch owner {
        case .a: personA.color.opacity(0.12)
        case .b: personB.color.opacity(0.12)
        case .shared: .clear
        }
    }
}

enum FieldBlendAngle {
    /// 90deg — lists, rules, the nav indicator.
    case horizontal
    /// 120deg — the onboarding preview block.
    case onboarding
    /// 135deg — larger square elements, the synthesis avatar.
    case square

    var start: UnitPoint {
        switch self {
        case .horizontal: .leading
        case .onboarding: UnitPoint(x: 0, y: 0.14)
        case .square: .topLeading
        }
    }

    var end: UnitPoint {
        switch self {
        case .horizontal: .trailing
        case .onboarding: UnitPoint(x: 1, y: 0.86)
        case .square: .bottomTrailing
        }
    }
}

// MARK: - Ambient accent
//
// "A single ambient accent *is* permitted … drifting warm in the morning and
// cool at night. It tracks the **hour**, never a person."

struct FieldAmbient: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var identity: FieldIdentity
    var hour: Int

    /// 0 at dawn, 1 at night. Interpolates warm to cool across the day.
    private var coolness: Double {
        let noon = 12.0
        let distance = abs(Double(hour) - noon) / noon
        return min(max(distance, 0), 1)
    }

    private var tint: Color {
        let warm = identity.personA.color
        let cool = identity.personB.color
        return coolness > 0.5 ? cool : warm
    }

    var body: some View {
        if reduceTransparency {
            Color.clear
        } else {
            RadialGradient(
                gradient: Gradient(colors: [
                    tint.opacity(0.13),
                    .clear,
                ]),
                center: UnitPoint(x: 0.88, y: 0.06),
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Typography
//
// Two families only. Newsreader carries all content; IBM Plex Mono carries
// labels, dates, counts, and buttons — always uppercase, always letter-spaced.
//
// The .ttf files live in Field/FONTS and are listed under UIAppFonts in
// WE-Info.plist. If either family fails to register, `FieldType` falls back to
// the system serif and the system monospaced face so the layout still reads.
// See Field/FONTS.md.

enum FieldType {
    // Newsreader ships as optical-size cuts, so there is no bare "Newsreader"
    // family to probe — 36pt is the one the display sizes use, and it standing
    // in for the pair is enough to know the bundle registered.
    static let serifFamily = "Newsreader 36pt"
    static let monoFamily = "IBM Plex Mono"

    private static let hasSerif: Bool = isAvailable(serifFamily)
    private static let hasMono: Bool = isAvailable(monoFamily)

    private static func isAvailable(_ family: String) -> Bool {
        #if canImport(UIKit)
        return !UIFont.fontNames(forFamilyName: family).isEmpty
        #else
        return false
        #endif
    }

    /// The text style a given point size scales *against*.
    ///
    /// Every face here used to be built with `fixedSize:`, which opts the
    /// whole Field surface out of Dynamic Type — the app rendered at exactly
    /// one size no matter what the person had set. That is the accessibility
    /// equivalent of ignoring the volume control.
    ///
    /// Sizes are still authored as absolute points, because the type ramp is
    /// a composition and "body plus two" is not a design decision anyone made.
    /// Anchoring each point size to the nearest style preserves the ramp's
    /// proportions while letting the whole thing move together.
    ///
    /// Display sizes anchor high on purpose: they are already clamped for
    /// accessibility sizes by `WEDisplayScale`, so the two systems meet rather
    /// than fight — the ramp scales the type, and the clamp keeps a hero
    /// thought from becoming a single word per line.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 34...: .largeTitle
        case 26..<34: .title
        case 20..<26: .title3
        case 17..<20: .body
        case 15..<17: .subheadline
        case 13..<15: .footnote
        default: .caption2
        }
    }

    // MARK: Newsreader

    private static func serif(
        _ size: CGFloat,
        _ weight: Font.Weight,
        italic: Bool = false
    ) -> Font {
        guard hasSerif else {
            let base = Font.system(size: size, weight: weight, design: .serif)
            return italic ? base.italic() : base
        }
        // Optical size, chosen the way the browser did when the handoff was
        // rendered: `font-optical-sizing: auto` tracks the point size, so the
        // display cuts stay thin at 42 and 44 and the text cut keeps its
        // sturdier fit down at label sizes.
        let opsz = size >= 20 ? "Newsreader36pt" : "Newsreader14pt"
        let face = switch (weight, italic) {
        case (.light, false): "\(opsz)-Light"
        case (.light, true): "\(opsz)-LightItalic"
        case (_, true): "\(opsz)-Italic"
        default: "\(opsz)-Regular"
        }
        return .custom(face, size: size, relativeTo: textStyle(for: size))
    }

    /// Hero statement on Today — 300 42/1.12, tracking -0.01em.
    static let hero = serif(42, .light)
    /// Page headline — 300 30–34/1.14–1.18.
    static let pageHeadline = serif(32, .light)
    /// The Us horizon. The largest type in the app — 300 44/1.06.
    ///
    /// Retained for surfaces not yet converted. "Type Holds the Room" makes 44
    /// the *floor* of the display range rather than the ceiling of the app;
    /// converted surfaces use `display(_:)` below.
    static let horizon = serif(44, .light)

    // MARK: The display range
    //
    // "One meaningful thought owns each viewport." The hero thought runs
    // roughly 64 to 92 points and the major question or horizon 48 to 64 —
    // starting ranges, not fixed values.
    //
    // Phase one ships the two roles Us needs. The rest of the ramp, and the
    // Dynamic Type conversion that lets these scale, land with the shared
    // system; until then these are `fixedSize` like every other role here, and
    // `WEDisplayScale` below is what keeps them from clipping.

    /// The hero thought. One per screen, and never more.
    static func hero(_ size: CGFloat = 76) -> Font { serif(size, .light) }

    /// A major question or horizon, one step below the hero.
    static func majorQuestion(_ size: CGFloat = 54) -> Font { serif(size, .light) }

    /// A Life category word — 300 38/1.
    static let categoryWord = serif(38, .light)
    /// The takeover cluster title — 300 40/1.1.
    static let clusterTitle = serif(40, .light)
    /// The season name — 300 38/1.1.
    static let seasonName = serif(38, .light)
    /// The synthesis sentence — 300 25/1.28.
    static let synthesis = serif(25, .light)
    /// Section title in a card — 400 18–21/1.2–1.35.
    static let cardTitle = serif(19, .regular)
    /// A list item — 400 15–16/1.35.
    static let listItem = serif(15.5, .regular)
    /// A prominent list item, Ours and the takeover — 400 18–21/1.25.
    static let listItemLarge = serif(18, .regular)
    /// The takeover's items — 400 21/1.25.
    static let takeoverItem = serif(21, .regular)
    /// Body / supporting — 400 13.5–15/1.6.
    static let body = serif(14.5, .regular)
    /// Reasoning — italic 400 12.5–13.5/1.6–1.65.
    static let reasoning = serif(13, .regular, italic: true)
    /// The receipt's reasoning — italic 400 13.5/1.65.
    static let receiptReasoning = serif(13.5, .regular, italic: true)
    /// Anchor quotes — italic 400 19/1.55.
    static let anchorQuote = serif(19, .regular, italic: true)
    /// The season narrative — 400 16.5/1.75.
    static let narrative = serif(16.5, .regular)
    /// A metric figure — 400 21–22/1.
    static let metric = serif(21.5, .regular)
    /// The capture field's own text — 400 17/1.3.
    static let captureInput = serif(17, .regular)
    /// The lock screen clock — 300 80/1.
    static let lockClock = serif(80, .light)
    /// The daily moment's statement — 400 20/1.35.
    static let momentStatement = serif(20, .regular)

    // MARK: IBM Plex Mono

    private static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        guard hasMono else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        let face = weight == .medium
            ? "IBMPlexMono-Medium"
            : "IBMPlexMono-Regular"
        return .custom(face, size: size, relativeTo: textStyle(for: size))
    }

    /// Zone label — LIFE / TODAY / US. 400 10, tracking 0.22em.
    static let zoneLabel = mono(10, .regular)
    /// Section label — 400 9.5, tracking 0.18em.
    static let sectionLabel = mono(9.5, .regular)
    /// Sub-label inside a card — 400 9, tracking 0.16em.
    static let subLabel = mono(9, .regular)
    /// Right-aligned date / count — 400 9.5–10, tracking 0.08–0.14em.
    static let dateCount = mono(9.75, .regular)
    /// A button label — 400 10.5–11.5, tracking 0.06–0.08em.
    static let button = mono(11, .regular)
    /// The WE mark's wordmark — 400 11, tracking 0.14em.
    static let mark = mono(11, .regular)
    /// The status bar clock — 500 13.5.
    static let statusClock = mono(13.5, .medium)
}

// MARK: - Responsive display sizing
//
// "Never shrink important text merely to avoid scrolling" — but a hero is a
// hero because it owns the viewport, and a forty character sentence set at
// seventy six points owns rather more than that. So the size is chosen from
// how much there is to say and how much room there is to say it in, which is
// what a typesetter would do and what a fixed point size cannot.

enum WEDisplayScale {
    /// The hero size for `text`, given the width it has to live in.
    ///
    /// Long strings step down rather than wrap into a wall. The floor is the
    /// old `FieldType.horizon` size, so nothing converted ever reads smaller
    /// than what it replaced.
    static func hero(
        _ text: String,
        width: CGFloat,
        typeSize: DynamicTypeSize
    ) -> CGFloat {
        size(text, width: width, typeSize: typeSize, ceiling: 88, floor: 44)
    }

    /// The same curve, one step down, for a question or a secondary horizon.
    static func majorQuestion(
        _ text: String,
        width: CGFloat,
        typeSize: DynamicTypeSize
    ) -> CGFloat {
        size(text, width: width, typeSize: typeSize, ceiling: 60, floor: 32)
    }

    private static func size(
        _ text: String,
        width: CGFloat,
        typeSize: DynamicTypeSize,
        ceiling: CGFloat,
        floor: CGFloat
    ) -> CGFloat {
        // The longest word cannot be broken, so it sets the hard upper bound:
        // Newsreader Light averages ~0.46em per character at display sizes.
        let longest = text
            .split(whereSeparator: \.isWhitespace)
            .map(\.count)
            .max() ?? 1
        let widthBound = width / (CGFloat(longest) * 0.46)

        // Total length sets the soft bound — three short lines beat six.
        let lengthBound: CGFloat = switch text.count {
        case ...14: ceiling
        case ...28: ceiling * 0.82
        case ...48: ceiling * 0.66
        default: ceiling * 0.52
        }

        // At accessibility sizes the theatrical scale gives way. Reading order
        // and the scroll are preserved; the drama is not.
        let accessibilityBound: CGFloat = typeSize.isAccessibilitySize
            ? ceiling * 0.5
            : ceiling

        // The floor guards against the length heuristic shrinking type that
        // had room to be large. It cannot guard against arithmetic: a word
        // that does not fit does not fit, so the width bound outranks it and
        // only a hard minimum sits below.
        let soft = max(floor, min(lengthBound, accessibilityBound))
        return max(28, min(soft, widthBound))
    }
}

// MARK: Letter-spacing
//
// SwiftUI takes tracking in points, not ems, so each em value is resolved
// against the size it is used at.

enum FieldTracking {
    static func em(_ value: CGFloat, at size: CGFloat) -> CGFloat {
        value * size
    }

    /// 0.22em at 10pt — zone labels and the nav.
    static let zoneLabel = em(0.22, at: 10)
    /// 0.18em at 9.5pt — section labels.
    static let sectionLabel = em(0.18, at: 9.5)
    /// 0.16em at 9pt — sub-labels.
    static let subLabel = em(0.16, at: 9)
    /// 0.14em at 9.5pt — dates, counts, the pull affordance.
    static let dateCount = em(0.14, at: 9.5)
    /// 0.08em at 11pt — button labels.
    static let button = em(0.08, at: 11)
    /// 0.14em at 11pt — the WE wordmark.
    static let mark = em(0.14, at: 11)
    /// -0.01em at 42pt — the Today hero only.
    static let hero = em(-0.01, at: 42)
}

// MARK: Line height
//
// SwiftUI's lineSpacing is the *gap* between lines, not the multiple, so a
// design line-height has to be converted against the point size.

extension View {
    func fieldLineHeight(_ multiple: CGFloat, size: CGFloat) -> some View {
        lineSpacing(max(0, size * multiple - size))
    }
}

// MARK: - Spacing, radius, shadow

enum FieldMetrics {
    /// The bottom value clears the nav bar.
    static let screenTop: CGFloat = 62
    static let screenSide: CGFloat = 30
    /// Clearance under a zone's content, so nothing ends up beneath the bar.
    ///
    /// The bar is type, so it grows when the person's type grows. A constant
    /// here was right at the default size and wrong at every other one: at
    /// the accessibility sizes the last row of each zone sat underneath the
    /// navigation, which is the one collision a fixed bottom bar can cause.
    static func screenBottom(at typeSize: DynamicTypeSize) -> CGFloat {
        switch typeSize {
        case .accessibility5: 216
        case .accessibility4: 196
        case .accessibility3: 176
        case .accessibility2: 156
        case .accessibility1: 140
        default: 112
        }
    }

    /// The default-size clearance, for the places that lay out without an
    /// environment to ask.
    static let screenBottom: CGFloat = 112

    /// Us runs slightly wider margins than the other two zones.
    static let usSide: CGFloat = 32
    /// The takeover runs narrower.
    static let takeoverSide: CGFloat = 26
    static let takeoverBottom: CGFloat = 30

    static let sectionGapLoose: CGFloat = 34
    static let sectionGap: CGFloat = 26
    static let sectionGapTight: CGFloat = 19
    static let cardGap: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let rowPaddingV: CGFloat = 13

    /// Near-square. A deliberate, precise look — do not round this up.
    static let cardRadius: CGFloat = 3
    static let sheetRadius: CGFloat = 22
    static let pillRadius: CGFloat = 999

    static let sheetShadow = (
        color: Color.black.opacity(0.42),
        radius: CGFloat(46),
        y: CGFloat(-20)
    )
    static let dropdownShadow = (
        color: Color.black.opacity(0.45),
        radius: CGFloat(50),
        y: CGFloat(22)
    )

    /// iPhone 15/16 logical size — the frame every screen was drawn against.
    static let referenceDevice = CGSize(width: 393, height: 852)

    /// The nav bar's occupied height, WE mark included.
    static let navBarHeight: CGFloat = 103
}

// MARK: - Dots
//
// "Solid dots identify a single owner … Always border-radius 50%, flex none,
// and nudged down ~6-8px to sit on the text baseline."

enum FieldDotSize {
    static let chip: CGFloat = 5
    static let inlinePair: CGFloat = 6
    static let list: CGFloat = 7
    static let prominentList: CGFloat = 8
    static let takeover: CGFloat = 9
}

struct FieldDot: View {
    @Environment(\.weCanvas) private var canvas
    var owner: FieldOwner
    var identity: FieldIdentity
    var size: CGFloat = FieldDotSize.list
    /// Nudge down to sit on the text baseline rather than the line box top.
    var baselineNudge: CGFloat = 7
    var opacity: Double = 1

    var body: some View {
        Group {
            if owner == .shared {
                Circle().fill(identity.blend(on: canvas))
            } else {
                Circle().fill(identity.color(for: owner, on: canvas))
            }
        }
        .frame(width: size, height: size)
        .opacity(opacity)
        .padding(.top, baselineNudge)
        .accessibilityHidden(true)
    }
}

/// One partner's choice of colour, as eight names rather than eight boxes.
///
/// This was two rows of four 58pt filled rectangles with a 2pt selection
/// border — a colour picker, which is the correct control for choosing a
/// colour and the wrong one for this. "Type Holds the Room" removes boxed
/// buttons and card framing, and a grid of swatches is both. It also made the
/// colour into the thing being chosen rather than the person: eight equal
/// blocks read as a palette, not as "anything of yours will be this".
///
/// So the families are set in the serif, at reading size, each carrying its
/// own colour as a trace beneath the word. Selection is weight and rule
/// width, never colour alone — the one state a person choosing a colour is
/// most likely to be unable to distinguish by hue is which colour is chosen.
///
/// Deep and soft do not appear. They are the same family resolved for the
/// canvas, and offering both would ask somebody to decide something they
/// cannot see the consequence of.
struct FieldSwatchRow: View {
    @Environment(\.weCanvas) private var canvas
    var owner: FieldOwner
    var identity: FieldIdentity
    /// Called with the tapped swatch. The caller persists.
    var choose: (FieldSwatch) -> Void

    /// Which eight to offer.
    ///
    /// All of them, to both people. The warm and cool split was a way of
    /// keeping two colours from being nearly the same colour, and Pigment
    /// does that by measurement instead — every pair is at least CIEDE2000 12
    /// apart. Halving somebody's choice to solve a problem that no longer
    /// exists is the system deciding for them.
    private var offered: [FieldSwatch] { FieldSwatch.allCases }

    var body: some View {
        let current = owner == .a ? identity.personA : identity.personB

        VStack(alignment: .leading, spacing: 18) {
            Text(identity.name(for: owner))
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .accessibilityAddTraits(.isHeader)

            // A flowing run rather than a grid. A grid of eight is a swatch
            // board however it is styled.
            FieldFlowLayout(spacing: 26, lineSpacing: 20) {
                ForEach(offered) { swatch in
                    WEEditorialAction(
                        swatch.name,
                        isSelected: swatch == current,
                        tint: swatch.color(on: canvas)
                    ) {
                        choose(swatch)
                    }
                    .accessibilityLabel(
                        swatch == current
                            ? "\(swatch.name), chosen"
                            : swatch.name
                    )
                    .accessibilityIdentifier("field.swatch.\(swatch.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.swatches.\(owner.rawValue)")
    }
}

struct FieldIntelligenceMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var identity: FieldIdentity
    var diameter: CGFloat = 14
    var period: Double = 7
    /// The 70pt ring drawn around the Today "nothing needs you" disc.
    var ringDiameter: CGFloat?

    var body: some View {
        ZStack {
            if let ringDiameter {
                Circle()
                    .strokeBorder(FieldRule.primary, lineWidth: 1)
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            Circle()
                .fill(identity.blend(.square))
                .frame(width: diameter, height: diameter)
                .opacity(reduceMotion ? 0.52 : (isBreathing ? 0.70 : 0.34))
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: period).repeatForever(
                            autoreverses: true
                        ),
                    value: isBreathing
                )
        }
        .onAppear { isBreathing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons
//
// "Every request the app makes offers a way to decline it." The three styles
// below are the full set: filled for the affirmative, outlined for the
// alternative, text-only for the escape.

struct FieldFilledButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FieldType.button)
            .tracking(FieldTracking.button)
            .textCase(.uppercase)
            .foregroundStyle(FieldPalette.bg)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(
                FieldPalette.ink,
                in: RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: configuration.isPressed
            )
    }
}

struct FieldOutlinedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Passed for the two person-tinted choices on a question toward Us.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FieldType.button)
            .tracking(FieldTracking.button)
            .textCase(.uppercase)
            .foregroundStyle(tint ?? FieldInk.legend.color(on: .dark))
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(
                (tint?.opacity(0.10) ?? .clear),
                in: RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
                .stroke(
                    tint?.opacity(0.55) ?? FieldRule.secondaryButton.color(on: .dark),
                    lineWidth: 1
                )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: configuration.isPressed
            )
    }
}

/// The escape. "Not yet," "Leave it," "Fine ✓".
struct FieldQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FieldType.button)
            .tracking(FieldTracking.button)
            .textCase(.uppercase)
            .foregroundStyle(.fieldInk(.monoLabel))
            .padding(.vertical, 13)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Recurring components

/// A tracked, uppercase mono label. The app's most repeated device.
struct FieldLabel: View {
    let text: String
    var font: Font = FieldType.sectionLabel
    var tracking: CGFloat = FieldTracking.sectionLabel
    // A ramp step rather than a colour. The eyebrow is on its way out, but a
    // component that is merely *retiring* still has to be legible on both
    // grounds: pinning it to the dark canvas turned every remaining label on
    // Life into cream ink on cream paper, which reads as a rendering bug
    // rather than as restraint.
    var ink: FieldInk = .monoLabel
    var isHeader = true

    init(
        _ text: String,
        font: Font = FieldType.sectionLabel,
        tracking: CGFloat = FieldTracking.sectionLabel,
        ink: FieldInk = .monoLabel,
        isHeader: Bool = true
    ) {
        self.text = text
        self.font = font
        self.tracking = tracking
        self.ink = ink
        self.isHeader = isHeader
    }

    var body: some View {
        Text(text.uppercased())
            .font(font)
            .tracking(tracking)
            .foregroundStyle(.fieldInk(ink))
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

/// A tracked mono word inside a hairline capsule.
///
/// The app's one small tappable token: the correction picker's destinations,
/// the item sheet's categories and days, and the two account actions on sign
/// in. Selected fills faintly rather than inverting — nothing at this size
/// earns the ink block a filled button gets.
struct FieldChip: View {
    let word: String
    var isSelected = false
    var tint: Color?
    var action: () -> Void

    init(
        _ word: String,
        isSelected: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.word = word
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(word)
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(
                    isSelected ? .fieldInk(.headline) : .fieldInk(.legend)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(
                            tint?.opacity(0.14)
                                ?? FieldPalette.ink.opacity(0.10)
                        )
                    }
                }
                .overlay {
                    Capsule().stroke(
                        isSelected
                            ? (tint ?? FieldPalette.ink).opacity(0.5)
                            : FieldRule.secondaryButton.color(on: .dark),
                        lineWidth: 1
                    )
                }
                // The capsule remains visually compact; the transparent frame
                // supplies Apple's 44pt minimum touch target.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The italic "why this, now" line, indented behind a person-coloured rule.
///
/// Almost every surface carries one. It is the mechanism by which the moat —
/// the intelligence — is made visible.
struct FieldReasoning: View {
    let text: String
    var accent: Color
    var font: Font = FieldType.reasoning

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.fieldInk(.reasoning))
            .fieldLineHeight(1.62, size: 13)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent.opacity(0.45))
                    .frame(width: 1)
            }
    }
}

/// A plain card. `rgba(232,228,217,.05)` at 3px radius, optionally with a 2px
/// person-coloured left border.
struct FieldCard<Content: View>: View {
    var accent: Color?
    var fill: Color = FieldPalette.ink.opacity(0.05)
    var dashed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FieldMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(alignment: .leading) {
                if let accent {
                    Rectangle().fill(accent).frame(width: 2)
                }
            }
            .overlay {
                if dashed {
                    RoundedRectangle(
                        cornerRadius: FieldMetrics.cardRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        FieldRule.dashed,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )
    }
}

// MARK: - Hex

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
