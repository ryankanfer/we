//
//  DesignSystem.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

extension Font {
    static var weLargeTitle: Font {
        .system(.largeTitle, design: .serif, weight: .regular)
    }

    static var weTitle: Font {
        .system(.title2, design: .serif, weight: .regular)
    }

    static var weHeadline: Font {
        .headline
    }

    static var weBody: Font {
        .body
    }

    static var weCaption: Font {
        .caption.weight(.medium)
    }
}

extension Animation {
    /// The house easing — a long, settling decelerate used for every
    /// transition WE treats as meaningful (joining, revealing, choosing).
    static func weSettle(duration: Double = 0.5) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    /// Same curve, honoring Reduce Motion by collapsing to no animation.
    static func weSettle(
        duration: Double = 0.5,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : .weSettle(duration: duration)
    }
}

/// A tracked, small-caps section label. The recurring editorial device that
/// separates one region of a surface from the next.
struct WESectionLabel: View {
    let text: String
    var color: Color = .white.opacity(0.62)

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.weCaption)
            .tracking(1.4)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

struct WEPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 18)
            .background(
                Color("WEBurgundy").opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
