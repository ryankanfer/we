import SwiftUI

struct WEMark: View {
    enum Style: Equatable {
        case micro
        case compact
        case display
    }

    var style: Style = .compact
    var joined = true
    var showsWordmark = true
    var personalHue: WEHue?
    var partnerHue: WEHue = .partnerDefault
    var accessibilityText = "WE"

    private var resolvedPersonalHue: WEHue {
        personalHue ?? .burgundy
    }

    private var diameter: CGFloat {
        switch style {
        case .micro:
            16
        case .compact:
            34
        case .display:
            104
        }
    }

    private var separation: CGFloat {
        joined ? diameter * 0.22 : diameter * 0.68
    }

    private var canvasWidth: CGFloat {
        switch style {
        case .micro:
            28
        case .compact:
            58
        case .display:
            246
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: diameter * 0.36) {
            ZStack {
                Circle()
                    .fill(resolvedPersonalHue.color.opacity(0.34))
                    .frame(width: diameter, height: diameter)
                    .glassEffect(
                        .regular.tint(
                            resolvedPersonalHue.color.opacity(0.34)
                        ),
                        in: Circle()
                    )
                    .offset(x: -separation)
                    .accessibilityHidden(true)

                Circle()
                    .fill(partnerHue.color.opacity(0.32))
                    .frame(width: diameter, height: diameter)
                    .glassEffect(
                        .regular.tint(partnerHue.color.opacity(0.32)),
                        in: Circle()
                    )
                    .offset(x: separation)
                    .accessibilityHidden(true)

                if showsWordmark {
                    Text("WE")
                        .font(
                            style == .display
                                ? .system(.title2, weight: .bold)
                                : .system(.caption2, weight: .bold)
                        )
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
        .frame(
            width: canvasWidth,
            height: diameter
        )
        .accessibilityHidden(true)
    }
}
