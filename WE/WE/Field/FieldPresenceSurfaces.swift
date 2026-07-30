//
//  FieldPresenceSurfaces.swift
//  WE
//
//  6b — Presence.
//  6c — One moment a day.
//
//  Presence is about **reachability**, never availability or effort. Nothing
//  on these screens compares who is more present, and nothing counts what
//  either person did.
//

import SwiftUI

// MARK: - 6b. Presence

struct FieldPresenceView: View {
    @Environment(FieldStore.self) private var store

    private var absent: FieldPartner? { store.absentPartner }
    private var present: FieldPartner? { store.presentPartner }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    banner
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    addressedMoment
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    holdingBlock
                        .padding(.bottom, FieldMetrics.sectionGap)

                    closingCard
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, FieldMetrics.screenBottom)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.presence")
    }

    /// The absent partner's dot renders at 0.45 — dimmed because they are
    /// unreachable, not because they are contributing less.
    private var banner: some View {
        FieldCard(accent: absentColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    FieldDot(
                        owner: absent?.owner ?? .a,
                        identity: store.identity,
                        size: FieldDotSize.prominentList,
                        baselineNudge: 7,
                        opacity: 0.45
                    )

                    Text(FieldSampleData.presenceBanner.statement)
                        .font(FieldType.cardTitle)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.3, size: 19)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                Text(FieldSampleData.presenceBanner.reasoning)
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.6, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var absentColor: Color {
        store.identity.color(for: absent?.owner ?? .a)
    }

    /// The day's item, addressed to one person by name — with the override
    /// always offered.
    private var addressedMoment: some View {
        FieldMomentView(moment: FieldSampleData.presenceMoment)
    }

    private var holdingBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            HStack(alignment: .firstTextBaseline) {
                FieldLabel("Holding until Sunday")
                Spacer()
                Text("\(FieldSampleData.holdingUntil.count)")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))
            }
            .padding(.top, 20)
            .padding(.bottom, 6)

            ForEach(FieldSampleData.holdingUntil, id: \.title) { item in
                VStack(alignment: .leading, spacing: 9) {
                    Text(item.title)
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.quietListItem))

                    Text(item.reason)
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fieldLineHeight(1.6, size: 13)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "In one go, not four notifications." The promise that makes holding
    /// feel like care rather than a queue.
    private var closingCard: some View {
        FieldCard(accent: store.identity.personB.color) {
            HStack(alignment: .top, spacing: 11) {
                FieldIntelligenceMark(identity: store.identity, diameter: 12)
                    .padding(.top, 4)

                Text(FieldSampleData.presenceClosing)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.fieldInk(.cardProse))
                    .fieldLineHeight(1.6, size: 15)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 6c. One moment a day
//
// A lock-screen design. One push, at a learned hour, with the reason given.
// No badge counts, no red dots, no second attempt.

struct FieldDailyMomentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FieldStore.self) private var store
    @State private var isBreathing = false

    private var decision: FieldMomentScheduler.Decision {
        store.momentDecision
    }

    var body: some View {
        ZStack {
            lockBackground

            VStack(spacing: 0) {
                clock
                    .padding(.top, 78)

                Spacer(minLength: 28)

                notification
                    .padding(.horizontal, 18)

                Text(decision.restraintLine)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.6, size: 13)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.horizontal, 40)

                Spacer()

                whyCard
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.bottom, 44)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.moment")
    }

    private var lockBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1E2A24),
                    FieldPalette.bg,
                    Color(hex: 0x101A16),
                ],
                startPoint: UnitPoint(x: 0.15, y: 0),
                endPoint: UnitPoint(x: 0.85, y: 1)
            )

            RadialGradient(
                gradient: Gradient(colors: [
                    store.identity.personB.color.opacity(0.10),
                    .clear,
                ]),
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: 0,
                endRadius: 280
            )
            .opacity(reduceMotion ? 0.6 : (isBreathing ? 0.85 : 0.4))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 11).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear { isBreathing = true }
        }
        .ignoresSafeArea()
    }

    private var clock: some View {
        VStack(spacing: 6) {
            Text(DateFormatter.fieldDayMonth.string(from: store.now).uppercased())
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.metadataProse))

            Text(store.state.dailyMoment.hourLabel)
                .font(FieldType.lockClock)
                .foregroundStyle(.fieldInk(.headline))
        }
        .accessibilityElement(children: .combine)
    }

    /// A translucent iOS notification: 22pt rounded-7pt blend app tile, the
    /// statement, and the detail.
    private var notification: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(store.identity.blend(.square))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("WE")
                        .font(FieldType.mark)
                        .tracking(FieldTracking.mark)
                        .foregroundStyle(.fieldInk(.legend))

                    Spacer()

                    Text("now")
                        .font(FieldType.subLabel)
                        .foregroundStyle(.fieldInk(.recessive))
                }

                Text(decision.statement ?? FieldSampleData.resolvedHeadline)
                    .font(FieldType.momentStatement)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.35, size: 20)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = decision.detail {
                    Text(detail)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.fieldInk(.cardProse))
                        .fieldLineHeight(1.6, size: 13)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(
            FieldPalette.ink.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// The learned hour, explained. Framed as evidence the app got the timing
    /// right — never as a metric about the couple.
    private var whyCard: some View {
        FieldCard(accent: store.identity.personA.color) {
            VStack(alignment: .leading, spacing: 13) {
                FieldLabel("Why \(store.state.dailyMoment.hourLabel)")

                Text(FieldMomentScheduler.hourExplanation(store.state.dailyMoment))
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.6, size: 13)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    pill("Earlier") { store.shiftMoment(byHours: -1) }
                    pill("Later") { store.shiftMoment(byHours: 1) }
                    pill("Not today") { store.skipToday() }
                }
            }
        }
    }

    private func pill(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .foregroundStyle(.fieldInk(.legend))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay {
                    Capsule().stroke(FieldRule.secondaryButton, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.moment.\(title.lowercased())")
    }
}
