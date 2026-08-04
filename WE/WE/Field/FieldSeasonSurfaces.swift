//
//  FieldSeasonSurfaces.swift
//  WE
//
//  6e — A season, closed.
//  6f — Onboarding.
//
//  6e is retention without a streak, and the one screen a couple would
//  screenshot. What stops it reading as a Spotify Wrapped is the section that
//  names the thing that didn't happen.
//
//  6f is the entire cold start: colour first, then three questions and a
//  calendar. "Resist adding fields — low barrier to entry is an explicit
//  product requirement, and the intelligence is supposed to earn its knowledge
//  by observation."
//

import SwiftUI

// MARK: - 6e. A season, closed

struct FieldSeasonClosedView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var season: FieldSeason = FieldSampleData.closedSeason

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1B2723),
                    FieldPalette.bg,
                    Color(hex: 0x131E1A),
                ],
                startPoint: UnitPoint(x: 0.9, y: 0),
                endPoint: UnitPoint(x: 0.1, y: 1)
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    narrative
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    decided
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    didntHappen
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    whatComesNext
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.usSide)
                .padding(.bottom, 60)
            }
        }
        .overlay(alignment: .topTrailing) { doneButton(dismiss) }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.season")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                FieldLabel("A season ended")
                Spacer()
                if let endedAt = season.endedAt {
                    Text(
                        DateFormatter.fieldMonthShort
                            .string(from: endedAt)
                            .uppercased()
                    )
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))
                }
            }
            .padding(.bottom, 24)

            Rectangle()
                .fill(store.identity.blend())
                .frame(width: 44, height: 2)
                .padding(.bottom, 24)
                .accessibilityHidden(true)

            Text(season.name)
                .font(FieldType.seasonName)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.1, size: 38)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            Text(season.spanLabel())
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .foregroundStyle(.fieldInk(.recessive))
        }
    }

    /// Generated from real logged data. Every figure in it is countable.
    @ViewBuilder
    private var narrative: some View {
        if let text = season.narrative {
            Text(text)
                .font(FieldType.narrative)
                .foregroundStyle(.fieldInk(.secondaryHeading))
                .fieldLineHeight(1.75, size: 16.5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(text)
        }
    }

    /// Dated decisions pulled from resolved Threads.
    private var decided: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine(color: FieldRule.us)

            FieldLabel("What you decided")
                .padding(.top, 20)
                .padding(.bottom, 6)

            ForEach(season.decisions) { decision in
                HStack(alignment: .top, spacing: 11) {
                    FieldDot(
                        owner: .shared,
                        identity: store.identity,
                        size: FieldDotSize.list,
                        baselineNudge: 7
                    )

                    Text(decision.text)
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.legend))
                        .fieldLineHeight(1.45, size: 15.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(
                        DateFormatter.fieldShortDate
                            .string(from: decision.decidedOn)
                            .uppercased()
                    )
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.dateCount))
                }
                .padding(.vertical, 13)
                .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The honesty that stops this reading as a year-in-review gimmick.
    @ViewBuilder
    private var didntHappen: some View {
        if let text = season.oneThingThatDidntHappen {
            FieldCard(accent: store.identity.personA.color) {
                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(
                        "The one thing that didn't happen",
                        color: .fieldInk(.monoLabelQuiet)
                    )

                    Text(text)
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.5, size: 17)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var whatComesNext: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldRuleLine(color: FieldRule.us)

            FieldLabel("What comes next")
                .padding(.top, 2)

            if let horizon = store.primaryHorizon {
                Text(
                    [horizon.title, horizon.window]
                        .compactMap { $0 }
                        .joined(separator: " ")
                )
                .font(FieldType.cardTitle)
                .foregroundStyle(.fieldInk(.headline))
            }

            Text(FieldSampleData.nextHorizonPrompt)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.65, size: 13)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 11) {
                Button("Name the season") {}
                    .buttonStyle(FieldFilledButtonStyle())

                Button("Keep this") { dismiss() }
                    .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
            }
        }
    }
}

// MARK: - 6f. Onboarding

