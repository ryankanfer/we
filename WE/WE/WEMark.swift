import SwiftUI

/// The relationship mark.
///
/// This used to be two overlapping glass circles — a diagram of what
/// `weConfluence` already does for real. The shader is the identity, so the
/// mark is now a masked instance of it: one field at `.micro`, a lozenge at
/// `.display`, converging exactly as far as `connection` says the relationship
/// has converged.
///
/// That removes the last decorative use of Liquid Glass and makes the mark
/// state-aware — it can report waiting, holding, or opening without a caption.
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

    /// How near the two fields sit. Defaults to joined; pass a phase's
    /// `confluenceConnection` to let the mark carry state.
    var connection: CGFloat?

    /// Spoken by VoiceOver in place of the field.
    ///
    /// Previously declared, passed by five callers with real state strings,
    /// and never read — the display mark in `togetherStateCard`, `emptyState`
    /// and `heldState` is often the only thing carrying that state, so it was
    /// silent to VoiceOver.
    var accessibilityText = "WE"

    private var resolvedPersonalHue: WEHue {
        personalHue ?? .burgundy
    }

    private var resolvedConnection: CGFloat {
        connection ?? (joined ? 1 : 0.24)
    }

    private var height: CGFloat {
        switch style {
        case .micro: 16
        case .compact: 34
        case .display: 64
        }
    }

    private var canvasWidth: CGFloat {
        switch style {
        case .micro: 28
        case .compact: 58
        case .display: 148
        }
    }

    var body: some View {
        field
            .frame(width: canvasWidth, height: height)
            .clipShape(shape)
            .overlay {
                shape.stroke(.white.opacity(0.14), lineWidth: 0.5)
            }
            .overlay {
                if showsWordmark {
                    Text("WE")
                        .font(
                            style == .display
                                ? .system(.title2, weight: .bold)
                                : .system(.caption2, weight: .bold)
                        )
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var shape: some InsettableShape {
        Capsule(style: .continuous)
    }

    /// A live shader under 20pt is invisible and not worth the frame, so the
    /// smallest size draws the same two-field idea as a static gradient.
    @ViewBuilder
    private var field: some View {
        if style == .micro {
            LinearGradient(
                colors: [
                    resolvedPersonalHue.atmosphereColor,
                    partnerHue.atmosphereColor
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            WEConfluenceForm(
                personalHue: resolvedPersonalHue,
                partnerHue: partnerHue,
                connection: resolvedConnection
            )
            .background(Color.weSurface)
        }
    }
}

#Preview {
    ZStack {
        Color.weCanvas.ignoresSafeArea()
        VStack(spacing: 28) {
            WEMark(style: .display, personalHue: .burgundy, partnerHue: .sage)
            WEMark(style: .compact, personalHue: .burgundy, partnerHue: .sage)
            WEMark(style: .micro, showsWordmark: false, personalHue: .burgundy)
            WEMark(
                style: .display,
                showsWordmark: false,
                personalHue: .burgundy,
                partnerHue: .sage,
                connection: TrustPhase.open.confluenceConnection,
                accessibilityText: "Nothing has crossed yet"
            )
        }
    }
}
