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

struct LegacyFieldUsZone: View {
    @Environment(FieldStore.self) private var store

    var body: some View {
        FieldZoneScaffold(
            zone: .us,
            horizontalPadding: FieldMetrics.usSide,
            background: AnyView(glow),
            showsZoneLabel: false
        ) {
            if store.usIsEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    horizonBlock
                        .padding(.top, 20)
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    if !store.state.evidence.isEmpty {
                        evidenceBlock
                            .padding(.bottom, FieldMetrics.sectionGapLoose)
                    }

                    if let horizon = store.primaryHorizon,
                       let question = horizon.openQuestion {
                        questionBlock(horizon, question)
                            .padding(.bottom, FieldMetrics.sectionGapLoose)
                    }

                    afterThat

                    if !store.behaviourChanges.isEmpty {
                        whatIveChanged
                            .padding(.top, FieldMetrics.sectionGapLoose)
                    }
                }
            }
        }
    }

    // MARK: 6a, at the close of the long view

    /// What the app changed, in the app's own words, and nowhere else.
    ///
    /// This lives at the close of Us rather than beside the evidence, because
    /// the two are about different subjects. Evidence is what the *couple* did
    /// for a horizon; this is what the *app* changed because it was corrected.
    /// Putting a line about the app's own behaviour under a heading about
    /// theirs would be the app taking credit for their week.
    ///
    /// It says its piece here and stops. There is nothing to tap: a teaser
    /// that opened a page of the same sentences at greater length was the app
    /// asking to be read about, which is the opposite of the claim it is
    /// making. At most three lines, because a fourth is a changelog.
    ///
    /// Hidden entirely until a correction has actually taught it something —
    /// `behaviourChanges` derives from `state.corrections`, so an untouched
    /// account sees nothing rather than an empty promise.
    private var whatIveChanged: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldRuleLine()

            Text("What I've changed")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .padding(.top, 18)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(store.behaviourChanges.prefix(3)) { change in
                Text(change.change)
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.us.corrections")
    }

    // MARK: Before there is anything
    //
    // Not a failure and not a prompt. The one screen in the app where saying
    // nothing would be worse than speaking: Us is the only zone whose purpose
    // isn't legible from what's on it, so before it holds anything it explains
    // what it will hold — and then asks for nothing.

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            WEDisplayText("This is the long view.", role: .majorQuestion)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "Us holds one horizon — the thing you're both heading "
                        + "toward — and the ordinary evidence that you're "
                        + "getting there. Neither is something you fill in. "
                        + "Both are drawn from what you capture in Life."
                )

                Text(
                    "When the horizon needs a decision, one question shows up "
                        + "here. One at a time."
                )
            }
            .font(.system(size: 15, design: .serif))
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 15)
            .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(store.identity.blend())
                .frame(width: 56, height: 2)
                .padding(.top, 26)
                .accessibilityHidden(true)
        }
        .padding(.top, FieldMetrics.sectionGap)
        // Ignore the child text nodes and expose one deliberate container.
        // `.combine` inherits static-text traits from its children, which
        // makes the identifier change XCUI element type across OS releases.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "What this becomes. This is the long view. "
                + "Us holds one horizon and the ordinary evidence that "
                + "you're getting there. When the horizon needs a decision, "
                + "one question shows up here."
        )
        .accessibilityIdentifier("field.us.empty")
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
                // The horizon alone. The window used to sit under the title in
                // the same size — a second line of display type carrying a
                // date, competing with the thing the page is about.
                WEDisplayText(horizon.title, role: .hero, alignment: .center)
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
                text: evidenceReasoning,
                accent: store.identity.personA.color
            )
        }
    }

    /// The line under the evidence.
    ///
    /// It used to open with a count — "Three ordinary things" — spelled out to
    /// dodge the numeral rule. Spelling a number is still saying it, and a
    /// tally of interface rows is the decorative kind: it tells the couple how
    /// many items the app drew, which is telemetry wearing a sentence. The
    /// evidence is listed directly above, so anyone who wants the number can
    /// see it without being told.
    private let evidenceReasoning =
        "Ordinary things. That's what a horizon is made of."

    // MARK: One thing to say
    //
    // "Us asks at most one question at a time."

    private func questionBlock(
        _ horizon: FieldHorizon,
        _ question: FieldQuestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine(color: FieldRule.us)

            WEDisplayText(question.prompt, role: .majorQuestion)
                .padding(.top, 20)
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

            // Two sentences, not two boxes. "Choices are plain text with
            // restrained colour traces, never poll buttons."
            HStack(spacing: 34) {
                ForEach(question.choices) { choice in
                    WEEditorialAction(
                        choice.title,
                        tint: store.identity.color(for: choice.tint)
                    ) {
                        store.answer(question, with: choice)
                    }
                    .accessibilityIdentifier("field.us.choice.\(choice.id)")
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: After that
    //
    // Deliberately de-emphasised so the primary horizon stays primary.
    // Individual horizons sit in the same list as shared ones, marked only by
    // dot colour.

    private var afterThat: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine(color: FieldRule.us)


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
    private func emphasis(for horizon: FieldHorizon) -> FieldInkStyle {
        if horizon.targetDate == nil { return .fieldInk(.deemphasisedItem) }
        if horizon.owner == .shared { return .fieldInk(.secondaryHeading) }
        return .fieldInk(.reasoning)
    }

}
