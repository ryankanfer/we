//
//  DesignSystem.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

extension Font {
    static var weLargeTitle: Font {
        .system(size: 34, weight: .regular, design: .serif)
    }

    static var weTitle: Font {
        .system(size: 24, weight: .regular, design: .serif)
    }

    static var weHeadline: Font {
        .system(size: 17, weight: .semibold)
    }

    static var weBody: Font {
        .system(size: 16, weight: .regular)
    }

    static var weCaption: Font {
        .system(size: 12, weight: .medium)
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

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.weCaption)
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.62))
            .accessibilityAddTraits(.isHeader)
    }
}
