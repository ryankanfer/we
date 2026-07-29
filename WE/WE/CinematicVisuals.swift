import SwiftUI

/// The three pieces of original artwork that carry WE's cinematic language.
///
/// They are deliberately content-free: SwiftUI owns every word and control,
/// so Dynamic Type, VoiceOver, localization, and state changes remain native.
enum WECinematicArtwork: String {
    case confluence = "WEConfluenceHero"
    case vessel = "WEQuietVessel"
    case horizon = "WESharedHorizon"
}

/// Displays cinematic artwork while guaranteeing a quiet edge for live type.
struct WECinematicArt: View {
    let artwork: WECinematicArtwork
    var height: CGFloat = 300
    var focalPoint: UnitPoint = .center
    var intensity: Double = 1

    var body: some View {
        GeometryReader { proxy in
            Image(artwork.rawValue)
                .resizable()
                .scaledToFill()
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: Alignment(
                        horizontal: focalPoint.x < 0.5
                            ? .leading
                            : focalPoint.x > 0.5
                                ? .trailing
                                : .center,
                        vertical: focalPoint.y < 0.5
                            ? .top
                            : focalPoint.y > 0.5
                                ? .bottom
                                : .center
                    )
                )
                .clipped()
                .opacity(intensity)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: Color.weCanvas.opacity(0.76), location: 0),
                            .init(color: .clear, location: 0.18),
                            .init(color: .clear, location: 0.76),
                            .init(color: Color.weCanvas.opacity(0.9), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.weCanvas.opacity(0.42),
                            .clear,
                            Color.weCanvas.opacity(0.42),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A viewport-sized cinematic stage.
///
/// Artwork is always decorative and may bleed to the edge. Live content stays
/// native SwiftUI so it can wrap, scale, and grow beyond `minHeight` when
/// Dynamic Type needs more room.
struct WECinematicFocusScene<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let artwork: WECinematicArtwork
    let minHeight: CGFloat
    var focalPoint: UnitPoint = .center
    var intensity: Double = 1
    private let content: Content

    init(
        artwork: WECinematicArtwork,
        minHeight: CGFloat,
        focalPoint: UnitPoint = .center,
        intensity: Double = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.artwork = artwork
        self.minHeight = minHeight
        self.focalPoint = focalPoint
        self.intensity = intensity
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.weCanvas

            GeometryReader { proxy in
                WECinematicArt(
                    artwork: artwork,
                    height: max(proxy.size.height, minHeight),
                    focalPoint: focalPoint,
                    intensity: intensity
                )
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )

                LinearGradient(
                    stops: [
                        .init(
                            color: Color.weCanvas.opacity(topScrimOpacity),
                            location: 0
                        ),
                        .init(color: .clear, location: 0.24),
                        .init(color: .clear, location: 0.52),
                        .init(
                            color: Color.weCanvas.opacity(bottomScrimOpacity),
                            location: 1
                        ),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .accessibilityHidden(true)
            }
            .allowsHitTesting(false)

            content
                .frame(
                    maxWidth: .infinity,
                    minHeight: minHeight,
                    alignment: .topLeading
                )
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(Color.weCanvas)
    }

    private var topScrimOpacity: Double {
        if reduceTransparency || contrast == .increased { return 0.94 }
        return 0.78
    }

    private var bottomScrimOpacity: Double {
        if reduceTransparency || contrast == .increased { return 0.98 }
        return 0.93
    }
}

/// A render-faithful hero: one image, one thought, and generous negative space.
struct WECinematicHero: View {
    let artwork: WECinematicArtwork
    let eyebrow: String
    let title: String
    var detail: String?
    var height: CGFloat = 410
    var titleAlignment: HorizontalAlignment = .leading

    var body: some View {
        ZStack(alignment: titleAlignment == .leading ? .bottomLeading : .bottom) {
            WECinematicArt(
                artwork: artwork,
                height: height,
                focalPoint: artwork == .horizon ? .bottom : .center
            )

            VStack(alignment: titleAlignment, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.weMeta)
                    .tracking(1.8)
                    .foregroundStyle(Color.weInkTertiary)

                Text(title)
                    .font(.weLargeTitle)
                    .foregroundStyle(Color.weInk)
                    .multilineTextAlignment(
                        titleAlignment == .leading ? .leading : .center
                    )
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.weSubheadline)
                        .foregroundStyle(Color.weInkSecondary)
                        .multilineTextAlignment(
                            titleAlignment == .leading ? .leading : .center
                        )
                        .frame(maxWidth: 330, alignment: titleAlignment == .leading ? .leading : .center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(
                maxWidth: .infinity,
                alignment: titleAlignment == .leading ? .leading : .center
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color.weCanvas)
        .accessibilityElement(children: .combine)
    }
}

/// A compact title treatment shared by the three primary destinations.
struct WEEditorialScreenHeader: View {
    let title: String
    let profileName: String
    var actionSystemImage: String?
    var actionAccessibilityLabel: String?
    var actionEnabled = true
    var onAction: (() -> Void)?
    let onProfile: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WE")
                    .font(.weMeta)
                    .tracking(1.8)
                    .foregroundStyle(Color.weInkTertiary)

                Text(title)
                    .font(.weLargeTitle)
                    .foregroundStyle(Color.weInk)
            }

            Spacer(minLength: 12)

            if let actionSystemImage, let onAction {
                Button(action: onAction) {
                    Image(systemName: actionSystemImage)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.weInkSecondary)
                        .frame(width: 44, height: 44)
                        .background(
                            Color.weSurfaceRaised.opacity(0.84),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.weHairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!actionEnabled)
                .accessibilityLabel(actionAccessibilityLabel ?? "More")
            }

            Button(action: onProfile) {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.weInk)
                    .frame(width: 44, height: 44)
                    .background(
                        Color.weSurfaceRaised.opacity(0.84),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.weHairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Profile")
            .accessibilityHint("Account, appearance, archives, and privacy")
            .accessibilityIdentifier("profileButton")
        }
    }

    private var initials: String {
        let value = profileName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return value.isEmpty ? "ME" : value.uppercased()
    }
}

struct WECinematicPanel<Content: View>: View {
    var padding: CGFloat = 18
    private let content: Content

    init(
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.weSurface.opacity(0.82),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.weHairline.opacity(0.82), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.26), radius: 22, y: 10)
    }
}

struct WEFocusPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                Color.weCanvas.opacity(isEnabled ? 1 : 0.58)
            )
            .background(
                Color.weInk.opacity(isEnabled ? 0.94 : 0.46),
                in: Capsule()
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.985
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.weQuick, value: configuration.isPressed)
    }
}
