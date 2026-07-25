//
//  TodayView.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var session: AppSession

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

                    if let firstInsight = visibleRecords.first {
                        AtmosphericInsightCard(
                            record: firstInsight,
                            featured: true
                        )
                    }

                    todayTogether

                    if let secondInsight = visibleRecords.dropFirst().first {
                        VStack(alignment: .leading, spacing: 10) {
                            WESectionLabel("STILL OPEN")

                            AtmosphericInsightCard(
                                record: secondInsight
                            )
                        }
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

    private var visibleRecords: [InsightRecord] {
        session.insightRecords.filter {
            guard let projection = session.projection(for: $0) else {
                return false
            }
            return !projection.dismissed
        }
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(timeGreeting), \(profileName).")
                    .font(.weTitle)
                    .foregroundStyle(.white)

                Text(partnershipLine)
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

    private var profileName: String {
        session.snapshot?.profile.name ?? "You"
    }

    private var partnershipLine: String {
        guard let snapshot = session.snapshot,
              let partner = snapshot.members.first(
                where: { $0.id != snapshot.profile.id }
              ) else {
            return "Your shared space, right now."
        }
        return "You and \(partner.name), right now."
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
    let record: InsightRecord
    var featured = false

    @State private var showsDetail = false
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    private var insight: Insight {
        record.insight
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
            NowInsightDetail(record: record)
        }
    }
}

private struct NowInsightDetail: View {
    let record: InsightRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var selectedOption: String?
    @AppStorage(WEHue.personalStorageKey)
    private var storedPersonalHue = ""

    private var personalHue: WEHue {
        WEHue.stored(storedPersonalHue)
    }

    private var insight: Insight {
        record.insight
    }

    private var projection: TrustProjection? {
        session.projection(for: record)
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

                    if let projection {
                        trustControls(projection)
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
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

    @ViewBuilder
    private func trustControls(
        _ projection: TrustProjection
    ) -> some View {
        switch projection.phase {
        case .hidden:
            EmptyView()
        case .open:
            status(
                "Open this together?",
                "Your partner will see the invitation, not your answer."
            )

            primaryButton("Ask to open together") {
                await session.requestReveal(insightID: insight.id)
            }

            Button("Not for me") {
                Task {
                    await session.dismissSuggestion(insightID: insight.id)
                    dismiss()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color("WEFaint"))
        case .waiting:
            status(
                "Waiting gently.",
                "Your partner can accept when they are ready."
            )

            Button("Withdraw invitation") {
                Task {
                    await session.withdrawReveal(insightID: insight.id)
                }
            }
            .buttonStyle(.bordered)
        case .invited:
            status(
                "Your partner wants to open this together.",
                "Declining stays private. They will only keep seeing "
                    + "that the invitation is waiting."
            )

            primaryButton("Open together") {
                await session.acceptReveal(insightID: insight.id)
            }

            Button("Not now") {
                Task {
                    await session.declineReveal(insightID: insight.id)
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
        case .answering:
            status(
                "Answer privately.",
                "Neither answer appears until both of you submit."
            )
            optionPicker

            primaryButton("Submit my answer") {
                guard let selectedOption else { return }
                await session.submitResponse(
                    insightID: insight.id,
                    choice: selectedOption
                )
            }
            .disabled(selectedOption == nil || session.isWorking)
        case .held:
            status(
                "Your answer is held safely.",
                "It will reveal only after your partner submits too."
            )
        case .revealed:
            revealedAnswers(projection)

            primaryButton("Mark this settled") {
                await session.resolveInsight(
                    insightID: insight.id,
                    type: .settled,
                    choice: projection.matched == true
                        ? projection.myResponse.choice
                        : nil
                )
            }

            HStack {
                Button("Leave open") {
                    Task {
                        await session.resolveInsight(
                            insightID: insight.id,
                            type: .leftOpen
                        )
                    }
                }
                .buttonStyle(.bordered)

                Button("Release it") {
                    Task {
                        await session.resolveInsight(
                            insightID: insight.id,
                            type: .released
                        )
                    }
                }
                .buttonStyle(.bordered)
            }
        case .resolved:
            status(
                "Held together.",
                resolutionMessage(projection.resolution)
            )
        }
    }

    private var optionPicker: some View {
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

    private func status(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.weHeadline)
                .foregroundStyle(Color("WEInk"))

            Text(message)
                .font(.weBody)
                .foregroundStyle(Color("WEFaint"))
        }
    }

    private func primaryButton(
        _ title: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                if session.isWorking {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(personalHue.controlColor)
        .disabled(session.isWorking)
    }

    private func revealedAnswers(
        _ projection: TrustProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            status(
                projection.matched == true
                    ? "You chose the same thing."
                    : "You see this differently.",
                "Both answers arrived before either was revealed."
            )

            answerRow("You", projection.myResponse.choice)
            answerRow("Your partner", projection.partnerResponse?.choice)
        }
    }

    private func answerRow(_ person: String, _ answer: String?) -> some View {
        HStack {
            Text(person)
                .foregroundStyle(Color("WEFaint"))
            Spacer()
            Text(answer ?? "No answer")
                .fontWeight(.semibold)
                .foregroundStyle(Color("WEInk"))
        }
        .font(.weBody)
        .padding(14)
        .background(
            Color("WEInk").opacity(0.05),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func resolutionMessage(
        _ resolution: TrustResolution?
    ) -> String {
        switch resolution?.type {
        case .settled:
            "You marked this as settled."
        case .released:
            "You chose to release this."
        case .leftOpen:
            "You chose to leave this open."
        case nil:
            "This moment has been resolved."
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
