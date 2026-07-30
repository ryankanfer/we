//
//  FieldTodayZone.swift
//  WE
//
//  WE / Today — the intelligent clearing. Option 5a.
//
//  **Nothing is ever stored here.** Every item is drawn from Life or Us at the
//  moment of viewing, which is why this view reads `store.todaySelection` (a
//  computed property) rather than any field.
//
//  Three states, all designed:
//    (a) Nothing needs you — the state to be proud of.
//    (b) Something needs you — one thing, full screen.
//    (c) A question toward Us — two equal-weight tinted choices.
//
//  Every one of them closes with the honest remainder, and every one carries a
//  reason.
//

import SwiftUI

struct FieldTodayZone: View {
    @Environment(FieldStore.self) private var store

    var body: some View {
        FieldZoneScaffold(
            zone: .we,
            headerMeta: DateFormatter.fieldDayMonth
                .string(from: store.now)
                .uppercased()
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // One hairline under the Today header, purely as a signal that
                // the space is jointly held. This is a sanctioned use of the
                // blend — it is not decoration and it appears nowhere else on
                // this screen.
                Rectangle()
                    .fill(store.identity.blend())
                    .frame(height: 1)
                    .opacity(0.55)
                    .padding(.bottom, 30)
                    .accessibilityHidden(true)

                switch store.todaySelection {
                case .resolved(let headline, let detail, let watching):
                    resolvedState(headline, detail, watching)
                case .needsYou(let moment):
                    FieldMomentView(moment: moment)
                }

                FieldCaptureField()
                    .padding(.top, FieldMetrics.sectionGapLoose)
            }
        }
    }

    // MARK: (a) Nothing needs you
    //
    // "This screen must feel like a resolution, not an empty state."

    private func resolvedState(
        _ headline: String,
        _ detail: String,
        _ watching: [FieldWatchItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 26) {
                FieldIntelligenceMark(
                    identity: store.identity,
                    diameter: 28,
                    ringDiameter: 70
                )
                .frame(height: 70)

                VStack(spacing: 16) {
                    Text(headline)
                        .font(FieldType.hero)
                        .tracking(FieldTracking.hero)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.12, size: 42)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.6, size: 15)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 270)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(headline) \(detail)")

            watchingBlock(watching)
                .padding(.bottom, FieldMetrics.sectionGap)

            horizonBlock
        }
    }

    private func watchingBlock(_ items: [FieldWatchItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("What I'm watching")
                .padding(.top, 18)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        FieldRuleLine(color: FieldRule.watching)
                    }

                    HStack(alignment: .top, spacing: 11) {
                        FieldDot(
                            owner: item.owner,
                            identity: store.identity,
                            size: FieldDotSize.list,
                            baselineNudge: 6,
                            opacity: item.isDeferred ? 0.55 : 1
                        )

                        Text(item.text)
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(
                                // The deferred line is dimmed because it is
                                // being held, not because it matters less.
                                item.isDeferred
                                    ? .fieldInk(.deemphasisedItem)
                                    : .fieldInk(.legend)
                            )
                            .fieldLineHeight(1.6, size: 14)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                }
            }
            .padding(.bottom, 4)

            FieldRuleLine()
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var horizonBlock: some View {
        if let horizon = store.primaryHorizon {
            let countdown = horizon.countdown(now: store.now)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("Next on the horizon")

                    Text(
                        [horizon.title, horizon.window]
                            .compactMap { $0 }
                            .joined(separator: " ")
                            .replacingOccurrences(of: ", ", with: " · ")
                    )
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(countdown)
                        .font(FieldType.metric)
                        .foregroundStyle(store.identity.personB.color)

                    FieldLabel(
                        "To tickets",
                        font: FieldType.subLabel,
                        tracking: FieldTracking.subLabel,
                        color: .fieldInk(.headerMeta),
                        isHeader: false
                    )
                }
            }
            .padding(.top, 22)
            .contentShape(Rectangle())
            .onTapGesture { store.go(to: .us) }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Us")
        }
    }
}

// MARK: - (b) and (c)
//
// Same shape: source label, the statement as the headline, the reasoning
// behind an accent border, then two or three actions — one filled, one
// outlined, one text-only escape.

struct FieldMomentView: View {
    @Environment(FieldStore.self) private var store
    let moment: FieldMoment

    private var accentColor: Color {
        moment.accent == .shared
            ? store.identity.personB.color
            : store.identity.color(for: moment.accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(moment.source)
                .padding(.bottom, 22)

            // Presence (6b): when one partner is unreachable the day's item is
            // addressed to the other by name, and the override is still there.
            if let addressee = moment.addressedTo {
                Text("FOR \(store.identity.name(for: addressee).uppercased()), ALONE")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(store.identity.color(for: addressee))
                    .padding(.bottom, 14)
            }

            Text(moment.headline)
                .font(FieldType.hero)
                .tracking(FieldTracking.hero)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.12, size: 42)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            if case .question(let question) = moment.shape {
                Text(question.stakes)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 15)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
            }

            FieldReasoning(text: moment.reasoning, accent: accentColor)
                .padding(.bottom, 30)

            actions

            if let remainder = moment.remainder {
                Text(remainder)
                    .font(.system(size: 13.5, design: .serif))
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.6, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 30)
            }
        }
        .accessibilityIdentifier("field.today.moment")
    }

    /// A question's two choices are equal weight and person-tinted; a
    /// statement's actions run filled, outlined, then the escape.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 11) {
            if case .question = moment.shape {
                HStack(spacing: 11) {
                    ForEach(moment.actions.filter { $0.weight == .outlined }) { action in
                        Button(action.title) {
                            perform(action)
                        }
                        .buttonStyle(
                            FieldOutlinedButtonStyle(
                                tint: action.tint.map {
                                    store.identity.color(for: $0)
                                }
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                // Branched here rather than in a helper: a function returning
                // `some ButtonStyle` can only ever return one concrete type,
                // and these are two.
                ForEach(moment.actions.filter { $0.weight != .quiet }) { action in
                    if action.weight == .filled {
                        Button(action.title) { perform(action) }
                            .buttonStyle(FieldFilledButtonStyle())
                    } else {
                        Button(action.title) { perform(action) }
                            .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
                    }
                }
            }

            ForEach(moment.actions.filter { $0.weight == .quiet }) { action in
                Button(action.title) { perform(action) }
                    .buttonStyle(FieldQuietButtonStyle())
            }
        }
    }

    private func perform(_ action: FieldMomentAction) {
        switch moment.shape {
        case .question(let question):
            if let choice = question.choices.first(where: { $0.id == action.id }) {
                store.answer(question, with: choice)
            }
        case .statement:
            if action.weight == .filled {
                store.complete(moment.id)
            }
        }
    }
}
