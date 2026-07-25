import SwiftUI

struct WEView: View {
    @EnvironmentObject private var session: AppSession
    @State private var holdsSomething = false
    let onProfile: () -> Void

    var body: some View {
        ZStack {
            WEAtmosphere()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header

                    Button {
                        holdsSomething = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                            Text("Hold something privately")
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                            Image(systemName: "plus")
                        }
                        .font(.body.weight(.semibold))
                        .padding(.vertical, 8)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.glass)
                    .tint(.white.opacity(0.14))
                    .disabled(!session.canMutate)
                    .accessibilityHint("Starts a private reflection that is not shown to your partner")

                    if visibleRecords.isEmpty {
                        EmptyWEState()
                    } else {
                        ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                            NavigationLink {
                                InsightDetailView(insightID: record.id)
                            } label: {
                                WEInsightCard(record: record, featured: index == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    SessionMessageView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $holdsSomething) {
            PrivateReflectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var visibleRecords: [InsightRecord] {
        session.insightRecords.filter {
            guard let projection = session.projection(for: $0) else { return false }
            return !projection.dismissed
        }
    }

    private var header: some View {
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
            Button(action: onProfile) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Profile")
            .accessibilityHint("Account, appearance, archives, and privacy")
            .accessibilityIdentifier("profileButton")
        }
    }

    private var profileName: String { session.snapshot?.profile.name ?? "You" }

    private var partnershipLine: String {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return "Your shared intelligence, held carefully."
        }
        return "You and \(partner.name), right now."
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct EmptyWEState: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WEMark(
                style: .compact,
                personalHue: personalHue,
                partnerHue: partnerHue,
                accessibilityText: "WE"
            )
            Text("Nothing is asking for attention.")
                .font(.weTitle)
                .foregroundStyle(.white)
            Text("Private reflections and shared patterns will appear here only when they have something useful to hold.")
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.66))
        }
        .padding(.vertical, 20)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        relationshipPartnerHue(session)
    }
}

private struct WEInsightCard: View {
    @EnvironmentObject private var session: AppSession
    let record: InsightRecord
    let featured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: featured ? 14 : 10) {
            if featured {
                HStack(spacing: 9) {
                    WEMark(
                        style: .micro,
                        showsWordmark: false,
                        personalHue: personalHue,
                        partnerHue: partnerHue,
                        accessibilityText: "WE notices"
                    )
                    Text("WE NOTICES").font(.weCaption)
                }
                .foregroundStyle(.white.opacity(0.68))
            }
            Text(record.insight.title)
                .font(featured ? .weTitle : .weHeadline)
                .foregroundStyle(.white)
            Text(record.insight.body)
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.68))
            HStack {
                Text(record.insight.actionTitle)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
            .foregroundStyle(.white)
        }
        .padding(featured ? 20 : 18)
        .glassEffect(
            featured
                ? .regular.tint(personalHue.color.opacity(0.28))
                : .regular,
            in: RoundedRectangle(cornerRadius: featured ? 24 : 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens insight detail")
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        relationshipPartnerHue(session)
    }
}

private struct PrivateReflectionView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("Private by default", systemImage: "lock.fill")
                    .font(.weCaption)
                    .foregroundStyle(Color("WEBurgundy"))
                Text("Hold onto something.")
                    .font(.weLargeTitle)
                Text("This reflection begins on your side. Saving it does not notify or reveal it to your partner.")
                    .font(.weBody)
                    .foregroundStyle(Color("WEFaint"))
                TextField("Start here…", text: $text, axis: .vertical)
                    .lineLimit(5...10)
                    .padding(14)
                    .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 16))
                SessionMessageView()
                Button("Keep privately") {
                    Task {
                        await session.saveReflection(text: text)
                        if session.errorMessage == nil {
                            saved = true
                            dismiss()
                        }
                    }
                }
                .buttonStyle(WEPrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.canMutate)
                Spacer()
            }
            .padding(20)
            .background(Color("WEBackground"))
            .navigationTitle("Private reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sensoryFeedback(.success, trigger: saved)
        }
    }
}

struct InsightDetailView: View {
    let insightID: String
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedOption: String?

    private var record: InsightRecord? {
        session.insightRecords.first { $0.id == insightID }
    }

