import SwiftUI
import WidgetKit

/// The pixels WE owns inside its ambient widgets.
///
/// WidgetKit's SpringBoard and Lock Screen hosts own the outer chrome,
/// clipping, margins, and rendering-mode transformations. Keeping this view
/// in `WEShared` lets the extension and the deterministic golden renderer use
/// the same family branching and content without pretending to reproduce
/// those system-owned layers.
struct WEAmbientWidgetSurface: View {
    enum BackgroundPresentation {
        /// Production: publish the background as a WidgetKit container trait.
        case widgetHost
        /// Tests: paint the same background into an explicit reference canvas.
        case referenceCanvas
    }

    let snapshot: ExternalSurfaceSnapshot
    let date: Date
    let family: WidgetFamily
    let backgroundPresentation: BackgroundPresentation

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryInline:
            Label(
                snapshot.wording(at: date),
                systemImage: "circle.hexagongrid"
            )
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                WEExternalContinuityMark(
                    state: snapshot.effectiveState(at: date)
                )
                .padding(10)
            }
            .accessibilityLabel(
                snapshot.effectiveState(at: date).accessibilityLabel
            )
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("WE")
                    .font(.caption2.weight(.semibold))
                Text(snapshot.wording(at: date))
                    .font(.caption)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
        default:
            homeSurface
        }
    }

    @ViewBuilder
    private var homeSurface: some View {
        let content = WEHomeSurface(
            snapshot: snapshot,
            date: date,
            isWide: family == .systemMedium
        )

        switch backgroundPresentation {
        case .widgetHost:
            content
                .containerBackground(for: .widget) {
                    WEExternalBackground()
                }
        case .referenceCanvas:
            ZStack {
                WEExternalBackground()
                content
            }
        }
    }
}

private struct WEHomeSurface: View {
    let snapshot: ExternalSurfaceSnapshot
    let date: Date
    let isWide: Bool

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 18) {
                    message
                    WEExternalContinuityMark(
                        state: snapshot.effectiveState(at: date)
                    )
                    .frame(width: 104)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WE")
                        .font(.caption.weight(.medium))
                        .tracking(1.3)
                        .foregroundStyle(Color.weWidgetPearl.opacity(0.78))

                    Spacer(minLength: 0)

                    WEExternalContinuityMark(
                        state: snapshot.effectiveState(at: date)
                    )
                    .frame(height: 18)

                    message
                }
            }
        }
        .padding(isWide ? 18 : 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(snapshot.effectiveState(at: date).accessibilityLabel). "
                + snapshot.wording(at: date)
        )
        .accessibilityHint("Opens Today in WE")
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isWide {
                Text("WE")
                    .font(.caption.weight(.medium))
                    .tracking(1.3)
                    .foregroundStyle(Color.weWidgetPearl.opacity(0.78))
            }
            Text(snapshot.wording(at: date))
                .font(
                    .system(
                        isWide ? .title3 : .body,
                        design: .serif
                    )
                )
                .foregroundStyle(Color.weWidgetPearl)
                .lineLimit(3)
        }
        .padding(.horizontal, isWide ? 12 : 9)
        .padding(.vertical, isWide ? 12 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.weWidgetPrivateInk.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    Color.weWidgetChampagne.opacity(0.28),
                    lineWidth: 1
                )
        }
    }
}

struct WEExternalBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.weWidgetPrivateInk,
                Color.weWidgetDuskBlue.opacity(0.82),
                Color.weWidgetWarmStone.opacity(0.88),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WEExternalContinuityMark: View {
    let state: ExternalSurfaceDisplayState

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let left = size.width * 0.08
            let right = size.width * 0.92
            let champagne = Color.weWidgetChampagne
            let pearl = Color.weWidgetPearl

            switch state {
            case .quiet:
                var path = Path()
                path.move(to: CGPoint(x: left, y: midY))
                path.addCurve(
                    to: CGPoint(x: right, y: midY),
                    control1: CGPoint(
                        x: size.width * 0.36,
                        y: midY - 2
                    ),
                    control2: CGPoint(
                        x: size.width * 0.64,
                        y: midY + 2
                    )
                )
                context.stroke(
                    path,
                    with: .color(pearl.opacity(0.68)),
                    lineWidth: 1.4
                )
            case .roomAvailable:
                var path = Path()
                path.move(to: CGPoint(x: left, y: midY + 2))
                path.addCurve(
                    to: CGPoint(x: right, y: midY - 2),
                    control1: CGPoint(
                        x: size.width * 0.40,
                        y: midY - 8
                    ),
                    control2: CGPoint(
                        x: size.width * 0.60,
                        y: midY + 8
                    )
                )
                context.stroke(
                    path,
                    with: .color(champagne),
                    lineWidth: 1.8
                )
            case .sharedRoomActive:
                let gap = size.width * 0.16
                var leftPath = Path()
                leftPath.move(to: CGPoint(x: left, y: midY))
                leftPath.addLine(
                    to: CGPoint(x: size.width / 2 - gap, y: midY)
                )
                var rightPath = Path()
                rightPath.move(
                    to: CGPoint(x: size.width / 2 + gap, y: midY)
                )
                rightPath.addLine(to: CGPoint(x: right, y: midY))
                context.stroke(
                    leftPath,
                    with: .color(champagne),
                    lineWidth: 1.7
                )
                context.stroke(
                    rightPath,
                    with: .color(pearl),
                    lineWidth: 1.7
                )
            case .resolved:
                var path = Path()
                path.move(
                    to: CGPoint(x: size.width * 0.26, y: midY)
                )
                path.addLine(
                    to: CGPoint(x: size.width * 0.74, y: midY)
                )
                context.stroke(
                    path,
                    with: .color(pearl.opacity(0.44)),
                    lineWidth: 1
                )
            }
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    static let weWidgetPrivateInk = Color(
        red: 23 / 255,
        green: 48 / 255,
        blue: 64 / 255
    )
    static let weWidgetDuskBlue = Color(
        red: 113 / 255,
        green: 132 / 255,
        blue: 151 / 255
    )
    static let weWidgetPearl = Color(
        red: 242 / 255,
        green: 238 / 255,
        blue: 230 / 255
    )
    static let weWidgetWarmStone = Color(
        red: 216 / 255,
        green: 208 / 255,
        blue: 196 / 255
    )
    static let weWidgetChampagne = Color(
        red: 199 / 255,
        green: 162 / 255,
        blue: 88 / 255
    )
}
