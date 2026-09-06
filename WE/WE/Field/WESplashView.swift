//
//  WESplashView.swift
//  WE
//
//  The collapse — 9b.
//
//  The screen begins as full-bleed gradient, identical to the launch screen,
//  and contracts into the mark. The gradient itself never moves or scales:
//  it stays pinned full-bleed and is only *revealed* through a shrinking
//  circle. That is what gives the ending its character — the final disc shows
//  the middle of the sweep, warm bleeding to cool across it, rather than a
//  flat band.
//
//  Frame 0 must be pixel-identical to `LaunchScreen.storyboard`, which is why
//  this draws the same `WELaunchGradient` asset rather than a computed
//  `LinearGradient`. Anything that differs at frame 0 shows as a flash at the
//  handoff from the OS launch screen.
//

import SwiftUI

@MainActor
struct WESplashView: View {
    /// The couple's own two colours, if there is a couple yet. The disc
    /// cross-tints to these as it closes, so the mark that finally lands is
    /// theirs rather than ours.
    var identity: FieldIdentity?
    /// Held on the finished mark while this returns true — or until
    /// `WESplashGate.holdCeiling` runs out, whichever comes first.
    ///
    /// A closure rather than a `Bool`, and that is load-bearing: `.task` does
    /// not restart when the view is recreated, so a captured value stays at
    /// whatever it was when the animation began. As a `Bool` this waited on a
    /// stale `true` and never handed over at all.
    var isWaiting: () -> Bool
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var marksIn: Double = 0
    @State private var tint: Double = 0

    /// The mark's drawn width, and the disc it ends inside.
    private static let markDiameter: CGFloat = 132
    /// 16.5% of the reference diagonal ≈ 110pt, read as a radius: a 220pt
    /// disc comfortably containing a 132pt mark. As a diameter it would be
    /// *smaller* than the mark, which cannot be "a little larger" than it.
    private static let finalRadius: CGFloat = 110
    /// Optical centring — the mark sits above true centre.
    private static let opticalRise: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // One constant. The disc, the vignette, and the mark all derive
            // from this — computing the mask from a height percentage and the
            // mark from a stack offset makes the mark slide as the disc
            // closes, on some devices only.
            let centre = CGPoint(
                x: size.width / 2,
                y: size.height / 2 - Self.opticalRise
            )
            let start = hypot(size.width, size.height)
            let radius = start + (Self.finalRadius - start) * progress

            ZStack {
                FieldPalette.bg.ignoresSafeArea()

                vignette(in: size, centre: centre)
                    .opacity(progress)

                gradient
                    .mask {
                        Circle()
                            .frame(width: radius * 2, height: radius * 2)
                            .position(centre)
                    }
                    .ignoresSafeArea()

                WELens(diameter: Self.markDiameter, showsOverlap: false)
                    .opacity(marksIn)
                    .scaleEffect(1.02 - 0.02 * marksIn)
                    .position(centre)
            }
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    // MARK: The gradient

    /// The launch asset, plus the couple's own blend fading in over it.
    ///
    /// The tint layer is **0 at frame 0** without exception — that frame
    /// belongs to the launch screen, and nothing may differ from it.
    private var gradient: some View {
        ZStack {
            Image("WELaunchGradient")
                .resizable()
                .aspectRatio(contentMode: .fill)

            if let identity {
                LinearGradient(
                    colors: [
                        identity.personA.color,
                        identity.personB.color,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(tint)
            }
        }
    }

    /// `radial-gradient(120% 90% at the mark centre, rgba(121,166,184,.10),
    /// transparent 64%)` — anchored to the mark rather than a fixed 47.2%.
    private func vignette(in size: CGSize, centre: CGPoint) -> some View {
        RadialGradient(
            colors: [
                Color(hex: 0x79A6B8).opacity(0.10),
                Color(hex: 0x79A6B8).opacity(0),
            ],
            center: UnitPoint(
                x: centre.x / max(size.width, 1),
                y: centre.y / max(size.height, 1)
            ),
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.64
        )
        .ignoresSafeArea()
    }

    // MARK: Timing

    private static let curve = Animation.timingCurve(
        0.22, 0.70, 0.20, 1.00, duration: 0.70
    )

    private func run() async {
        if reduceMotion {
            // No contraction, ever. Hold the gradient, then cross-dissolve
            // straight to the finished mark.
            progress = 1
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.25)) {
                marksIn = 1
                tint = 1
            }
            try? await Task.sleep(for: .milliseconds(250))
        } else {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(Self.curve) { progress = 1 }

            // Starts after the disc is well underway, so frame 0 stays the
            // launch gradient exactly.
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeInOut(duration: 0.40)) { tint = 1 }

            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeOut(duration: 0.28)) { marksIn = 1 }

            try? await Task.sleep(for: .milliseconds(380))
        }

        // The mark is the wait state — no spinner. But it is a wait state
        // with an end: past the ceiling the app hands over regardless and
        // lets the real screen show its own offline or failed state, which
        // it already knows how to do. Silence is right for a slow network
        // and wrong for a broken one.
        let deadline = ContinuousClock.now.advanced(by: WESplashGate.holdCeiling)
        while isWaiting(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(80))
        }

        onFinish()
    }
}

#Preview("Collapse") {
    WESplashView(
        identity: FieldIdentity.seed,
        isWaiting: { false },
        onFinish: {}
    )
}
