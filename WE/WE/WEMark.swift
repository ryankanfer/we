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

    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var resolvedPersonalHue: WEHue {
        personalHue ?? WEHue.stored(storedPersonalHue)
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

                Circle()
                    .fill(partnerHue.color.opacity(0.32))
                    .frame(width: diameter, height: diameter)
                    .glassEffect(
                        .regular.tint(partnerHue.color.opacity(0.32)),
                        in: Circle()
                    )
                    .offset(x: separation)

                if showsWordmark {
                    Text("WE")
                        .font(
                            style == .display
                                ? .system(.title2, weight: .bold)
                                : .system(.caption2, weight: .bold)
                        )
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(
            width: canvasWidth,
            height: diameter
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("WE, Ryan and Dylan together")
    }
}
