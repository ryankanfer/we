import CoreMotion
import Combine
import SwiftUI
import UIKit

struct LivingConfluencePromise: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var motion = PromiseMotion()
    @State private var beat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var joined = false
    @State private var joinArmed = false
    @State private var hapticTrigger = 0

    private let copy = [
        ("PRIVATE", "Yours stays yours.", "A private reflection begins on your side. You decide whether it ever moves."),
        ("SHARED", "Nothing crosses without both.", "Your partner can come close. The boundary opens only through mutual consent."),
        ("MUTUAL", "What opens, opens together.", "Hold deliberately to join the two fields into WE.")
    ]

    var body: some View {
        ZStack {
            Color.weCinematicInk.ignoresSafeArea()
            promiseField
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.weCinematicInk.opacity(0.7),
                    Color.weCinematicInk.opacity(0.18),
                    Color.weCinematicInk.opacity(0.7),
                    Color.weCinematicInk.opacity(0.98),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 180)
                copyBlock
                action
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private var topBar: some View {
        HStack {
            Text(String(format: "%02d", beat + 1))
                .foregroundStyle(.white.opacity(0.48))
            Text(copy[beat].0)
                .foregroundStyle(.white.opacity(0.76))
            Spacer()
            Button(isLastBeat ? "Close" : "Skip") { onComplete() }
                .foregroundStyle(.white.opacity(0.72))
                .frame(minHeight: 44)
        }
        .font(.caption.weight(.semibold))
        .tracking(1.4)
        .padding(.top, 10)
    }

    private var promiseField: some View {
        GeometryReader { proxy in
            let parallax = reduceMotion ? CGSize.zero : motion.offset
            ZStack {
                WEConfluenceForm(
                    personalHue: .burgundy,
                    partnerHue: .sage,
                    connection: connection
                )
                .opacity(0.78)
                .scaleEffect(1.25)
                .offset(
                    x: parallax.width + dragOffset.width * 0.12,
                    y: parallax.height + dragOffset.height * 0.12
                )

                if beat == 0 {
                    Circle()
                        .fill(.white.opacity(0.001))
                        .frame(
                            width: min(proxy.size.width, 300),
                            height: 300
                        )
                        .contentShape(Circle())
                        .offset(dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { dragOffset = $0.translation }
                                .onEnded { _ in
                                    withAnimation(promiseAnimation) {
                                        dragOffset = .zero
                                    }
                                }
                        )
                        .accessibilityLabel("Private fluid field")
                        .accessibilityHint("Drag to feel your private side respond")
                }
            }
            .animation(promiseAnimation, value: connection)
        }
        .accessibilityElement(children: voiceOverEnabled ? .ignore : .contain)
        .accessibilityLabel(copy[beat].1 + " " + copy[beat].2)
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy[beat].1)
                .font(.weLargeTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Text(copy[beat].2)
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 330, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(beat)
        .transition(.opacity)
    }

    @ViewBuilder
    private var action: some View {
        if isLastBeat {
            if voiceOverEnabled {
                Button {
                    completePromise(delay: 0)
                } label: {
                    Label(
                        "Complete the promise",
                        systemImage: "checkmark"
                    )
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .background(
                    WEHue.burgundy.controlColor,
                    in: RoundedRectangle(cornerRadius: 17)
                )
                .accessibilityHint(
                    "Opens WE after the Private, Shared, and Mutual promise"
                )
                .padding(.top, 26)
            } else {
                Button {
                    if joinArmed {
                        completePromise(delay: reduceMotion ? 0 : 0.45)
                    } else {
                        joinArmed = true
                        hapticTrigger += 1
                    }
                } label: {
                    Label(
                        joined
                            ? "Promise held"
                            : joinArmed
                                ? "Activate again to join"
                                : "Hold to join",
                        systemImage: joined ? "checkmark" : "hand.tap"
                    )
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .background(
                    WEHue.burgundy.controlColor,
                    in: RoundedRectangle(cornerRadius: 17)
                )
                .simultaneousGesture(
                    LongPressGesture(
                        minimumDuration: reduceMotion ? 0.25 : 1.2
                    )
                    .onEnded { _ in
                        completePromise(delay: reduceMotion ? 0 : 0.45)
                    }
                )
                .accessibilityHint(
                    "Press and hold, or activate twice, to complete the promise"
                )
                .padding(.top, 26)
            }
        } else {
            Button {
                hapticTrigger += 1
                withAnimation(promiseAnimation) {
                    beat += 1
                }
            } label: {
                Label("Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(
                WEHue.burgundy.controlColor,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .padding(.top, 26)
        }
    }

    private var connection: CGFloat {
        switch beat {
        case 0: 0.08
        case 1: 0.42
        default: joined ? 1 : 0.62
        }
    }

    private var isLastBeat: Bool { beat == copy.count - 1 }

    private var promiseAnimation: Animation? {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .weSettle(duration: 0.8, reduceMotion: false)
    }

    private func completePromise(delay: TimeInterval) {
        guard !joined else { return }
        joined = true
        hapticTrigger += 1
        if delay == 0 {
            onComplete()
        } else {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: onComplete
            )
        }
    }
}

@MainActor
private final class PromiseMotion: ObservableObject {
    @Published var offset: CGSize = .zero
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.offset = CGSize(
                width: motion.attitude.roll * 10,
                height: motion.attitude.pitch * 10
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

#Preview {
    LivingConfluencePromise(onComplete: {})
}
