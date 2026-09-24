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

import SwiftUI

struct FieldTodayZone: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession

    /// 6d, reached from "What I'm watching".
    @State private var showsDeferral = false
    /// The shared question, opened from its line. Us is no longer a zone.
    @State private var showsSharedQuestion = false

    /// The watched line somebody tapped, when that line is reading a filed
    /// thing back.
    @State private var openItem: FieldItemReference?

    var body: some View {
        FieldZoneScaffold(
            zone: .today,
            showsZoneLabel: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").font(FieldType.pageHeadline)
                        Spacer()
                        todayDate
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today").font(FieldType.pageHeadline)
                        todayDate
                    }
                }
                .foregroundStyle(.fieldInk(.headline))
                .padding(.bottom, 24)

                if let error = store.itemSaveError {
                    Text(error).font(FieldType.body)
                        .foregroundStyle(.fieldInk(.headline))
                        .padding(.bottom, 20)
                        .accessibilityIdentifier("field.today.saveError")
                }
                FieldDayConversationView(
                    part: .opening,
                    openItem: $openItem,
                    showsDeferral: $showsDeferral
                )
                .padding(.bottom, 8)

                Group {
                    switch store.todaySelection {
                    case .resolved(let headline, let detail, _):
                        resolvedHero(headline, detail)
                    case .needsYou(let moment):
                        FieldMomentView(moment: moment)
                    }
                }
                .padding(.vertical, 12)

                if WEFeatureFlags.shareInboxEnabled {
                    WEPrivateTimeItems().environment(store).padding(.vertical, 12)
                    WESharedTimeItems().environment(store).padding(.vertical, 12)
                }
                if sharedQuestionIsReady {
                    sharedJourneyHandoff
                        .padding(.top, FieldMetrics.sectionGapLoose)
                }

                // The day's conversation: what either of you added today, WE's
                // replies, decisions, and this person's private look-ups. It
                // replaces the watching list and the separate chat.
                FieldDayConversationView(
                    part: .thread,
                    openItem: $openItem,
                    showsDeferral: $showsDeferral
                )
                .padding(.top, FieldMetrics.sectionGap)
                .padding(.bottom, FieldMetrics.sectionGap)
            }
        }
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
        }
        .fullScreenCover(isPresented: $showsDeferral) {
            FieldDeferralView()
                .environment(store)
        }
        .sheet(isPresented: $showsSharedQuestion) {
            SharedJourneyUsSurface()
                .environment(store)
                .environmentObject(session)
        }

    }

    private var todayDate: some View {
        Text(store.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.reasoning))
            .fixedSize()
    }

    private var sharedQuestionIsReady: Bool {
        guard WEFeatureFlags.sharedJourneysEnabled,
              let snapshot = session.snapshot,
              let viewer = session.user?.id
        else { return false }
        if case .question = SharedJourneyPolicy.presentation(
            snapshot: snapshot,
            viewerID: viewer,
            now: store.now
        ) { return true }
        return false
    }

    private var sharedJourneyHandoff: some View {
        Button {
            showsSharedQuestion = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("One shared question is ready.")
                    .font(FieldType.listItem)
                    .foregroundStyle(.fieldInk(.headline))
                Spacer(minLength: 0)
                Text("OPEN")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.dateCount))
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { FieldRuleLine() }
            .overlay(alignment: .bottom) { FieldRuleLine(color: FieldRule.row) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.today.sharedJourney")
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

                VStack(spacing: 16) {
                    Text(headline)
                        .font(FieldType.hero)
                        .tracking(FieldTracking.hero)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.12, size: 42)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.6, size: 15)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 270)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The combine stops here rather than wrapping the mark with
                // it. The mark used to be inside this element and
                // `accessibilityHidden(true)` besides — correct while it was
                // decoration, and wrong the moment it became the only control
                // on this screen. A button folded into a combined label is not
                // a button to VoiceOver.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(headline) \(detail)")
            }
            .frame(maxWidth: .infinity)
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

    // The horizon is not repeated here.
    //
    // Us states it larger, with its thesis and its evidence attached, and a
    // second rendering of the same sentence taught people that Today was where
    // the long view lived. Today is about now; the horizon is the one thing on
    // this app that explicitly is not. The old copy also carried a hardcoded
    // "To tickets" sub-label, which was true of exactly one horizon.
}

// MARK: - (b) and (c)
//
// Same shape: source label, the statement as the headline, the reasoning
// behind an accent border, then two or three actions — one filled, one
// outlined, one text-only escape.

struct FieldMomentView: View {
    @Environment(FieldStore.self) private var store
    @State private var actionItem: FieldItemReference?
    let moment: FieldMoment

    private var accentColor: Color {
        moment.accent == .shared
            ? store.identity.personB.color(on: .cream)
            : store.identity.color(for: moment.accent, on: .cream)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = store.state.lifeItems.first(where: { $0.id == moment.id }) {
                WEPrivacyLabel(text: store.privacyLabel(for: item)).padding(.bottom, 8)
            }
            FieldLabel(moment.source)
                .padding(.bottom, 22)

            // Presence (6b): when one partner is unreachable the day's item is
            // addressed to the other by name, and the override is still there.
            if let addressee = moment.addressedTo {
                Text("FOR \(store.identity.name(for: addressee).uppercased()), ALONE")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(store.identity.color(for: addressee, on: .cream))
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
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 15)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
            }

            DisclosureGroup("Why this?") {
                FieldReasoning(text: moment.reasoning, accent: accentColor)
                    .padding(.top, 12)
            }
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.headline))
            .padding(.bottom, 24)

            // The app opened the phone and does not know how it went. Asked
            // once, above the usual actions, and never asked again today.
            if let outcome = store.awaitingOutcome, outcome.id == moment.id {
                outcomeQuestion(outcome)
                    .padding(.bottom, 22)
            }

            actions


        }
        .accessibilityIdentifier("field.today.moment")
        // Where anything outward gets confirmed. It is a sheet rather than an
        // inline card because it is the one screen in the app that stands
        // between a tap and something happening in the world, and it should
        // take the whole of somebody's attention for the second it needs.
        .sheet(item: $actionItem) { reference in
            FieldItemSheet(itemID: reference.id)
                .environment(store)
        }
    }

    /// "You called the vet. Is that one done?"
    private func outcomeQuestion(_ outcome: FieldOutcomeQuestion) -> some View {
        FieldCard(accent: accentColor) {
            VStack(alignment: .leading, spacing: 13) {
                Text(outcome.question)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Button("It's done") { store.resolveOutcome(outcome, done: true) }
                        .buttonStyle(FieldFilledButtonStyle())
                        .accessibilityIdentifier("field.outcome.done")
                    Button("I reached out and am waiting for a reply") {
                        store.confirmWaitingForReply(outcome)
                    }
                    .buttonStyle(FieldOutlinedButtonStyle())
                    .accessibilityIdentifier("field.outcome.waiting")
                    Button("Still on me") { store.resolveOutcome(outcome, done: false) }
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
                                    store.identity.color(for: $0, on: .cream)
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
                        Button { perform(action) } label: {
                            Text(action.title)
                                .font(FieldType.button)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                        }
                            .buttonStyle(.glassProminent)
                            .tint(WECanvas.cream.ink)
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
    /// Anything that needs a number goes through the store, which finds what
    /// it can and then stops, because the last decision before something
    /// leaves the phone is never the app's.
    private func begin(_ act: FieldAct) {
        guard store.state.lifeItems.contains(where: { $0.id == moment.id }) else { return }
        actionItem = FieldItemReference(id: moment.id)
    }
}
