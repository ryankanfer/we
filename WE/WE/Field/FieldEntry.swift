//
//  FieldEntry.swift
//  WE
//
//  The way into the handoff build, and the gallery of every accepted screen.
//
//  The zones are behind a flag rather than swapped in, because the cutover is
//  a product decision and not a refactor. The existing `AppShell` carries the
//  live auth, Supabase session, and trust/consent flows; `FieldZoneShell`
//  carries the handoff's information architecture and violates one thing
//  AppShell does deliberately — AppShell has a bottom tab bar, and the handoff
//  forbids it. They cannot both be right, so they are kept apart until the
//  decision is made.
//
//  Run the zones:      WE_FIELD=1
//  Run the gallery:    WE_FIELD=gallery
//
//  When the cutover happens, `WEApp` swaps `ContentView` for
//  `FieldZoneShell` and this file goes away.
//

import SwiftUI

enum FieldEntry {
    enum Mode: String {
        case off
        case zones
        case gallery

        static var current: Mode {
            switch ProcessInfo.processInfo.environment["WE_FIELD"] {
            case "1", "zones": .zones
            case "gallery": .gallery
            default: .off
            }
        }
    }
}

// MARK: - The gallery
//
// Eleven screens, exactly as designed. This is the review surface: it is not
// shipped, and it is the fastest way to check a token change against
// `design_handoff_we_app/screens/`.

@MainActor
struct FieldGallery: View {
    private enum Screen: String, CaseIterable, Identifiable {
        case zones = "01·03·05  The three zones"
        case reminders = "02  Reminders — takeover (4c)"
        case ours = "04  Ours — the shared lists (5b)"
        case corrections = "06  The correction receipt (6a)"
        case presence = "07  Presence (6b)"
        case moment = "08  One moment a day (6c)"
        case deferral = "09  Deferral, said out loud (6d)"
        case season = "10  A season, closed (6e)"
        case onboarding = "11  Onboarding (6f)"

        var id: String { rawValue }
    }

    @State private var store = FieldStore()
    @State private var selection: Screen?

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel("Accepted screens")
                        .padding(.bottom, 18)

                    Text("Build from 3a, 4c, 5a, 5b, 5c, and 6a–6f.")
                        .font(FieldType.pageHeadline)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.16, size: 32)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, FieldMetrics.sectionGap)

                    ForEach(Screen.allCases) { screen in
                        Button {
                            selection = screen
                        } label: {
                            HStack {
                                Text(screen.rawValue)
                                    .font(FieldType.listItem)
                                    .foregroundStyle(.fieldInk(.legend))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text("→")
                                    .foregroundStyle(.fieldInk(.dateCount))
                            }
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                FieldRuleLine(color: FieldRule.row)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selection) { screen in
            destination(screen)
                .environment(store)
                .overlay(alignment: .topLeading) {
                    Button {
                        selection = nil
                    } label: {
                        Text("← GALLERY")
                            .font(FieldType.subLabel)
                            .tracking(FieldTracking.subLabel)
                            .foregroundStyle(.fieldInk(.recessive))
                            .padding(18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
        }
    }

    @ViewBuilder
    private func destination(_ screen: Screen) -> some View {
        switch screen {
        case .zones:
            FieldZoneShell(store: store)
        case .reminders:
            FieldRemindersTakeover(store: store)
        case .ours:
            FieldOursView()
        case .corrections:
            FieldCorrectionReceiptView()
        case .presence:
            FieldPresenceView()
        case .moment:
            FieldDailyMomentView()
        case .deferral:
            FieldDeferralView()
        case .season:
            FieldSeasonClosedView()
        case .onboarding:
            FieldOnboardingView()
        }
    }
}

#Preview("Gallery") {
    FieldGallery()
}

#Preview("Zones") {
    FieldZoneShell()
}

#Preview("Reminders") {
    let store = FieldStore()
    store.openReminders()
    return FieldRemindersTakeover(store: store)
        .environment(store)
}

#Preview("Ours") {
    FieldOursView().environment(FieldStore())
}

#Preview("Presence") {
    // The Hamptons window, so 6b has something to reroute around.
    FieldPresenceView()
        .environment(FieldStore(now: FieldSampleData.date(2025, 8, 29)))
}

#Preview("A season, closed") {
    FieldSeasonClosedView().environment(FieldStore())
}

#Preview("Onboarding") {
    FieldOnboardingView().environment(FieldStore())
}
