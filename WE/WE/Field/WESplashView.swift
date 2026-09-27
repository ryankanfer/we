// A quiet arrival on paper. Frame zero matches the system launch canvas.
import SwiftUI

@MainActor
struct WESplashView: View {
    var identity: FieldIdentity?
    var isWaiting: () -> Bool
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The icon, coming alive: two lights at the corners drift together and
    /// the app opens around them. Tapping the icon and arriving in Today are
    /// meant to feel like one continuous move.
    @State private var pose: WELightsPose = .apart

    var body: some View {
        ZStack {
            WECanvas.surface.bg
            WELights(identity: identity ?? .seed, pose: pose)
            Text("WE")
                .font(FieldType.mark)
                .tracking(FieldTracking.mark * 2)
                .foregroundStyle(.fieldInk(.headline))
                .opacity(appeared ? 1 : 0)
                .blur(radius: appeared || reduceMotion ? 0 : 6)
        }
        .ignoresSafeArea()
        .environment(\.weCanvas, WECanvas.surface)
        .preferredColorScheme(WETheme.shared.colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("WE")
        .task { await run() }
    }

    private func run() async {
        do {
            try await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.65)) {
                appeared = true
            }
            pose = .near
            try await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 850))
            let deadline = ContinuousClock.now.advanced(by: WESplashGate.holdCeiling)
            while isWaiting(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(80))
            }
            try Task.checkCancellation()
            onFinish()
        } catch {
            // A cancelled splash must never finish a newer presentation.
        }
    }
}

#Preview("Paper arrival") {
    WESplashView(identity: nil, isWaiting: { false }, onFinish: {})
}
