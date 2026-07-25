import SwiftUI

struct WEView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holdsSomething = false
    @State private var showsSharedPulse = false
    let onProfile: () -> Void

    var body: some View {
        ZStack {
            WEAtmosphere()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                        .weArrival()

                    Button {
                        holdsSomething = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Hold something privately")
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                            Image(systemName: "plus")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.glass)
                    .tint(personalHue.color.opacity(0.22))
                    .disabled(!session.canMutate)
                    .accessibilityHint("Starts a private reflection that is not shown to your partner")
                    .weArrival(order: 1)

                    if visibleRecords.isEmpty {
                        EmptyWEState(onHoldPrivately: { holdsSomething = true })
                            .weArrival(order: 2)
                    } else {
                        ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                            NavigationLink {
                                InsightDetailView(insightID: record.id)
                            } label: {
                                WEInsightCard(record: record, featured: index == 0)
                            }
                            .buttonStyle(WEPressableCardStyle())
                            .weArrival(order: index + 2)
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
        .sheet(isPresented: $showsSharedPulse) {
            SharedConnectionPulseSheet()
                .presentationDetents([.medium])
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
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(timeGreeting), \(profileName).")
                    .font(.weTitle)
                    .foregroundStyle(.white)

                Button {
                    showsSharedPulse = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.path")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(partnershipLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shared connection pulse")
                .accessibilityValue(partnershipLine)
                .accessibilityHint("Shows what is open, ahead, and carried together")
            }
            Spacer()
            Button(action: onProfile) {
                ZStack {
                    Circle()
                        .fill(personalHue.atmosphereColor)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                    Text(initials)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Profile")
            .accessibilityHint("Account, appearance, archives, and privacy")
            .accessibilityIdentifier("profileButton")
        }
    }

    private var profileName: String { session.snapshot?.profile.name ?? "You" }

    private var initials: String {
        let parts = profileName.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "ME" : value.uppercased()
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

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
    let onHoldPrivately: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            WEMark(
                style: .display,
                personalHue: personalHue,
                partnerHue: partnerHue,
                accessibilityText: "WE"
            )
            .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Nothing is asking for attention.")
                    .font(.weTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Private reflections and shared patterns will appear here only when they have something useful to hold.")
                    .font(.weBody)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(action: onHoldPrivately) {
                Label("Start a private reflection", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .tint(personalHue.color.opacity(0.3))
            .disabled(!session.canMutate)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .glassEffect(
            .regular.tint(personalHue.color.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let record: InsightRecord
    let featured: Bool

    var body: some View {
        let projection = session.projection(for: record)
        VStack(alignment: .leading, spacing: featured ? 14 : 10) {
            HStack(alignment: .center, spacing: 9) {
                if featured {
                    WEMark(
                        style: .micro,
                        showsWordmark: false,
                        personalHue: personalHue,
                        partnerHue: partnerHue,
                        accessibilityText: "WE notices"
                    )
                    Text("WE NOTICES").font(.weCaption)
                } else {
                    Text(record.insight.domain == .us ? "BETWEEN US" : "LIFE")
                        .font(.weCaption)
                }

                Spacer()

            if let statusLabel = statusBadgeText(projection) {
                Text(statusLabel.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            statusBadgeColor(projection).opacity(0.25),
                            in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .id(statusLabel)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96))
                    )
                }
            }
            .foregroundStyle(.white.opacity(0.72))

            Text(record.insight.title)
                .font(featured ? .weTitle : .weHeadline)
                .foregroundStyle(.white)

            Text(record.insight.body)
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.72))

            HStack {
                Text(actionButtonTitle(projection))
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
            .foregroundStyle(.white)
        }
        .padding(featured ? 22 : 18)
        .glassEffect(
            featured
                ? .regular.tint(personalHue.color.opacity(0.32))
                : .regular,
            in: RoundedRectangle(cornerRadius: featured ? 26 : 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: featured ? 26 : 20, style: .continuous)
                .stroke(.white.opacity(featured ? 0.18 : 0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens insight detail")
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .weState,
            value: projection?.phase
        )
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        relationshipPartnerHue(session)
    }

    private func statusBadgeText(_ projection: TrustProjection?) -> String? {
        switch projection?.phase {
        case .waiting: "Waiting"
        case .invited: "Invitation"
        case .answering: "Ready to answer"
        case .held: "Answer held"
        case .revealed: projection?.matched == true ? "Matched" : "Revealed"
        case .resolved: "Settled"
        default: nil
        }
    }

    private func statusBadgeColor(_ projection: TrustProjection?) -> Color {
        switch projection?.phase {
        case .invited, .answering: Color.amber
        case .revealed: projection?.matched == true ? Color.emerald : Color.indigo
        case .resolved: Color.white
        default: personalHue.color
        }
    }

    private func actionButtonTitle(_ projection: TrustProjection?) -> String {
        switch projection?.phase {
        case .invited: "Review invitation"
        case .answering: "Submit answer"
        case .held: "View status"
        case .revealed: "View answers"
        default: record.insight.actionTitle
        }
    }
}

private struct PrivateReflectionView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved = false

    private let maxCharacters = 4000

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Private by default", systemImage: "lock.fill")
                        .font(.weCaption)
                        .foregroundStyle(Color("WEBurgundy"))
                    Spacer()
                    Text("\(text.count)/\(maxCharacters)")
                        .font(.caption2)
                        .foregroundStyle(text.count > maxCharacters ? .red : Color("WEFaint"))
                }

                Text("Hold onto something.")
                    .font(.weLargeTitle)

                Text("This reflection begins on your side. Saving it does not notify or reveal it to your partner.")
                    .font(.weBody)
                    .foregroundStyle(Color("WEFaint"))

                TextField("Start here…", text: $text, axis: .vertical)
                    .lineLimit(5...10)
                    .padding(14)
                    .background(
                        Color("WECard"),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color("WEBurgundy").opacity(text.isEmpty ? 0 : 0.4), lineWidth: 1)
                    )
                    .onChange(of: text) { _, value in
                        if value.count > maxCharacters {
                            text = String(value.prefix(maxCharacters))
                        }
                    }

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
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !session.canMutate
                )

                Spacer()
            }
            .padding(20)
            .background(Color("WEBackground"))
            .navigationTitle("Private reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }
}

struct InsightDetailView: View {
    let insightID: String
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedOption: String?
    @State private var noteText = ""

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

                VStack(alignment: .leading, spacing: 10) {
                    Text(record.insight.domain == .us ? "BETWEEN US" : "LIFE")
                        .font(.weCaption)
                        .foregroundStyle(Color("WEBurgundy"))
                    Text(record.insight.title)
                        .font(.weLargeTitle)
                    Text(record.insight.evidence)
                        .font(.weBody)
                        .foregroundStyle(Color("WEFaint"))
                }

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
            statusCard(
                title: "Open this together?",
                message: "Your partner will see the invitation, never an answer you have not mutually revealed."
            )
            primary("Ask to open together") { await session.requestReveal(insightID: record.id) }
            Button("Not for me") { Task { await session.dismissSuggestion(insightID: record.id) } }
                .buttonStyle(.plain)
                .foregroundStyle(Color("WEFaint"))
                .frame(minHeight: 44)
        case .waiting:
            statusCard(
                title: "Waiting gently.",
                message: "Your partner can accept when they are ready."
            )
            Button("Withdraw invitation") { Task { await session.withdrawReveal(insightID: record.id) } }
                .buttonStyle(.bordered)
                .disabled(!session.canMutate)
        case .invited:
            statusCard(
                title: "Your partner wants to open this together.",
                message: "Declining stays private. They will only continue to see that the invitation is waiting."
            )
            primary("Open together") { await session.acceptReveal(insightID: record.id) }
            Button("Not now") { Task { await session.declineReveal(insightID: record.id) } }
                .buttonStyle(.bordered)
                .disabled(!session.canMutate)
        case .declined:
            statusCard(
                title: "Held on your side.",
                message: "Your “not now” remains private. Your partner still sees only that their invitation is waiting."
            )
            primary("Open together after all") {
                await session.acceptReveal(insightID: record.id)
            }
        case .answering:
            statusCard(
                title: "Answer privately.",
                message: "Neither answer appears until both of you submit."
            )
            optionPicker(record)
            TextField("Optional private note or reasoning…", text: $noteText, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            primary("Submit my answer") {
                guard let selectedOption else { return }
                await session.submitResponse(
                    insightID: record.id,
                    choice: selectedOption,
                    note: noteText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            }
            .disabled(selectedOption == nil || !session.canMutate)
        case .held:
            statusCard(
                title: "Your answer is held safely.",
                message: "It will reveal only after your partner submits too."
            )
        case .revealed:
            statusCard(
                title: projection.matched == true ? "You chose the same thing." : "You see this differently.",
                message: "Both answers arrived before either was revealed."
            )
            answerCard("You", projection.myResponse.choice, note: projection.myResponse.note)
            answerCard("Your partner", projection.partnerResponse?.choice, note: projection.partnerResponse?.note)
            primary("Mark this settled") {
                await session.resolveInsight(
                    insightID: record.id,
                    type: .settled,
                    choice: projection.matched == true ? projection.myResponse.choice : nil
                )
            }
            HStack(spacing: 12) {
                Button("Leave open") { Task { await session.resolveInsight(insightID: record.id, type: .leftOpen) } }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Release it") { Task { await session.resolveInsight(insightID: record.id, type: .released) } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!session.canMutate)
        case .resolved:
            statusCard(
                title: "Held together.",
                message: resolutionMessage(projection.resolution)
            )
        }
    }

    private func optionPicker(_ record: InsightRecord) -> some View {
        VStack(spacing: 10) {
            ForEach(record.insight.options, id: \.self) { option in
                Button {
                    withAnimation(.weSettle(duration: 0.25, reduceMotion: reduceMotion)) {
                        selectedOption = option
                    }
                } label: {
                    HStack {
                        Text(option)
                            .font(.body.weight(.semibold))
                        Spacer()
                        if selectedOption == option {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(selectedOption == option ? hue.controlColor : Color("WEFaint"))
            }
        }
        .sensoryFeedback(.selection, trigger: selectedOption)
    }

    private func statusCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.weHeadline)
            Text(message).font(.weBody).foregroundStyle(Color("WEFaint"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color("WECard"),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func primary(_ title: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            if session.isWorking { ProgressView().tint(.white) } else { Text(title) }
        }
        .buttonStyle(WEPrimaryButtonStyle())
        .disabled(!session.canMutate)
    }

    private func answerCard(_ person: String, _ value: String?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(person).foregroundStyle(Color("WEFaint")).font(.subheadline)
                Spacer()
                Text(value ?? "No answer").fontWeight(.semibold).font(.weBody)
            }
            if let note, !note.isEmpty {
                Divider()
                Text("“\(note)”")
                    .font(.subheadline.italic())
                    .foregroundStyle(Color("WEInk"))
            }
        }
        .padding(14)
        .background(Color("WEInk").opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        let hue = session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
        let partnerHue = relationshipPartnerHue(session)
        ZStack {
            LinearGradient(
                colors: [
                    hue.atmosphereColor.opacity(isBreathing ? 0.98 : 0.90),
                    Color.weCinematicInk,
                    partnerHue.color.opacity(isBreathing ? 0.88 : 0.78)
                ],
                startPoint: isBreathing ? .topLeading : .top,
                endPoint: isBreathing ? .bottomTrailing : .bottom
            )
            RadialGradient(
                colors: [.white.opacity(isBreathing ? 0.22 : 0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 340
            )
            Color.black.opacity(0.08)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
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

private extension Color {
    static let amber = Color(red: 0.92, green: 0.65, blue: 0.22)
    static let emerald = Color(red: 0.22, green: 0.72, blue: 0.48)
    static let indigo = Color(red: 0.42, green: 0.48, blue: 0.88)
}

struct SharedConnectionPulseSheet: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auraIsOpen = false

    var body: some View {
        ZStack {
            WarmEditorialBackground()

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHARED PULSE")
                            .font(.weCaption)
                            .foregroundStyle(Color("WEFaint"))
                        Text("What needs us now")
                            .font(.weTitle)
                            .foregroundStyle(Color("WEInk"))
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color("WEBurgundy"))
                        .frame(minWidth: 44, minHeight: 44)
                }

                ScrollView {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            personalHue.color.opacity(0.24),
                                            partnerHue.color.opacity(0.12),
                                            .clear
                                        ],
                                        center: .center,
                                        startRadius: 8,
                                        endRadius: 72
                                    )
                                )
                                .frame(width: 144, height: 144)
                                .scaleEffect(auraIsOpen ? 1.04 : 0.92)
                                .opacity(auraIsOpen ? 0.92 : 0.62)

                        WEMark(
                            style: .display,
                            showsWordmark: true,
                            personalHue: personalHue,
                            partnerHue: partnerHue,
                            accessibilityText: "The shared connection between you and \(partnerName)"
                        )
                        }
                        .accessibilityElement(children: .combine)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("You and \(partnerName), right now")
                                .font(.weHeadline)
                                .foregroundStyle(Color("WEInk"))
                            Text("A quiet view of what is open, ahead, and carried together.")
                                .font(.weBody)
                                .foregroundStyle(Color("WEFaint"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        VStack(spacing: 12) {
                            pulseRow(
                                title: "Open together",
                                value: activeInsightCount,
                                symbol: "circle.lefthalf.filled"
                            )
                            pulseRow(
                                title: "Plans ahead",
                                value: activePlanCount,
                                symbol: "calendar"
                            )
                            pulseRow(
                                title: "Carried together",
                                value: togetherResponsibilityCount,
                                symbol: "person.2"
                            )
                        }
                    }
                    .padding(20)
                    .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
            }
            .padding(20)
        }
        .onAppear {
            guard !reduceMotion else {
                auraIsOpen = true
                return
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                auraIsOpen = true
            }
        }
    }

    private func pulseRow(title: String, value: Int, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(Color("WEBurgundy"))
            Text(title)
                .font(.weBody)
                .foregroundStyle(Color("WEInk"))
            Spacer()
            Text(value, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color("WEFaint"))
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    private var activeInsightCount: Int {
        session.insightRecords.filter { record in
            guard let projection = session.projection(for: record) else { return false }
            return !projection.dismissed
                && projection.phase != .hidden
                && projection.phase != .resolved
        }.count
    }

    private var activePlanCount: Int {
        session.plans.filter { $0.status == .active }.count
    }

    private var togetherResponsibilityCount: Int {
        session.responsibilities.filter {
            $0.status == .active && $0.owner == .together
        }.count
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerHue: WEHue {
        relationshipPartnerHue(session)
    }

    private var partnerName: String {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(where: { $0.id != user.id }) else {
            return "Partner"
        }
        return partner.name
    }
}

#Preview {
    NavigationStack { WEView(onProfile: {}) }
        .environmentObject(AppSession(repository: PreviewRepository()))
}
