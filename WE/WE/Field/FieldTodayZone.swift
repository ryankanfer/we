//
//  FieldTodayZone.swift
//  WE
//
//  WE / Today, as a short brief.
//
//  **Nothing is ever stored here.** Every section is read from Life at the
//  moment of viewing through `FieldTodayBriefBuilder`, so editing or deleting
//  an item changes every place it appears.
//
//  The page used to be a transcript: a greeting bubble, each addition as a
//  bubble, WE's reply to each, and private look ups as exchanges. That made
//  a list of shared things read like a chat room with a third speaker in it.
//  It reads top to bottom now and then stops:
//
//    the date · what matters now · what they kept · what is coming ·
//    what still needs deciding · keep something, or ask
//
//  Look ups open in Ask WE (`FieldAskSheet`). Saving says where it went from
//  the bar (`FieldZoneShell.savedLine`). Neither is written into the page.
//

import SwiftUI

struct FieldTodayZone: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession

    /// 6d, reached from the held line.
    @State private var showsDeferral = false
    /// The shared question, opened from its line. Us is no longer a zone.
    @State private var showsSharedQuestion = false
    /// Whatever section somebody tapped.
    @State private var openItem: FieldItemReference?

    var body: some View {
        let brief = FieldTodayBriefBuilder.build(store: store)

        FieldZoneScaffold(
            zone: .today,
            showsZoneLabel: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TodayEditorialHeader()
                    .padding(.bottom, 36)

                if let error = store.itemSaveError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.headline))
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("field.today.saveError")
                }

                lead(brief.lead)
                    .padding(.bottom, FieldMetrics.sectionGap)

                // Only me, on the day its author picked. Only ever on the
                // author's phone: a private row reaches nobody else.
                ForEach(store.heldItemsReadyToOffer) { item in
                    FieldHeldReadyCard(item: item, openItem: $openItem)
                        .padding(.bottom, FieldMetrics.sectionGap)
                }

                if let discovery = brief.discovery {
                    TodayPartnerDiscovery(entry: discovery, openItem: $openItem)
                }

                if let ahead = brief.ahead {
                    TodayLookingAhead(entry: ahead, openItem: $openItem)
                }

                if !brief.proposalIDs.isEmpty {
                    TodayProposals(messageIDs: brief.proposalIDs, openItem: $openItem)
                }

                if WEFeatureFlags.shareInboxEnabled {
                    WEPrivateTimeItems().environment(store).padding(.vertical, 12)
                    WESharedTimeItems().environment(store).padding(.vertical, 12)
                }

                if sharedQuestionIsReady {
                    sharedJourneyHandoff
                }

                FieldRuleLine()
                    .padding(.bottom, 4)
                TodayRemainder(moreItemIDs: brief.moreItemIDs, showsDeferral: $showsDeferral)
                TodayCaptureBar()
                    .padding(.top, 12)
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
        // Proposals shown here are seen; see `FieldStore.markDecisionsSeen`.
        .task(id: "\(store.activeZone == .today):\(store.chatMessages.count)") {
            guard store.activeZone == .today else { return }
            await store.markDecisionsSeen()
        }
        .sheet(isPresented: $showsSharedQuestion) {
            SharedJourneyUsSurface()
                .environment(store)
                .environmentObject(session)
        }
    }

    @ViewBuilder
    private func lead(_ lead: FieldTodayBrief.Lead) -> some View {
        switch lead {
        case .moment(let moment, let fact, let sourceURL):
            FieldMomentView(moment: moment, fact: fact, sourceURL: sourceURL)
        case .discovery(let entry):
            TodayDiscoveryLead(entry: entry, openItem: $openItem)
        case .clear(let headline, let detail):
            TodayClearLead(headline: headline, detail: detail)
        }
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
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.today.sharedJourney")
    }
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
    /// One factual sentence under the headline, read from the item itself.
    var fact: String? = nil
    /// The page the item arrived as. The only source of its picture.
    var sourceURL: URL? = nil

    private var accentColor: Color {
        moment.accent == .shared
            ? store.identity.personB.color(on: .surface)
            : store.identity.color(for: moment.accent, on: .cream)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = store.state.lifeItems.first(where: { $0.id == moment.id }) {
                WEPrivacyLabel(text: store.privacyLabel(for: item)).padding(.bottom, 8)
            }
            FieldLabel(moment.source)
                .padding(.bottom, 18)

            // Presence (6b): when one partner is unreachable the day's item is
            // addressed to the other by name, and the override is still there.
            if let addressee = moment.addressedTo {
                Text("FOR \(store.identity.name(for: addressee).uppercased()), ALONE")
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(store.identity.color(for: addressee, on: .cream))
                    .padding(.bottom, 14)
            }

            // The one large picture on the page, when the thing came from a
            // page that has one. Its frame is reserved before it arrives.
            if let sourceURL {
                FieldPreviewPlate(url: sourceURL, aspect: 3 / 2)
                    .padding(.bottom, 22)
            }

            WEWordReveal(
                text: moment.headline,
                font: FieldType.hero,
                tracking: FieldTracking.hero,
                lineSpacing: 4
            )
            .foregroundStyle(.fieldInk(.headline))
            .padding(.bottom, 14)

            if let fact {
                Text(fact)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 15)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                    .accessibilityIdentifier("field.today.lead.fact")
            }

            // The app opened the phone and does not know how it went. Asked
            // once, above the usual actions, and never asked again today.
            if let outcome = store.awaitingOutcome, outcome.id == moment.id {
                outcomeQuestion(outcome)
                    .padding(.bottom, 22)
            }

            actions

            // Why this, and not something else. Quiet, and after the action:
            // the reason is there for whoever wants it, not in the way.
            DisclosureGroup("Why this?") {
                FieldReasoning(text: moment.reasoning, accent: accentColor)
                    .padding(.top, 12)
            }
            .font(FieldType.reasoning)
            .foregroundStyle(.fieldInk(.reasoning))
            .padding(.top, 20)
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
                            .tint(WECanvas.surface.ink)
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


