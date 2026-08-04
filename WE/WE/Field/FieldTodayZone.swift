//
//  FieldTodayZone.swift
//  WE
//
//  WE / Today — the intelligent clearing. Option 5a.
//
//  **Nothing is ever stored here.** Every item is drawn from Life or Us at the
//  moment of viewing, which is why this view reads `store.todaySelection` (a
//  computed property) rather than any field.
//
//  Three states, all designed:
//    (a) Today is clear — the state to be proud of.
//    (b) Something needs you — one thing, full screen.
//    (c) A question toward Us — two equal-weight tinted choices.
//
//  Every one of them closes with the honest remainder, and every one carries a
//  reason.
//

// The event store is passed to Apple's editor and never written to here.
// See `FieldEventEditor`.
import EventKit
import EventKitUI
import SwiftUI

struct FieldTodayZone: View {
    @Environment(FieldStore.self) private var store

    /// 6d, reached from "What I'm watching".
    @State private var showsDeferral = false

    /// The watched line somebody tapped, when that line is reading a filed
    /// thing back.
    @State private var openItem: FieldItemReference?

    var body: some View {
        FieldZoneScaffold(
            zone: .we,
            headerMeta: DateFormatter.fieldDayMonth
                .string(from: store.now)
                .uppercased()
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // One hairline under the Today header, purely as a signal that
                // the space is jointly held. This is a sanctioned use of the
                // blend — it is not decoration and it appears nowhere else on
                // this screen.
                Rectangle()
                    .fill(store.identity.blend())
                    .frame(height: 1)
                    .opacity(0.55)
                    .padding(.bottom, 30)
                    .accessibilityHidden(true)

                // The hero, then the way in. Capture sits directly under
                // whatever the app has to say, because saying something back
                // is the reply to it — everything else on this screen is
                // context and belongs below.
                switch store.todaySelection {
                case .resolved(let headline, let detail, _):
                    resolvedHero(headline, detail)
                case .needsYou(let moment):
                    FieldMomentView(moment: moment)
                }

                FieldCaptureField()
                    .padding(.top, FieldMetrics.sectionGapLoose)

                if case .resolved(_, _, let watching) = store.todaySelection {
                    // The heading is a claim, and with nothing under it the
                    // claim was false: a label, two rules and a gap, on the
                    // one screen that is supposed to read as resolved. A
                    // couple with no open question, no horizon and nothing
                    // held is not being watched over — so the app says
                    // nothing rather than drawing an empty frame around it.
                    if !watching.isEmpty {
                        watchingBlock(watching)
                            .padding(.top, FieldMetrics.sectionGapLoose)
                            .padding(.bottom, FieldMetrics.sectionGap)
                    }

                    horizonBlock
                }
            }
        }
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
        }
        .fullScreenCover(isPresented: $showsDeferral) {
            FieldDeferralView()
                .environment(store)
        }
    }

    // MARK: (a) Today is clear
    //
    // "This screen must feel like a resolution, not an empty state." Which is
    // why the sentence is one — an absence phrased as an absence reads as the
    // app having nothing to offer, and it has cleared the day.

    /// The resolved headline — a real state, and the only thing above the
    /// capture field. What the app is watching, and the horizon, follow the
    /// capture rather than separating it from the headline.
    ///
    /// Both strings are derived, so this renders whatever the intelligence
    /// found true: a clear day, or an account it is still learning.
    private func resolvedHero(
        _ headline: String,
        _ detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 26) {
                FieldIntelligenceMark(
                    identity: store.identity,
                    diameter: 28,
                    ringDiameter: 70
                )
                .frame(height: 70)

                VStack(spacing: 16) {
                    Text(headline)
                        .font(FieldType.hero)
                        .tracking(FieldTracking.hero)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.12, size: 42)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.6, size: 15)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 270)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(headline) \(detail)")
        }
    }

    private func watchingBlock(_ items: [FieldWatchItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            // 6d is reached from the label rather than from a new control.
            //
            // "What I'm watching" is already the sentence the deferral screen
            // elaborates on, so the heading *is* the affordance and the zone
            // gains nothing to look at. Shown only when something is actually
            // held back — a heading that opens an empty screen is worse than a
            // heading that does nothing.
            Group {
                if store.heldTopics.isEmpty {
                    FieldLabel("What I'm watching")
                } else {
                    Button {
                        showsDeferral = true
                    } label: {
                        FieldLabel("What I'm watching")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows what is being held back, and why")
                    .accessibilityIdentifier("field.today.watching.open")
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        FieldRuleLine(color: FieldRule.watching)
                    }

                    watchingRow(item)
                }
            }
            .padding(.bottom, 4)

            FieldRuleLine()
        }
        .accessibilityElement(children: .contain)
    }

    /// One watched line — and, when the line is reading a filed thing back,
    /// the way into it.
    ///
    /// The rows all looked alike and none of them did anything, so the section
    /// read as a printout. A line about an open question is a line about an
    /// item that exists, and tapping it opens that item where every other
    /// surface opens it. A line about a horizon question or a held topic has
    /// no item behind it and stays exactly as it was.
    @ViewBuilder
    private func watchingRow(_ item: FieldWatchItem) -> some View {
        if let itemID = item.itemID,
            store.state.lifeItems.contains(where: { $0.id == itemID })
        {
            Button {
                openItem = FieldItemReference(id: itemID)
            } label: {
                watchingRowBody(item)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens where it was filed")
            .accessibilityIdentifier("field.watching.row")
        } else {
            watchingRowBody(item)
        }
    }

    private func watchingRowBody(_ item: FieldWatchItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            FieldDot(
                owner: item.owner,
                identity: store.identity,
                size: FieldDotSize.list,
                baselineNudge: 6,
                opacity: item.isDeferred ? 0.55 : 1
            )

            Text(item.text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(
                    // The deferred line is dimmed because it is being held,
                    // not because it matters less.
                    item.isDeferred
                        ? .fieldInk(.deemphasisedItem)
                        : .fieldInk(.legend)
                )
                .fieldLineHeight(1.6, size: 14)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var horizonBlock: some View {
        if let horizon = store.primaryHorizon {
            let countdown = horizon.countdown(now: store.now)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("Next on the horizon")

                    Text(
                        [horizon.title, horizon.window]
                            .compactMap { $0 }
                            .joined(separator: " ")
                            .replacingOccurrences(of: ", ", with: " · ")
                    )
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(countdown)
                        .font(FieldType.metric)
                        .foregroundStyle(store.identity.personB.color)

                    FieldLabel(
                        "To tickets",
                        font: FieldType.subLabel,
                        tracking: FieldTracking.subLabel,
                        color: .fieldInk(.headerMeta),
                        isHeader: false
                    )
                }
            }
            .padding(.top, 22)
            .contentShape(Rectangle())
            .onTapGesture { store.go(to: .us) }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Us")
        }
    }
}

