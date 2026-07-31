//
//  FieldOursView.swift
//  WE
//
//  Ours — the shared lists. Option 5b.
//
//  **These are not to-dos — they are appetite.** No dates, no completion, no
//  pressure. This is the raw material the intelligence uses when it needs an
//  idea.
//
//  Lives inside Us; written to by the capture field; read by WE.
//

import SwiftUI

struct FieldOursView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store

        return ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGap)

                    filterPills(store: store)
                        .padding(.bottom, FieldMetrics.sectionGapTight)

                    list
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    // Both are the app proposing something out of Ours. They
                    // appear when it has a proposal, and not before — see
                    // `FieldStore.oursPayoff`.
                    if let payoff = store.oursPayoff {
                        payoffCard(payoff)
                            .padding(.bottom, FieldMetrics.sectionGap)

                        alsoPossible(payoff.alsoPossible)
                    }
                }
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.screenSide)
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
                    .padding(FieldMetrics.screenSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.ours")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                FieldLabel("Ours")
                Spacer()
                Text("\(store.oursTotal) THINGS")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))
            }

            Text("Everything you've both mentioned.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "No dates, no pressure. This is the raw material WE uses when "
                    + "it needs an idea."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.sectionSubtitle))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Filter pills

    private func filterPills(store: FieldStore) -> some View {
        @Bindable var store = store

        return FieldFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(OursList.allCases) { list in
                let isActive = store.oursFilter == list

                Button {
                    store.oursFilter = list
                } label: {
                    Text("\(list.label) \(store.count(for: list))")
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(
                            isActive
                                ? FieldPalette.bg
                                : FieldPalette.ink.opacity(0.6)
                        )
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background {
                            if isActive {
                                Capsule().fill(FieldPalette.ink)
                            } else {
                                Capsule().stroke(
                                    FieldRule.secondaryButton,
                                    lineWidth: 1
                                )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityIdentifier("field.ours.filter.\(list.rawValue)")
            }
        }
    }

    // MARK: The list

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.oursForFilter) { item in
                row(item)
            }
        }
    }

    private func row(_ item: OursItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            FieldDot(
                owner: item.displayOwner,
                identity: store.identity,
                size: FieldDotSize.list,
                baselineNudge: 7
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.25, size: 18)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    item.provenance(
                        identity: store.identity,
                        horizonTitle: store.horizonTitle(item.horizonID),
                        now: store.now
                    )
                )
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount * 0.6)
                .foregroundStyle(
                    // A horizon tag is the one provenance line that carries
                    // colour, because it is the only one that means something
                    // beyond bookkeeping.
                    item.horizonID != nil
                        ? store.identity.personB.color
                        : .fieldInk(.dateCount)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(item))
    }

    private func accessibilityLabel(_ item: OursItem) -> String {
        if item.bothAdded {
            return "\(item.title). Both of you added it independently."
        }
        if item.isStandingNote {
            return "\(item.title). A standing note from "
                + "\(store.identity.name(for: item.addedBy))."
        }
        return "\(item.title). Added by "
            + "\(store.identity.name(for: item.addedBy))."
    }

    // MARK: The payoff card
    //
    // "Every clause of that reasoning cites a different signal: the lists,
    // geography, the coincidence, and the calendar. That is the demo."

    private func payoffCard(
        _ payoff: FieldOursPayoff
    ) -> some View {
        FieldCard(accent: store.identity.personA.color) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    FieldIntelligenceMark(
                        identity: store.identity,
                        diameter: 12
                    )
                    FieldLabel(payoff.label)
                }

                Text(payoff.headline)
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.35, size: 19)
                    .fixedSize(horizontal: false, vertical: true)

                Text(payoff.reasoning)
                    .font(FieldType.receiptReasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.65, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 11) {
                    Button(payoff.hold) {}
                        .buttonStyle(FieldFilledButtonStyle())

                    Button(payoff.alternative) {}
                        .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Also possible
    //
    // Including "Nothing at all. That's allowed." — the app never insists.

    private func alsoPossible(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Also possible")
                .padding(.bottom, 4)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 14.5, design: .serif))
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.85, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
