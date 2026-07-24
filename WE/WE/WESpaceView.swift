//
//  WESpaceDestination.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//


import SwiftUI

enum WESpaceDestination: String, CaseIterable, Identifiable, Hashable {
    case now = "Now"
    case us = "Us"
    case life = "Life"
    case plans = "Plans"
    case memories = "Memories"
    case reflections = "Private reflections"
    case appearance = "Appearance"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .now: "sun.max"
        case .us: "circle.hexagongrid"
        case .life: "house"
        case .plans: "calendar"
        case .memories: "photo"
        case .reflections: "lock"
        case .appearance: "paintpalette"
        }
    }
}

struct WESpaceView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WESpaceBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 56)

                        WEConfluenceForm(
                            personalHue: personalHue,
                            connection: 1
                        )
                        .frame(height: 260)
                        .padding(.bottom, -30)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "Ryan and Dylan’s shared atmosphere"
                        )

                        VStack(spacing: 8) {
                            Text("Your shared space.")
                                .font(.weLargeTitle)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            Text("Two whole people. One shared space.")
                                .font(.weBody)
                                .foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                        }

                        GlassEffectContainer(spacing: 12) {
                            VStack(spacing: 12) {
                                ForEach(WESpaceDestination.allCases) { destination in
                                    destinationButton(destination)
                                }
                            }
                        }
                        .frame(maxWidth: 340)

                        Spacer(minLength: 60)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)

                closeButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WESpaceDestination.self) { destination in
                if destination == .appearance {
                    HueSettingsView()
                } else {
                    WESpacePlaceholder(destination: destination)
                }
            }
        }
    }

    private func destinationButton(
        _ destination: WESpaceDestination
    ) -> some View {
        NavigationLink(value: destination) {
            ZStack {
                HStack(spacing: 10) {
                    destinationGlyph(destination)

                    Text(destination.rawValue)
                }
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.white)

                HStack {
                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    @ViewBuilder
    private func destinationGlyph(
        _ destination: WESpaceDestination
    ) -> some View {
        if destination == .us {
            WEMark(
                style: .micro,
                showsWordmark: false
            )
            .accessibilityHidden(true)
        } else {
            Image(systemName: destination.symbol)
                .frame(width: 22)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.body, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.white)
                .accessibilityLabel("Close WE space")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
        }
    }
}

private struct WESpaceBackground: View {
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    personalHue.color,
                    Color.weCinematicInk,
                    WEHue.partnerDefault.color.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    .white.opacity(0.22),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 330
            )

            RadialGradient(
                colors: [
                    personalHue.color.opacity(0.55),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )

            HStack(spacing: -62) {
                Circle()
                    .fill(personalHue.color.opacity(0.12))

                Circle()
                    .fill(WEHue.partnerDefault.color.opacity(0.1))
            }
            .frame(width: 360, height: 210)
            .rotationEffect(.degrees(-18))
            .offset(x: 92, y: -240)
            .blur(radius: 2)
        }
        .ignoresSafeArea()
    }
}

private struct WESpacePlaceholder: View {
    let destination: WESpaceDestination

    var body: some View {
        ZStack {
            WESpaceBackground()

            VStack(spacing: 12) {
                Image(systemName: destination.symbol)
                    .font(.largeTitle)

                Text(destination.rawValue)
                    .font(.weLargeTitle)

                Text("This space comes next.")
                    .font(.weBody)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
        }
        .navigationTitle(destination.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
