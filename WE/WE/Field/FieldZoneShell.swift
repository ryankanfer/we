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
//      A tap on LIFE while Life is already showing opens the calendar.
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

            if !store.calendarOpen, !store.searchOpen {
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

            if store.searchOpen {
                FieldLifeSearch(store: store)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        // The status bar is the one piece of chrome WE does not draw. Every
        // ground is near-black now, so this no longer varies — but it still
        // has to be stated, because the default follows the system and a
        // phone in light mode would paint a black clock onto #0A0A09.
        .preferredColorScheme(.dark)
        .environment(store)
        .animation(.fieldZone(reduceMotion), value: store.activeZone)
        .animation(.fieldZone(reduceMotion), value: store.calendarOpen)
        .animation(.fieldZone(reduceMotion), value: store.searchOpen)
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
            }
            Task { await store.refreshDailyMoment() }
        }
        .fullScreenCover(isPresented: $showsAccount) {
            FieldAccountView()
                .environment(store)
        }
        // The circle. Presented from the shell rather than from Today, because
        // the second person's tap can land while the first is reading Life —
        // it belongs to both of them, not to one navigation zone.
        .fullScreenCover(isPresented: roomBinding) {
            FieldCircleRoom(
                identity: store.identity,
                // Non-nil whenever the state is `.both`, which is the only
                // state this binding is true for. Nothing is invented locally
                // if it somehow is nil — the room simply does not open, which
                // is better than opening it around words nobody was given.
                prompt: store.circle.prompt ?? "",
                onClose: { store.closeRoom() }
            )
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
        }
        .padding(.top, 16)
        .padding(.horizontal, FieldMetrics.screenSide)
        .padding(.bottom, 30)
        // The bar is chrome over whichever page is showing, so it takes that
        // page's canvas rather than a scaffold's. Without this the labels stay
        // cream ink and vanish the moment Life scrolls under them.
        .environment(\.weCanvas, store.activeZone.canvas)
        .animation(.weCanvasCrossing, value: store.activeZone)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: store.activeZone.canvas.bg.opacity(0.96), location: 0),
                        .init(color: store.activeZone.canvas.bg.opacity(0.96), location: 0.45),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )

                // Sits *behind* the navigation and below the words, at the
                // display edge. It replaces the sliding indicator that used to
                // live here: an indicator tracking the selected zone is a
                // progress device, and the direction bans those. Selection is
                // carried by the words themselves, full ink against reduced.
                //
                // Both hues, in every zone. The bar is the couple's chrome and
                // all three zones hold both people's material; `.mine` is for
                // the genuinely private surfaces — composition, the stillness,
                // the Promise — which arrive with the ceremony.
                WEColourField(state: .shared, identity: store.identity)
            }
            .ignoresSafeArea(edges: .bottom)
            // Deliberately *not* `accessibilityHidden`. The scrim and the
            // field are colour with no node of their own, and marking a view
            // that is not an accessibility element hidden promotes it to one
            // — an element carrying nothing but a hidden flag, which the
            // audit then reports as a node with no description. Hiding what
            // was never there is what created the defect.
        }
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
            if zone == .life, store.activeZone == .life {
                store.openCalendar()
            } else {
                store.go(to: zone)
            }
        } label: {
            Text(zone.navLabel)
                .font(FieldType.zoneLabel)
                .tracking(FieldTracking.zoneLabel)
                .foregroundStyle(
                    store.activeZone == zone
                        ? .fieldInk(.headline)
                        : .fieldInk(.labelQuiet)
                )
                .frame(minWidth: 44, minHeight: 44)
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

    /// 40 × 40pt circle, 1px border at ink .5, fill ink .06, the wordmark in
    /// 11pt DM Sans at +2.4. Present on every zone.
    ///
    /// Tap returns to Today; long-press opens the account. A long-press does
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
        .accessibilityHint(isHome ? "" : "Returns to Today")
        .accessibilityIdentifier("field.nav.we")
        .accessibilityAction { store.returnHome() }
        .accessibilityAction(named: "Account") { showsAccount = true }
    }

    /// Whether the mark has nothing left to do as a way home.
    ///
    /// Today, with nothing over it. The two overlays count as "not home"
    /// deliberately: while one is up the mark has to mean *close this*.
    private var isHome: Bool {
        store.activeZone == .we && !store.calendarOpen && !store.searchOpen
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
struct FieldZoneScaffold<Content: View>: View {
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
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, horizontalPadding)
                // The bar grows with the type size, so a constant clearance
                // is only correct at one setting. At the accessibility sizes
                // the old 112 left the last row of every zone sitting under
                // LIFE, WE, and US.
                .padding(.bottom, FieldMetrics.screenBottom(at: typeSize))
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
