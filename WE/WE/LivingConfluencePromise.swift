import SwiftUI

/// The trust promise shown after account creation.
///
/// Two people remain visually intact throughout. The final beat creates a
/// third shared clearing between them; it never depicts one person merging
/// into the other.
struct LivingConfluencePromise: View {
    private struct Beat {
        let eyebrow: String
        let title: String
        let detail: String
        let state: WEJourneyState
    }

    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var beat = 0
    @State private var hapticTrigger = 0

    private let beats = [
        Beat(
            eyebrow: "MINE",
            title: "Yours stays yours.",
            detail: "A thought begins on your side. You decide whether any prepared wording ever leaves it.",
            state: .privateState
        ),
        Beat(
            eyebrow: "OFFERED",
            title: "You see what crosses.",
            detail: "WE shows the exact topic first. Nothing moves past the threshold until you approve it.",
            state: .offerPreview
        ),
        Beat(
            eyebrow: "OURS",
            title: "Shared is a new space.",
            detail: "Your answers remain private. When both of you consent, WE opens a direction between two intact sides.",
            state: .shared
        ),
    ]

    var body: some View {
        ZStack {
            WEJourneyBackdrop(state: current.state)

            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                        Spacer(minLength: 24)
                        architecture
                        Spacer(minLength: 28)
                        copyBlock
                        action
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(0, viewport.size.height - 40),
                        alignment: .topLeading
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(
            current.state == .privateState ? .dark : .light
        )
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private var topBar: some View {
        let palette = WEJourneyPalette.palette(for: current.state)
        return HStack {
            Text(String(format: "%02d", beat + 1))
            Text(current.eyebrow)
            Spacer()
            Button(isLastBeat ? "Close" : "Skip", action: onComplete)
                .frame(minHeight: 44)
        }
        .font(.caption.weight(.semibold))
        .tracking(1.4)
        .foregroundStyle(palette.secondaryInk)
    }

    private var architecture: some View {
        let palette = WEJourneyPalette.palette(for: current.state)
        return VStack(spacing: 18) {
            HStack(spacing: 16) {
                side(
                    title: "Mine",
                    color: .weDuskBlue,
                    palette: palette
                )

                if current.state == .shared {
                    VStack(spacing: 8) {
                        Text("Ours")
                            .font(.weMeta)
                            .tracking(1.2)
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.62))
                            .overlay {
                                Image(systemName: "arrow.left.and.right")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.weSharedOlive)
                            }
                    }
                    .foregroundStyle(palette.secondaryInk)
                    .frame(maxWidth: 92)
                    .transition(.opacity)
                } else {
                    Rectangle()
                        .fill(
                            current.state == .offerPreview
                                ? Color.weChampagne
                                : palette.secondaryInk.opacity(0.22)
                        )
                        .frame(width: 1)
                        .accessibilityLabel(
                            current.state == .offerPreview
                                ? "Consent threshold"
                                : "Private boundary"
                        )
                }

                side(
                    title: "Theirs",
                    color: .weChampagne,
                    palette: palette
                )
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 160 : 250)

            WEContinuityLine(state: current.state)
                .frame(height: 64)
        }
        .animation(
            reduceMotion ? nil : .weSettle(duration: 0.45),
            value: beat
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.state.accessibilityDescription)
    }

    private func side(
        title: String,
        color: Color,
        palette: WEJourneyPalette
    ) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.weMeta)
                .tracking(1.2)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.secondaryBackground.opacity(0.28))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(color)
                        .frame(width: 2)
                        .padding(.vertical, 24)
                }
                .overlay {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                }
        }
        .foregroundStyle(palette.secondaryInk)
        .frame(maxWidth: .infinity)
    }

    private var copyBlock: some View {
        let palette = WEJourneyPalette.palette(for: current.state)
        return VStack(alignment: .leading, spacing: 10) {
            Text(current.title)
                .font(.weLargeTitle)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(current.detail)
                .font(.weBody)
                .foregroundStyle(palette.secondaryInk)
                .frame(maxWidth: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(beat)
        .transition(.opacity)
    }

    private var action: some View {
        Button(isLastBeat ? "Enter WE" : "Continue") {
            if isLastBeat {
                onComplete()
            } else {
                hapticTrigger += 1
                withAnimation(
                    reduceMotion
                        ? nil
                        : .weSettle(duration: 0.4)
                ) {
                    beat += 1
                }
            }
        }
        .buttonStyle(WEJourneyPrimaryButtonStyle(state: current.state))
        .padding(.top, 26)
        .accessibilityHint(
            isLastBeat
                ? "Completes the privacy and consent promise"
                : "Shows the next privacy and consent promise"
        )
    }

    private var current: Beat { beats[beat] }
    private var isLastBeat: Bool { beat == beats.count - 1 }
}

#Preview {
    LivingConfluencePromise(onComplete: {})
}
