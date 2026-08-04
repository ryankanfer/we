//
//  FieldLearningSurfaces.swift
//  WE
//
//  6a — the correction receipt.
//  6d — deferral, said out loud.
//
//  These two are the retention argument, and they share one tonal rule:
//
//  **Every statistic on these screens is about the *app's* behaviour.** The
//  app critiques itself and never the users. "Your reply rate went from 40% to
//  91%" is framed as evidence that the app learned the right hour — not as a
//  compliance metric.
//

import SwiftUI

// MARK: - 6a. The correction receipt

struct FieldCorrectionReceiptView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var changes: [FieldBehaviourChange] { store.behaviourChanges }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGap)

                    VStack(spacing: FieldMetrics.cardGap) {
                        ForEach(changes) { change in
                            card(change)
                        }
                    }
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                    closing
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .overlay(alignment: .topTrailing) { doneButton(dismiss) }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.corrections")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 10) {
                    FieldIntelligenceMark(
                        identity: store.identity,
                        diameter: 14
                    )
                    FieldLabel("What I've learned")
                }

                Spacer()

                Text("MONTH \(store.monthsLearning)")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))
            }

            Text(
                "\(store.state.corrections.count.spelled.capitalized) "
                    + "correction"
                    + "\(store.state.corrections.count == 1 ? "" : "s") "
                    + "changed how I work."
            )
            .font(FieldType.pageHeadline)
            .foregroundStyle(.fieldInk(.headline))
            .fieldLineHeight(1.16, size: 32)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "Every time you moved something, I kept the reason. Here's "
                    + "what's different now."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The observed behaviour as a mono label, the app's changed behaviour in
    /// 18pt, and the outcome in italic at 0.48.
    private func card(_ change: FieldBehaviourChange) -> some View {
        FieldCard(accent: accentColor(change.accent)) {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel(
                    change.observation,
                    color: .fieldInk(.monoLabelQuiet)
                )

                Text(change.change)
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.35, size: 18)
                    .fixedSize(horizontal: false, vertical: true)

                Text(change.outcome)
                    .font(FieldType.reasoning)
                    .foregroundStyle(FieldPalette.ink.opacity(0.48))
                    .fieldLineHeight(1.6, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(change.observation). \(change.change) \(change.outcome)"
        )
    }

    private func accentColor(_ owner: FieldOwner) -> Color {
        owner == .shared
            ? FieldPalette.ink.opacity(0.22)
            : store.identity.color(for: owner)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Still getting something wrong? Tell me once and it stops.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 15)
                .fixedSize(horizontal: false, vertical: true)

            Button("Something's still off") {}
                .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
        }
    }
}

// MARK: - 6d. Deferral, said out loud

struct FieldDeferralView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var held: [FieldHeldTopic] { store.heldTopics }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGap)

                    VStack(spacing: 0) {
                        ForEach(held) { topic in
                            topicRow(topic)
                        }
                    }
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                    standingRules
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .overlay(alignment: .topTrailing) { doneButton(dismiss) }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.deferral")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 10) {
                    FieldIntelligenceMark(
                        identity: store.identity,
                        diameter: 14
                    )
                    FieldLabel("Held back")
                }

                Spacer()

                Text("\(held.count)")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))
            }

            Text("Things I'm not bringing up yet.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)

            // The line that makes deferral feel like tact rather than
            // withholding.
            Text(
                "Timing is most of tact. You can override any of these — I'd "
                    + "rather be early than sneaky."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func topicRow(_ topic: FieldHeldTopic) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.title)
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))

                Spacer(minLength: 10)

                Text(topic.timing)
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.dateCount))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay {
                        Capsule().stroke(FieldRule.row, lineWidth: 1)
                    }
            }

            FieldReasoning(
                text: topic.reason,
                accent: store.identity.personB.color
            )

            HStack(spacing: 11) {
                Button("Raise it now") { store.raiseNow(topic) }
                    .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
                    .accessibilityIdentifier("field.deferral.raise.\(topic.id)")

                Button("Leave it") { store.leaveIt(topic) }
                    .buttonStyle(FieldQuietButtonStyle())
                    .accessibilityIdentifier("field.deferral.leave.\(topic.id)")
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(topic.title), \(topic.timing). \(topic.reason)")
    }

    /// Standing rules are user-authored constraints on the intelligence's
    /// behaviour — a real, editable data type rather than a setting.
    private var standingRules: some View {
        VStack(spacing: FieldMetrics.cardGap) {
            ForEach(store.state.standingRules) { rule in
                FieldCard(accent: nil, fill: .clear, dashed: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        FieldLabel(
                            "A standing rule you gave me",
                            color: .fieldInk(.monoLabelQuiet)
                        )

                        Text("“\(rule.text)”")
                            .font(FieldType.anchorQuote)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.5, size: 19)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(rule.ageLabel(now: store.now))
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.metadataProse))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Shared chrome

@ViewBuilder
func doneButton(_ dismiss: DismissAction) -> some View {
    Button {
        dismiss()
    } label: {
        Text("DONE ✕")
            .font(FieldType.button)
            .tracking(FieldTracking.button)
            .foregroundStyle(.fieldInk(.legend))
            .padding(FieldMetrics.screenSide)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Done")
}
