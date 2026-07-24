import SwiftUI

struct HueOnboardingView: View {
    let onComplete: (WEHue) -> Void

    @State private var selection: WEHue = .burgundy
    @State private var phase: Phase = .personal

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private enum Phase: Hashable {
        case personal
        case shared
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HueAtmosphere(personalHue: selection)

                ScrollView {
                    VStack(spacing: 0) {
                        header

                        WEConfluenceForm(
                            personalHue: selection,
                            connection: phase == .personal ? 0.18 : 1
                        )
                        .frame(height: phase == .personal ? 330 : 390)
                        .scaleEffect(phase == .personal ? 0.94 : 1.04)
                        .padding(.top, phase == .personal ? 2 : -16)
                        .gesture(colorSwipe)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            phase == .personal
                                ? "\(selection.name), Ryan’s selected color"
                                : "Ryan and Dylan’s shared atmosphere"
                        )

                        editorialCopy
                            .padding(.top, phase == .personal ? -8 : -22)

                        if phase == .personal {
                            HueSelector(selection: $selection)
                                .padding(.top, 24)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            sharedLegend
                                .padding(.top, 24)
                                .transition(.opacity)
                        }

                        actionButton
                            .padding(.top, 26)

                        if phase == .personal {
                            Text("You can change this later in Appearance.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.46))
                                .padding(.top, 12)
                        }

                        Spacer(minLength: 22)
                    }
                    .frame(maxWidth: 430)
                    .frame(
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .medium), trigger: phase)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 12) {
                Text(phase == .personal ? "01" : "02")
                    .foregroundStyle(.white.opacity(0.42))

                Text(
                    phase == .personal
                        ? "YOUR COLOR"
                        : "OUR ATMOSPHERE"
                )
                .foregroundStyle(.white.opacity(0.7))
            }
            .fixedSize()

            Spacer(minLength: 16)

