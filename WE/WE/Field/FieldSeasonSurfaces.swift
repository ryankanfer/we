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
                        ink: .monoLabelQuiet
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

/// Choosing colours, and nothing else.
///
/// This screen used to be setup: a step counter reading "Setting up · 1 of 3",
/// a preview card, an eyebrow reading "Then three questions", three numbered
/// questions, and boxed yes and no buttons. All of it is gone.
///
/// The step counter first, because it is the clearest case. "The ceremony
/// reveals its own length by ending" — a counter is the app telling somebody
/// how much of its own process is left, which is a fact about the app.
///
/// The three questions are cut rather than restyled (3k). They sat after the
/// blend, so the moment the couple's two colours became a third thing was
/// immediately followed by a form, and they were the only screen in the
/// sequence asking the couple to produce data rather than receive something.
/// They come back days later as the first thing WE asks on its own, which
/// suits a product meant to grow quieter with trust — an app that asks
/// questions once it has been useful is different from one that asks before
/// it has done anything.
///
/// What is left is the choice, the blend, and one word.
struct FieldOnboardingView: View {
    @Environment(FieldStore.self) private var store

    var onFinish: () -> Void = {}

    var body: some View {
        ZStack {
            WECanvas.dark.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WEDisplayText("Choose yours.", role: .hero)
                        .padding(.bottom, 18)

                    Text(
                        "Anything of \(store.identity.nameA)'s will be one "
                            + "colour, anything of \(store.identity.nameB)'s "
                            + "the other, and anything you share is both."
                    )
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                    swatchRow(for: .a)
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    swatchRow(for: .b)
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    blend
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    // One word. Not "That's us", which answers on the
                    // couple's behalf, and not "Continue", which is a step in
                    // a process the counter used to be counting.
                    WEEditorialAction("Begin") { finish() }
                        .accessibilityIdentifier("field.onboarding.finish")
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.usSide)
                .padding(.bottom, 60)
            }

            WEColourField(
                state: .shared,
                identity: store.identity,
                height: 168
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.weCanvas, .dark)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.onboarding")
    }

    /// The emotional peak, and the reason difference is the mechanism rather
    /// than a problem: two colours stay distinct and produce a third that
    /// neither person made.
    ///
    /// Three words on the page, not a filled card containing one. The card
    /// made the blend into a specimen being displayed; the colour field
    /// underneath is where the blend actually lives everywhere else in the
    /// app, so it is where it is shown being made.
    private var blend: some View {
        WEDisplayText(
            "\(store.identity.nameA)'s. \(store.identity.nameB)'s. Ours.",
            role: .majorQuestion
        )
        .accessibilityLabel(
            "\(store.identity.personA.name) and "
                + "\(store.identity.personB.name)"
        )
    }

    private func swatchRow(for owner: FieldOwner) -> some View {
        FieldSwatchRow(owner: owner, identity: store.identity) { swatch in
            store.choose(swatch, for: owner)
        }
        .disabled(!store.canChooseSwatch(for: owner))
    }

    private func finish() {
        // Nothing to commit. The three questions this used to gather are cut
        // from onboarding entirely; `store.answerSavingFor` and its siblings
        // are still the way they are answered, from wherever WE eventually
        // asks them.

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