struct FieldOnboardingView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var savingFor = ""
    @State private var looksAfter = ""
    @State private var calendarOutcome: FieldCalendarAccess.Outcome?
    @State private var isConnectingCalendar = false

    var onFinish: () -> Void = {}

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGap)

                    preview
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    swatchRow(for: .a)
                        .padding(.bottom, FieldMetrics.sectionGap)

                    swatchRow(for: .b)
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    questions
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    closing
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.onboarding")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldLabel("Setting up · 1 of 3")

            Text("Choose a colour each.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)

            Text(
                "From here on, anything of \(store.identity.nameA)'s is one "
                    + "colour, anything of \(store.identity.nameB)'s is the "
                    + "other, and anything you share is both."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A 104pt block filled with the blend, containing the word "Ours.", with
    /// the pair's names beneath. **The preview updates live on tap.**
    private var preview: some View {
        VStack(spacing: 14) {
            ZStack {
                Rectangle()
                    .fill(store.identity.blend(.onboarding))

                Text("Ours.")
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .foregroundStyle(FieldPalette.bg.opacity(0.86))
            }
            .frame(height: 104)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )
            .animation(
                .fieldZone(reduceMotion),
                value: store.identity
            )

            Text(
                "\(store.identity.personA.name) and \(store.identity.personB.name)"
            )
            .font(FieldType.subLabel)
            .tracking(FieldTracking.subLabel)
            .foregroundStyle(.fieldInk(.recessive))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Preview. \(store.identity.personA.name) and "
                + "\(store.identity.personB.name)."
        )
    }

    /// Four 58pt swatches, headed by that partner's name and current dot.
    private func swatchRow(for owner: FieldOwner) -> some View {
        FieldSwatchRow(owner: owner, identity: store.identity) { swatch in
            store.choose(swatch, for: owner)
        }
        .disabled(!store.canChooseSwatch(for: owner))
    }

    /// Three questions, and no more. "Resist adding fields — low barrier to
    /// entry is an explicit product requirement, and the intelligence is
    /// supposed to earn its knowledge by observation."
    ///
    /// Every one is skippable. Leaving a field empty stores nil rather than
    /// an empty string, so "they did not say" stays distinct from "they said
    /// nothing".
    private var questions: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("Then three questions")
                .padding(.top, 20)
                .padding(.bottom, 6)

            question(1, FieldSampleData.onboardingQuestions[0]) {
                livesTogetherChoice
            }

            question(2, FieldSampleData.onboardingQuestions[1]) {
                answerField(
                    "Nothing in particular",
                    text: $savingFor,
                    identifier: "field.onboarding.savingFor"
                ) { store.answerSavingFor(savingFor) }
            }

            question(3, FieldSampleData.onboardingQuestions[2]) {
                answerField(
                    "No one else, for now",
                    text: $looksAfter,
                    identifier: "field.onboarding.looksAfter"
                ) { store.answerLooksAfter(looksAfter) }
            }
        }
    }

    private func question<Answer: View>(
        _ number: Int,
        _ prompt: String,
        @ViewBuilder answer: () -> Answer
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.dateCount))
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 12) {
                Text(prompt)
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.legend))
                    .fieldLineHeight(1.35, size: 18)
                    .fixedSize(horizontal: false, vertical: true)

                answer()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
    }

    /// Yes / no, and neither is preselected — the third state is the one where
    /// they simply have not said.
    private var livesTogetherChoice: some View {
        HStack(spacing: 10) {
            livesTogetherButton(true)
            livesTogetherButton(false)
        }
    }

    private func livesTogetherButton(_ value: Bool) -> some View {
        let isChosen: Bool = store.identity.livesTogether == value
        let tint: Color? = isChosen ? store.identity.personA.color : nil

        return Button(value ? "Yes" : "No") {
            // Tapping the chosen answer again clears it. Nothing here is
            // compulsory, including having answered.
            store.answerLivesTogether(isChosen ? nil : value)
        }
        .buttonStyle(FieldOutlinedButtonStyle(tint: tint))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("field.onboarding.livesTogether.\(value)")
    }

    private func answerField(
        _ placeholder: String,
        text: Binding<String>,
        identifier: String,
        commit: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .font(FieldType.captureInput)
            .foregroundStyle(.fieldInk(.headline))
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .onSubmit(commit)
            // Committing on blur as well as on submit, because the keyboard's
            // Done key is not the only way out of a field.
            .onChange(of: text.wrappedValue) { _, _ in commit() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                FieldPalette.ink.opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: FieldMetrics.cardRadius,
                    style: .continuous
                )
                .stroke(FieldRule.row, lineWidth: 1)
            }
            .accessibilityIdentifier(identifier)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(FieldSampleData.onboardingClosing)
                .font(FieldType.listItem)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 15.5)
                .fixedSize(horizontal: false, vertical: true)

            calendarStep

            Button("That's us") { finish() }
                .buttonStyle(FieldFilledButtonStyle())
                .disabled(isConnectingCalendar)
                .accessibilityIdentifier("field.onboarding.finish")
        }
    }

    /// The calendar is offered, never required. Declining is an outcome the
    /// app acknowledges out loud rather than a dead end it re-asks about.
    @ViewBuilder
    private var calendarStep: some View {
        switch calendarOutcome {
        case .granted:
            Text("Connected. I'll watch, and stay out of the way.")
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.6, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("field.onboarding.calendar.granted")

        case .declined:
            Text("No calendar, then. I'll learn from what you tell me.")
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.6, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("field.onboarding.calendar.declined")

        case nil:
            Button("Connect a calendar") {
                isConnectingCalendar = true
                Task {
                    calendarOutcome = await FieldCalendarAccess.request()
                    isConnectingCalendar = false
                }
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(isConnectingCalendar)
            .accessibilityIdentifier("field.onboarding.calendar.connect")
        }
    }

    private func finish() {
        // Commit whatever is in the fields but never got a submit — leaving
        // the screen is as much an answer as tapping Done.
        store.answerSavingFor(savingFor)
        store.answerLooksAfter(looksAfter)

        // Hand over first, then ask. Awaiting the permission sheet before
        // calling `onFinish` leaves them staring at the setup screen behind a
        // system dialog, and a decline would strand them there — the way in
        // must not depend on an answer the app is willing to take "no" for.
        onFinish()

        // Asked for here and nowhere else. Not at launch: the app is supposed
        // to earn this, and a permission sheet on first run is the opposite of
        // earning it.
        Task { await FieldMomentDelivery.requestAuthorization() }
    }
}
