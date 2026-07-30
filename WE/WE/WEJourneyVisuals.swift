import SwiftUI

/// The semantic visual states used by trust-bearing WE surfaces.
///
/// Color never carries the meaning alone: the continuity line changes shape
/// and VoiceOver receives the state description as well.
nonisolated enum WEJourneyState: String, Codable, CaseIterable, Sendable {
    case privateState
    case offerPreview
    case offered
    case held
    case shared
    case resolved

    var accessibilityDescription: String {
        switch self {
        case .privateState:
            "Private. Only your side is present."
        case .offerPreview:
            "Offer preview. You are choosing exactly what can cross."
        case .offered:
            "Offered. The topic is waiting at the consent threshold."
        case .held:
            "Both sides are present and remain private."
        case .shared:
            "Shared. A new direction is open between two intact sides."
        case .resolved:
            "Resolved. The shared direction is resting."
        }
    }
}

extension Color {
    static let wePrivateInk = Color(red: 23 / 255, green: 48 / 255, blue: 64 / 255)
    static let weDuskBlue = Color(red: 113 / 255, green: 132 / 255, blue: 151 / 255)
    static let wePearl = Color(red: 242 / 255, green: 238 / 255, blue: 230 / 255)
    static let weWarmStone = Color(red: 216 / 255, green: 208 / 255, blue: 196 / 255)
    static let weChampagne = Color(red: 199 / 255, green: 162 / 255, blue: 88 / 255)
    static let weSharedOlive = Color(red: 124 / 255, green: 128 / 255, blue: 82 / 255)
    static let weCharcoal = Color(red: 30 / 255, green: 48 / 255, blue: 58 / 255)
}

struct WEJourneyPalette {
    let background: Color
    let secondaryBackground: Color
    let ink: Color
    let secondaryInk: Color
    let accent: Color

    static func palette(for state: WEJourneyState) -> WEJourneyPalette {
        switch state {
        case .privateState, .held:
            WEJourneyPalette(
                background: .wePrivateInk,
                secondaryBackground: .weDuskBlue,
                ink: .wePearl,
                secondaryInk: .wePearl.opacity(0.74),
                accent: .weChampagne
            )
        case .offerPreview, .offered:
            WEJourneyPalette(
                background: .wePearl,
                secondaryBackground: .weWarmStone,
                ink: .weCharcoal,
                secondaryInk: .weCharcoal.opacity(0.76),
                accent: .weChampagne
            )
        case .shared, .resolved:
            WEJourneyPalette(
                background: .wePearl,
                secondaryBackground: .white,
                ink: .weCharcoal,
                secondaryInk: .weCharcoal.opacity(0.76),
                accent: .weSharedOlive
            )
        }
    }
}

