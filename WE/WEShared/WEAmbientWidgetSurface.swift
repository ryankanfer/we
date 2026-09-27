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

/// The two lights, as the widget's ground: the same burgundy and sage glow
/// that sits under Today, so the home screen and the app are one place.
struct WEExternalBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.035)
            RadialGradient(
                colors: [Color.weWidgetYou.opacity(0.75), Color.weWidgetYou.opacity(0)],
                center: UnitPoint(x: 0.28, y: 1.05),
                startRadius: 0,
                endRadius: 150
            )
            RadialGradient(
                colors: [Color.weWidgetThem.opacity(0.65), Color.weWidgetThem.opacity(0)],
                center: UnitPoint(x: 0.74, y: 1.05),
                startRadius: 0,
                endRadius: 150
            )
        }
    }
}

/// The widget's small mark, in the lights' grammar: two dots that sit
/// apart, drift close, overlap, or settle into one, by what is going on
/// between the two of them.
struct WEExternalContinuityMark: View {
    let state: ExternalSurfaceDisplayState

    var body: some View {
        Canvas { context, size in
            let r = min(size.height, size.width / 3) / 2
            let midY = size.height / 2
            let gap: CGFloat
            switch state {
            case .quiet: gap = r * 2.6
            case .roomAvailable: gap = r * 1.5
            case .sharedRoomActive: gap = r * 0.9
            case .resolved: gap = 0
            }
            let a = CGRect(x: size.width / 2 - gap / 2 - r, y: midY - r, width: r * 2, height: r * 2)
            let b = CGRect(x: size.width / 2 + gap / 2 - r, y: midY - r, width: r * 2, height: r * 2)
            if state == .resolved {
                context.fill(Path(ellipseIn: a), with: .color(Color.weWidgetPearl.opacity(0.7)))
            } else {
                context.fill(Path(ellipseIn: a), with: .color(Color.weWidgetYou))
                context.blendMode = .screen
                context.fill(Path(ellipseIn: b), with: .color(Color.weWidgetThem))
            }
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Burgundy and sage, the two lights. Soft values, for a dark ground.
    static let weWidgetYou = Color(red: 0.706, green: 0.341, blue: 0.416)
    static let weWidgetThem = Color(red: 0.541, green: 0.663, blue: 0.545)

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
