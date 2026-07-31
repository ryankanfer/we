//
//  FieldLifeZone.swift
//  WE
//
//  Life — "run life". Option 3a.
//
//  Everything that keeps the week moving, and never the first thing you see.
//
//  "Life must stay this calm. An early version put the full Reminders list
//  inline and it swamped the page; that is why Reminders became an overlay."
//  Nothing on this screen enumerates items. The synthesis block reads the
//  shape of the week, and the five categories are single large words.
//

import SwiftUI

struct FieldLifeZone: View {
    @Environment(FieldStore.self) private var store
    @State private var isAtTop = true

    var body: some View {
        FieldZoneScaffold(zone: .life) {
            VStack(alignment: .leading, spacing: 0) {
                synthesisBlock
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                categories
            }
        }
        .overlay(alignment: .top) {
            pullAffordance
                .padding(.top, FieldMetrics.screenTop)
                .padding(.trailing, FieldMetrics.screenSide)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(true)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= geometry.contentInsets.top + 1
        } action: { _, atTop in
            isAtTop = atTop
        }
        // Pull down anywhere on Life. The gesture is simultaneous so it never
        // fights the vertical scroll — it only fires from the top.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard isAtTop,
                          value.translation.height > 90,
                          abs(value.translation.width) < 60
                    else { return }
                    store.openReminders()
                }
        )
    }

    // MARK: The synthesis block
    //
    // Bordered top and bottom with ink .16, 18pt above and 20pt below.

    /// "The shape of this week" — the intelligence speaking in its own voice
    /// about the week ahead.
    ///
    /// **Nothing generates this yet.** The handoff's sentence, its reasoning,
    /// and its three metrics are written by hand about the fictional couple,
    /// and printing them for a real one told them their week was
    /// front-loaded, that they had committed $540, and that Friday was the
    /// one to settle — none of it true, none of it theirs.
    ///
    /// So it renders only when there is something real to say, which today is
    /// never. Silence is the app's own rule: it "stays quiet rather than
    /// manufacturing a reason to speak." Restore this with a generator
    /// reading `store.state`, not by putting the sample strings back.
    @ViewBuilder
    private var synthesisBlock: some View {
        if let synthesis = store.weekSynthesis {
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 10) {
                        FieldIntelligenceMark(
                            identity: store.identity,
                            diameter: 14
                        )
                        FieldLabel("The shape of this week")
                    }

                    Text(synthesis.shape)
                        .font(FieldType.synthesis)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.28, size: 25)
                        .fixedSize(horizontal: false, vertical: true)

                    metricRow(synthesis.metrics)

                    FieldReasoning(
                        text: synthesis.reasoning,
                        accent: store.identity.personA.color
                    )
                }
                .padding(.top, 18)
                .padding(.bottom, 20)

                FieldRuleLine()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "The shape of this week. \(synthesis.shape) "
                    + synthesis.reasoning
            )
        }
    }

    /// Three columns, divided by 1pt left borders with 14pt left padding. The
    /// first column carries no divider.
    private func metricRow(
        _ metrics: [FieldWeekSynthesis.Metric]
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.figure)
                        .font(FieldType.metric)
                        .foregroundStyle(.fieldInk(.headline))

                    FieldLabel(
                        metric.label,
                        font: FieldType.subLabel,
                        tracking: FieldTracking.subLabel,
                        color: .fieldInk(.monoLabelQuiet),
                        isHeader: false
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index == 0 ? 0 : 14)
                .overlay(alignment: .leading) {
                    if index > 0 {
                        Rectangle()
                            .fill(FieldRule.primary)
                            .frame(width: 1)
                    }
                }
            }
        }
    }

    // MARK: The five categories
    //
    // Ordered by attention needed, not alphabetically or by a fixed taxonomy.

    private var categories: some View {
        VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
            ForEach(store.categoryOrder) { category in
                categoryRow(category)
            }
        }
    }

    private func categoryRow(_ category: LifeCategory) -> some View {
        let count = store.openItems(in: category).count
        let pressured = store.isPressured(category)
        let hasNothingPressing = !pressured && count == 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(category.word)
                    .font(FieldType.categoryWord)
                    .foregroundStyle(
                        pressured || count > 0
                            ? .fieldInk(.headline)
                            : .fieldInk(.reasoning)
                    )

                if count > 0 {
                    Text("\(count)")
                        .font(FieldType.zoneLabel)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(
                            pressured
                                ? store.identity.personA.color
                                : .fieldInk(.dateCount)
                        )
                }
            }

            Text(store.summary(for: category))
                .font(FieldType.body)
                .foregroundStyle(
                    hasNothingPressing
                        ? .fieldInk(.monoLabel)
                        : .fieldInk(.categorySummary)
                )
                .fieldLineHeight(1.5, size: 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            count > 0
                ? "\(category.word), \(count) items. \(store.summary(for: category))"
                : "\(category.word). \(store.summary(for: category))"
        )
        .accessibilityIdentifier("field.life.\(category.rawValue)")
    }

    // MARK: The entry affordance

    private var pullAffordance: some View {
        Button {
            store.openReminders()
        } label: {
            Text("↓ PULL FOR REMINDERS")
                .font(FieldType.subLabel)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.recessive))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reminders")
        .accessibilityHint("Opens the full list, grouped by occasion")
        .accessibilityIdentifier("field.life.reminders")
    }
}

#Preview {
    FieldZoneShell(store: FieldStore())
}