// MARK: - (b) and (c)
//
// Same shape: source label, the statement as the headline, the reasoning
// behind an accent border, then two or three actions — one filled, one
// outlined, one text-only escape.

struct FieldMomentView: View {
    @Environment(FieldStore.self) private var store
    let moment: FieldMoment

    /// The event about to be offered to Apple's editor. Held here rather than
    /// in the store because nothing has been decided until the person taps
    /// Add in a sheet the app does not own.
    @State private var calendarDraft: FieldEventDraft?

    private var accentColor: Color {
        moment.accent == .shared
            ? store.identity.personB.color
            : store.identity.color(for: moment.accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(moment.source)
                .padding(.bottom, 22)

            // Presence (6b): when one partner is unreachable the day's item is
            // addressed to the other by name, and the override is still there.
            if let addressee = moment.addressedTo {
                Text("FOR \(store.identity.name(for: addressee).uppercased()), ALONE")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(store.identity.color(for: addressee))
                    .padding(.bottom, 14)
            }

            Text(moment.headline)
                .font(FieldType.hero)
                .tracking(FieldTracking.hero)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.12, size: 42)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            if case .question(let question) = moment.shape {
                Text(question.stakes)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 15)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
            }

            FieldReasoning(text: moment.reasoning, accent: accentColor)
                .padding(.bottom, 30)

            // The app opened the phone and does not know how it went. Asked
            // once, above the usual actions, and never asked again today.
            if let outcome = store.awaitingOutcome, outcome.id == moment.id {
                outcomeQuestion(outcome)
                    .padding(.bottom, 22)
            }

            actions

