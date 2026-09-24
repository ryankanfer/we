//
//  FieldSeasonSurfaces.swift
//  WE
//
//  6e — A season, closed.
//
//  6e is retention without a streak, and the one screen a couple would
//  screenshot. What stops it reading as a Spotify Wrapped is the section that
//  names the thing that didn't happen.
//

import SwiftUI

// MARK: - 6e. A season, closed

struct FieldSeasonClosedView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let season: FieldSeason

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
                        ink: .labelQuiet
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

}

// MARK: - 6f. Onboarding