/// WE's persistent orientation mark. It is intentionally still: waiting is
/// never rendered as progress, partner presence, or a read receipt.
struct WEContinuityLine: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let state: WEJourneyState
    var lineWidth: CGFloat = 1.25

    var body: some View {
        Canvas { context, size in
            let palette = WEJourneyPalette.palette(for: state)
            let effectiveLineWidth =
                colorSchemeContrast == .increased
                ? max(2, lineWidth * 1.5)
                : lineWidth
            switch state {
            case .privateState:
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height * 0.55))
                path.addCurve(
                    to: CGPoint(x: size.width, y: size.height * 0.5),
                    control1: CGPoint(x: size.width * 0.28, y: size.height * 0.76),
                    control2: CGPoint(x: size.width * 0.66, y: size.height * 0.34)
                )
                context.stroke(
                    path,
                    with: .color(palette.accent.opacity(0.92)),
                    lineWidth: effectiveLineWidth
                )
                endpoint(in: &context, at: CGPoint(x: size.width - 5, y: size.height * 0.5), color: palette.accent)

            case .offerPreview, .offered:
                let thresholdX = size.width * 0.7
                var privatePath = Path()
                privatePath.move(to: CGPoint(x: 0, y: size.height * 0.58))
                privatePath.addLine(to: CGPoint(x: thresholdX, y: size.height * 0.58))
                context.stroke(
                    privatePath,
                    with: .color(.wePrivateInk.opacity(0.72)),
                    lineWidth: effectiveLineWidth
                )

                var threshold = Path()
                threshold.move(to: CGPoint(x: thresholdX, y: 0))
                threshold.addLine(to: CGPoint(x: thresholdX, y: size.height))
                context.stroke(
                    threshold,
                    with: .color(.weChampagne),
                    lineWidth: effectiveLineWidth
                )
                endpoint(
                    in: &context,
                    at: CGPoint(x: thresholdX, y: size.height * 0.58),
                    color: .weChampagne
                )

            case .held:
                twoSides(
                    in: &context,
                    size: size,
                    opens: false,
                    lineWidth: effectiveLineWidth
                )

            case .shared:
                twoSides(
                    in: &context,
                    size: size,
                    opens: true,
                    lineWidth: effectiveLineWidth
                )

            case .resolved:
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.56))
                path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.56))
                context.stroke(
                    path,
                    with: .color(.weSharedOlive.opacity(0.58)),
                    lineWidth: max(0.75, effectiveLineWidth * 0.72)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityDescription)
        .allowsHitTesting(false)
    }

    private func endpoint(
        in context: inout GraphicsContext,
        at point: CGPoint,
        color: Color
    ) {
        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.wePearl), lineWidth: 1)
    }

    private func twoSides(
        in context: inout GraphicsContext,
        size: CGSize,
        opens: Bool,
        lineWidth: CGFloat
    ) {
        let leftX = size.width * 0.25
        let rightX = size.width * 0.75
        var left = Path()
        left.move(to: CGPoint(x: leftX, y: 0))
        left.addLine(to: CGPoint(x: leftX, y: size.height))
        var right = Path()
        right.move(to: CGPoint(x: rightX, y: 0))
        right.addLine(to: CGPoint(x: rightX, y: size.height))
        context.stroke(left, with: .color(.weDuskBlue), lineWidth: lineWidth)
        context.stroke(right, with: .color(.weChampagne), lineWidth: lineWidth)

        let y = size.height * 0.55
        endpoint(in: &context, at: CGPoint(x: leftX, y: y), color: .weDuskBlue)
        endpoint(in: &context, at: CGPoint(x: rightX, y: y), color: .weChampagne)

        if opens {
            let clearing = CGRect(
                x: leftX,
                y: y - size.height * 0.16,
                width: rightX - leftX,
                height: size.height * 0.32
            )
            context.fill(
                Path(roundedRect: clearing, cornerRadius: clearing.height / 2),
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        .wePearl.opacity(0.9),
                        .clear,
                    ]),
                    startPoint: CGPoint(x: clearing.minX, y: clearing.midY),
                    endPoint: CGPoint(x: clearing.maxX, y: clearing.midY)
                )
            )
        }
    }
}

struct WEJourneyBackdrop: View {
    let state: WEJourneyState
    var showsContinuityLine = true

    var body: some View {
        let palette = WEJourneyPalette.palette(for: state)
        ZStack {
            palette.background
            LinearGradient(
                colors: [
                    palette.secondaryBackground.opacity(0.42),
                    palette.background.opacity(0.08),
                    palette.background,
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            if showsContinuityLine {
                WEContinuityLine(state: state)
                    .frame(height: 190)
                    .padding(.horizontal, 24)
                    .opacity(0.88)
            }
        }
        .ignoresSafeArea()
    }
}

struct WEJourneyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: WEJourneyState

    func makeBody(configuration: Configuration) -> some View {
        let usesDarkSurface = state == .privateState || state == .held
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(
                usesDarkSurface ? Color.wePrivateInk : Color.wePearl
            )
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 18)
            .background(
                (usesDarkSurface ? Color.weChampagne : Color.wePrivateInk)
                    .opacity(isEnabled ? 1 : 0.42),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.985
            )
            .animation(
                reduceMotion ? nil : .weQuick,
                value: configuration.isPressed
            )
    }
}

struct WEJourneySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: WEJourneyState

    func makeBody(configuration: Configuration) -> some View {
        let palette = WEJourneyPalette.palette(for: state)
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.ink.opacity(isEnabled ? 1 : 0.44))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 18)
            .background(
                palette.background.opacity(0.001),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        palette.ink.opacity(isEnabled ? 0.42 : 0.2),
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.985
            )
            .animation(
                reduceMotion ? nil : .weQuick,
                value: configuration.isPressed
            )
    }
}
