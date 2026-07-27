import SwiftUI

struct WEView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holdsSomething = false
    @State private var selectedMomentID = ""
    let onProfile: () -> Void

    var body: some View {
        ZStack {
            WEAtmosphere()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .weArrival()

                if activeMoments.isEmpty {
                    emptyState
                        .weArrival(order: 1)
                } else {
                    TabView(selection: $selectedMomentID) {
                        ForEach(activeMoments) { record in
                            SharedMomentPage(record: record)
                                .tag(record.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    momentIndex
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $holdsSomething) {
            PrivateReflectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: activeMoments.map(\.id), initial: true) { _, ids in
            guard !ids.contains(selectedMomentID) else { return }
            selectedMomentID = ids.first ?? ""
        }
    }

    private var activeMoments: [InsightRecord] {
        session.insightRecords.enumerated()
            .compactMap { index, record -> (Int, Int, InsightRecord)? in
                guard let projection = session.projection(for: record),
                      !projection.dismissed,
                      projection.phase != .hidden,
                      projection.phase != .resolved
                else {
                    return nil
                }

                let isInMotion = projection.phase != .open
                guard record.insight.present || isInMotion else { return nil }
                return (phasePriority(projection.phase), index, record)
            }
            .sorted {
                if $0.0 == $1.0 { return $0.1 < $1.1 }
                return $0.0 < $1.0
            }
            .map(\.2)
    }

    private func phasePriority(_ phase: TrustPhase) -> Int {
        switch phase {
        case .revealed: 0
        case .answering: 1
        case .held: 2
        case .invited: 3
        case .waiting: 4
        case .declined: 5
        case .open: 6
        case .hidden, .resolved: 7
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WEMark(
                style: .micro,
                personalHue: personalHue,
                partnerHue: relationshipPartnerHue(session),
                accessibilityText: "WE"
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("WE")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(partnershipLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                holdsSomething = true
            } label: {
                Image(systemName: "lock.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canMutate)
            .accessibilityLabel("Hold something privately")
            .accessibilityHint("Starts a reflection that stays on your side")

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

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            WEMark(
                style: .display,
                personalHue: personalHue,
                partnerHue: relationshipPartnerHue(session),
                accessibilityText: "WE"
            )

            VStack(spacing: 8) {
                Text("Nothing needs an answer.")
                    .font(.weLargeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("The next shared moment will appear when there is something useful to decide together.")
                    .font(.weBody)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button {
                holdsSomething = true
            } label: {
                Label("Hold something privately", systemImage: "lock.fill")
                    .frame(minHeight: 48)
            }
            .buttonStyle(.glass)
            .tint(personalHue.color.opacity(0.24))
            .disabled(!session.canMutate)

            Spacer()
        }
        .padding(24)
    }

    private var momentIndex: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(activeMoments) { record in
                    Capsule()
                        .fill(
                            record.id == selectedMomentID
                                ? .white
                                : .white.opacity(0.28)
                        )
                        .frame(
                            width: record.id == selectedMomentID ? 22 : 7,
                            height: 7
                        )
                        .animation(
                            reduceMotion ? nil : .weState,
                            value: selectedMomentID
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shared moments")
            .accessibilityValue(
                "\(selectedMomentNumber) of \(activeMoments.count)"
            )

            Spacer()

            if activeMoments.count > 1 {
                Text("\(activeMoments.count) moments")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(minHeight: 28)
    }

    private var selectedMomentNumber: Int {
        (activeMoments.firstIndex { $0.id == selectedMomentID } ?? 0) + 1
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
              let partner = snapshot.members.first(where: { $0.id != user.id })
        else {
            return "A private space for two"
        }
        return "\(profileName) + \(partner.name)"
    }
}

private struct SharedMomentPage: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedOption: String?
    let record: InsightRecord

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 12)

                    HStack {
                        Text(eyebrow)
                            .font(.weCaption)
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.66))
                        Spacer()
                        privacyLabel
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(record.insight.title)
                            .font(.weLargeTitle)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(record.insight.body)
                            .font(.weBody)
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let projection {
                        momentControls(projection)
                    }

                    SessionMessageView()
                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }

            if projection?.phase == .answering {
                primary("Hold my answer") {
                    guard let selectedOption else { return }
                    await session.submitResponse(
                        insightID: record.id,
                        choice: selectedOption,
                        note: nil
                    )
                }
                .disabled(selectedOption == nil || !session.canMutate)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.42))
            }
        }
        .scrollIndicators(projection?.phase == .answering ? .visible : .hidden)
        .animation(
            .weSettle(duration: 0.45, reduceMotion: reduceMotion),
            value: projection?.phase
        )
        .sensoryFeedback(.selection, trigger: selectedOption)
        .sensoryFeedback(.success, trigger: projection?.phase == .revealed)
    }

    private var projection: TrustProjection? {
        session.projection(for: record)
    }

    private var eyebrow: String {
        if record.insight.seedKey.hasPrefix("tonight-") {
            return "FOR TONIGHT"
        }
        if record.insight.seedKey.hasPrefix("weekend-") {
            return "FOR THE WEEKEND"
        }
        if record.insight.seedKey.hasPrefix("load-") {
            return "BETWEEN LIFE AND US"
        }
        if record.insight.seedKey.hasPrefix("plan-") {
            return "BEFORE WHAT'S AHEAD"
        }
        return record.insight.domain == .us ? "BETWEEN US" : "FROM LIFE"
    }

    private var privacyLabel: some View {
        Label("Answers stay private", systemImage: "lock.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(
                "Answers stay private until both people submit"
            )
    }

    @ViewBuilder
    private func momentControls(_ projection: TrustProjection) -> some View {
        switch projection.phase {
        case .hidden, .resolved:
            EmptyView()
        case .open:
            quietStatus(
                "Open this together",
                "Your partner sees only the invitation."
            )
            primary("Invite \(partnerName)") {
                await session.requestReveal(insightID: record.id)
            }
        case .waiting:
            quietStatus(
                "Waiting gently",
                "\(partnerName) can open this whenever it feels right."
            )
            secondary("Withdraw invitation") {
                await session.withdrawReveal(insightID: record.id)
            }
        case .invited:
            quietStatus(
                "\(partnerName) opened a moment for both of you",
                "Nothing is revealed until you each choose."
            )
            primary("Choose privately") {
                await session.acceptReveal(insightID: record.id)
            }
            secondary("Not now") {
                await session.declineReveal(insightID: record.id)
            }
        case .declined:
            quietStatus(
                "Held on your side",
                "Your “not now” remains private."
            )
            primary("Choose after all") {
                await session.acceptReveal(insightID: record.id)
            }
        case .answering:
            answerOptions
        case .held:
            heldState
        case .revealed:
            revealedState(projection)
        }
    }

    private var answerOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose what is true for you.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

            ForEach(record.insight.options, id: \.self) { option in
                Button {
                    withAnimation(
                        .weSettle(duration: 0.24, reduceMotion: reduceMotion)
                    ) {
                        selectedOption = option
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(option)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(
                            systemName: selectedOption == option
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .font(.title3)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.glass)
                .tint(
                    selectedOption == option
                        ? personalHue.color.opacity(0.42)
                        : .white.opacity(0.04)
                )
                .accessibilityAddTraits(
                    selectedOption == option ? .isSelected : []
                )
            }
        }
    }

    private var heldState: some View {
        VStack(alignment: .leading, spacing: 14) {
            WEMark(
                style: .display,
                personalHue: personalHue,
                partnerHue: relationshipPartnerHue(session),
                accessibilityText: "Your private answer is held"
            )
            quietStatus(
                "Your answer is held",
                "WE will open only the shared direction after \(partnerName) answers too."
            )
        }
    }

    @ViewBuilder
    private func revealedState(_ projection: TrustProjection) -> some View {
        if let interpretation = SharedMomentInterpreter.interpretation(
            for: record.insight,
            mine: projection.myResponse.choice,
            partner: projection.partnerResponse?.choice
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: interpretation.symbol)
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                Text(interpretation.eyebrow)
                    .font(.weCaption)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.64))

                Text(interpretation.title)
                    .font(.weTitle)
                    .foregroundStyle(.white)

                Text(interpretation.message)
                    .font(.weBody)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .accessibilityElement(children: .combine)

            primary("Keep this direction") {
                await session.resolveInsight(
                    insightID: record.id,
                    type: .settled,
                    choice: interpretation.title
                )
            }
            secondary("Let this moment rest") {
                await session.resolveInsight(
                    insightID: record.id,
                    type: .released,
                    choice: nil
                )
            }
        } else {
            quietStatus(
                "Both answers are ready",
                "Open the full reflection to hold what each of you shared."
            )
            NavigationLink {
                InsightDetailView(insightID: record.id)
            } label: {
                Text("Open together")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(personalHue.controlColor)
        }
    }

    private func quietStatus(
        _ title: String,
        _ message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.weHeadline)
                .foregroundStyle(.white)
            Text(message)
                .font(.weBody)
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    private func primary(
        _ title: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            if session.isWorking {
                ProgressView().tint(.white)
            } else {
                Text(title)
            }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 50)
        .buttonStyle(.glassProminent)
        .tint(personalHue.controlColor)
        .disabled(!session.canMutate)
    }

    private func secondary(
        _ title: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.72))
        .disabled(!session.canMutate)
    }

    private var personalHue: WEHue {
        session.snapshot?.membership.map { WEHue($0.hue) } ?? .burgundy
    }

    private var partnerName: String {
        guard let snapshot = session.snapshot,
              let user = session.user,
              let partner = snapshot.members.first(
                  where: { $0.id != user.id }
              )
        else {
            return "your partner"
        }
        return partner.name
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
                    .lineLimit(5 ... 10)
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
                if projection?.phase == .revealed || projection?.phase == .resolved,

                   record.insight.kind != .logistical
                   || projection?.matched == true
                   || SharedMomentInterpreter.interpretation(
                       for: record.insight,
                       mine: projection?.myResponse.choice,
                       partner: projection?.partnerResponse?.choice
                   ) != nil
                {
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
                .lineLimit(2 ... 4)
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
            if record.insight.kind == .logistical {
                if let interpretation = SharedMomentInterpreter.interpretation(
                    for: record.insight,
                    mine: projection.myResponse.choice,
                    partner: projection.partnerResponse?.choice
                ) {
                    statusCard(
                        title: interpretation.title,
                        message: interpretation.message
                    )
                    primary("Keep this direction") {
                        await session.resolveInsight(
                            insightID: record.id,
                            type: .settled,
                            choice: interpretation.title
                        )
                    }
                } else {
                    statusCard(
                        title: "No mutual match this round.",
                        message: "Neither preference is shown. There is nothing to explain or decline."
                    )
                    primary("Let this round rest") {
                        await session.resolveInsight(
                            insightID: record.id,
                            type: .released,
                            choice: nil
                        )
                    }
                }
            } else {
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
            }
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

    private func matchCard(_ value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Color("WEBurgundy"))
                .frame(width: 44, height: 44)
                .background(
                    Color("WEBurgundy").opacity(0.1),
                    in: Circle()
                )
                .accessibilityHidden(true)
            Text(value ?? "A shared choice")
                .font(.weHeadline)
                .foregroundStyle(Color("WEInk"))
            Spacer(minLength: 4)
        }
        .padding(14)
        .background(
            Color("WECard"),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
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
                    partnerHue.color.opacity(isBreathing ? 0.88 : 0.78),
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
          )
    else {
        return .partnerDefault
    }
    return WEHue(partner.hue)
}

#Preview {
    NavigationStack { WEView(onProfile: {}) }
        .environmentObject(AppSession(repository: PreviewRepository()))
}
