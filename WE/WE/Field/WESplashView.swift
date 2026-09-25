// A quiet arrival on paper. Frame zero matches the system launch canvas.
import SwiftUI

@MainActor
struct WESplashView: View {
    var identity: FieldIdentity?
    var isWaiting: () -> Bool
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WECanvas.cream.bg
                VStack(spacing: 28) {
                    WelcomeBloom(
                        diameter: 230,
                        identity: identity,
                        formation: appeared || reduceMotion ? 1 : 0
                    )
                    Text("WE")
                        .font(FieldType.hero(42))
                        .foregroundStyle(.fieldInk(.headline))
                }
                .opacity(appeared ? 1 : 0)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 24)
            }
        }
        .ignoresSafeArea()
        .environment(\.weCanvas, WECanvas.cream)
        .preferredColorScheme(.light)
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
