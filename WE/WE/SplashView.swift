//
//  SplashView.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

struct SplashView: View {
    let extendedWelcome: Bool
    let onFinished: () -> Void

    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var joined = false
    @State private var showsWordmark = false
    @State private var showsIndividualNames = true
    @State private var showsCoupleName = false

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: 0) {
                Text("WE")
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .tracking(4.2)
                    .foregroundStyle(.white.opacity(0.82))
                    .opacity(showsWordmark ? 1 : 0)
                    .offset(y: showsWordmark ? 0 : 6)

                ZStack(alignment: .bottom) {
                    WEConfluenceForm(
                        personalHue: personalHue,
                        connection: joined ? 1 : 0.02
                    )
                    .frame(width: 340, height: 360)
                    .scaleEffect(joined ? 1.04 : 0.94)
                    .animation(
                        reduceMotion
                            ? nil
                            : .timingCurve(
                                0.16,
                                1,
                                0.3,
                                1,
                                duration: extendedWelcome ? 1.45 : 0.78
                            ),
                        value: joined
                    )

                    HStack {
                        Text("Ryan")

                        Spacer()

                        Text("Dylan")
                    }
                    .font(.system(.caption, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.66))
                    .frame(width: 226)
                    .opacity(showsIndividualNames ? 1 : 0)
                    .padding(.bottom, 14)
                }

                Text("Ryan & Dylan")
                    .font(.system(.title3, design: .serif, weight: .regular))
                    .foregroundStyle(.white.opacity(0.84))
                    .opacity(showsCoupleName ? 1 : 0)
                    .offset(y: showsCoupleName ? -4 : 4)

                Text("Two whole people. One shared space.")
                    .font(.footnote)
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.46))
                    .opacity(showsCoupleName && extendedWelcome ? 1 : 0)
                    .offset(y: showsCoupleName ? 8 : 14)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: joined)
        .task {
            if reduceMotion {
                joined = true
                showsWordmark = true
                showsIndividualNames = false
                showsCoupleName = true
            } else {
                try? await Task.sleep(
                    nanoseconds: extendedWelcome ? 550_000_000 : 180_000_000
                )

                withAnimation(
                    .timingCurve(
                        0.16,
                        1,
                        0.3,
                        1,
                        duration: extendedWelcome ? 1.45 : 0.78
                    )
                ) {
                    joined = true
                }

                try? await Task.sleep(
                    nanoseconds: extendedWelcome ? 820_000_000 : 430_000_000
                )

                withAnimation(.easeOut(duration: 0.38)) {
                    showsIndividualNames = false
                    showsWordmark = true
                    showsCoupleName = true
                }
            }

            try? await Task.sleep(
                nanoseconds: extendedWelcome ? 1_650_000_000 : 520_000_000
            )

            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

private struct SplashBackground: View {
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        ZStack {
            Color.weCinematicInk

            RadialGradient(
                colors: [
                    personalHue.color.opacity(0.52),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.24),
                startRadius: 0,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    WEHue.partnerDefault.color.opacity(0.38),
                    .clear
                ],
                center: UnitPoint(x: 0.86, y: 0.78),
                startRadius: 0,
                endRadius: 390
            )

            RadialGradient(
                colors: [
                    .white.opacity(0.09),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView(extendedWelcome: true) {}
}
