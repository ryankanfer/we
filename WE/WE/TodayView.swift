//
//  TodayView.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

struct TodayView: View {
    let onOpenSpace: () -> Void

    init(onOpenSpace: @escaping () -> Void = {}) {
        self.onOpenSpace = onOpenSpace
    }

    var body: some View {
        ZStack {
            HomeAtmosphere()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    greeting

                    AtmosphericInsightCard(
                        insight: PreviewData.insights[0],
                        featured: true
                    )

                    todayTogether

                    VStack(alignment: .leading, spacing: 10) {
                        WESectionLabel("STILL OPEN")

                        AtmosphericInsightCard(
                            insight: PreviewData.insights[1]
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(timeGreeting), Ryan.")
                    .font(.weTitle)
                    .foregroundStyle(.white)

                Text("You and Dylan, right now.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            Button {
                onOpenSpace()
            } label: {
                WEMark(style: .compact)
                    .frame(minWidth: 58, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your WE space")
            .accessibilityHint("Opens your shared history and spaces")
        }
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        return switch hour {
        case 5..<12:
            "Good morning"
        case 12..<17:
            "Good afternoon"
        default:
            "Good evening"
        }
    }

    private var todayTogether: some View {
        VStack(alignment: .leading, spacing: 16) {
            WESectionLabel("TODAY TOGETHER")

            timelineRow(
                time: "Today",
                title: "Two events",
                symbol: "calendar"
            )

            Divider()
                .overlay(.white.opacity(0.12))

            timelineRow(
                time: "Together",
                title: "One open task",
                symbol: "checkmark.circle"
            )

            Divider()
                .overlay(.white.opacity(0.12))

            timelineRow(
                time: "7:00 PM",
                title: "Dinner at Nami",
                symbol: "fork.knife"
            )
        }
        .padding(20)
        .background(
            .black.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12))
        }
    }

    private func timelineRow(
        time: String,
        title: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.white.opacity(0.65))

            Text(title)
                .font(.weBody)
                .foregroundStyle(.white)

            Spacer()

            Text(time)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(minHeight: 44)
    }
}

private struct AtmosphericInsightCard: View {
    let insight: Insight
    var featured = false

    @State private var showsDetail = false
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: featured ? 14 : 10) {
            if featured {
                HStack(spacing: 9) {
                    WEMark(
                        style: .micro,
                        showsWordmark: false
                    )
                    .accessibilityHidden(true)

                    Text("WE NOTICES")
                        .font(.weCaption)
                }
                .foregroundStyle(.white.opacity(0.68))
            }

            Text(insight.title)
                .font(featured ? .weTitle : .weHeadline)
                .foregroundStyle(.white)

            Text(insight.body)
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.68))

            Button {
                showsDetail = true
            } label: {
                HStack {
                    Text(insight.actionTitle)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                }
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glassProminent)
            .tint(personalHue.controlColor)
        }
        .padding(featured ? 20 : 18)
        .glassEffect(
            featured
                ? .regular.tint(personalHue.color.opacity(0.28))
                : .regular,
            in: RoundedRectangle(
                cornerRadius: featured ? 24 : 20,
                style: .continuous
            )
        )
        .sensoryFeedback(.impact(weight: .light), trigger: showsDetail)
        .sheet(isPresented: $showsDetail) {
            NowInsightDetail(insight: insight)
        }
    }
}

private struct NowInsightDetail: View {
    let insight: Insight

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: String?
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(insight.title)
                        .font(.weLargeTitle)
                        .foregroundStyle(Color("WEInk"))

                    Text(insight.evidence)
                        .font(.weBody)
                        .foregroundStyle(Color("WEFaint"))

                    VStack(spacing: 10) {
                        ForEach(insight.options, id: \.self) { option in
                            Button {
                                withAnimation(.weSettle(duration: 0.32)) {
                                    selectedOption = option
                                }
                            } label: {
                                HStack {
                                    Text(option)

                                    Spacer()

                                    if selectedOption == option {
                                        Image(systemName: "checkmark")
                                            .transition(
                                                .opacity.combined(
                                                    with: .scale(scale: 0.6)
                                                )
                                            )
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(personalHue.controlColor)
                            .fontWeight(
                                selectedOption == option ? .semibold : .regular
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(Color("WEBackground"))
            .sensoryFeedback(.selection, trigger: selectedOption)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HomeAtmosphere: View {
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    personalHue.atmosphereColor.opacity(0.94),
                    Color.weCinematicInk,
                    WEHue.partnerDefault.color.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    .white.opacity(0.18),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 320
            )

            RadialGradient(
                colors: [
                    personalHue.atmosphereColor.opacity(0.42),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 380
            )

            Color.black.opacity(0.08)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    TodayView()
}
