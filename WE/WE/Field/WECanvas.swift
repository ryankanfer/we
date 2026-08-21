//
//  WECanvas.swift
//  WE
//
//  Two canvases, one ink ramp.
//
//  `FieldPalette` described a single dark green page, so every surface that
//  wanted a colour reached for a global. The direction now asks for two
//  grounds with different meanings — warm ink dark for private and ceremonial
//  moments, warm cream for shared and resolved ones — and the shift between
//  them is supposed to be *felt*. A global cannot carry that, so the canvas
//  moved into the environment and a surface now declares which ground it is
//  standing on rather than naming a colour.
//
//  The fifteen-step ink ramp in `FieldTokens.swift` is unchanged and is not
//  duplicated here. A step is a *role* at a given prominence; what changes
//  between canvases is only which ink the role is drawn in. That is why
//  `.fieldInk(_:)` resolves through the environment instead of returning a
//  fixed colour: one ramp, two grounds, and no screen has to know which.
//

import SwiftUI

// MARK: - The two grounds

enum WECanvas: String, CaseIterable, Sendable {
    /// Warm ink black rather than neutral digital black. Today, Us, the
    /// Promise, pairing and arrival, stillness, private composition, and
    /// sensitive decisions.
    case dark

    /// Warm uncoated paper rather than bright white. Life, shared resolved
    /// material, archives, account and privacy documents, longer forms.
    ///
    /// Deliberately not beige: the wellness register is a real failure mode
    /// for a cream page, and the guard against it is a ground that stays
    /// close to paper while the *ink* carries the warmth.
    case cream

    /// The page.
    var bg: Color {
        switch self {
        case .dark: Color(hex: 0x16211D)
        case .cream: Color(hex: 0xF2ECE0)
        }
    }

    /// Sheets and overlays that sit *above* the page.
    var bgElevated: Color {
        switch self {
        case .dark: Color(hex: 0x1B2723)
        case .cream: Color(hex: 0xFAF6EE)
        }
    }

    /// Below the page in perceived depth, which is why the dark canvas goes
    /// darker and the cream one goes *deeper into the paper* rather than
    /// lighter. Depth is a direction away from the page, not toward white.
    var bgDeep: Color {
        switch self {
        case .dark: Color(hex: 0x101A17)
        case .cream: Color(hex: 0xE7DFD0)
        }
    }

    /// Primary text at full prominence.
    var ink: Color {
        switch self {
        case .dark: Color(hex: 0xE8E4D9)
        case .cream: Color(hex: 0x14100C)
        }
    }

    /// The ink channel as raw components, so alpha ramps stay one source.
    var inkRGB: (r: Double, g: Double, b: Double) {
        switch self {
        case .dark: (232.0 / 255, 228.0 / 255, 217.0 / 255)
        case .cream: (20.0 / 255, 16.0 / 255, 12.0 / 255)
        }
    }

    /// What a ramp step is actually worth on this ground.
    ///
    /// The ramp is fifteen *roles*, and the first cut of the cream canvas
    /// reused the dark canvas's alphas for all fifteen. Measured, every step
    /// below the headline lost contrast — `metadataProse` fell from 4.26:1 to
    /// 3.27:1 and `monoLabel` from 3.22:1 to 2.47:1 — because compositing
    /// toward a light ground loses contrast faster than compositing toward a
    /// dark one. It is not a question of picking a darker ink: pure black on
    /// this paper still reaches only about 86 percent of the dark canvas's
    /// contrast at the worst step.
    ///
    /// So cream carries its own alphas, solved per role to land on the dark
    /// canvas's measured ratio. A role means the same thing on both grounds,
    /// which is the point — and it could only mean the same thing if the
    /// number underneath it were allowed to differ.
    func alpha(for step: FieldInk) -> Double {
        switch self {
        case .dark:
            step.rawValue
        case .cream:
            switch step {
            case .headline: 0.907
            case .secondaryHeading: 0.795
            case .quietListItem: 0.751
            case .legend: 0.732
            case .cardProse: 0.705
            case .reasoning: 0.663
            case .sectionSubtitle: 0.611
            case .categorySummary: 0.586
            case .metadataProse: 0.570
            case .deemphasisedItem: 0.526
            case .monoLabel: 0.479
            case .monoLabelQuiet: 0.460
            case .dateCount: 0.429
            case .headerMeta: 0.397
            case .recessive: 0.375
            }
        }
    }

    /// The same solve, for hairlines. Rules are ink at a weight rather than a
    /// named role, so they scale by the ratio between the two grounds at the
    /// quiet end rather than by a table.
    func ruleAlpha(_ weight: Double) -> Double {
        self == .cream ? min(weight * 1.25, 1) : weight
    }

    /// The other one. Used by the crossfade and by contrast assertions that
    /// want to walk both grounds without hard-coding the pair.
    var opposite: WECanvas {
        self == .dark ? .cream : .dark
    }
}

// MARK: - Declaring a canvas

extension EnvironmentValues {
    /// The ground the current subtree is standing on.
    ///
    /// Dark is the default because it is what the app shipped and what every
    /// unconverted surface still assumes. A cream surface opts in; nothing
    /// opts in by accident.
    @Entry var weCanvas: WECanvas = .dark
}

extension View {
    /// Stand this subtree on a canvas: paint the ground and tell every
    /// descendant which ink it is drawing in.
    ///
    /// Both halves matter. Setting the environment without painting leaves
    /// cream ink on a dark page; painting without setting the environment
    /// leaves dark ink on a cream page. They are one decision, so they are
    /// one modifier.
    func weCanvas(_ canvas: WECanvas, ignoringSafeArea: Bool = true) -> some View {
        modifier(WECanvasModifier(canvas: canvas, ignoringSafeArea: ignoringSafeArea))
    }
}

private struct WECanvasModifier: ViewModifier {
    let canvas: WECanvas
    let ignoringSafeArea: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.weCanvas, canvas)
            .background {
                if ignoringSafeArea {
                    canvas.bg.ignoresSafeArea()
                } else {
                    canvas.bg
                }
            }
    }
}

// MARK: - Crossing between them

extension AnyTransition {
    /// "Never slide a dark page away to reveal a cream one."
    ///
    /// A slide makes the two grounds into two places and the move into
    /// travel. They are the same room under different light, so the only
    /// honest transition is the light changing.
    static var weCanvasCrossing: AnyTransition {
        .opacity
    }
}

extension Animation {
    /// The crossfade between grounds. Slow enough to read as light changing
    /// rather than as a screen being replaced.
    static var weCanvasCrossing: Animation {
        .easeInOut(duration: 0.55)
    }
}
