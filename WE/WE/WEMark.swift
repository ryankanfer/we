import SwiftUI

struct WEMark: View {
    enum Style: Equatable {
        case micro
        case compact
        case display

        /// Exposed so the personal mark can share this geometry exactly.
        /// CIRCLE.md §2 makes the whole product legible at a glance — one
        /// circle is yours, two apart is invited, two joined is WE — and that
        /// only reads if all three are demonstrably the same circle.
        var diameter: CGFloat {
            switch self {
            case .micro: 16
            case .compact: 34
            case .display: 64
            }
        }
    }

    /// How many circles.
    ///
    /// `we` is the mark as it has always been. `personal` is the same mark
    /// with the partner circle absent, which is the identity of the personal
    /// space — §2 notes this is already half-built, and it is: the geometry,
    /// the hue and the separation were all here, and only the option to leave
    /// one circle out was missing.
    ///
    /// Defaulted to `we` so the existing caller is untouched.
    enum Composition: Equatable {
        case we
        case personal
    }

    var style: Style = .compact
    var composition: Composition = .we
    var joined = true
    var showsWordmark = true
    var personalHue: WEHue?
    var partnerHue: WEHue = .partnerDefault
    var accessibilityText = "WE"

    private var resolvedPersonalHue: WEHue {
        personalHue ?? .burgundy
    }

    private var diameter: CGFloat { style.diameter }

    private var separation: CGFloat {
        switch composition {
        case .personal:
            // Nothing to be separate from. Centring rather than offsetting
            // matters for the one animation this enables: preparing an offer
            // is the solitary circle drifting toward the partner circle and
            // stopping short of joining, and it has to start from the middle.
            0
        case .we:
            joined ? diameter * 0.22 : diameter * 0.68
        }
    }

    private var canvasWidth: CGFloat {
        switch composition {
        case .personal:
            diameter
        case .we:
            switch style {
            case .micro: 28
            case .compact: 58
            case .display: 148
            }
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

                if composition == .we {
                    Circle()
                        .fill(partnerHue.color.opacity(0.32))
                        .frame(width: diameter, height: diameter)
                        .glassEffect(
                            .regular.tint(partnerHue.color.opacity(0.32)),
                            in: Circle()
                        )
                        .offset(x: separation)
                        .accessibilityHidden(true)
                }

                if showsWordmark, composition == .we {
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
        }
        .frame(
            width: canvasWidth,
            height: diameter
        )
        // `accessibilityText` was declared and passed by five callers with
        // real state strings, then silenced by four nested
        // accessibilityHidden(true) calls. In togetherStateCard, emptyState
        // and heldState the mark is the only thing carrying that state.
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }
}
