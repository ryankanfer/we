// WE canvas roles. Practical reading uses warm cream; Today and Us remain
// dark, with warmer private and cooler reading variations. Every descendant
// resolves ink, pigment and separators against its declared canvas.

import SwiftUI

// MARK: - The ground, and its two deviations

enum WECanvas: String, CaseIterable, Sendable {
    /// Near-black, everywhere. Today, Life, Us, entry, and every surface that
    /// has not been given a reason to differ.
    ///
    /// Warm-shifted rather than neutral digital black: person hue at the
    /// bottom edge has to sit *on* the ground rather than fight it, and a warm
    /// rust glow against a neutral page reads as soot.
    case ground
    /// Practical reading surfaces use warm paper and dark ink.
    case cream

    /// The private room — Yours (14f). Warmer than the ground, and the warmth
    /// is the whole signal: this is the one surface with no strip, no mark,
    /// and nothing filed or learned. §4: "never indexed, never learned from,
    /// carries no mark."
    case room

    /// The Sunday read (16e). Cooler and deeper than the ground, because it is
    /// the only prose in the app and the only thing WE writes on its own.
    case page

    /// The page.
    var bg: Color {
        switch self {
        case .cream: Color(hex: 0xF0EBDD)
        case .ground: Color(hex: 0x0A0A09)
        case .room: Color(hex: 0x15100D)
        case .page: Color(hex: 0x100E0C)
        }
    }

    /// Sheets and overlays that sit *above* the page.
    ///
    /// One value across all three grounds, per §3: sheets sit on #17140F "so
    /// they read as a layer above the page." A sheet that took its elevation
    /// from whatever it happened to be covering would read as a layer above
    /// the room and a layer *below* the Sunday read.
    var bgElevated: Color { self == .cream ? Color(hex: 0xF8F4EA) : Color(hex: 0x17140F) }

    /// Below the page in perceived depth. Depth is a direction away from the
    /// page, and from a ground this near black there is very little room left
    /// — which is the honest answer, not a reason to invent one.
    var bgDeep: Color { self == .cream ? Color(hex: 0xE8E1D2) : Color(hex: 0x050505) }

    /// Primary text at full prominence.
    var ink: Color { self == .cream ? Color(hex: 0x241F19) : Color(hex: 0xF0EBDD) }

    /// The ink channel as raw components, so alpha ramps stay one source.
    var inkRGB: (r: Double, g: Double, b: Double) {
        if self == .cream { return (0.1411764706, 0.1215686275, 0.0980392157) }
        return (0.9411764706, 0.9215686275, 0.8666666667)
    }

    /// What a ramp step is worth on this ground.
    ///
    /// Kept as a method rather than collapsed into `step.rawValue` at the call
    /// sites. The cream canvas needed a solved table here because compositing
    /// toward a light ground loses contrast faster than toward a dark one;
    /// three near-black grounds do not, and the widest spread between them
    /// (#0A0A09 to #15100D) moves the worst step by well under a tenth of a
    /// ratio point. If a fourth ground ever arrives with a different problem,
    /// this is where it says so.
    func alpha(for step: FieldInk) -> Double {
        self == .cream ? 0.36 + 0.64 * step.rawValue : step.rawValue
    }

    /// The same, for hairlines. Rules are ink at a weight rather than a named
    /// role, so they pass straight through for the same reason.
    func ruleAlpha(_ weight: Double) -> Double { weight }
}

// MARK: - Declaring a canvas

extension EnvironmentValues {
    /// The ground the current subtree is standing on.
    ///
    /// `.ground` is the default because it is what almost every surface wants.
    /// A room or a page opts in; nothing opts in by accident.
    @Entry var weCanvas: WECanvas = .ground
}

extension View {
    /// Stand this subtree on a canvas: paint the ground and tell every
    /// descendant which ink it is drawing in.
    ///
    /// Both halves still matter, even now that the ink is common. The ground
    /// is what changes, and a surface that sets the environment without
    /// painting sits on whatever it was dropped onto.
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
    /// "Never slide one ground away to reveal another."
    ///
    /// A slide makes two grounds into two places and the move into travel.
    /// They are the same room under different light, so the only honest
    /// transition is the light changing.
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
