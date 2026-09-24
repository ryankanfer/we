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
//      tapping it returns to Today from anywhere.
//
//      One consequence, used deliberately: on Today the mark has nothing left
//      to do. So a tap there opens Yours, and a tap on LIFE while Life is
//      already showing opens the calendar. Tap to go, tap again to go deeper —
//      the same sentence twice, and the only way this bar can hold two more
//      destinations without gaining a control.
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
    @State private var planNavigation = WEPlanNavigation.shared
    @State private var intentPlan: FieldItemReference?
    /// The + card.
    @State private var showsComposer = false
    @State private var footerHeight: CGFloat = 240


    // Constructed in the body, not as a default argument. Default argument
    // expressions are evaluated in a nonisolated context, so `= FieldStore()`
    // cannot call a @MainActor initializer even though this type is
    // @MainActor. Inside the init body the isolation applies.
    init(store: FieldStore? = nil) {
        _store = State(initialValue: store ?? FieldStore())
    }

    var body: some View {
        ZStack {
            // The ground crossfades with the zone. Never a slide: the two
            // canvases are the same room under different light, and sliding
            // one away to reveal the other makes them into two places.
            store.activeZone.canvas.bg
                .ignoresSafeArea()
                .animation(.weCanvasCrossing, value: store.activeZone)

            // One glow statement per screen, and the zone is what decides
            // which one. V2 §3: warm pooling bottom-left is Life, cool
            // bottom-right is Us, split at the bottom is Today. The ground
            // beneath is constant, so this is the only thing that moves when
            // a zone changes — which is why it is the orientation.
            FieldGlow(
                identity: store.identity,
                statement: store.activeZone.glow
            )
            .animation(.weCanvasCrossing, value: store.activeZone)

            pager
                .ignoresSafeArea(.container, edges: .bottom)
                .environment(\.fieldFooterHeight, footerHeight)


            if store.calendarOpen {
                FieldCalendarSurface(store: store)
                    .environment(\.weCanvas, WECanvas.cream)
                    .transition(.opacity)
                    .zIndex(20)
            }

            if store.searchOpen {
                FieldLifeSearch(store: store)
                    .environment(\.weCanvas, WECanvas.cream)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        // The status bar is the one piece of chrome WE does not draw. Every
        // ground is near-black now, so this no longer varies — but it still
        // has to be stated, because the default follows the system and a
        // phone in light mode would paint a black clock onto #0A0A09.
        .preferredColorScheme(store.activeZone.canvas == .cream ? .light : .dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button { showsAccount = true } label: {
                    Text("Account").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("field.openAccount")
            }
            .font(FieldType.body)
            .foregroundStyle(store.activeZone.canvas.ink)
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .padding(.horizontal, FieldMetrics.screenSide)
            .background(store.activeZone.canvas.bg)
        }
        .overlay(alignment: .bottom) {
            if !store.calendarOpen, !store.searchOpen {
                VStack(spacing: 0) {
                    FieldLoadStateLine(store: store)
                    navigationBar
                }
                .foregroundStyle(store.activeZone.canvas.ink)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    footerHeight = $0
                }
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask {
                            LinearGradient(
                                colors: [.clear, .black, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay {
            FieldComposerOverlay(isPresented: $showsComposer) { store.go(to: .today) }
                .preferredColorScheme(.light)
                .environment(\.weCanvas, .cream)
                .environment(store)
        }
        .environment(store)
        .animation(.fieldZone(reduceMotion), value: store.activeZone)
        .animation(.fieldZone(reduceMotion), value: store.calendarOpen)
        .animation(.fieldZone(reduceMotion), value: store.searchOpen)
        .task { await store.load() }
        .task {
            if WEFeatureFlags.shareInboxEnabled { WEIntelligenceStore.shared.reload(); await WEIntelligenceStore.shared.synchronize() }
        }
        .sheet(item: $intentPlan) { FieldItemSheet(itemID: $0.id).environment(store) }
        .task(id: planNavigation.pendingID) {
            guard let id = planNavigation.pendingID else { return }
            await store.retryLoad()
            if store.intelligenceEligibleLifeItems.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
                intentPlan = FieldItemReference(id: id)
            }
            planNavigation.pendingID = nil
        }
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
        // The other half of the same idea: the reason a write failed may have
        // just stopped being true. `.reconnecting` is the edge `AppSession`
        // publishes the instant the path comes back, ahead of its own refresh.
        .onChange(of: session.connectionState) { _, state in
            guard state == .online || state == .reconnecting else { store.invalidateSharedIntelligence(); return }
            Task {
                await store.flushPending()
                await store.retryLoad()
                if WEFeatureFlags.shareInboxEnabled { WEIntelligenceStore.shared.reload(); await WEIntelligenceStore.shared.synchronize() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background || phase == .active else { return }
            if phase == .background { store.invalidateSharedIntelligence() }
            if phase == .active {
                store.tick()
                // A write queued on a train drains when the app comes back,
                // rather than waiting for the person to happen to type
                // something else. `flushPending` is idempotent — every
                // mutation is an upsert on a client-generated id — so a
                // foreground during a flush cannot send anything twice.
                Task {
                await store.flushPending()
                await store.retryLoad()
                if WEFeatureFlags.shareInboxEnabled { WEIntelligenceStore.shared.reload(); await WEIntelligenceStore.shared.synchronize() }
            }
            }
            Task { await store.refreshDailyMoment() }
        }
        .fullScreenCover(isPresented: $showsAccount) {
            FieldAccountView()
                .environment(store)
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
        // Told once, on the next open after a partner deleted their account.
        // The setter is ignored, like the crossing above: this is not a thing
        // to be swiped away unread, and `FieldDepartureView` dismisses itself
        // only after `acknowledge_departure()` has recorded the telling.
        .fullScreenCover(isPresented: departureBinding) {
            FieldDepartureView()
        }
        // Writing that was on this phone and owed to the server, in a file
        // that could not be read. It used to be moved aside in silence, which
        // meant the one case where somebody genuinely lost something was the
        // one case the app said nothing about — the item simply was not there
        // the next time they looked, and there was no reason for it.
        //
        // An alert rather than the hairline `FieldLoadStateLine` draws, and
        // deliberately: that line is for not knowing, and this is a loss. It
        // is also the reason there is only one button. There is nothing to
        // retry — a queue the app could not decode is a queue it cannot send —
        // so offering an action would be a second untruth on top of the first.
        .alert(
            "Some unsent writing was lost",
            isPresented: lostWritingBinding
        ) {
            Button("OK") { store.acknowledgeLostUnsentWriting() }
        } message: {
            Text(
                """
                Writing saved on this phone but not yet synced couldn't be \
                read, so it was set aside. WE can't recover it or say what it \
                said. Anything that had already synced is safe.
                """
            )
        }
        .task(id: session.snapshot?.membership?.coupleID) {
            guard let decision = crossingDecision else { return }
            await store.considerCrossing(decision: decision)
        }
    }

    /// Open while both of them are open, closed once somebody closes it.
    ///
    /// The setter is live rather than ignored, unlike the crossing below: a
    /// swipe down is a legitimate way to leave a room whose entire premise is
    /// that it can be left without residue. Routing it through `closeRoom()`
    /// rather than a local flag is what stops the cover reopening on the next
    /// realtime tick, which would be the app pushing two people back into a
    /// moment they had just stepped out of.
    private var roomBinding: Binding<Bool> {
        Binding(
            get: { store.shouldOpenRoom && store.circle.prompt != nil },
            set: { if !$0 { store.closeRoom() } }
        )
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

    /// Both halves come from the couple row: somebody left, and this person
    /// has not been told. `Couple.owesDepartureNotice` holds them together so
    /// that no caller can check one and forget the other — `departedAt` alone
    /// would raise this screen on every launch for the rest of the account's
    /// life.
    private var departureBinding: Binding<Bool> {
        Binding(
            get: { session.snapshot?.couple?.owesDepartureNotice ?? false },
            set: { _ in }
        )
    }

    /// The setter is ignored for the same reason the two covers above ignore
    /// theirs: this closes when the telling has been recorded, not because a
    /// gesture dismissed it. The button is what records it.
    private var lostWritingBinding: Binding<Bool> {
        Binding(get: { store.lostUnsentWriting }, set: { _ in })
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
            FieldTodayZone()
                .tag(FieldZone.today)

            FieldLifeZone()
                .environment(\.weCanvas, WECanvas.cream)
                .tag(FieldZone.life)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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

    /// Add something, from either zone. The one way in, always in the same
    /// place — it replaced a composer that lived only on Today.
    private var addButton: some View {
        Button {
            showsComposer = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.fieldInk(.headline))
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add something")
        .accessibilityIdentifier("field.capture.open")
    }

    private var navigationBar: some View {
        HStack(alignment: .center, spacing: 46) {
            zoneLabel(.today)
            addButton
            zoneLabel(.life)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .environment(\.weCanvas, store.activeZone.canvas)
        .animation(.weCanvasCrossing, value: store.activeZone)
    }

    /// Tap to go there. Tap it again, once you are there, to open the room
    /// behind it — the calendar, for Life.
    ///
    /// The same grammar the WE mark carries, and stated once here so the two
    /// cannot drift: a nav word that is already selected has nothing left to
    /// do, which makes it the only free surface in a bar the handoff allows no
    /// chrome on. Deliberately not a double-tap, which would delay every
    /// ordinary navigation tap by the interval SwiftUI has to wait to find out
    /// whether a second one is coming.
    private func zoneLabel(_ zone: FieldZone) -> some View {
        Button {
            // Life only. US has no room behind it, and inventing a general
            // `zone.deeperRoom` for a single case would make the bar look like
            // it holds three of these when it holds one.
            if zone == .today {
                store.returnHome()
            } else {
                store.go(to: zone)
            }
        } label: {
            Text(zone.navLabel.capitalized)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(
                    store.activeZone == zone
                        ? .fieldInk(.headline)
                        : .fieldInk(.labelQuiet)
                )
                .frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: .bottom) {
                    if store.activeZone == zone {
                        Capsule().fill(store.activeZone.canvas.ink).frame(width: 18, height: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(zone.navLabel.capitalized)
        .accessibilityHint(
            zone == .life && store.activeZone == .life
                ? "Opens the month, and everything with a date on it"
                : "Opens \(zone.navLabel.capitalized)"
        )
        .accessibilityAddTraits(store.activeZone == zone ? .isSelected : [])
        .accessibilityIdentifier("field.nav.\(zone.navLabel.lowercased())")
        // Both rooms behind Life, from the word itself, whether or not Life is
        // the active zone. The asymmetry with the sighted gestures is the
        // point: a sighted person can see which word is selected and tap it
        // twice, and can pull the screen down — where a VoiceOver user would
        // have to move focus, activate, then find the same element again to
        // reach an action that was never announced, and cannot perform a drag
        // at all.
        //
        // Search in particular has no other route for these users. It ships
        // here with the gesture, never after it.
        .accessibilityActions {
            if zone == .life {
                Button("Calendar") { store.openCalendar() }
                Button("Search") { store.openSearch() }
            }
        }
    }

}

// MARK: - Motion

extension Animation {
    /// `transform .34s cubic-bezier(.4,0,.2,1)` — the zone change, and every
    /// transition the handoff timed.
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
extension EnvironmentValues {
    @Entry var fieldFooterHeight: CGFloat = 0
}

struct FieldZoneScaffold<Content: View>: View {
    @Environment(\.fieldFooterHeight) private var footerHeight
    @Environment(\.dynamicTypeSize) private var typeSize
    let zone: FieldZone
    var horizontalPadding: CGFloat = FieldMetrics.screenSide
    /// Us carries a top-centred glow; Life and Today do not.
    var background: AnyView?
    /// Header-right metadata, at ink 0.32. Only Today carries any — it shows
    /// the date, because it is the one zone whose content is about right now.
    var headerMeta: String?
    /// Whether the zone announces itself with a tracked uppercase word.
    ///
    /// "Type Holds the Room" deletes eyebrow labels: hierarchy comes from type
    /// scale and space, not from a category header above every section. Us is
    /// the first zone converted, and turns this off.
    ///
    /// Nothing is lost to VoiceOver by doing so. The nav bar already carries
    /// each zone's name with an `.isSelected` trait, so the zone is announced
    /// once rather than twice — which is what removing a redundant header
    /// means for a screen reader as well as for the eye.
    var showsZoneLabel = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            if let background {
                background
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsZoneLabel {
                        HStack(alignment: .firstTextBaseline) {
                            FieldLabel(
                                zone.label,
                                font: FieldType.zoneLabel,
                                tracking: FieldTracking.zoneLabel,
                                ink: .label
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
                    }

                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
                .padding(.horizontal, horizontalPadding)
                // The bar grows with the type size, so a constant clearance
                // is only correct at one setting. At the accessibility sizes
                // the old 112 left the last row of every zone sitting under
                // LIFE, WE, and US.
                .padding(.bottom, footerHeight + 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Scrolling away from the capture field puts the keyboard away
            // with it. Without this, the only way out of a multi-line field is
            // its own toolbar button — and a keyboard that will not leave is
            // the loudest thing this app could possibly do.
            .scrollDismissesKeyboard(.interactively)
            // "Which zone is showing" used to be answered by the eyebrow at
            // the top of the page, which meant deleting the eyebrow deleted
            // the answer. It is a property of the zone, not of a label the
            // design happens to want, so it lives here now and survives every
            // later conversion.
            // A container, and a named one. An identifier on a bare scroll
            // view promotes it to an accessibility element with nothing to
            // say, which the audit correctly calls a defect. Naming the
            // container is not the redundancy the eyebrow was: a container
            // label is how VoiceOver reports *where you are* when you enter a
            // region, which is precisely what the deleted eyebrow used to do
            // for the eye and what the nav bar cannot do for the ear once
            // focus has moved into the page.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(zone.label)
            .accessibilityIdentifier("field.zone.\(zone.navLabel.lowercased())")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The zone declares its ground; every ramp step and hairline inside
        // resolves against it. The ground itself is painted once at the root
        // so the crossfade happens behind the pager rather than per page.
        .environment(\.weCanvas, zone.canvas)
    }
}

// MARK: - A section rule

struct FieldRuleLine: View {
    /// A rule weight rather than a colour, so the line resolves against
    /// whichever canvas it is drawn on.
    var color: FieldRuleStyle = FieldRule.primary

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
