//
//  WEColourField.swift
//  WE
//
//  The animated bottom colour field, from the "Type Holds the Room" direction.
//
//  Two broad blurred fields originate just below the bottom edge, one hue per
//  person. Their shared colour may appear softly where the fields meet, but
//  only in genuinely shared states — its scarcity is what gives it meaning.
//
//  What this is not, and must never become:
//
//    · a progress indicator
//    · a presence indicator
//    · a network or loading indicator
//    · a report on the other person's timing
//
//  The motion is a breath, not a journey: opacity, scale, and two to four
//  points of vertical drift over eight to twelve seconds. No horizontal
//  sweeping, no rotating gradient, no liquid blob, no continuous shimmer. If
//  it ever reads as "something is happening", it is wrong.
//
//  Blur is expensive to animate, so the blurred fields are composed once and
//  the breath animates opacity, scale, and offset *around* them. The radius
//  itself never animates.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// What the field is allowed to say. Nothing here encodes *when* anyone acted.
enum WEColourFieldState: Equatable, Sendable {
    /// A private surface. Only the current person's hue.
    case mine(FieldOwner)

    /// A shared surface. Both hues, with a quiet shared atmosphere between.
    case shared

    /// One person has acted. Their hue strengthens briefly and then settles;
    /// the other hue is untouched.
    ///
    /// Deliberately unimplemented until the ceremony exists. It renders as
    /// `.shared`, which is the honest answer while nothing can produce the
    /// event: a surface that cannot know one person acted must not imply it.
    case oneActed(FieldOwner)

    /// Both actions landed. The fields converge and the shared atmosphere
    /// appears. Also unimplemented until the ceremony exists.
    case bothLanded

    /// Stillness. An almost motionless trace, and no pulsing reassurance.
    case still
}

extension WEColourFieldState {
    /// The states phase one can actually produce. `oneActed` and `bothLanded`
    /// need a second device, so they resolve to `shared` rather than
    /// pretending to a transition nothing can trigger yet.
    var resolved: WEColourFieldState {
        switch self {
        case .oneActed, .bothLanded: .shared
        default: self
        }
    }

    var showsBothHues: Bool {
        switch resolved {
        case .mine: false
        default: true
        }
    }

    /// Stillness breathes so faintly it reads as stopped.
    var isStill: Bool { resolved == .still }
}

struct WEColourField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.weCanvas) private var canvas

    var state: WEColourFieldState
    var identity: FieldIdentity
    /// Typical visible height is twenty four to fifty points. The glow should
    /// feel embedded in the display edge, not painted on top of the interface.
    var height: CGFloat = 44

    @State private var breathing = false

    /// Eight to twelve seconds. Stillness runs slower still, which is the only
    /// way a trace can move at all without reading as a pulse.
    private var period: Double { state.isStill ? 16 : 10 }

    /// Low Power Mode permits a static field, and a backgrounded app has
    /// nothing to animate for.
    private var animates: Bool {
        guard !reduceMotion, !isLowPower, scenePhase == .active else {
            return false
        }
        return true
    }

    private var isLowPower: Bool {
        #if canImport(UIKit)
        ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        false
        #endif
    }

    // The first pass ran these at 0.72 and 0.94, which produced a saturated
    // band across the bottom of the screen rather than light coming from
    // under the edge. A glow you can name the shape of is a graphic, and the
    // brief asks for atmosphere.
    //
    // Cream sits lower still. Person colour on the paper canvas is limited to
    // authorship points, fine rules, and this atmosphere, and the same alpha
    // that reads as a glow against warm ink black reads as a printed stripe
    // against paper.
    private var baseOpacity: Double {
        if state.isStill { return canvas == .cream ? 0.12 : 0.16 }
        return canvas == .cream ? 0.26 : 0.42
    }

    private var breathOpacity: Double {
        if state.isStill { return canvas == .cream ? 0.16 : 0.21 }
        return canvas == .cream ? 0.34 : 0.58
    }
    private var drift: CGFloat { state.isStill ? 1 : 3 }

    var body: some View {
        Group {
            if reduceTransparency {
                crispEdge
            } else {
                atmosphere
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        // Decorative in the strictest sense: it carries no information a
        // VoiceOver user could be missing, because it carries no information.
        .accessibilityHidden(true)
        .onAppear { breathing = animates }
        .onChange(of: animates) { _, now in breathing = now }
    }

    // MARK: The blurred fields

    private var atmosphere: some View {
        ZStack {
            field(for: leadingHue, alignment: .leading)

            if state.showsBothHues {
                field(for: trailingHue, alignment: .trailing)

                // The shared atmosphere, and only in genuinely shared states.
                sharedAtmosphere
            }
        }
        .compositingGroup()
        .opacity(breathing ? breathOpacity : baseOpacity)
        .scaleEffect(
            x: 1,
            y: breathing ? 1.06 : 1,
            anchor: .bottom
        )
        .offset(y: breathing ? -drift : 0)
        .animation(breath, value: breathing)
        .clipped()
        // Clipping alone leaves a straight horizontal cut where the field
        // meets the page, which is the one thing a light source never has.
        // The mask dissolves the upper edge so the glow ends by running out
        // rather than by stopping.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.62), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }

    private var breath: Animation? {
        guard animates else { return nil }
        return .easeInOut(duration: period).repeatForever(autoreverses: true)
    }

    /// One person's field. Originates *below* the bottom edge, which is what
    /// makes it read as embedded in the display rather than drawn on the page.
    private func field(
        for hue: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            RadialGradient(
                colors: [hue, .clear],
                center: UnitPoint(
                    x: alignment == .leading ? 0.26 : 0.74,
                    y: 1.34
                ),
                startRadius: 0,
                endRadius: max(w * 0.62, 1)
            )
            .blur(radius: 24)
        }
    }

    private var sharedAtmosphere: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            RadialGradient(
                colors: [blendCentre.opacity(0.55), .clear],
                center: UnitPoint(x: 0.5, y: 1.3),
                startRadius: 0,
                endRadius: max(w * 0.34, 1)
            )
            .blur(radius: 26)
        }
    }

    // MARK: Reduce Transparency

    /// No blurred atmosphere. A crisp, low intensity colour edge instead — the
    /// same information, which is to say none, at a hard edge.
    private var crispEdge: some View {
        HStack(spacing: 0) {
            Rectangle().fill(leadingHue.opacity(0.55))
            if state.showsBothHues {
                Rectangle().fill(trailingHue.opacity(0.55))
            }
        }
        .frame(height: 2)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: Hues

    private var leadingHue: Color {
        switch state.resolved {
        case .mine(let owner): identity.color(for: owner)
        default: identity.personA.color
        }
    }

    private var trailingHue: Color { identity.personB.color }

    /// The colour where the two fields meet. Neither person made it.
    private var blendCentre: Color {
        identity.personA.color.mix(with: identity.personB.color, by: 0.5)
    }
}
