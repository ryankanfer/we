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

    /// The local person has acted. Their own hue strengthens briefly and then
    /// settles; the other hue is untouched.
    ///
    /// The owner here is **always the viewer**. There is no honest way to draw
    /// "they acted and I have not": `WEBeatState` has no case for it, because
    /// from this device it is indistinguishable from nothing having happened.
    /// Passing the partner here would be the one thing the field must never
    /// do, so the ceremony passes its own `viewerOwner` and nothing else.
    case oneActed(FieldOwner)

    /// Both acknowledgements landed. The two fields draw toward the centre and
    /// the shared atmosphere appears, over about eight hundred milliseconds.
    ///
    /// The moment is transient by construction: the field relaxes back to
    /// `shared` on its own, so nothing accumulates across the three beats. A
    /// field that brightened beat by beat would be the step counter drawn in
    /// colour, which is the thing this whole surface exists to avoid.
    case bothLanded

    /// Stillness. An almost motionless trace, and no pulsing reassurance.
    case still
}

extension WEColourFieldState {
    /// The resting state a transient one returns to.
    ///
    /// `oneActed` and `bothLanded` are moments rather than conditions: each
    /// plays once and settles back into the shared field. Everything that
    /// describes the *resting* appearance reads through here, so a held beat
    /// an hour old looks exactly like a held beat a second old.
    var settled: WEColourFieldState {
        switch self {
        case .oneActed, .bothLanded: .shared
        default: self
        }
    }

    var showsBothHues: Bool {
        switch settled {
        case .mine: false
        default: true
        }
    }

    /// Stillness breathes so faintly it reads as stopped.
    var isStill: Bool { settled == .still }

    /// Whose hue strengthens, when someone's does. Never the partner's.
    var strengthens: FieldOwner? {
        if case .oneActed(let owner) = self { return owner }
        return nil
    }

    /// Whether the two fields draw toward one another.
    var converges: Bool { self == .bothLanded }
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

    /// The two transient moments. Both play once and come back down, and both
    /// are held here rather than in the caller so that a state which persists
    /// — a beat can sit `held` for an hour — cannot leave a mark on screen.
    @State private var strengthening = false
    @State private var converging = false

    /// Eight to twelve seconds. Stillness runs slower still, which is the only
    /// way a trace can move at all without reading as a pulse.
    private var period: Double { state.isStill ? 16 : 10 }

    /// Low Power Mode permits a static field, and a backgrounded app has
    /// nothing to animate for.
    private var animates: Bool {
        guard !reduceMotion, isAwake else { return false }
        return true
    }

    /// A moment may still be *marked* under Reduce Motion — as a change in
    /// light rather than a change in position. What it may not do is happen
    /// while the app is in the background or the battery is being conserved,
    /// where there is nobody to mark it for.
    private var isAwake: Bool { !isLowPower && scenePhase == .active }

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
    // These used to split per canvas, because the alpha that reads as a glow
    // against warm ink black reads as a printed stripe against paper. There
    // is no paper any more, so the paper values went with it.
    private var baseOpacity: Double {
        state.isStill ? 0.16 : 0.42
    }

    private var breathOpacity: Double {
        state.isStill ? 0.21 : 0.58
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
        //
        // Which is why it is not marked hidden. Colour and shapes are not
        // accessibility elements to begin with, and `accessibilityHidden`
        // promotes a view into one in order to flag it — leaving a node that
        // carries nothing but the flag, which the audit reports as a node
        // with no description. Nothing here reaches VoiceOver either way.
        .onAppear { breathing = animates }
        .onChange(of: animates) { _, now in breathing = now }
        // Keyed on the state, so arriving in a moment plays it and leaving
        // mid way cancels it cleanly rather than stranding a flag on.
        .task(id: state) { await playTheMoment() }
    }

    // MARK: The blurred fields

