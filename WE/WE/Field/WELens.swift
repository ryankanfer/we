//
//  WELens.swift
//  WE
//
//  The mark — 7a, the lens.
//
//  Two circles that overlap, and the overlap is the point: it is the shape
//  that only exists because both are there. The app is named for it.
//
//  Built as the **intersection of two circles**, never a traced almond path.
//  The spec is explicit about this and it is right — an intersection is
//  correct at every size for free, and cannot drift from the source artwork
//  the way a hand-fitted bezier does.
//
//  Every number derives from `diameter`, so the same view serves the splash
//  at 132pt and the app icon at 72% of its tile.
//

import SwiftUI

struct WELens: View {
    /// The mark's full width. The source viewBox is 200 units drawn at 132pt,
    /// so everything below scales by `diameter / 200` — 0.66 at 132pt.
    var diameter: CGFloat = 132
    /// `#E8E4D9` on dark, `#16211D` on light. Never tinted.
    var foreground: Color = FieldPalette.ink
    /// The filled overlap. Off for the splash, where the gradient disc is
    /// already showing through and a second fill would muddy it.
    var showsOverlap = true

    // MARK: Geometry
    //
    //  viewBox    rendered at 132pt
    //  ————————   ————————————————
    //  radius 56  36.96pt
    //  offset 26  ±17.16pt
    //  stroke 3   ≈2pt

    private var scale: CGFloat { diameter / 200 }
    private var radius: CGFloat { 56 * scale }
    private var offset: CGFloat { 26 * scale }
    private var stroke: CGFloat { 3 * scale }

    /// The hairlines sit at 34% of the foreground; the overlap never does.
    private static let hairlineOpacity = 0.34

    var body: some View {
        ZStack {
            ring(dx: -offset)
            ring(dx: offset)

            if showsOverlap {
                overlap
            }
        }
        .frame(width: diameter, height: radius * 2)
        .accessibilityHidden(true)
    }

    private func ring(dx: CGFloat) -> some View {
        Circle()
            .strokeBorder(
                foreground.opacity(Self.hairlineOpacity),
                lineWidth: stroke
            )
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: dx)
    }

    /// The intersection: one circle, masked by the other.
    private var overlap: some View {
        Circle()
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: -offset)
            .mask {
                Circle()
                    .frame(width: radius * 2, height: radius * 2)
                    .offset(x: offset)
            }
            .foregroundStyle(foreground)
    }
}

extension WELens {
    /// Where the two circle centres sit, relative to the mark's own centre.
    ///
    /// Exposed so the splash can place its collapsing disc and vignette on
    /// exactly the same point the mark is drawn around, rather than deriving
    /// one from a screen percentage and the other from a stack offset — which
    /// is how the mark ends up sliding as the disc closes.
    static func centreOffsets(diameter: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let offset = 26 * (diameter / 200)
        return (-offset, offset)
    }

    /// The radius of each circle at a given mark width.
    static func circleRadius(diameter: CGFloat) -> CGFloat {
        56 * (diameter / 200)
    }
}

#Preview("Lens — dark") {
    ZStack {
        FieldPalette.bg.ignoresSafeArea()
        WELens()
    }
}

#Preview("Lens — light") {
    ZStack {
        FieldPalette.ink.ignoresSafeArea()
        WELens(foreground: FieldPalette.bg)
    }
}

#Preview("Lens — splash treatment") {
    ZStack {
        FieldPalette.bg.ignoresSafeArea()
        WELens(showsOverlap: false)
    }
}
