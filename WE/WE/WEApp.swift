//
//  WEApp.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

@main
struct WEApp: App {
    @AppStorage("lastExtendedWelcomeDay")
    private var lastExtendedWelcomeDay = ""

    @AppStorage(WEHue.personalStorageKey)
    private var personalHueRawValue = ""

    @State private var showsSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .allowsHitTesting(
                        !showsSplash && !personalHueRawValue.isEmpty
                    )
                    .accessibilityHidden(
                        showsSplash || personalHueRawValue.isEmpty
                    )

                if !showsSplash && personalHueRawValue.isEmpty {
                    HueOnboardingView { hue in
                        withAnimation(.easeInOut(duration: 0.55)) {
                            personalHueRawValue = hue.rawValue
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(5)
                }

                if showsSplash {
                    SplashView(
                        extendedWelcome: lastExtendedWelcomeDay != todayKey
                    ) {
                        lastExtendedWelcomeDay = todayKey

                        withAnimation(.easeOut(duration: 0.5)) {
                            showsSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
    }

    private var todayKey: String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: Date()
        )

        return [
            components.year,
            components.month,
            components.day
        ]
        .map { String($0 ?? 0) }
        .joined(separator: "-")
    }
}