    private var atmosphere: some View {
        ZStack {
            field(for: leadingHue, alignment: .leading)
                .offset(x: convergence)
                .overlay { strengthened(.a) }

            if state.showsBothHues {
                field(for: trailingHue, alignment: .trailing)
                    .offset(x: -convergence)
                    .overlay { strengthened(.b) }

                // The shared atmosphere, and only in genuinely shared states.
                // It deepens as the fields meet, which is the whole of what
                // "both landed" is allowed to say.
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

    /// The strengthening, drawn as a second copy of that person's own field
    /// rather than by dimming the other one.
    ///
    /// Dimming would be a statement about the partner, and there is nothing to
    /// state: their hue is untouched here, at every point in the moment.
    @ViewBuilder
    private func strengthened(_ side: FieldOwner) -> some View {
        if state.strengthens == side {
            field(
                for: side == .a ? leadingHue : trailingHue,
                alignment: side == .a ? .leading : .trailing
            )
            .opacity(strengthening ? 0.55 : 0)
            .allowsHitTesting(false)
        }
    }

    /// How far each field travels toward the other. Motion, so Reduce Motion
    /// keeps it at zero and the moment is carried by light alone.
    private var convergence: CGFloat {
        guard converging, !reduceMotion else { return 0 }
        return 38
    }

    private var sharedAtmosphere: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            RadialGradient(
                colors: [blendCentre.opacity(converging ? 0.82 : 0.55), .clear],
                center: UnitPoint(x: 0.5, y: 1.3),
                startRadius: 0,
                endRadius: max(w * (converging ? 0.44 : 0.34), 1)
            )
            .blur(radius: 26)
        }
    }

    // MARK: The two moments

    /// Plays whichever transient the current state names, then puts it away.
    ///
    /// Both end where they started. The relaxation is deliberately slower than
    /// the arrival in each case: something appearing quickly and leaving slowly
    /// reads as a breath being taken, and the reverse reads as a flash.
    private func playTheMoment() async {
        strengthening = false
        converging = false
        guard isAwake else { return }

        if state.strengthens != nil {
            animate(.easeOut(duration: 0.5)) { strengthening = true }
            guard await pause(for: 1.2) else { return }
            animate(.easeInOut(duration: 1.8)) { strengthening = false }
        } else if state.converges {
            // The eight hundred milliseconds the direction asks for, and then
            // the field lets go of the moment rather than keeping it.
            animate(.easeInOut(duration: 0.8)) { converging = true }
            guard await pause(for: 1.3) else { return }
            animate(.easeInOut(duration: 1.6)) { converging = false }
        }
    }

    /// Under Reduce Motion the change still happens, without being eased into
    /// place: a crossfade of the same length, which is a change in light.
    private func animate(_ curve: Animation, _ change: () -> Void) {
        withAnimation(reduceMotion ? curve.speed(1.4) : curve, change)
    }

    /// `false` if the moment was interrupted, which is the caller's cue to
    /// leave the flags exactly as the next state found them.
    private func pause(for seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    // MARK: Reduce Transparency

    /// No blurred atmosphere. A crisp, low intensity colour edge instead — the
    /// same information, which is to say none, at a hard edge.
    private var crispEdge: some View {
        HStack(spacing: 0) {
            Rectangle().fill(edgeHue(leadingHue, side: .a))
            if state.showsBothHues {
                Rectangle().fill(edgeHue(trailingHue, side: .b))
            }
        }
        .frame(height: 2)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// The same two moments at a hard edge: the acting person's own segment
    /// takes on more of its colour, and both segments move toward the blend as
    /// the acknowledgements land. No width changes, so nothing slides.
    private func edgeHue(_ hue: Color, side: FieldOwner) -> Color {
        if converging { return hue.mix(with: blendCentre, by: 0.6).opacity(0.72) }
        return hue.opacity(strengthening && state.strengthens == side ? 0.8 : 0.55)
    }

    // MARK: Hues

    private var leadingHue: Color {
        switch state.settled {
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