// MARK: - Hold until, on the day

/// "You held this for today." The one moment Only me asks anything of
/// anyone, and it asks its author. Two equal answers: share it, or keep it.
/// Keeping it clears the day rather than snoozing, because a question asked
/// twice about the same private thing starts to feel like pressure.
private struct FieldHeldReadyCard: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.weCanvas) private var canvas
    let item: LifeItem
    @Binding var openItem: FieldItemReference?
    @State private var confirmsShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                FieldDot(owner: item.owner, isPrivate: true, identity: store.identity)
                FieldLabel(WEOnlyMeCopy.readyLabel)
            }

            Button {
                openItem = FieldItemReference(id: item.id)
            } label: {
                Text(item.title)
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.headline))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            Text(WEOnlyMeCopy.readyLine)
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))

            HStack(spacing: 12) {
                Button(WEOnlyMeCopy.readyShare(partner: store.partnerName)) {
                    confirmsShare = true
                }
                .buttonStyle(FieldFilledButtonStyle())
                .accessibilityIdentifier("field.today.held.share")

                Button(WEOnlyMeCopy.readyKeep) {
                    store.setHold(item.id, until: nil)
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .accessibilityIdentifier("field.today.held.keep")
            }
        }
        .padding(FieldMetrics.cardPadding + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: FieldMetrics.cardRadius)
                .strokeBorder(
                    canvas.ink.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .confirmationDialog(
            "Share with \(store.partnerName)?",
            isPresented: $confirmsShare,
            titleVisibility: .visible
        ) {
            Button("Share it") { store.share(item.id) }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("\(store.partnerName) will be able to see it from now on. It can't be made private again.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.today.held")
    }
}