            Text("WE")
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize()
        }
        .font(.system(.caption2, weight: .semibold))
        .tracking(1.5)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    @ViewBuilder
    private var editorialCopy: some View {
        VStack(spacing: 10) {
            Text(
                phase == .personal
                    ? "Choose yours."
                    : "Yours. Dylan’s. Ours."
            )
            .font(.system(size: 38, weight: .regular, design: .serif))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Text(
                phase == .personal
                    ? "A color for your side of WE."
                    : "This is the atmosphere you create together."
            )
            .font(.system(.subheadline, weight: .regular))
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(.center)
        }
        .id(phase)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 12)),
                    removal: .opacity.combined(with: .offset(y: -8))
                )
        )
    }

    private var sharedLegend: some View {
        HStack(spacing: 14) {
            personLabel("RYAN", hue: selection)

            Image(systemName: "plus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.36))

            personLabel("DYLAN", hue: .partnerDefault)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Ryan’s \(selection.name) and Dylan’s \(WEHue.partnerDefault.name)"
        )
    }

    private func personLabel(
        _ name: String,
        hue: WEHue
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hue.color)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.44), lineWidth: 0.5)
                }

            Text(name)
                .font(.system(.caption2, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .glassEffect(
            .regular,
            in: Capsule()
        )
    }

    private var actionButton: some View {
        Button {
            if phase == .personal {
                withAnimation(
                    reduceMotion
                        ? .linear(duration: 0.01)
                        : .timingCurve(
                            0.16,
                            1,
                            0.3,
                            1,
                            duration: 0.82
                        )
                ) {
                    phase = .shared
                }
            } else {
                onComplete(selection)
            }
        } label: {
            HStack(spacing: 16) {
                Text(
                    phase == .personal
                        ? "Make it mine"
                        : "Enter WE"
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .font(.system(.body, weight: .semibold))
            .padding(.leading, 22)
            .padding(.trailing, 8)
            .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .tint(selection.controlColor)
        .accessibilityHint(
            phase == .personal
                ? "Reveals the atmosphere Ryan and Dylan create together"
                : "Finishes appearance setup"
        )
    }

    private var colorSwipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard phase == .personal else { return }
                guard abs(value.translation.width) > 35 else { return }

                moveSelection(
                    value.translation.width < 0 ? 1 : -1
                )
            }
    }

    private func moveSelection(_ offset: Int) {
        let hues = WEHue.pickerOrder
        guard let currentIndex = hues.firstIndex(of: selection) else {
            selection = hues[0]
            return
        }

        let nextIndex = (
            currentIndex + offset + hues.count
        ) % hues.count

        withAnimation(
            reduceMotion
                ? nil
                : .timingCurve(0.16, 1, 0.3, 1, duration: 0.5)
        ) {
            selection = hues[nextIndex]
        }
    }
}

struct HueSettingsView: View {
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = WEHue.burgundy.rawValue

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var selection: Binding<WEHue> {
        Binding {
            WEHue.stored(storedPersonalHue)
        } set: { hue in
            withAnimation(
                reduceMotion
                    ? nil
                    : .timingCurve(0.16, 1, 0.3, 1, duration: 0.5)
            ) {
                storedPersonalHue = hue.rawValue
            }
        }
    }

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        ZStack {
            HueAtmosphere(personalHue: personalHue)

            ScrollView {
                VStack(spacing: 0) {
                    Text("YOUR COLOR")
                        .font(.system(.caption2, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.top, 20)

                    WEConfluenceForm(
                        personalHue: personalHue,
                        connection: 1
                    )
                    .frame(height: 360)
                    .padding(.top, -2)
                    .gesture(colorSwipe)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Ryan and Dylan’s shared atmosphere"
                    )

                    Text("Your color.")
                        .font(.system(size: 38, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.top, -24)

                    Text("Only you choose this.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.top, 8)

                    HueSelector(selection: selection)
                        .padding(.top, 24)

                    VStack(spacing: 8) {
                        Text("OUR ATMOSPHERE")
                            .font(.system(.caption2, weight: .semibold))
                            .tracking(1.4)

                        Text("Created from both of you.")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 28)

                    Spacer(minLength: 44)
                }
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.selection, trigger: personalHue)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var colorSwipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard abs(value.translation.width) > 35 else { return }

                moveSelection(
                    value.translation.width < 0 ? 1 : -1
                )
            }
    }

    private func moveSelection(_ offset: Int) {
        let hues = WEHue.pickerOrder
        guard let currentIndex = hues.firstIndex(of: personalHue) else {
            selection.wrappedValue = hues[0]
            return
        }

        let nextIndex = (
            currentIndex + offset + hues.count
        ) % hues.count

        selection.wrappedValue = hues[nextIndex]
    }
}

private struct HueSelector: View {
    @Binding var selection: WEHue

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let hues = WEHue.pickerOrder

    var body: some View {
        HStack(spacing: 14) {
            arrowButton(
                symbol: "arrow.left",
                label: "Previous color",
                offset: -1
            )

            VStack(spacing: 3) {
                Text(selection.name)
                    .font(.system(.title3, design: .serif, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                Text(positionLabel)
                    .font(.system(.caption2, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.46))
            }
            .frame(width: 150)
            .frame(minHeight: 52)
            .id(selection)
            .transition(.opacity)

            arrowButton(
                symbol: "arrow.right",
                label: "Next color",
                offset: 1
            )
        }
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: 0.26),
            value: selection
        )
        .accessibilityElement(children: .contain)
    }

    private var positionLabel: String {
        let position = (hues.firstIndex(of: selection) ?? 0) + 1
        return "\(position) OF \(hues.count)"
    }

    private func arrowButton(
        symbol: String,
        label: String,
        offset: Int
    ) -> some View {
        Button {
            moveSelection(offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(.body, weight: .medium))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.glass)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
        .accessibilityValue(selection.name)
    }

    private func moveSelection(_ offset: Int) {
        guard let currentIndex = hues.firstIndex(of: selection) else {
            selection = hues[0]
            return
        }

        let nextIndex = (
            currentIndex + offset + hues.count
        ) % hues.count

        withAnimation(
            reduceMotion
                ? nil
                : .timingCurve(0.16, 1, 0.3, 1, duration: 0.5)
        ) {
            selection = hues[nextIndex]
        }
    }
}

private struct HueAtmosphere: View {
    let personalHue: WEHue

    var body: some View {
        ZStack {
            Color.weCinematicInk

            RadialGradient(
                colors: [
                    personalHue.atmosphereColor.opacity(0.34),
                    .clear
                ],
                center: UnitPoint(x: 0.08, y: 0.12),
                startRadius: 0,
                endRadius: 430
            )

            RadialGradient(
                colors: [
                    WEHue.partnerDefault.color.opacity(0.25),
                    .clear
                ],
                center: UnitPoint(x: 0.92, y: 0.82),
                startRadius: 0,
                endRadius: 460
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.08),
                    .clear,
                    .black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(
            .timingCurve(0.16, 1, 0.3, 1, duration: 0.72),
            value: personalHue
        )
        .ignoresSafeArea()
    }
}

#Preview("First-run color") {
    HueOnboardingView { _ in }
}
