//
//  FieldEntry.swift
//  WE
//
//  The way into the handoff build, and the gallery of every accepted screen.
//
//  The cutover has happened. With no `WE_FIELD` set the mode is `.live`, and
//  `WEApp` hands the screen to `FieldRoot` the moment a couple is ready — the
//  zones are the app, on real Supabase data. The old tab-bar shell that could
//  not coexist with them (the handoff forbids a bottom tab bar) is gone.
//
//  The other two modes are development surfaces and are never shipped to:
//
//    WE_FIELD=gallery    the eleven accepted screens, for review
//    WE_FIELD=seeded     the zones on the fictional couple, no network
//                        (WE_FIELD=1 is an alias)
//
//  What still runs the old way is everything *before* a couple exists — sign
//  in, verification, password recovery, pairing, hue choice. Those are setup,
//  not zones, and 6f replaces them. See Field/CUTOVER.md.
//

import SwiftUI

enum FieldEntry {
    enum Mode: String {
        /// The real app, backed by Supabase.
        case live
        /// The real app on seeded data — no couple, no network.
        case seeded
        /// The review surface.
        case gallery

        static var current: Mode {
            switch ProcessInfo.processInfo.environment["WE_FIELD"] {
            case "seeded", "1": .seeded
            case "gallery": .gallery
            default: .live
            }
        }
    }
}

// MARK: - The root
//
// Builds the store from the live session. This is the cutover: once a couple
// exists, the zones are the app.
//
// The store is held in @State rather than rebuilt per render, because it owns
// the ephemeral UI state — the active zone, the capture draft, the open
// takeover — and rebuilding it would throw all of that away on every snapshot
// change.

@MainActor
struct FieldRoot: View {
    let snapshot: RelationshipSnapshot
    @State private var store: FieldStore?

    var body: some View {
        Group {
            if let store {
                FieldZoneShell(store: store)
            } else {
                // Not an empty state, a held one. The canvas is already the
                // right colour, so the handoff never flashes.
                FieldPalette.bg.ignoresSafeArea()
            }
        }
        .task(id: snapshot.membership?.coupleID) {
            guard store == nil else { return }
            // Empty and *now* — explicitly, both of them. The store's own
            // defaults are the fictional couple on a fixed August date,
            // which is right for the gallery and wrong for a real person:
            // it puts someone else's groceries on their screen and dates
            // every calculation to 2025.
            //
            // A clock rather than an instant, because an instant is what the
            // app had before: `Date()` read once at launch and then believed
            // for the rest of the process. `FieldLiveClock.app` still honours
            // a pinned QA date, so nothing about the harnesses changes.
            let durable = FieldDurableBackend.live(for: snapshot)
            let cached = durable?.outbox.cachedState()
            store = FieldStore(
                // The cache, when there is one. A couple opening the app on a
                // train used to see a blank account until thirteen queries
                // answered; now they see what was there last time, with
                // anything still queued already on top of it.
                state: cached?.state ?? snapshot.emptyFieldState,
                backend: durable?.outbox,
                clock: FieldLiveClock.app,
                // The real one only here. Previews and the gallery get the
                // resolver that finds nobody, so a screenshot run can never
                // depend on what is in this machine's address book or reach
                // out of the process.
                resolver: FieldResolvers(),
                // So a first load that fails reads as "last seen on Tuesday"
                // rather than as an empty relationship.
                lastLoadedAt: cached?.savedAt
            )
        }
    }
}

// MARK: - The durable seam
//
// Composed in one place because it is composed twice — here and in
// `FieldOnboardingRoot` — and the two differing is exactly the kind of
// asymmetry that leaves one screen writing durably and the other not.

@MainActor
struct FieldDurableBackend {
    let outbox: FieldOutbox

    static func live(for snapshot: RelationshipSnapshot) -> Self? {
        guard let coupleID = snapshot.membership?.coupleID,
              let first = snapshot.members.first?.id
        else { return nil }

        guard let remote = FieldSupabaseBackend(
            client: SupabaseClientProvider.shared.client,
            coupleID: coupleID,
            viewerID: snapshot.profile.id,
            members: snapshot.members,
            firstMemberID: first
        ) else { return nil }

        return Self(
            outbox: FieldOutbox(
                wrapping: remote,
                // Both halves: a queue must not survive into another account,
                // and it must not survive into another relationship either.
                partition: FieldOutboxPartition(
                    userID: snapshot.profile.id,
                    coupleID: coupleID
                ),
                cache: FieldStateCache()
            )
        )
    }
}

// MARK: - Onboarding (6f)
//
// The last screen before the zones, and the first drawn in their language.
// It needs its own root because it runs while `AppSession` is still
// `.choosingHue` — the couple exists, so there is a backend to write to, but
// `FieldRoot` has not taken the screen yet.

@MainActor
struct FieldOnboardingRoot: View {
    @EnvironmentObject private var session: AppSession
    @State private var store: FieldStore?

    /// Called with the swatch they chose, so the caller can keep the legacy
    /// `couple_members.hue` column in step.
    var onFinish: (FieldSwatch) -> Void

    var body: some View {
        Group {
            if let store {
                FieldOnboardingView(
                    onFinish: {
                        onFinish(
                            store.speaker == .b
                                ? store.identity.personB
                                : store.identity.personA
                        )
                    }
                )
                .environment(store)
            } else {
                FieldPalette.bg.ignoresSafeArea()
            }
        }
        .task(id: session.snapshot?.membership?.coupleID) {
            guard store == nil else { return }
            let durable = session.snapshot.flatMap(FieldDurableBackend.live)
            let cached = durable?.outbox.cachedState()
            store = FieldStore(
                state: cached?.state ?? session.snapshot?.emptyFieldState,
                backend: durable?.outbox,
                clock: FieldLiveClock.app,
                lastLoadedAt: cached?.savedAt
            )
        }
    }
}

extension RelationshipSnapshot {
    /// A blank slate carrying only the two real names.
    ///
    /// The couple's own names are known from the session before any Field
    /// table has been read, so the app can address them correctly during the
    /// moment between launch and the first load — rather than calling them
    /// Ryan and Dylan.
    var emptyFieldState: FieldState {
        // `SupabaseRepository` orders members by stable member_slot. Keep that
        // canonical A/B order even for the held frame before Field data loads;
        // otherwise Partner B briefly becomes A and onboarding can write the
        // wrong person's colour.
        let first = members.first?.name ?? profile.name
        let second = members.dropFirst().first?.name ?? "Your partner"
        return .empty(
            nameA: first,
            nameB: second,
            now: AppTestConfiguration.current.now(fallback: Date())
        )
    }
}

extension FieldSwatch {
    /// The nearest `MemberHue`.
    ///
    /// `FieldSwatch` replaced `MemberHue` in the UI, but `couple_members.hue`
    /// is a database column with its own enum and cannot be dropped without a
    /// migration — so onboarding writes both until something migrates it.
    /// Two names overlap; the rest map by warmth, which is the only property
    /// the two vocabularies actually share.
    var memberHue: MemberHue {
        switch self {
        case .clay: .clay
        case .rust: .ember
        case .amber: .ember
        case .rose: .blush
        case .slate: .tide
        case .teal: .tide
        case .indigo: .plum
        case .sage: .sage
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
        case calendar = "02  The calendar — takeover"
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
        case .calendar:
            FieldCalendarSurface(store: store)
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

#Preview("Calendar") {
    let store = FieldStore()
    store.openCalendar()
    return FieldCalendarSurface(store: store)
        .environment(store)
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
