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
    /// Provided in all three modes — `FieldRoot` injects the live session and
    /// `WEApp` injects a preview one for the gallery and seeded runs.
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: FieldStore
    @State private var showsAccount = false
    @State private var showsYours = false

    // Constructed in the body, not as a default argument. Default argument
    // expressions are evaluated in a nonisolated context, so `= FieldStore()`
    // cannot call a @MainActor initializer even though this type is
    // @MainActor. Inside the init body the isolation applies.
    init(store: FieldStore? = nil) {
        _store = State(initialValue: store ?? FieldStore())
    }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()
            FieldAmbient(
                identity: store.identity,
                hour: Calendar.gregorianUS.component(.hour, from: store.now)
            )

            pager

            if !store.calendarOpen {
                navigationBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)

                // Above the navigation bar and below everything else, in all
                // three zones at once, because what it reports is true of all
                // three at once.
                FieldLoadStateLine(store: store)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 96)
                    .transition(.opacity)
            }

            if store.calendarOpen {
                FieldCalendarSurface(store: store)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .preferredColorScheme(.dark)
        .environment(store)
        .animation(.fieldZone(reduceMotion), value: store.activeZone)
        .animation(.fieldZone(reduceMotion), value: store.calendarOpen)
        .task { await store.load() }
        // The day turning, for as long as the app is on screen. Owned by the
        // store — it is the only thing that holds `now` — but driven from
        // here, because a `.task` is cancelled with the view and a Task the
        // store started would have to reinvent that.
        .task { await store.followTheClock() }
        // Both directions matter: backgrounding is the last chance to write
        // an accurate moment, and foregrounding is when yesterday's may have
        // gone stale.
        //
        // The tick comes first and is the reason this comment is now true.
        // Re-planning before catching the clock up plans against the day the
        // app went to sleep on, which is exactly what it claimed not to do.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background || phase == .active else { return }
            if phase == .active {
                store.tick()
                // §5's ninety-day rule is about the product, not this room, so
                // this fires on every foreground whether or not Yours is ever
                // opened. Without it, somebody who used the shared side daily
                // and never opened the space would have their private writing
                // swept out from under them at ninety days.
                if FieldEntry.Mode.current == .live {
                    Task {
                        try? await YoursSupabaseBackend(
                            client: SupabaseClientProvider.shared.client
                        )?.touch()
                    }
                }
            }
            Task { await store.refreshDailyMoment() }
        }
        .fullScreenCover(isPresented: $showsAccount) {
            FieldAccountView()
                .environment(store)
        }
        .fullScreenCover(isPresented: $showsYours) {
            YoursSurface(store: yoursStore())
        }
        // 2a. Asked once, on the first arrival in the zones after a second
        // person joins — which is where both people land, whichever of them
        // redeemed the code.
        //
        // Nothing has crossed by this point and nothing can without an answer,
        // because the boundary is enforced in RLS rather than here. That is
        // what makes it safe to ask on arrival rather than mid-redemption: the
        // screen is the door, not the lock.
        .fullScreenCover(isPresented: crossingBinding) {
            if let decision = crossingDecision {
                FieldCrossingView(decision: decision)
                    .environment(store)
            }
        }
        .task(id: session.snapshot?.membership?.coupleID) {
            guard let decision = crossingDecision else { return }
            await store.considerCrossing(decision: decision)
        }
    }

    /// Read-only in the outward direction: the cover closes when the store
    /// says the question has been answered, never because a gesture dismissed
    /// it. `interactiveDismissDisabled` on the view is the other half.
    private var crossingBinding: Binding<Bool> {
        Binding(
            get: { store.owesCrossingDecision && crossingDecision != nil },
            set: { _ in }
        )
    }

    /// Built per presentation rather than held, because the store owns
    /// ephemeral state — the draft, the open drawer, the visit — and a visit
    /// that outlived the screen would defeat the presentation gate: the whole
    /// point of §5 is that the next entry waits until somebody comes back.
    ///
    /// The mode decides the backend, rather than whether a client happens to
    /// exist. `SupabaseClientProvider.shared.client` is non-nil in seeded and
    /// gallery runs too — the configuration comes from the bundle, not from
    /// being signed in — so keying off it would send `WE_FIELD=seeded`, which
    /// promises no network, straight at the network and leave every UI test
    /// asserting on a failed load.
    private func yoursStore() -> YoursStore {
        let clock = FieldLiveClock.app
        let backend: YoursBackend = switch FieldEntry.Mode.current {
        case .live:
            YoursSupabaseBackend(client: SupabaseClientProvider.shared.client)
                ?? YoursMemoryBackend(clock: clock)
        case .seeded, .gallery:
            YoursMemoryBackend(clock: clock)
        }
        return YoursStore(backend: backend, clock: clock)
    }

    private var crossingDecision: FieldCrossingDecision? {
        guard let user = session.user?.id,
              let couple = session.snapshot?.membership?.coupleID
        else { return nil }
        return FieldCrossingDecision(
            userID: user,
            coupleID: couple
        )
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
            // At the trailing edge rather than between the labels, so the
            // LIFE / WE / US symmetry the handoff specifies is untouched.
            //
            // Beside the WE mark deliberately: CIRCLE.md §2 makes the whole
            // product legible at a glance — one circle is yours, two apart is
            // invited, two joined is WE — and that grammar only teaches itself
            // if the two marks are visible in the same place at the same time.
            .overlay(alignment: .trailing) { yoursMark }

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
    ///
    /// Tap returns to Today; long-press opens the account. The handoff allows
    /// no chrome for settings, so the mark carries it — but a long-press does
    /// not exist for VoiceOver, so the accessibility action below is the only
    /// route for those users and is not optional.
    private var weMark: some View {
        // Not a `Button`: a Button consumes the long press, so tap and
        // long-press have to be attached as peers to the same shape.
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
        .onTapGesture { store.returnHome() }
        .onLongPressGesture(minimumDuration: 0.5) { showsAccount = true }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("WE")
        .accessibilityHint("Returns to Today")
        .accessibilityIdentifier("field.nav.we")
        .accessibilityAction { store.returnHome() }
        .accessibilityAction(named: "Account") { showsAccount = true }
    }

    /// The way in, and the mark that carries the whole state grammar.
    ///
    /// Not a fourth zone: `FieldZone.rawValue` is the indicator's offset
    /// multiplier over a 48pt track and the enum is persisted, so a fourth
    /// case fights both — and §7's surface is not zone-shaped anyway. Not a
    /// long-press either, because the WE mark's long-press is the account.
    ///
    /// A cover, like the account and the crossing. Wordless: after the two
    /// teaching moments the shape carries it alone, so there is no label here
    /// and no settings row anywhere that names it.
    private var yoursMark: some View {
        Button {
            showsYours = true
        } label: {
            YoursMark(
                style: .compact,
                presence: .living,
                hue: store.identity.personA.color
            )
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.nav.yours")
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
            // Scrolling away from the capture field puts the keyboard away
            // with it. Without this, the only way out of a multi-line field is
            // its own toolbar button — and a keyboard that will not leave is
            // the loudest thing this app could possibly do.
            .scrollDismissesKeyboard(.interactively)
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
