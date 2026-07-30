//
//  FieldRemindersTakeover.swift
//  WE
//
//  Reminders — the immersive takeover. Option 4c.
//
//  The organising idea is the feature, not the list: reminders are grouped by
//  **occasion**, not by category and not by date, and every cluster states why
//  it exists. "Categories are a filing system; occasions are how people
//  actually think."
//
//  This is the only surface in the app permitted to cover the WE mark, and
//  only while it is open. Hiding the nav is the point of the treatment.
//

import SwiftUI

struct FieldRemindersTakeover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: FieldStore

    private var clusters: [FieldCluster] { store.orderedClusters }

    var body: some View {
        ZStack {
            FieldPalette.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                progress
                    .padding(.top, 18)

                Spacer(minLength: 0)

                cluster
                    .id(store.activeClusterIndex)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity),
                                removal: .move(edge: .leading)
                                    .combined(with: .opacity)
                            )
                    )

                Spacer(minLength: 0)

                footer
            }
            .padding(.top, FieldMetrics.screenTop)
            .padding(.horizontal, FieldMetrics.takeoverSide)
            .padding(.bottom, FieldMetrics.takeoverBottom)
        }
        .animation(.fieldZone(reduceMotion), value: store.activeClusterIndex)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // Horizontal swipe advances clusters; a downward swipe
                    // exits, matching the pull-down that opened it.
                    if value.translation.height > 110,
                       abs(value.translation.width) < 80 {
                        store.closeReminders()
                        return
                    }
                    if value.translation.width < -60 {
                        store.advanceCluster()
                    } else if value.translation.width > 60 {
                        store.retreatCluster()
                    }
                }
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("field.reminders")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            FieldLabel("Reminders")

            Spacer()

            Button {
                store.closeReminders()
            } label: {
                Text("DONE ✕")
                    .font(FieldType.button)
                    .tracking(FieldTracking.button)
                    .foregroundStyle(.fieldInk(.legend))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .accessibilityHint("Closes reminders")
            .accessibilityIdentifier("field.reminders.done")
        }
    }

    /// One 2pt segment per cluster, 5pt apart. The active one carries the
    /// blend; the rest sit at ink .14.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(Array(clusters.enumerated()), id: \.element.id) { index, _ in
                Group {
                    if index == store.activeClusterIndex {
                        Rectangle().fill(store.identity.blend())
                    } else {
                        Rectangle().fill(FieldRule.us)
                    }
                }
                .frame(height: 2)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: One cluster fills the screen

    @ViewBuilder
    private var cluster: some View {
        if let cluster = store.activeCluster {
            VStack(alignment: .leading, spacing: 0) {
                Text(clusterEyebrow(cluster))
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(store.identity.personA.color)
                    .padding(.bottom, 18)

                Text(cluster.title)
                    .font(FieldType.clusterTitle)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.1, size: 40)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                Text(cluster.rationale)
                    .font(.system(size: 14.5, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 26)

                itemList(cluster)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(cluster.title). \(cluster.rationale)")
        }
    }

    private func clusterEyebrow(_ cluster: FieldCluster) -> String {
        let position = (store.activeClusterIndex + 1)
        let total = clusters.count
        let when = cluster.anchorDate.map {
            DateFormatter.fieldWeekday.string(from: $0).uppercased()
        } ?? cluster.timeframe
        return "CLUSTER \(position) OF \(total) · \(when)"
    }

    /// A 1pt divider above each row and below the last. Rows carry 15pt of
    /// vertical padding, a 9pt owner dot, and an optional detail line.
    private func itemList(_ cluster: FieldCluster) -> some View {
        let items = store.items(in: cluster)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                FieldRuleLine(color: FieldRule.rowInCluster)

                HStack(alignment: .top, spacing: 12) {
                    FieldDot(
                        owner: item.owner,
                        identity: store.identity,
                        size: FieldDotSize.takeover,
                        baselineNudge: 8
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(FieldType.takeoverItem)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.25, size: 21)
                            .fixedSize(horizontal: false, vertical: true)

                        if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 11.5, design: .serif))
                                .foregroundStyle(
                                    item.isTimeCritical
                                        ? store.identity.personA.color
                                        : FieldPalette.ink.opacity(0.42)
                                )
                                .fieldLineHeight(1.5, size: 11.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 15)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(itemLabel(item))
            }

            if !items.isEmpty {
                FieldRuleLine(color: FieldRule.rowInCluster)
            }
        }
    }

    private func itemLabel(_ item: LifeItem) -> String {
        let owner = item.owner == .shared
            ? "Both of you"
            : store.identity.name(for: item.owner)
        return [item.title, owner, item.detail]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            FieldRuleLine(color: FieldRule.rowInCluster)

            HStack(alignment: .center) {
                if let next = store.nextCluster {
                    Button {
                        store.advanceCluster()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            FieldLabel(
                                "Next cluster",
                                font: FieldType.subLabel,
                                tracking: FieldTracking.subLabel,
                                color: .fieldInk(.monoLabelQuiet),
                                isHeader: false
                            )
                            Text("\(next.title) →")
                                .font(FieldType.listItem)
                                .foregroundStyle(.fieldInk(.legend))
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next cluster, \(next.title)")
                    .accessibilityIdentifier("field.reminders.next")
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        FieldLabel(
                            "Last cluster",
                            font: FieldType.subLabel,
                            tracking: FieldTracking.subLabel,
                            color: .fieldInk(.monoLabelQuiet),
                            isHeader: false
                        )
                        Text("That's all of it.")
                            .font(FieldType.listItem)
                            .foregroundStyle(.fieldInk(.metadataProse))
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }

                Spacer()

                Text("SWIPE TO ADVANCE")
                    .font(FieldType.subLabel)
                    .tracking(FieldTracking.subLabel)
                    .foregroundStyle(.fieldInk(.recessive))
                    .accessibilityHidden(true)
            }
            .padding(.top, 14)
        }
    }
}
