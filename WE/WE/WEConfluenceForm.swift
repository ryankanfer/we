import SwiftUI

struct WEConfluenceForm: View, Animatable {
    var personalHue: WEHue
    var partnerHue: WEHue = .partnerDefault
    var connection: CGFloat = 1

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var animatableData: CGFloat {
        get { connection }
        set { connection = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: reduceMotion
                )
            ) { context in
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.weConfluence(
                            .float2(proxy.size),
                            .float(animationTime(context.date)),
                            .color(personalHue.color),
                            .color(partnerHue.color),
                            .float(connection)
                        )
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func animationTime(_ date: Date) -> Double {
        guard !reduceMotion else { return 2.4 }

        return date
            .timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 10_000)
    }
}

#Preview {
    ZStack {
        Color.weCinematicInk.ignoresSafeArea()

        WEConfluenceForm(
            personalHue: .burgundy,
            connection: 1
        )
        .frame(height: 380)
    }
}
