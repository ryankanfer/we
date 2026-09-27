//
//  FirstRunKit.swift
//  WE
//
//  One frame for every screen before a couple exists: welcome, the account
//  sheet, pairing, the invitation and the invited person's first screen.
//
//  They were five separate layouts — a full-bleed scroll, a sheet with its
//  own header, a centred scaffold, underlined text buttons, uppercase
//  outlined buttons — so moving from one to the next felt like changing
//  apps. Here they share:
//
//    - the same paper, margins and headline size
//    - one primary button (ink, full width, pinned to the bottom where the
//      thumb is) and one secondary (outlined, same size)
//    - a quiet text link for everything else
//    - cards for things you can pick or keep: a choice, a code
//
//  Content scrolls; the actions do not. Nobody should have to scroll to find
//  the one thing a screen is asking them to do.
//

import SwiftUI

/// A first-run screen: optional top bar, a headline, content, and actions
/// pinned to the bottom.
struct FirstRunScreen<Hero: View, Content: View, Actions: View>: View {
    var title: String
    var subtitle: String?
    var lights: WELightsPose = .apart
    var showsTheirPlace = false
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        lights: WELightsPose = .apart,
        showsTheirPlace: Bool = false,
        @ViewBuilder hero: () -> Hero = { EmptyView() },
        @ViewBuilder content: () -> Content = { EmptyView() },
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.lights = lights
        self.showsTheirPlace = showsTheirPlace
        self.hero = hero()
        self.content = content()
        self.actions = actions()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                hero
                FirstRunHeadline(title: title, subtitle: subtitle)
                    .modifier(FirstRunArrival(visible: arrived, delay: 0))
                content
                    .modifier(FirstRunArrival(visible: arrived, delay: 0.08))
            }
            .frame(maxWidth: FirstRunMetrics.column, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FirstRunMetrics.side)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) { actions }
                .frame(maxWidth: FirstRunMetrics.column)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, FirstRunMetrics.side)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .background {
                    LinearGradient(
                        colors: [WECanvas.surface.bg.opacity(0), WECanvas.surface.bg.opacity(0.85)],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.35)
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
                .modifier(FirstRunArrival(visible: arrived, delay: 0.16))
        }
        // The two lights, apart: before there is a couple, there are two
        // people at opposite corners of the same ground.
        .background {
            ZStack {
                WECanvas.surface.bg
                WELights(identity: .seed, pose: lights, showsTheirPlace: showsTheirPlace)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(.fieldInk(.headline))
        .environment(\.weCanvas, .surface)
        .preferredColorScheme(WETheme.shared.colorScheme)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { arrived = true }
        }
    }
}

enum FirstRunMetrics {
    static let side: CGFloat = 24
    static let column: CGFloat = 440
    static let radius: CGFloat = 18
}

struct FirstRunHeadline: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WEWordReveal(
                text: title.replacingOccurrences(of: "\n", with: " "),
                font: FieldType.hero,
                tracking: -0.4,
                lineSpacing: 2
            )
            .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .weArrival(delay: 0.3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Buttons

/// Ink, full width, 56pt. The one thing the screen is asking for.
struct FirstRunPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(WECanvas.surface.bg)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(WECanvas.surface.ink, in: Capsule())
            .shadow(color: .black.opacity(WECanvas.surface.isDark ? 0.35 : 0.12), radius: 16, y: 8)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// The same size, outlined. The other real choice, never a lesser button.
struct FirstRunSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .foregroundStyle(WECanvas.surface.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .weGlass(in: Capsule(), interactive: true)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// Everything else: small, inked, 44pt tall.
struct FirstRunLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(WECanvas.surface.ink.opacity(configuration.isPressed ? 0.5 : 0.78))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// "Already have an account? Sign in" — a prompt and its link on one line.
struct FirstRunPromptLink: View {
    let prompt: String
    let link: String
    var identifier: String?
    var action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.fieldInk(.reasoning))
            Button(link, action: action)
                .buttonStyle(FirstRunLinkStyle())
                .underline()
                .accessibilityIdentifier(identifier ?? "")
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Cards

/// A raised panel on the paper.
struct FirstRunCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .weGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A card you pick: a mark, a line, what it does, and a chevron.
struct FirstRunChoiceCard: View {
    let symbol: String
    let title: String
    let detail: String
    var isWorking = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FirstRunCard {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .regular))
                        .frame(width: 44, height: 44)
                        .background(WECanvas.surface.ink.opacity(0.06), in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(FieldType.listItemLarge)
                            .foregroundStyle(.fieldInk(.headline))
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Group {
                        if isWorking { ProgressView() }
                        else { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)) }
                    }
                    .foregroundStyle(.fieldInk(.reasoning))
                    .frame(height: 44)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(FirstRunPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// A slight press for whole cards.
struct FirstRunPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct FirstRunArrival: ViewModifier {
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(delay), value: visible)
    }
}
