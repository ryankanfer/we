//
//  FieldZoneShell.swift
//  WE
//
//  Three zones on one horizontal axis, fixed order:
//
//      LIFE   ←   WE / Today   →   US
//
//  Two hard constraints from the handoff govern this file:
//
//    · **No bottom tab bar.** Navigation is horizontal swipe plus a persistent
//      WE mark. The mark is not a tab — it is the app's own avatar, and
//      tapping it always returns to Today.
//    · The Reminders takeover is the **only** surface permitted to cover the
//      WE mark, and only while open.
//
//  The pager is a real paging component with gesture-driven transitions, not a
//  scroll-snap container: one zone per gesture, always snapped.
//

import SwiftUI

@MainActor
struct FieldZoneShell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: FieldStore

    init(store: FieldStore = FieldStore()) {
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()
            FieldAmbient(
                identity: store.identity,
                hour: Calendar.gregorianUS.component(.hour, from: store.now)
            )

            pager

            if !store.remindersOpen {
                navigationBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }

            if store.remindersOpen {
                FieldRemindersTakeover(store: store)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .preferredColorScheme(.dark)
        .environment(store)
        .animation(.fieldZone(reduceMotion), value: store.activeZone)
        .animation(.fieldZone(reduceMotion), value: store.remindersOpen)
        .task { await store.load() }
    }

    // MARK: The pager

    private var pager: some View {
        TabView(selection: zoneBinding) {
            FieldLifeZone()
                .tag(FieldZone.life)

            FieldTodayZone()
                .tag(FieldZone.we)

            FieldUsZone()
                .tag(FieldZone.us)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    /// Routed through the store so the mark, the flanking labels, and the
    /// deep-link router all move the same value.
    private var zoneBinding: Binding<FieldZone> {
        Binding(
            get: { store.activeZone },
            set: { store.activeZone = $0 }
        )
    }

    // MARK: The nav bar
    //
    // "The nav bar sits on linear-gradient(to top, rgba(22,33,29,.96) 55%,
    // transparent) so content scrolls softly beneath it. Bar padding
    // 16px 30px 30px; the bar occupies roughly 103pt."

    private var navigationBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                zoneLabel(.life)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                weMark
                    .padding(.horizontal, 26)

                zoneLabel(.us)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            indicator
        }
        .padding(.top, 16)
        .padding(.horizontal, FieldMetrics.screenSide)
        .padding(.bottom, 30)
        .background {
            LinearGradient(
                stops: [
                    .init(color: FieldPalette.bg.opacity(0.96), location: 0),
                    .init(color: FieldPalette.bg.opacity(0.96), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func zoneLabel(_ zone: FieldZone) -> some View {
        Button {
            store.go(to: zone)
        } label: {
            Text(zone.navLabel)
                .font(FieldType.zoneLabel)
                .tracking(FieldTracking.zoneLabel)
                .foregroundStyle(
                    store.activeZone == zone
                        ? .fieldInk(.headline)
                        : .fieldInk(.monoLabelQuiet)
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(zone.navLabel.capitalized)
        .accessibilityHint("Opens \(zone.navLabel.capitalized)")
        .accessibilityAddTraits(store.activeZone == zone ? .isSelected : [])
        .accessibilityIdentifier("field.nav.\(zone.navLabel.lowercased())")
    }

    /// 40 × 40pt circle, 1px border at ink .5, fill ink .06, the wordmark in
    /// 11pt mono at .14em. Present on every zone.
    private var weMark: some View {
        Button {
            store.returnHome()
        } label: {
            ZStack {
                Circle()
                    .fill(FieldPalette.ink.opacity(0.06))
                    .overlay {
                        Circle().strokeBorder(FieldRule.mark, lineWidth: 1)
                    }
                    .frame(width: 40, height: 40)

                Text("WE")
                    .font(FieldType.mark)
                    .tracking(FieldTracking.mark)
                    .foregroundStyle(.fieldInk(.headline))
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("WE")
        .accessibilityHint("Returns to Today")
        .accessibilityIdentifier("field.nav.we")
    }

    /// A 48 × 1pt track containing a 16pt segment filled with the blend,
    /// translated 0 / 16 / 32pt for zone 0 / 1 / 2.
    private var indicator: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(FieldRule.primary)
                .frame(width: 48, height: 1)

            Rectangle()
                .fill(store.identity.blend())
                .frame(width: 16, height: 1)
                .offset(x: CGFloat(store.activeZone.rawValue) * 16)
        }
        .frame(width: 48, height: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

extension Animation {
    /// `transform .34s cubic-bezier(.4,0,.2,1)` — the indicator, the zone
    /// change, and every transition the handoff timed.
    static func fieldZone(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.34)
    }

    /// The ~300ms tap-to-zone animation.
    static func fieldJump(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.30)
    }
}

// MARK: - Zone scaffolding
//
// Every zone shares the same screen padding and the same vertical scroll that
// persists its offset while the app is alive.

// Each zone scrolls vertically and independently, and its position persists
// while the app is alive. That falls out of the paging TabView keeping all
// three mounted — the scaffold does not track offsets itself, and adding a
// second source of truth for them would only fight SwiftUI's.
struct FieldZoneScaffold<Content: View>: View {
    let zone: FieldZone
    var horizontalPadding: CGFloat = FieldMetrics.screenSide
    /// Us carries a top-centred glow; Life and Today do not.
    var background: AnyView?
    /// Header-right metadata, at ink 0.32. Only Today carries any — it shows
    /// the date, because it is the one zone whose content is about right now.
    var headerMeta: String?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            if let background {
                background
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        FieldLabel(
                            zone.label,
                            font: FieldType.zoneLabel,
                            tracking: FieldTracking.zoneLabel,
                            color: .fieldInk(.monoLabel)
                        )

                        if let headerMeta {
                            Spacer()
                            Text(headerMeta)
                                .font(FieldType.zoneLabel)
                                .tracking(FieldTracking.zoneLabel)
                                .foregroundStyle(.fieldInk(.headerMeta))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.bottom, 24)

                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, FieldMetrics.screenBottom)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - A section rule

struct FieldRuleLine: View {
    var color: Color = FieldRule.primary

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
