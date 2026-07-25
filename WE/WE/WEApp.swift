//
//  WEApp.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

@main
struct WEApp: App {
    @StateObject private var session: AppSession

    @AppStorage("lastExtendedWelcomeDay")
    private var lastExtendedWelcomeDay = ""

    @AppStorage(WEHue.personalStorageKey)
    private var personalHueRawValue = ""

    @State private var showsSplash = true

    init() {
        _session = StateObject(
            wrappedValue: AppSession(
                repository: RepositoryFactory.make()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(session)
                    .allowsHitTesting(!isCovered || !session.isReady)
                    .accessibilityHidden(isCovered && session.isReady)

                // First run asks for a color before anything else, so the
                // splash that follows is already lit in the user's own hue.
                if session.isReady && needsOnboarding {
                    HueOnboardingView { hue in
                        withAnimation(.easeInOut(duration: 0.55)) {
                            personalHueRawValue = hue.rawValue
                        }
                    }
                    .transition(
                        .opacity.combined(with: .scale(scale: 1.02))
                    )
                    .zIndex(10)
                } else if session.isReady && showsSplash {
                    SplashView(
                        extendedWelcome: lastExtendedWelcomeDay != todayKey
                    ) {
                        lastExtendedWelcomeDay = todayKey

                        withAnimation(.easeOut(duration: 0.5)) {
                            showsSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(5)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: needsOnboarding)
            .task {
                await session.restoreIfNeeded()
            }
        }
    }

    private var needsOnboarding: Bool {
        personalHueRawValue.isEmpty
    }

    private var isCovered: Bool {
        session.isReady && (needsOnboarding || showsSplash)
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