            if let remainder = moment.remainder {
                Text(remainder)
                    .font(.system(size: 13.5, design: .serif))
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.6, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 30)
            }
        }
        .accessibilityIdentifier("field.today.moment")
        // Where anything outward gets confirmed. It is a sheet rather than an
        // inline card because it is the one screen in the app that stands
        // between a tap and something happening in the world, and it should
        // take the whole of somebody's attention for the second it needs.
        .sheet(item: outreachBinding) { request in
            FieldOutreachConfirmation(request: request)
                .environment(store)
        }
        .sheet(item: calendarDraftBinding) { draft in
            FieldEventEditor(draft: draft, store: EKEventStore()) { action in
                calendarDraft = nil
                // The only outcome the app may treat as fact: EventKit is
                // telling it an event exists, rather than the app assuming
                // one does because it opened a sheet.
                if action == .saved { store.complete(moment.id) }
            }
            .ignoresSafeArea()
        }
    }

    private var outreachBinding: Binding<FieldOutreachRequest?> {
        Binding(
            get: { store.pendingOutreach },
            set: { if $0 == nil { store.dismissOutreach() } }
        )
    }

    private var calendarDraftBinding: Binding<FieldEventDraft?> {
        Binding(get: { calendarDraft }, set: { calendarDraft = $0 })
    }

    /// "You called the vet. Is that one done?"
    private func outcomeQuestion(_ outcome: FieldOutcomeQuestion) -> some View {
        FieldCard(accent: accentColor) {
            VStack(alignment: .leading, spacing: 13) {
                Text(outcome.question)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 11) {
                    Button("Done") { store.resolveOutcome(outcome, done: true) }
                        .buttonStyle(FieldFilledButtonStyle())
                        .accessibilityIdentifier("field.outcome.done")

                    Button("Not yet") { store.resolveOutcome(outcome, done: false) }
                        .buttonStyle(FieldQuietButtonStyle())
                        .accessibilityIdentifier("field.outcome.notYet")
                }
            }
        }
    }

    /// A question's two choices are equal weight and person-tinted; a
    /// statement's actions run filled, outlined, then the escape.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 11) {
            if case .question = moment.shape {
                HStack(spacing: 11) {
                    ForEach(moment.actions.filter { $0.weight == .outlined }) { action in
                        Button(action.title) {
                            perform(action)
                        }
                        .buttonStyle(
                            FieldOutlinedButtonStyle(
                                tint: action.tint.map {
                                    store.identity.color(for: $0)
                                }
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                // Branched here rather than in a helper: a function returning
                // `some ButtonStyle` can only ever return one concrete type,
                // and these are two.
                ForEach(moment.actions.filter { $0.weight != .quiet }) { action in
                    if action.weight == .filled {
                        Button(action.title) { perform(action) }
                            .buttonStyle(FieldFilledButtonStyle())
                            .accessibilityIdentifier(identifier(for: action))
                    } else {
                        Button(action.title) { perform(action) }
                            .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
                            .accessibilityIdentifier(identifier(for: action))
                    }
                }
            }

            ForEach(moment.actions.filter { $0.weight == .quiet }) { action in
                Button(action.title) { perform(action) }
                    .buttonStyle(FieldQuietButtonStyle())
                    .accessibilityIdentifier(identifier(for: action))
            }
        }
    }

    /// Addressable by what the button is for rather than by what it says.
    ///
    /// The words change with the thing — "Make the call", "Book it", "Mark it
    /// done" — and every button style uppercases its label, so a test that
    /// matched on text was matching on two coincidences at once.
    private func identifier(for action: FieldMomentAction) -> String {
        switch action.role {
        case .act: "field.moment.act"
        case .choice: "field.moment.choice"
        case .postpone: "field.moment.postpone"
        case .overrideAbsence: "field.moment.override"
        }
    }

    /// Every button, by what it is for.
    ///
    /// This used to switch on the moment's shape and the button's *weight*,
    /// which meant a statement's escape and its override — the two quietest,
    /// most-needed buttons on the screen — fell through to nothing at all.
    /// The role is decided where the action is built, so there is no branch
    /// left here that can silently do nothing.
    private func perform(_ action: FieldMomentAction) {
        switch action.role {
        case .choice(let choice):
            guard case .question(let question) = moment.shape else { return }
            store.answer(question, with: choice)

        case .postpone(let window):
            // The escape is an answer too — it means "not now", and the app
            // has to actually stop asking until the time it agreed to.
            store.hold(
                id: moment.id,
                subject: moment.headline,
                until: window,
                reason: "You asked me to come back to it."
            )

        case .overrideAbsence:
            store.raiseWithBoth(moment.id)

        case .act(let act):
            begin(act)
        }
    }

    /// The verb, doing what it says.
    ///
    /// A calendar draft is decided here and now — it needs nothing from the
    /// world, so there is nothing to look up and nothing to confirm beyond
    /// Apple's own sheet. Anything that needs a number goes through the
    /// store, which finds what it can and then stops, because the last
    /// decision before something leaves the phone is never the app's.
    private func begin(_ act: FieldAct) {
        guard let item = store.state.lifeItems.first(where: {
            $0.id == moment.id
        }) else {
            store.complete(moment.id)
            return
        }

        switch act {
        case .call, .message, .email, .book:
            // Booking is a phone call when there is somebody to call — that
            // is what booking a vet actually is. The store finds what it can
            // and then stops.
            Task { await store.begin(act, for: moment.id) }

        case .schedule:
            guard FieldCalendarAccess.isAuthorized else {
                // There is a calendar to fill in and the couple never
                // connected one. The app does not go asking for access at the
                // moment somebody wanted something else entirely.
                store.complete(moment.id)
                return
            }
            calendarDraft = FieldOutreach.draft(for: item, now: store.now)

        case .pay, .order, .none:
            // Real acts with no honest destination on this phone. Paying a
            // bill means somebody's banking app and the app has no idea
            // which; opening the wrong one is worse than opening nothing.
            store.complete(moment.id)
        }
    }
}
