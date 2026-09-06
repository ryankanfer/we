//
//  YoursMark.swift
//  WE
//
//  One shape, five conditions, and not a single numeral.
//
//  CIRCLE.md §2 is unusually specific about this, and the specificity is the
//  design: no badges, no counts, no numerals anywhere. A dot with a number on
//  it would turn a private space into an inbox, and an inbox is a thing you
//  are behind on.
//
//    living           circle outline, personal hue
//    nearing return   the stroke lightens gradually across the final week —
//                     legible if you look, invisible if you do not. Never a
//                     countdown, never a date on the object.
//    returned         fully weighted, present, waiting
//    held             solid fill, the same shape made permanent
//    let go           the circle contracts to nothing and the surface returns
//                     to empty
//
//  The fifth is a transition rather than a state, which is why `Presence` has
//  four cases and `isLetGo` is a separate flag: there is no such thing as an
//  entry that *is* let go, only the moment of it becoming nothing.
//
//  The nearing ramp arrives as a `Double` from `YoursDates.nearingProgress`
//  rather than as a date, deliberately. A view holding the date could render
//  it; a view holding a fraction cannot turn into a countdown by accident.
//

import SwiftUI

struct YoursMark: View {
    enum Presence: Equatable {
        case living
        /// 0 at the start of the final week, 1 at the moment it is ready.
        case nearing(Double)
        case returned
        case held
    }

    var style: WEMark.Style = .compact
    var presence: Presence = .living
    var hue: Color
    /// Drives the one transition. Set it and the circle contracts to nothing.
    var isLetGo = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat { style.diameter }

    /// The stroke lightens as the return approaches. It never darkens, never
    /// pulses, and never moves — a mark that animated as a deadline neared
    /// would be the interface tapping somebody on the shoulder about their own
    /// private writing.
    private var strokeOpacity: Double {
        switch presence {
        case .living: 0.55
        case .nearing(let progress): 0.55 - (0.33 * min(max(progress, 0), 1))
        case .returned: 1
        case .held: 0
        }
    }

    private var strokeWidth: CGFloat {
        switch presence {
        case .returned: max(2, diameter * 0.08)
        case .held: 0
        default: max(1, diameter * 0.05)
        }
    }

    private var fillOpacity: Double {
        presence == .held ? 0.9 : 0
    }

    var body: some View {
        Circle()
            .fill(hue.opacity(fillOpacity))
            .overlay {
                Circle()
                    .strokeBorder(
                        hue.opacity(strokeOpacity),
                        lineWidth: strokeWidth
                    )
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isLetGo ? 0 : 1)
            .opacity(isLetGo ? 0 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.45),
                value: isLetGo
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.35),
                value: presence
            )
            .accessibilityElement()
            // The spoken name, and the only word attached to this shape after
            // the two teaching moments. Deliberately the same word sighted
            // users are taught: naming it after the furniture — "your circle",
            // "your space" — would give sighted and unsighted people different
            // mental models of the same product.
            //
            // State is deliberately absent from the label. VoiceOver
            // announcing "Yours, one waiting" would be the count §2 forbids,
            // read aloud.
            .accessibilityLabel(YoursCopy.accessibilityName)
    }
}

// MARK: - Preparing an offer

/// The solitary circle drifting toward the partner circle and stopping short.
///
/// §2 notes this motion is native to the mark rather than invented for it,
/// because separation was already an animatable parameter. It matters that it
/// stops short: the circles do not join until the offer actually crosses, and
/// an animation that completed the join early would be the interface
/// promising something the person has not done yet.
struct YoursPrepareMark: View {
    var style: WEMark.Style = .compact
    var personalHue: WEHue?
    var partnerHue: WEHue = .partnerDefault
    /// False while composing, true once the wording is approved and the offer
    /// is ready to be sent.
    var isPrepared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WEMark(
            style: style,
            composition: isPrepared ? .we : .personal,
            joined: false,
            showsWordmark: false,
            personalHue: personalHue,
            partnerHue: partnerHue,
            accessibilityText: isPrepared
                ? YoursCopy.prepareAnOffer
                : YoursCopy.accessibilityName
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.5),
            value: isPrepared
        )
    }
}

#Preview("The five conditions") {
    VStack(spacing: 28) {
        YoursMark(style: .display, presence: .living, hue: .purple)
        YoursMark(style: .display, presence: .nearing(0.9), hue: .purple)
        YoursMark(style: .display, presence: .returned, hue: .purple)
        YoursMark(style: .display, presence: .held, hue: .purple)
    }
    .padding(40)
}