    private var hue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    var body: some View {
        Group {
            if let record {
                detail(record)
            } else {
                ContentUnavailableView(
                    "This insight is no longer available",
                    systemImage: "person.2.slash",
                    description: Text(
                        "Your shared space changed while this was open."
                    )
                )
            }
        }
        .background(WarmEditorialBackground())
        .navigationTitle("Insight")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ record: InsightRecord) -> some View {
        let projection = session.projection(for: record)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if projection?.phase == .revealed || projection?.phase == .resolved {
                    WEConfluenceForm(
                        personalHue: hue,
                        partnerHue: relationshipPartnerHue(session),
                        connection: 1
                    )
                        .frame(height: 170)
                        .mask(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .transition(.opacity)
                        .accessibilityLabel("Both answers opened together")
                }
                Text(record.insight.title).font(.weLargeTitle)
                Text(record.insight.evidence)
                    .font(.weBody)
                    .foregroundStyle(Color("WEFaint"))
                if let projection {
                    trustControls(projection, record: record)
                }
                SessionMessageView()
            }
            .padding(20)
        }
        .animation(
            .weSettle(duration: 0.6, reduceMotion: reduceMotion),
            value: projection?.phase
        )
        .sensoryFeedback(.success, trigger: projection?.phase == .revealed)
    }

    @ViewBuilder
    private func trustControls(
        _ projection: TrustProjection,
        record: InsightRecord
    ) -> some View {
        switch projection.phase {
        case .hidden:
            EmptyView()
        case .open:
            status("Open this together?", "Your partner will see the invitation, never an answer you have not mutually revealed.")
            primary("Ask to open together") { await session.requestReveal(insightID: record.id) }
            Button("Not for me") { Task { await session.dismissSuggestion(insightID: record.id) } }
                .buttonStyle(.plain).foregroundStyle(Color("WEFaint")).frame(minHeight: 44)
        case .waiting:
            status("Waiting gently.", "Your partner can accept when they are ready.")
            Button("Withdraw invitation") { Task { await session.withdrawReveal(insightID: record.id) } }
                .buttonStyle(.bordered).disabled(!session.canMutate)
        case .invited:
            status("Your partner wants to open this together.", "Declining stays private. They will only continue to see that the invitation is waiting.")
            primary("Open together") { await session.acceptReveal(insightID: record.id) }
            Button("Not now") { Task { await session.declineReveal(insightID: record.id) } }
                .buttonStyle(.bordered).disabled(!session.canMutate)
        case .declined:
            status(
                "Held on your side.",
                "Your “not now” remains private. Your partner still sees only that their invitation is waiting."
            )
            primary("Open together after all") {
                await session.acceptReveal(insightID: record.id)
            }
        case .answering:
            status("Answer privately.", "Neither answer appears until both of you submit.")
            optionPicker(record)
            primary("Submit my answer") {
                guard let selectedOption else { return }
                await session.submitResponse(insightID: record.id, choice: selectedOption)
            }
            .disabled(selectedOption == nil || !session.canMutate)
        case .held:
            status("Your answer is held safely.", "It will reveal only after your partner submits too.")
        case .revealed:
            status(projection.matched == true ? "You chose the same thing." : "You see this differently.", "Both answers arrived before either was revealed.")
            answer("You", projection.myResponse.choice)
            answer("Your partner", projection.partnerResponse?.choice)
            primary("Mark this settled") {
                await session.resolveInsight(insightID: record.id, type: .settled, choice: projection.matched == true ? projection.myResponse.choice : nil)
            }
            HStack {
                Button("Leave open") { Task { await session.resolveInsight(insightID: record.id, type: .leftOpen) } }
                Button("Release it") { Task { await session.resolveInsight(insightID: record.id, type: .released) } }
            }
            .buttonStyle(.bordered).disabled(!session.canMutate)
        case .resolved:
            status("Held together.", resolutionMessage(projection.resolution))
        }
    }

    private func optionPicker(_ record: InsightRecord) -> some View {
        VStack(spacing: 10) {
            ForEach(record.insight.options, id: \.self) { option in
                Button {
                    withAnimation(.weSettle(duration: 0.25, reduceMotion: reduceMotion)) { selectedOption = option }
                } label: {
                    HStack { Text(option); Spacer(); if selectedOption == option { Image(systemName: "checkmark") } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(hue.controlColor)
            }
        }
    }

    private func status(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.weHeadline)
            Text(message).font(.weBody).foregroundStyle(Color("WEFaint"))
        }
    }

    private func primary(_ title: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            if session.isWorking { ProgressView().tint(.white) } else { Text(title) }
        }
        .buttonStyle(WEPrimaryButtonStyle())
        .disabled(!session.canMutate)
    }

    private func answer(_ person: String, _ value: String?) -> some View {
        HStack { Text(person).foregroundStyle(Color("WEFaint")); Spacer(); Text(value ?? "No answer").fontWeight(.semibold) }
            .font(.weBody).padding(14).background(Color("WEInk").opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func resolutionMessage(_ resolution: TrustResolution?) -> String {
        switch resolution?.type {
        case .settled: "You marked this as settled."
        case .released: "You chose to release this."
        case .leftOpen: "You chose to leave this open."
        case nil: "This moment has been resolved."
        }
    }
}

private struct WEAtmosphere: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let hue = session.snapshot?.membership.map { WEHue($0.hue) }
            ?? .burgundy
        let partnerHue = relationshipPartnerHue(session)
        ZStack {
            LinearGradient(
                colors: [
                    hue.atmosphereColor.opacity(0.94),
                    Color.weCinematicInk,
                    partnerHue.color.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
            Color.black.opacity(0.08)
        }
        .ignoresSafeArea()
    }
}

@MainActor
private func relationshipPartnerHue(_ session: AppSession) -> WEHue {
    guard let snapshot = session.snapshot,
          let user = session.user,
          let partner = snapshot.members.first(
            where: { $0.id != user.id }
          ) else {
        return .partnerDefault
    }
    return WEHue(partner.hue)
}

#Preview {
    NavigationStack { WEView(onProfile: {}) }
        .environmentObject(AppSession(repository: PreviewRepository()))
}
