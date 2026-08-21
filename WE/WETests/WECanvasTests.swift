import Foundation
import SwiftUI
import Testing
@testable import WE

/// The two canvases, held to the same standard as each other.
///
/// A second ground is the easiest place in a design system for contrast to
/// quietly rot: the dark canvas was measured when it was the only one, and
/// nothing about adding cream re-checks it. So every assertion here runs
/// across `WECanvas.allCases` rather than naming a canvas, which means a third
/// ground could not be added without being measured too.
struct WECanvasTests {

    // MARK: Colour maths
    //
    // Duplicated from `DesignTokenTests` deliberately. These are the reference
    // formulas from WCAG 2.1; a shared helper that drifted would take both
    // suites with it, and the suites are the thing that is supposed to catch
    // drift.

    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private static func contrast(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// A ramp step is ink at an alpha, so what actually reaches the eye is the
    /// composite against the page. Measuring the ink itself would score every
    /// step identically and prove nothing.
    private static func composite(
        _ step: FieldInk,
        on canvas: WECanvas
    ) -> (Double, Double, Double) {
        let ink = canvas.inkRGB
        let bg = components(canvas.bg)
        let a = canvas.alpha(for: step)
        return (
            ink.r * a + bg.0 * (1 - a),
            ink.g * a + bg.1 * (1 - a),
            ink.b * a + bg.2 * (1 - a)
        )
    }

    private static func components(_ color: Color) -> (Double, Double, Double) {
        let resolved = color.resolve(in: EnvironmentValues())
        return (
            Double(resolved.red),
            Double(resolved.green),
            Double(resolved.blue)
        )
    }

    private static let aa = 4.5
    private static let aaLarge = 3.0

    // MARK: The grounds

    /// Full-strength ink must clear AA on both grounds.
    ///
    /// This is the assertion that would have caught the cream canvas shipping
    /// with the dark canvas's near-white ink, which is not a contrast failure
    /// so much as an invisibility one.
    @Test func primaryInkClearsAAOnBothCanvases() {
        for canvas in WECanvas.allCases {
            let ratio = Self.contrast(
                Self.composite(.headline, on: canvas),
                Self.components(canvas.bg)
            )
            #expect(
                ratio >= Self.aa,
                "\(canvas.rawValue) headline ink scored \(ratio)"
            )
        }
    }

    /// The steps that carry running prose clear AA on both grounds.
    ///
    /// The line sits at `.sectionSubtitle` because that is where the ramp
    /// actually stops being body copy — below it are summaries, tracked mono
    /// labels, and right-aligned metadata, none of which is read in
    /// paragraphs. Pinning the assertion here rather than at the bottom of
    /// the ramp keeps it a real floor: it fails if anyone quietly reassigns a
    /// quiet step to a sentence.
    @Test func proseStepsClearAAOnBothCanvases() {
        let prose: [FieldInk] = [
            .headline, .secondaryHeading, .quietListItem, .legend,
            .cardProse, .reasoning, .sectionSubtitle,
        ]
        for canvas in WECanvas.allCases {
            for step in prose {
                let ratio = Self.contrast(
                    Self.composite(step, on: canvas),
                    Self.components(canvas.bg)
                )
                #expect(
                    ratio >= Self.aa,
                    "\(canvas.rawValue) \(step) scored \(ratio)"
                )
            }
        }
    }

    /// Adding a ground may not cost contrast anywhere.
    ///
    /// This is the assertion the cream canvas actually needed. The first cut
    /// reused the dark canvas's alphas and lost contrast at every step below
    /// the headline — `metadataProse` 4.26:1 to 3.27:1, `monoLabel` 3.22:1 to
    /// 2.47:1 — which no absolute threshold would have caught, because the
    /// dark ramp does not clear AA down there either. What was wrong was not
    /// the number, it was that the same role got quieter on the second
    /// ground while claiming to mean the same thing.
    ///
    /// The tolerance is one percent for rounding: the cream alphas are solved
    /// to four figures against these exact ratios.
    @Test func creamMatchesDarkAtEveryStep() {
        for step in FieldInk.allCases {
            let dark = Self.contrast(
                Self.composite(step, on: .dark),
                Self.components(WECanvas.dark.bg)
            )
            let cream = Self.contrast(
                Self.composite(step, on: .cream),
                Self.components(WECanvas.cream.bg)
            )
            #expect(
                cream >= dark * 0.99,
                "\(step): dark \(dark), cream \(cream)"
            )
        }
    }

    /// The ramp only means anything if it descends, on both grounds.
    @Test func theRampIsMonotonicOnBothCanvases() {
        for canvas in WECanvas.allCases {
            let ratios = FieldInk.allCases.map { step in
                Self.contrast(
                    Self.composite(step, on: canvas),
                    Self.components(canvas.bg)
                )
            }
            for (a, b) in zip(ratios, ratios.dropFirst()) {
                #expect(a > b, "\(canvas.rawValue) ramp went \(a) then \(b)")
            }
        }
    }

    /// Depth reads as a direction away from the page, in both directions.
    ///
    /// The dark canvas goes darker to recede and lighter to lift. Cream has to
    /// do the opposite on one of those and the same on neither, which is
    /// exactly the kind of thing that gets copied wrong from the dark values.
    @Test func depthOrderingHoldsOnBothCanvases() {
        for canvas in WECanvas.allCases {
            let page = Self.luminance(Self.components(canvas.bg))
            let lifted = Self.luminance(Self.components(canvas.bgElevated))
            let deep = Self.luminance(Self.components(canvas.bgDeep))

            switch canvas {
            case .dark:
                #expect(lifted > page)
                #expect(deep < page)
            case .cream:
                // Lifting a sheet off paper means catching more light;
                // receding means going further into the stock, not toward
                // white, which would read as a hole rather than as depth.
                #expect(lifted > page)
                #expect(deep < page)
            }
        }
    }

    /// The two grounds must actually be two grounds.
    @Test func theCanvasesAreFarApart() {
        let ratio = Self.contrast(
            Self.components(WECanvas.dark.bg),
            Self.components(WECanvas.cream.bg)
        )
        #expect(ratio >= 10, "the canvases scored \(ratio) against each other")
    }

    /// `opposite` is the crossfade's only way to name the other ground.
    @Test func oppositeRoundTrips() {
        for canvas in WECanvas.allCases {
            #expect(canvas.opposite.opposite == canvas)
            #expect(canvas.opposite != canvas)
        }
    }

    // MARK: Which zone stands where

    /// Life is the shared, resolved zone and takes the paper. Today and Us
    /// hold decisions that are still open, and those stay on the dark ground.
    @Test func zonesDeclareTheirCanvas() {
        #expect(FieldZone.life.canvas == .cream)
        #expect(FieldZone.we.canvas == .dark)
        #expect(FieldZone.us.canvas == .dark)
    }
}
