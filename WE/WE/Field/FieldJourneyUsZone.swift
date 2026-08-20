import SwiftUI

/// Us is a shared decision room, not a report of Life. The old horizon report
/// remains behind the rollout flag for a safe binary rollback.
struct FieldUsZone: View {
    var body: some View {
        if WEFeatureFlags.sharedJourneysEnabled {
            SharedJourneyUsSurface()
        } else {
            LegacyFieldUsZone()
        }
    }
}

private struct SharedJourneyUsSurface: View {
    @EnvironmentObject private var session: AppSession
    @Environment(FieldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedChoice: String?
    @State private var privateNote = ""
    @State private var showsPrivateNote = false
    @State private var allowsAIProcessing = false
    @State private var showsEvidence = false
    @State private var showsPrivacyPolicy = false
    @State private var openJourney: SharedJourney?

    private var presentation: SharedJourneyPresentation {
        guard let snapshot = session.snapshot,
              let viewer = session.user?.id
        else { return .empty }
        return SharedJourneyPolicy.presentation(
            snapshot: snapshot,
            viewerID: viewer,
            now: store.now
        )
    }

    var body: some View {
        FieldZoneScaffold(
            zone: .us,
            horizontalPadding: FieldMetrics.usSide,
            background: AnyView(glow)
        ) {
            Group {
                switch presentation {
                case .empty:
                    empty
                case .question(let record):
                    question(record)
                case .held(let record):
                    held(record)
                case .proposal(let record, let direction):
                    proposal(record, direction)
                case .active(let journeys):
                    active(journeys)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .offset(y: 8)))
            .animation(
                reduceMotion ? .linear(duration: 0.16) : .weSettle(duration: 0.46),
                value: stateKey
            )
        }
        // Presented from the zone rather than the shell: unlike the circle
        // room, nothing the partner does can open this on your screen. It is
        // reached by your own tap on a journey you are already looking at.
        .fullScreenCover(item: $openJourney) { journey in
            FieldJourneyRoom(journey: journey)
                .environment(store)
                .environmentObject(session)
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            NavigationStack {
                WEPrivacyPolicyView(showsCloseButton: true)
            }
        }
    }

    private var stateKey: String {
        switch presentation {
        case .empty: "empty"
        case .question(let record): "question:\(record.id)"
        case .held(let record): "held:\(record.id)"
        case .proposal(let record, _): "proposal:\(record.id)"
        case .active(let journeys): "active:\(journeys.first?.id ?? "")"
        }
    }

    private var glow: some View {
        ZStack {
            RadialGradient(
                colors: [store.identity.personA.color.opacity(0.09), Color.clear],
                center: UnitPoint(x: 0.4, y: 0.14),
                startRadius: 0,
                endRadius: 390
            )
            RadialGradient(
                colors: [store.identity.personB.color.opacity(0.09), Color.clear],
                center: UnitPoint(x: 0.6, y: 0.14),
                startRadius: 0,
                endRadius: 390
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            JourneyMark(state: .quiet, store: store)
                .frame(maxWidth: .infinity)
                .padding(.top, 34)
                .padding(.bottom, 40)

            FieldLabel("A shared journey")
                .padding(.bottom, 18)
                .accessibilityIdentifier("field.us.journey.empty")

            Text("This room changes only when something real asks for a shared direction.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.18, size: 32)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            Text(
                "WE may bring one question from a plan, a repeated hope, or a rhythm that needs a new shape. You each answer privately. Nothing becomes part of Life until you both choose the direction it creates."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.58, size: 15)
            .fixedSize(horizontal: false, vertical: true)

            if session.connectionState == .offline {
                Text("Offline · the last shared state is still safe here.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.legend))
                    .padding(.top, 22)
            }
        }
    }

    private func question(_ record: InsightRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            JourneyMark(state: .apart, store: store)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 34)

            FieldLabel(scopeLabel(record.insight.journeyScope))
                .padding(.bottom, 14)
                .accessibilityIdentifier("field.us.journey.question")

            Text(record.insight.title)
                .font(FieldType.synthesis)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.2, size: 28)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Text(record.insight.evidence)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(Array(record.insight.options.prefix(4)), id: \.self) { option in
                    Button {
                        selectedChoice = option
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(
                                    selectedChoice == option
                                        ? store.identity.personA.color
                                        : FieldPalette.ink.opacity(0.16)
                                )
                                .frame(width: 8, height: 8)
                            Text(option)
                                .font(FieldType.body)
                                .foregroundStyle(.fieldInk(.headline))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { FieldRuleLine(color: FieldRule.row) }
                    .accessibilityIdentifier("field.us.answer.\(option)")
                }
            }
            .padding(.bottom, 20)

            if showsPrivateNote {
                TextEditor(text: $privateNote)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 84)
                    .overlay(alignment: .bottom) { FieldRuleLine() }
                    .accessibilityLabel("Optional private note")
                    .accessibilityIdentifier("field.us.privateNote")
                    .transition(.opacity)
            } else {
                Button("Add a private note") { showsPrivateNote = true }
                    .buttonStyle(FieldQuietButtonStyle())
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "To look for a shared direction, WE sends your selected "
                        + "answer, this question and its available choices, "
                        + "and up to three lines of shared evidence to OpenAI. "
                        + "Your private note is never sent. OpenAI does not "
                        + "train on API data by default, but may retain API "
                        + "content for up to 30 days for abuse monitoring "
                        + "unless WE's project has approved Zero Data Retention."
                )
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.legend))
                .fieldLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    "I agree to this OpenAI processing for this answer.",
                    isOn: $allowsAIProcessing
                )
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.headline))
                .tint(store.identity.personA.color)
                .accessibilityIdentifier("field.us.aiConsent")

                Button("Read the privacy policy") {
                    showsPrivacyPolicy = true
                }
                .buttonStyle(FieldQuietButtonStyle())
                .accessibilityIdentifier("field.us.privacyPolicy")
            }
            .padding(.vertical, 22)

            Button("Hold my answer") {
                guard let selectedChoice else { return }
                Task {
                    await session.submitResponse(
                        insightID: record.id,
                        choice: selectedChoice,
                        note: privateNote.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).nilIfEmpty,
                        consentsToAIProcessing: allowsAIProcessing
                    )
                }
            }
            .buttonStyle(FieldFilledButtonStyle())
            .disabled(
                selectedChoice == nil
                    || !allowsAIProcessing
                    || session.isWorking
            )
            .accessibilityIdentifier("field.us.holdAnswer")

            Button("Not now — don't send") {
                Task { await session.passJourneyQuestion(insightID: record.id) }
            }
            .buttonStyle(FieldQuietButtonStyle())
            .padding(.top, 8)
            .accessibilityIdentifier("field.us.pass")
        }
        .onChange(of: record.id) { _, _ in resetAnswer() }
        .task(id: record.id) {
            await session.recordJourneyQuestionShown(insightID: record.id)
        }
    }

    private func held(_ record: InsightRecord) -> some View {
        VStack(spacing: 0) {
            JourneyMark(state: .held, store: store)
                .padding(.top, 74)
                .padding(.bottom, 38)

            FieldLabel("Safely held")
                .padding(.bottom, 16)
                .accessibilityIdentifier("field.us.journey.held")
                .accessibilityLabel(
                    "Safely held. Your selected answer may be processed by "
                        + "OpenAI with your permission. Your note stays private."
                )

            Text("Your answer is here.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(
                "Your private note stays here. With your permission, OpenAI "
                    + "may process your selected answer with the question, "
                    + "available choices, and shared evidence to look for an "
                    + "honest shared direction."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .multilineTextAlignment(.center)
            .fieldLineHeight(1.58, size: 15)
            .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity)
    }

    private func proposal(
        _ record: InsightRecord,
        _ direction: SharedDirection
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            JourneyMark(state: .near, store: store)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 32)

            FieldLabel("A direction to choose")
                .padding(.bottom, 14)
                .accessibilityIdentifier("field.us.journey.proposal")

            Text(direction.displaySummary)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.18, size: 32)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            Text(direction.displayRationale)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.58, size: 15)
                .fixedSize(horizontal: false, vertical: true)

            if !direction.proposedActions.isEmpty {
                FieldRuleLine()
                    .padding(.top, 28)
                    .padding(.bottom, 18)
                FieldLabel("If you both choose it")
                    .padding(.bottom, 8)
                ForEach(direction.proposedActions.prefix(3)) { action in
                    Text(action.title)
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.headline))
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            FieldRuleLine(color: FieldRule.row)
                        }
                }
            }

            Text(
                "This direction was made from the shared evidence and broad preferences in both private answers. Neither answer is shown."
            )
            .font(FieldType.reasoning)
            .foregroundStyle(.fieldInk(.legend))
            .fieldLineHeight(1.5, size: 13)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 24)

            Button("Choose this direction") {
                Task {
                    await session.confirmSharedDirection(
                        insightID: record.id,
                        decision: .choose
                    )
                }
            }
            .buttonStyle(FieldFilledButtonStyle())
            .disabled(session.isWorking)
            .accessibilityIdentifier("field.us.chooseDirection")

            Button("Let it rest") {
                Task {
                    await session.confirmSharedDirection(
                        insightID: record.id,
                        decision: .rest
                    )
                }
            }
            .buttonStyle(FieldQuietButtonStyle())
            .padding(.top, 8)
            .accessibilityIdentifier("field.us.restDirection")
        }
    }

    private func active(_ journeys: [SharedJourney]) -> some View {
        // The first is drawn in full; the rest are named and nothing more. Us
        // shows one thing at a time, and a list of undertakings is a backlog —
        // which is the shape this zone has always refused to take.
        let journey = journeys[0]
        return VStack(alignment: .leading, spacing: 0) {
            JourneyMark(state: .joined, store: store)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .padding(.bottom, 34)

            FieldLabel("Your shared journey")
                .padding(.bottom, 14)
                .accessibilityIdentifier("field.us.journey.active")

            Text(journey.title)
                .font(FieldType.horizon)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.06, size: 44)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            Text(journey.summary)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.58, size: 15)
                .fixedSize(horizontal: false, vertical: true)

            if let next = journey.nextMove {
                FieldRuleLine()
                    .padding(.top, 30)
                    .padding(.bottom, 18)
                FieldLabel("The next useful move")
                    .padding(.bottom, 12)
                Text(next)
                    .font(FieldType.synthesis)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.28, size: 25)
            }

            if !store.hasBeenTaught(FieldTeaching.journeyOpened) {
                // The opening moment, in place. A room becoming available,
                // not a congratulation — the circles above have already moved
                // to `.joined`, which is the whole announcement.
                Text("This space can grow from things you already share. Private thoughts remain private.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 26)
            }

            Button("Enter this journey") {
                store.teach(FieldTeaching.journeyOpened)
                openJourney = journey
            }
            .buttonStyle(.plain)
            .font(FieldType.reasoning)
            .foregroundStyle(.fieldInk(.legend))
            .padding(.top, 26)
            .accessibilityIdentifier("field.us.journey.enter")

            if journeys.count > 1 {
                Text("You are also carrying " + journeys.dropFirst()
                    .map(\.title).formatted(.list(type: .and)) + ".")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }

            if !journey.evidence.isEmpty {
                Button {
                    showsEvidence.toggle()
                } label: {
                    HStack {
                        Text("What brought this here")
                            .font(FieldType.reasoning)
                        Spacer()
                        Image(systemName: showsEvidence ? "minus" : "plus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.fieldInk(.legend))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 28)

                if showsEvidence {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(journey.evidence.prefix(3)), id: \.self) {
                            Text($0)
                                .font(FieldType.reasoning)
                                .foregroundStyle(.fieldInk(.reasoning))
                                .fieldLineHeight(1.5, size: 13)
                        }
                    }
                    .padding(.top, 16)
                    .transition(.opacity)
                }
            }
        }
    }

    private func scopeLabel(_ scope: JourneyScope) -> String {
        switch scope {
        case .immediate: "A choice close at hand"
        case .nearTerm: "A direction for what is near"
        case .longTerm: "A direction for the season ahead"
        }
    }

    private func resetAnswer() {
        selectedChoice = nil
        privateNote = ""
        showsPrivateNote = false
        allowsAIProcessing = false
    }
}

private struct JourneyMark: View {
    enum State { case quiet, apart, held, near, joined }

    let state: State
    let store: FieldStore

    private var separation: CGFloat {
        switch state {
        case .quiet: 11
        case .apart: 22
        case .held: 0
        case .near: 7
        case .joined: -5
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(store.identity.personA.color.opacity(0.8), lineWidth: 1.4)
                .background(
                    Circle().fill(
                        state == .held
                            ? store.identity.personA.color.opacity(0.22)
                            : .clear
                    )
                )
                .frame(width: 38, height: 38)
                .offset(x: state == .held ? 0 : -separation)

            if state != .held {
                Circle()
                    .stroke(store.identity.personB.color.opacity(0.8), lineWidth: 1.4)
                    .frame(width: 38, height: 38)
                    .offset(x: separation)
            }
        }
        .frame(width: 110, height: 48)
        .accessibilityHidden(true)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
