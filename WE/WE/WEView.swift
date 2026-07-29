import SwiftUI

struct WEView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holdsSomething = false
    @State private var passesPhone = false
    @State private var showsPresencePicker = false
    @State private var selectedMomentID = ""
    @State private var swipeDirection: SwipeDirection = .forward
    let onProfile: () -> Void

    var body: some View {
        ZStack {
            Color.weCanvas.ignoresSafeArea()
            WEAtmosphere(connection: fieldConnection)
                .opacity(0.38)

            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        todayFocusScene(
                            minHeight: max(viewport.size.height, 620)
                        )
                        .weArrival()

                        if session.presenceMode != .together {
                            VStack(alignment: .leading, spacing: 22) {
                                todayAfterglow
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 30)
                            .padding(.bottom, 36)
                            .background(Color.weCanvas)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $holdsSomething) {
            PrivateReflectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $passesPhone) {
            PassThePhoneView()
        }
        .confirmationDialog(
            "Right now",
            isPresented: $showsPresencePicker,
            titleVisibility: .visible
        ) {
            ForEach(PresenceMode.allCases, id: \.self) { mode in
                Button(mode.title) {
                    Task { await session.setPresence(mode) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how much room WE should hold around this moment.")
        }
        .onChange(of: activeMoments.map(\.id), initial: true) { _, ids in
            guard !ids.contains(selectedMomentID) else { return }
            selectedMomentID = ids.first ?? ""
        }
    }

    private var activeMoments: [InsightRecord] {
        guard session.presenceMode != .together else { return [] }
        return session.insightRecords.enumerated()
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

    /// Together collapses the field to one. Otherwise the leading moment —
    /// the one already sorted to the top by `phasePriority` — sets how near
    /// the two halves sit.
    private var fieldConnection: CGFloat {
        if session.presenceMode == .together { return 1 }
        guard let record = activeMoments.first,
              let projection = session.projection(for: record)
        else {
            return TrustPhase.open.confluenceConnection
        }
        return projection.phase.confluenceConnection
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
        WEEditorialScreenHeader(
            title: "Today",
            profileName: session.snapshot?.profile.name ?? "You",
            actionSystemImage: "circle.dotted",
            actionAccessibilityLabel: "Change presence",
            actionEnabled: session.canMutate,
            onAction: { showsPresencePicker = true },
            onProfile: onProfile
        )
    }

    private func todayFocusScene(minHeight: CGFloat) -> some View {
        WECinematicFocusScene(
            artwork: heroArtwork,
            minHeight: minHeight,
            focalPoint: heroArtwork == .horizon ? .bottom : .center,
            intensity: 0.96
        ) {
            VStack(alignment: .leading, spacing: 0) {
                header

                Spacer(minLength: 28)

                if session.presenceMode == .together {
                    presenceState(
                        eyebrow: "TOGETHER",
                        title: "You are together.",
                        detail: "WE will stay quiet. Go be together."
                    )
                } else if session.presenceMode == .away {
                    presenceState(
                        eyebrow: "AWAY",
                        title: "Room can wait.",
                        detail: "Shared moments will wait safely until you reconnect."
                    )
                } else if activeMoments.isEmpty {
                    presenceState(
                        eyebrow: greeting,
                        title: "Nothing needs you here.",
                        detail: "Everything between \(partnershipLine) has somewhere to belong."
                    )
                } else {
                    activeMomentsSection
                }

                Spacer(minLength: 18)

                if activeMoments.isEmpty {
                    PresenceControl()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 72)
        }
    }

    private func presenceState(
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.weMeta)
                .tracking(1.8)
                .foregroundStyle(Color.weInkTertiary)

            Text(title)
                .font(.weLargeTitle)
                .foregroundStyle(Color.weInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.weSubheadline)
                .foregroundStyle(Color.weInkSecondary)
                .frame(maxWidth: 330, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var todayHero: some View {
        WECinematicHero(
            artwork: heroArtwork,
            eyebrow: greeting,
            title: heroTitle,
            detail: heroDetail,
            height: 430
        )
    }

    private var heroArtwork: WECinematicArtwork {
        guard let selectedMoment,
              let projection = session.projection(for: selectedMoment)
        else {
            return .confluence
        }

        switch projection.phase {
        case .held, .waiting, .invited:
            return .vessel
        case .revealed, .resolved:
            return .horizon
        default:
            return .confluence
        }
    }

    private var heroTitle: String {
        if session.presenceMode == .together {
            return "You are together."
        }
        if session.presenceMode == .away {
            return "Room can wait."
        }
        if activeMoments.isEmpty {
            return "Nothing needs you here."
        }
        return "One thing worth holding."
    }

    private var heroDetail: String {
        if session.presenceMode == .together {
            return "WE stays quiet. Go be together."
        }
        if session.presenceMode == .away {
            return "Shared moments will wait safely until you reconnect."
        }
        if let selectedMoment {
            return selectedMoment.insight.title
        }
        return "Everything between \(partnershipLine) has somewhere to belong."
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let period: String
        switch hour {
        case 5..<12: period = "Good morning"
        case 12..<17: period = "Good afternoon"
        default: period = "Good evening"
        }
        return "\(period) · \(partnershipLine)"
    }

    private var togetherStateCard: some View {
        WECinematicPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("TOGETHER")
                    .font(.weMeta)
                    .tracking(1.6)
                    .foregroundStyle(Color.weInkTertiary)

                Text("WE will stay quiet.")
                    .font(.weTitle)
                    .foregroundStyle(Color.weInk)

                Text("Everything can wait until there is room again.")
                    .font(.weSubheadline)
                    .foregroundStyle(Color.weInkSecondary)
            }
        }
    }

    private var awayStateCard: some View {
        WECinematicPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("APART")
                    .font(.weMeta)
                    .tracking(1.6)
                    .foregroundStyle(Color.weInkTertiary)

                Text("The timing widens.")
                    .font(.weTitle)
                    .foregroundStyle(Color.weInk)

                Text("Shared moments remain safe until both of you are home.")
                    .font(.weSubheadline)
                    .foregroundStyle(Color.weInkSecondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            WEMark(
                style: .display,
                personalHue: personalHue,
                partnerHue: relationshipPartnerHue(session),
                accessibilityText: "WE"
            )

            VStack(spacing: 6) {
                Text("Nothing needs an answer.")
                    .font(.weTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("The next shared moment will appear when there is something useful to decide together.")
                    .font(.weSubheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var activeMomentsSection: some View {
        if let selectedMoment {
            VStack(spacing: 12) {
                SharedMomentPage(record: selectedMoment)
                    .id(selectedMoment.id)
                    .transition(momentTransition)
                    .gesture(momentSwipe)

                if activeMoments.count > 1 {
                    momentIndex
                }
            }
            .animation(
                reduceMotion ? nil : .weSettle(duration: 0.34),
                value: selectedMomentID
            )
        }
    }

    /// Moments slide in from the side they came from. Reduce Motion gets a
    /// crossfade instead — the direction is not load-bearing.
    private var momentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .push(from: swipeDirection == .forward ? .trailing : .leading),
            removal: .opacity
        )
    }

    private enum SwipeDirection { case forward, backward }

    /// A horizontal drag on the card, deliberately requiring more sideways
    /// travel than vertical so it never steals from the enclosing scroll.
    private var momentSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5,
                      abs(horizontal) > 48
                else { return }
                selectMoment(offset: horizontal < 0 ? 1 : -1)
            }
    }

    private var selectedMoment: InsightRecord? {
        activeMoments.first { $0.id == selectedMomentID }
            ?? activeMoments.first
    }

    private var quietActions: some View {
        VStack(spacing: 10) {
            quietAction(
                title: "Hold privately",
                detail: "Stays on your side",
                systemImage: "lock.fill"
            ) {
                holdsSomething = true
            }
            .disabled(!session.canMutate)

            quietAction(
                title: "Pass the phone",
                detail: "Share this screen",
                systemImage: "iphone.gen3"
            ) {
                passesPhone = true
            }
        }
        .weArrival(order: 4)
    }

    @ViewBuilder
    private var todayAfterglow: some View {
        if let suggestion = session.contextualSuggestions.first {
            ContextualSuggestionCard(suggestion: suggestion)
        } else if case .ready = session.seasonReadiness {
            SeasonReadyCard()
        } else {
            HorizonGlimpse()
        }

        DisclosureGroup {
            quietActions
                .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Leave something here")
                    .font(.weHeadline)
                    .foregroundStyle(Color.weInk)
                Text("Private reflection and pass-the-phone stay out of the way until useful.")
                    .font(.weMeta)
                    .foregroundStyle(Color.weInkTertiary)
            }
        }
        .tint(Color.weInkSecondary)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.weHairline)
                .frame(height: 0.5)
        }
    }

    private func quietAction(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(personalHue.atmosphereColor)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.weMeta)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                .white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(WEPressableCardStyle())
    }

    private var momentIndex: some View {
        HStack(spacing: 10) {
            Button {
                selectMoment(offset: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(selectedMomentNumber > 1 ? 0.8 : 0.24))
            .disabled(selectedMomentNumber <= 1)
            .accessibilityLabel("Previous shared moment")

            HStack(spacing: 7) {
                ForEach(activeMoments) { record in
                    Button {
                        selectMoment(id: record.id)
                    } label: {
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
                            .frame(minWidth: 16, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Shared moment \(momentNumber(for: record))"
                    )
                    .accessibilityAddTraits(
                        record.id == selectedMomentID ? .isSelected : []
                    )
                }
            }

            Spacer()

            Text("\(selectedMomentNumber) of \(activeMoments.count)")
                .font(.weMeta)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.58))

            Button {
                selectMoment(offset: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                .white.opacity(
                    selectedMomentNumber < activeMoments.count ? 0.8 : 0.24
                )
            )
            .disabled(selectedMomentNumber >= activeMoments.count)
            .accessibilityLabel("Next shared moment")
        }
        .frame(minHeight: 44)
        .sensoryFeedback(.selection, trigger: selectedMomentID)
    }

    private func selectMoment(offset: Int) {
        guard !activeMoments.isEmpty else { return }
        let currentIndex = max(selectedMomentNumber - 1, 0)
        let nextIndex = min(
            max(currentIndex + offset, 0),
            activeMoments.count - 1
        )
        guard nextIndex != currentIndex else { return }
        swipeDirection = offset > 0 ? .forward : .backward
        selectedMomentID = activeMoments[nextIndex].id
    }

    private func selectMoment(id: String) {
        let current = max(selectedMomentNumber - 1, 0)
        let target = activeMoments.firstIndex { $0.id == id } ?? current
        swipeDirection = target >= current ? .forward : .backward
        selectedMomentID = id
    }

    private func momentNumber(for record: InsightRecord) -> Int {
        (activeMoments.firstIndex { $0.id == record.id } ?? 0) + 1
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

private struct InsightEvidenceDisclosure: View {
    let insight: Insight

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                Text(insight.evidence)
                Label(insight.source, systemImage: "link")
                Label(
                    "Did not read private reflections or unrevealed answers",
                    systemImage: "lock.shield"
                )
            }
            .font(.weSubheadline)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.top, 8)
        } label: {
            Label("Why this surfaced", systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .tint(.white.opacity(0.72))
        .accessibilityHint(
            "Shows the shared evidence and excluded private data"
        )
    }
}

private struct SharedMomentPage: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedOption: String?
    let record: InsightRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    eyebrowLabel
                    Spacer()
                    privacyLabel
                }

                VStack(alignment: .leading, spacing: 8) {
                    eyebrowLabel
                    privacyLabel
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(record.insight.title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(record.insight.body)
                    .font(.weSubheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            InsightEvidenceDisclosure(insight: record.insight)

            if let projection {
                momentControls(projection)
            }

            SessionMessageView()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            .weSettle(duration: 0.45, reduceMotion: reduceMotion),
            value: projection?.phase
        )
        .sensoryFeedback(.selection, trigger: selectedOption)
        .sensoryFeedback(.success, trigger: projection?.phase == .revealed)
    }

    private var eyebrowLabel: some View {
        Text(eyebrow)
            .font(.weMeta)
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.6))
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
            quietStatus(
                "A private choice is ready",
                "Choose on your side. WE opens only the direction that can belong to both of you."
            )

            NavigationLink {
                InsightDetailView(insightID: record.id)
            } label: {
                Text("Choose privately")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(WEFocusPrimaryButtonStyle())
            .accessibilityIdentifier("today.openMoment")
        case .held:
            heldState
        case .revealed:
            revealedState(projection)
        }
    }

    private var answerOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose what is true for you.")
                .font(.weCaption)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.weInkTertiary)

            WEAnswerOptions(
                options: record.insight.options,
                hue: personalHue,
                selection: $selectedOption
            )
        }
    }

    private var heldState: some View {
        VStack(alignment: .leading, spacing: 14) {
            WECinematicArt(
                artwork: .vessel,
                height: 220,
                intensity: 0.9
            )
            .accessibilityLabel("Your private answer is held")
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
                WECinematicArt(
                    artwork: .horizon,
                    height: 210,
                    focalPoint: .bottom,
                    intensity: 0.92
                )

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
            .buttonStyle(WEFocusPrimaryButtonStyle())
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
                .font(.weSubheadline)
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
                ProgressView().tint(Color.weCanvas)
            } else {
                Text(title)
            }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 50)
        .buttonStyle(WEFocusPrimaryButtonStyle())
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
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(WESecondaryButtonStyle(tintColor: .white.opacity(0.78)))
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

                InsightEvidenceDisclosure(insight: record.insight)

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
            let action = session.questionAction(for: record)
            statusCard(
                title: "Answer privately.",
                message: action.explanation
            )
            optionPicker(record)
            TextField("Optional private note or reasoning…", text: $noteText, axis: .vertical)
                .lineLimit(2 ... 4)
                .padding(12)
                .background(Color("WECard"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            primary(action.title) {
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
        WEAnswerOptions(
            options: record.insight.options,
            hue: hue,
            selection: $selectedOption
        )
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

    /// How near the two fields sit — driven by the leading moment's trust
    /// phase, so the canvas itself reports how far something has travelled
    /// toward being shared.
    var connection: CGFloat

    var body: some View {
        WEAmbientField(
            personalHue: session.snapshot?.membership
                .map { WEHue($0.hue) } ?? .burgundy,
            partnerHue: relationshipPartnerHue(session),
            connection: connection
        )
    }
}

@MainActor
func relationshipPartnerHue(_ session: AppSession) -> WEHue {
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
