import SwiftUI

extension TrustPhase {
    /// How near the two fields sit while the relationship is in this phase.
    ///
    /// The confluence is not decoration — `connection` *is* the state display.
    /// Two separate fields drift at `open` and merge into one at `revealed`,
    /// so the surface shows how far a thing has travelled toward being shared
    /// before a single word of copy is read.
    var confluenceConnection: CGFloat {
        switch self {
        case .hidden: 0.18
        case .open: 0.18
        case .declined: 0.24
        case .waiting: 0.30
        case .invited: 0.30
        case .answering: 0.44
        case .held: 0.62
        case .revealed: 1
        case .resolved: 1
        }
    }
}

struct WEConfluenceForm: View, Animatable {
    var personalHue: WEHue
    var partnerHue: WEHue = .partnerDefault
    var connection: CGFloat = 1

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.scenePhase)
    private var scenePhase

    var animatableData: CGFloat {
        get { connection }
        set { connection = newValue }
    }

    /// The shader is a continuous 30fps GPU pass. It has no reason to run
    /// while the app is backgrounded or while Reduce Motion holds it on a
    /// fixed frame.
    private var isPaused: Bool {
        reduceMotion || scenePhase != .active
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: isPaused
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
        Color.weCanvas.ignoresSafeArea()

        WEConfluenceForm(
            personalHue: .burgundy,
            connection: 1
        )
        .frame(height: 380)
    }
}
