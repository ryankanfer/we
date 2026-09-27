//
//  WETheme.swift
//  WE
//
//  Paper by day, dark by night, or either all the time.
//
//  The app was drawn on two grounds already: warm paper (`WECanvas.cream`)
//  for the practical surfaces and warm ink black (`WECanvas.ground`) for the
//  ceremonial ones. This makes the paper surfaces follow a choice instead:
//  every screen that used to name `.cream` now names `.surface`, which is
//  paper or ink black depending on the person's Appearance setting.
//
//  Ceremonial surfaces that are dark by nature (the crossing, the departure,
//  the stillness) still name `.ground` and stay dark in every mode. They are
//  moments, and a moment is allowed to dim the lights.
//
//  WHY A SHARED OBJECT RATHER THAN AN ENVIRONMENT VALUE
//
//  About two hundred call sites read `WECanvas.cream.ink` and friends as a
//  plain static, including button styles and places with no view
//  environment. `WECanvas.surface` is a static too, but it reads an
//  `@Observable` object, so any view whose body reads it redraws when the
//  appearance changes. No call site had to learn about the environment.
//

import Combine
import Observation
import SwiftUI
import UIKit

enum WEAppearance: String, CaseIterable, Identifiable, Sendable {
    /// Follows the iPhone's own Light and Dark setting, which can itself
    /// switch at sunset. Paper by day, dark by night, with no clock of ours.
    case auto
    case paper
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .paper: "Paper"
        case .dark: "Dark"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Follows your iPhone. Set it to switch at sunset for paper by day, dark by night."
        case .paper: "Warm paper, all the time."
        case .dark: "Dark, all the time."
        }
    }
}

@Observable
final class WETheme {
    static let shared = WETheme()

    static let defaultsKey = "we.appearance"

    var appearance: WEAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.defaultsKey)
            resolve()
        }
    }

    /// Whether the app is drawing its dark ground right now.
    private(set) var isNight: Bool = false

    @ObservationIgnored private var systemIsDark = false

    private init() {
        appearance = UserDefaults.standard.string(forKey: Self.defaultsKey)
            .flatMap(WEAppearance.init(rawValue:)) ?? .auto
        refreshFromSystem()
    }

    /// The paper surfaces' ground, resolved.
    var surface: WECanvas { isNight ? .ground : .cream }

    /// What every paper surface asks the window for. Never nil: the app
    /// always states its scheme, so a sheet can never inherit the wrong one.
    var colorScheme: ColorScheme { isNight ? .dark : .light }

    /// Reads the system's own Light or Dark setting.
    ///
    /// From the screen rather than from a view's environment: every surface
    /// in the app sets `preferredColorScheme`, which overrides the window, so
    /// the environment only ever reports what the app itself asked for.
    /// The screen's traits are the system's and nobody else's.
    func refreshFromSystem() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let style = (scene?.traitCollection ?? UITraitCollection.current).userInterfaceStyle
        systemIsDark = style == .dark
        resolve()
    }

    private func resolve() {
        let night = appearance == .dark || (appearance == .auto && systemIsDark)
        if night != isNight { isNight = night }
    }
}

extension WECanvas {
    /// Paper or ink black, by the person's Appearance setting. Use this for
    /// every surface that is not ceremonial by nature.
    static var surface: WECanvas { WETheme.shared.surface }

    /// Whether this ground is a dark one.
    var isDark: Bool { self != .cream }
}

// MARK: - Keeping Auto honest

/// Re-reads the system's appearance whenever the app comes forward, and
/// every half minute while it is up, so a sunset switch lands without a
/// relaunch. Cheap: one trait read, and nothing redraws unless it changed.
struct WEThemeWatcher: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { WETheme.shared.refreshFromSystem() }
            }
            .onReceive(tick) { _ in
                if WETheme.shared.appearance == .auto {
                    WETheme.shared.refreshFromSystem()
                }
            }
    }
}

extension View {
    /// At the scene root only.
    func weThemeRoot() -> some View {
        modifier(WEThemeWatcher())
            .preferredColorScheme(WETheme.shared.colorScheme)
    }
}

// MARK: - The setting

/// Three glass segments. Choosing one changes the light immediately, which
/// is the preview.
struct WEAppearancePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    private var theme: WETheme { WETheme.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(WEAppearance.allCases) { option in
                    Button {
                        withAnimation(reduceMotion ? nil : .weCanvasCrossing) {
                            theme.appearance = option
                        }
                    } label: {
                        Text(option.title)
                            .font(FieldType.button)
                            .foregroundStyle(.fieldInk(theme.appearance == option ? .headline : .reasoning))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                if theme.appearance == option {
                                    Capsule()
                                        .fill(WECanvas.surface.bgElevated)
                                        .matchedGeometryEffect(id: "appearance", in: selection)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme.appearance == option ? .isSelected : [])
                    .accessibilityIdentifier("field.account.appearance.\(option.rawValue)")
                }
            }
            .padding(4)
            .weGlass(in: Capsule())

            Text(theme.appearance.detail)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }
}
