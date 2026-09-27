// A quiet arrival on paper. Frame zero matches the system launch canvas.
import SwiftUI

@MainActor
struct WESplashView: View {
    var identity: FieldIdentity?
    var isWaiting: () -> Bool
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The icon, coming alive. Frame zero is the icon itself: burgundy and
    /// sage overlapping in the middle of the launch surface. Then the two
    /// lights take on the couple's own colours and settle to the bottom
    /// edge, where they live for the rest of the app.
    @State private var pose: WELightsPose = .icon
    @State private var shownIdentity: FieldIdentity = .seed

    var body: some View {
        ZStack {
            WECanvas.surface.bg
            WELights(identity: shownIdentity, pose: pose)
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
            try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 220))
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.9)) {
                shownIdentity = identity ?? .seed
            }
            pose = .near
            try await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 950))
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
