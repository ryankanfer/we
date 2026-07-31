//
//  FieldUsZone.swift
//  WE
//
//  Us — the long-term reason any of it matters. Option 5c.
//
//  **This replaces the earlier analytical version.** Us was originally built
//  as a path diagram with a legend and it was rejected for being too
//  analytical. No diagram. No legend. No metrics. One horizon and plain
//  evidence.
//
//  The vocabulary on this screen is the product's language and is not to be
//  paraphrased: Horizons, Rhythms, Anchors, Threads, Seasons, Evidence. 5c
//  surfaces Horizons, Evidence and Season prominently and lets the others live
//  one level down.
//

import SwiftUI

struct FieldUsZone: View {
    @Environment(FieldStore.self) private var store
    @State private var showsOurs = false
    @State private var showsThreads = false

    var body: some View {
        FieldZoneScaffold(
            zone: .us,
            horizontalPadding: FieldMetrics.usSide,
            background: AnyView(glow)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                horizonBlock
                    .padding(.top, 20)
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                evidenceBlock
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                if let horizon = store.primaryHorizon,
                   let question = horizon.openQuestion {
                    questionBlock(horizon, question)
                        .padding(.bottom, FieldMetrics.sectionGapLoose)
                }

                oursEntry
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                afterThat
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                seasonBlock
            }
        }
        .sheet(isPresented: $showsOurs) {
            FieldOursView()
                .environment(store)
        }
        .sheet(isPresented: $showsThreads) {
            FieldThreadsView()
                .environment(store)
        }
    }

    /// A top-centred glow. The only ambient element on Us, and it tracks the
    /// screen rather than a person.
    private var glow: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                store.identity.personA.color.opacity(0.15),
                .clear,
            ]),
            center: UnitPoint(x: 0.5, y: 0.12),
            startRadius: 0,
            endRadius: 420
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: The horizon
    //
    // The largest type in the app.

    @ViewBuilder
    private var horizonBlock: some View {
        if let horizon = store.primaryHorizon {
            VStack(spacing: 0) {
                FieldLabel("Where you're headed")
                    .padding(.bottom, 22)

                VStack(spacing: 0) {
                    Text(horizon.title)
                    if let window = horizon.window {
                        Text(window)
                    }
                }
                .font(FieldType.horizon)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.06, size: 44)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

                if let thesis = horizon.thesis {
                    // "This sentence is the thesis of the whole product;
                    // keep it."
                    Text(thesis)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.6, size: 15)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle()
                    .fill(store.identity.blend())
                    .frame(width: 56, height: 2)
                    .padding(.top, 22)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: What this week did for it
    //
    // "This section is the mechanism that connects Life to Us. It must be
    // plain sentences about real events — never a progress bar, percentage,
    // or chart."

    private var evidenceBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("What this week did for it")
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 15) {
                ForEach(store.state.evidence) { item in
                    HStack(alignment: .top, spacing: 12) {
                        FieldDot(
                            owner: item.owner,
                            identity: store.identity,
                            size: FieldDotSize.prominentList,
                            baselineNudge: 8
                        )

                        Text(item.statement)
                            .font(.system(size: 19, design: .serif))
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.35, size: 19)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(item.statement). \(store.identity.name(for: item.owner))"
                    )
                }
            }
            .padding(.bottom, 20)

            FieldReasoning(
                text: FieldSampleData.evidenceReasoning,
                accent: store.identity.personA.color
            )
        }
    }

    // MARK: One thing to say
    //
    // "Us asks at most one question at a time."

    private func questionBlock(
        _ horizon: FieldHorizon,
        _ question: FieldQuestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine(color: FieldRule.us)

            FieldLabel("One thing to say")
                .padding(.top, 20)
                .padding(.bottom, 14)

            Text(question.prompt)
                .font(FieldType.synthesis)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.28, size: 25)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            Text(question.stakes)
                .font(.system(size: 14.5, design: .serif))
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            FieldReasoning(
                text: question.reasoning,
                accent: store.identity.personB.color
            )
            .padding(.bottom, 20)

            HStack(spacing: 11) {
                ForEach(question.choices) { choice in
                    Button(choice.title) {
                        store.answer(question, with: choice)
                    }
                    .buttonStyle(
                        FieldOutlinedButtonStyle(
                            tint: store.identity.color(for: choice.tint)
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("field.us.choice.\(choice.id)")
                }
            }
        }
    }

    // MARK: Ours

    private var oursEntry: some View {
        Button {
            showsOurs = true
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel("Ours")
                    Text("Everything you've both mentioned.")
                        .font(FieldType.cardTitle)
                        .foregroundStyle(.fieldInk(.headline))
                }

                Spacer()

                Text("\(store.oursTotal) →")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.dateCount))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the shared lists")
        .accessibilityIdentifier("field.us.ours")
    }

    // MARK: After that
    //
    // Deliberately de-emphasised so the primary horizon stays primary.
    // Individual horizons sit in the same list as shared ones, marked only by
    // dot colour.

    private var afterThat: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine(color: FieldRule.us)

            FieldLabel("After that")
                .padding(.top, 20)
                .padding(.bottom, 6)

            ForEach(store.otherHorizons) { horizon in
                HStack(alignment: .top, spacing: 11) {
                    if horizon.owner != .shared {
                        FieldDot(
                            owner: horizon.owner,
                            identity: store.identity,
                            size: FieldDotSize.list,
                            baselineNudge: 7
                        )
                    }

                    Text(horizon.title)
                        .font(FieldType.listItem)
                        .foregroundStyle(emphasis(for: horizon))
                        .fieldLineHeight(1.35, size: 15.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(horizon.countdown(now: store.now))
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

    /// The four rows step down 0.82 → 0.62 → 0.62 → 0.45. A dated shared
    /// horizon leads; the two personal ones sit level with each other; an
    /// undated one is quietest.
    private func emphasis(for horizon: FieldHorizon) -> Color {
        if horizon.targetDate == nil { return .fieldInk(.deemphasisedItem) }
        if horizon.owner == .shared { return .fieldInk(.secondaryHeading) }
        return .fieldInk(.reasoning)
    }

    // MARK: You're in
    //
    // "The season is the couple's own name for their current chapter."

    @ViewBuilder
    private var seasonBlock: some View {
        if let season = store.currentSeason {
            VStack(spacing: 0) {
                FieldRuleLine(color: FieldRule.us)

                FieldLabel("You're in")
                    .padding(.top, 22)
                    .padding(.bottom, 16)

                Text(season.name)
                    .font(FieldType.anchorQuote)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.4, size: 21)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                Text(season.spanLabel())
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.recessive))

                Button {
                    showsThreads = true
                } label: {
                    Text("ANCHORS · THREADS →")
                        .font(FieldType.subLabel)
                        .tracking(FieldTracking.subLabel)
                        .foregroundStyle(.fieldInk(.headerMeta))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityHint("Opens what you've agreed and what's still open")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Anchors and Threads
//
// One level down from 5c, as the handoff specifies. Anchors are what you've
// already agreed on so you don't relitigate it; Threads are conversations
// still open, with no pressure to finish.

struct FieldThreadsView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: FieldMetrics.sectionGapLoose) {
                    VStack(alignment: .leading, spacing: 18) {
                        FieldLabel("Anchors")

                        ForEach(store.state.anchors) { anchor in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(anchor.text)
                                    .font(FieldType.anchorQuote)
                                    .foregroundStyle(.fieldInk(.headline))
                                    .fieldLineHeight(1.55, size: 19)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(
                                    "AGREED \(DateFormatter.fieldMonthYear.string(from: anchor.agreedAt).uppercased())"
                                )
                                .font(FieldType.subLabel)
                                .tracking(FieldTracking.subLabel)
                                .foregroundStyle(.fieldInk(.recessive))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FieldLabel("Threads")

                        Text("Still open. There's no pressure to finish them.")
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.sectionSubtitle))

                        ForEach(store.state.threads) { thread in
                            HStack(alignment: .top, spacing: 11) {
                                FieldDot(
                                    owner: .shared,
                                    identity: store.identity,
                                    size: FieldDotSize.list
                                )
                                Text(thread.question)
                                    .font(FieldType.listItemLarge)
                                    .foregroundStyle(.fieldInk(.legend))
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 13)
                            .overlay(alignment: .top) {
                                FieldRuleLine(color: FieldRule.row)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FieldLabel("Rhythms")

                        ForEach(store.state.rhythms) { rhythm in
                            HStack(alignment: .firstTextBaseline) {
                                Text(rhythm.title)
                                    .font(FieldType.listItem)
                                    .foregroundStyle(.fieldInk(.legend))

                                Spacer()

                                // A two-case signal, never a streak.
                                Text(rhythm.health == .running ? "RUNNING" : "SLIPPING")
                                    .font(FieldType.subLabel)
                                    .tracking(FieldTracking.subLabel)
                                    .foregroundStyle(
                                        rhythm.health == .running
                                            ? .fieldInk(.dateCount)
                                            : store.identity.personA.color
                                    )
                            }
                            .padding(.vertical, 12)
                            .overlay(alignment: .top) {
                                FieldRuleLine(color: FieldRule.row)
                            }
                        }
                    }
                }
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.usSide)
                .padding(.bottom, 60)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Text("DONE ✕")
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    .foregroundStyle(.fieldInk(.legend))
                    .padding(FieldMetrics.usSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .preferredColorScheme(.dark)
    }
}
