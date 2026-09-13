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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Presence").font(FieldType.pageHeadline)
                Text("Presence describes shared away windows. It never measures effort or compares you.")
                    .font(FieldType.reasoning)
                ForEach(store.state.partners) { partner in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(partner.name).font(FieldType.cardTitle)
                        if let window = partner.awayWindow(on: store.now) {
                            Text(window.reason)
                            Text("Until " + window.end.formatted(date: .abbreviated, time: .shortened))
                        } else {
                            Text("No shared away window right now.")
                        }
                    }
                }
                if store.state.partners.isEmpty {
                    Text("No shared presence information is available yet.")
                }
                if !store.heldTopics.isEmpty {
                    Text("What I'm holding").font(FieldType.body)
                    ForEach(store.heldTopics) { topic in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(topic.title)
                            Text(topic.reason).font(FieldType.reasoning)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .accessibilityIdentifier("field.presence")
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

            ScrollView {
                VStack(spacing: 0) {
                    clock
                        .padding(.top, 32)

                    Color.clear.frame(height: 28)

                    notification
                        .padding(.horizontal, 18)

                    Text(decision.shouldSend ? decision.restraintLine : "WE stays quiet when nothing needs you. Your notification permission also controls delivery.")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.fieldInk(.metadataProse))
                        .fieldLineHeight(1.6, size: 13)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                        .padding(.horizontal, 40)

                    Color.clear.frame(height: 32)

                    whyCard
                        .padding(.horizontal, FieldMetrics.screenSide)
                        .padding(.bottom, 44)
                }
            }
        }
        .environment(\.weCanvas, WECanvas.ground)
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

                    Text("Preview")
                        .font(FieldType.subLabel)
                        .foregroundStyle(.fieldInk(.recessive))
                }

                Text(decision.statement ?? "No moment is due right now.")
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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { momentActions }
                    VStack(alignment: .leading, spacing: 12) { momentActions }
                }
            }
        }
    }

    @ViewBuilder
    private var momentActions: some View {
        pill("Earlier") { store.shiftMoment(byHours: -1) }
        pill("Later") { store.shiftMoment(byHours: 1) }
        pill("Not today") { store.skipToday() }
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
                .frame(minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
                .overlay {
                    Capsule().stroke(FieldRule.secondaryButton, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.moment.\(title.lowercased())")
    }
}
