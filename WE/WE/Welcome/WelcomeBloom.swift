//
//  WelcomeBloom.swift
//  WE
//
//  The mark, as light.
//
//  `WELens` draws the two circles as hairlines and fills their intersection.
//  This draws the same two circles as soft warm discs and lets the intersection
//  brighten *itself* — the discs composite with `.plusLighter`, so the overlap
//  is luminous because both are there, which is the whole argument of the mark
//  and the app. Nothing paints the hot core directly.
//
//  Geometry comes from `WELens.centreOffsets` and `WELens.circleRadius` rather
//  than from screen percentages, so the bloom and the mark can never drift.
//
//  On the token doctrine: `FieldTokens` says `FieldPalette.bg` is never a
//  gradient fill, and the A→B blend is never a page wash. Neither is happening
//  here. This is a bounded hero element in the top third of one screen, drawn
//  in the warm swatches, not the two-person blend. It is not licence for
//  gradients elsewhere.
//

import SwiftUI

struct WelcomeBloom: View {
    /// The bloom's full width. The lens geometry scales off this, so the whole
    /// cluster grows and shrinks as one.
    var diameter: CGFloat = 320

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @State private var breathes = false

    /// Where each disc sits, in multiples of the lens's own centre offset.
    /// The first two are the mark itself; the rest are the cluster around it,
    /// which is what keeps the shape from reading as a plain figure eight.
    private static let placements: [CGPoint] = [
        CGPoint(x: -1.00, y: 0.00),
        CGPoint(x: 1.00, y: 0.00),
        CGPoint(x: -0.18, y: -0.92),
        CGPoint(x: 0.24, y: 0.88),
        CGPoint(x: -0.86, y: 0.62),
        CGPoint(x: 0.78, y: -0.58)
    ]

    private var radius: CGFloat {
        WELens.circleRadius(diameter: diameter)
    }

    private var offset: CGFloat {
        WELens.centreOffsets(diameter: diameter).trailing
    }

    var body: some View {
        Group {
            if reduceTransparency {
                // The same decision `FieldAmbient` makes: when the person has
                // asked for less haze, the soft version is not dimmed, it is
                // replaced by the honest one.
                WELens(diameter: diameter * 0.42)
            } else {
                bloom
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: diameter * 0.86)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var bloom: some View {
        ZStack {
            halo

            ZStack {
                ForEach(Array(Self.placements.enumerated()), id: \.offset) {
                    _, placement in
                    disc
                        .offset(
                            x: placement.x * offset * 1.75,
                            y: placement.y * offset * 1.75
                        )
                }
            }
            .compositingGroup()
        }
        .scaleEffect(breathes ? 1.02 : 0.99)
        .opacity(breathes ? 1.0 : 0.86)
        .onAppear {
            guard !reduceMotion else { return }
            // The same 7s breathe as `FieldIntelligenceMark`. Anything faster
            // reads as a loading state, which this is not.
            withAnimation(
                .easeInOut(duration: 7).repeatForever(autoreverses: true)
            ) {
                breathes = true
            }
        }
    }

    private var disc: some View {
        Circle()
            .fill(
                // Held, then dropped. A plain three-stop ramp fades from the
                // centre outward and the discs dissolve into one blur; holding
                // most of the value to 0.45 and falling off late is what keeps
                // each circle's edge legible inside the cluster.
                RadialGradient(
                    gradient: Gradient(stops: [
                        // Low, because six of these composite additively. Any
                        // higher and the centre clips to a flat yellow mass
                        // and the mark stops being readable in it.
                        .init(
                            color: FieldSwatch.amber.color.opacity(0.17),
                            location: 0
                        ),
                        .init(
                            color: FieldSwatch.amber.color.opacity(0.14),
                            location: 0.45
                        ),
                        .init(
                            color: FieldSwatch.clay.color.opacity(0.07),
                            location: 0.80
                        ),
                        .init(color: .clear, location: 1)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .blendMode(.plusLighter)
    }

    /// A wide, very faint wash under the cluster so its edge dissolves into the
    /// green instead of ending on a visible circle.
    private var halo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        FieldSwatch.amber.color.opacity(0.05),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.78
                )
            )
            .frame(width: diameter * 1.56, height: diameter * 1.56)
    }
}

#Preview("Bloom") {
    ZStack {
        FieldPalette.bg.ignoresSafeArea()
        WelcomeBloom()
    }
}
