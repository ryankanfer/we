//
//  FieldItemHelp.swift
//  WE
//
//  The block under an item, on the occasions there is one.
//
//  The gate is the feature. `FieldItemSteps.actions` returns an empty array for
//  most things a couple files, and an empty array draws nothing at all — no
//  heading, no rule line, no "no suggestions". A sheet that grows a helpful
//  section under every single item is an app with an opinion about a shopping
//  list, and the whole discipline here is that it usually has none.
//
//  Nothing on this screen has already happened. Every button opens something
//  at the moment it is tapped, to a place named underneath it, and the app is
//  not involved after that. There is no lookup on appear.
//

import EventKit
import SwiftUI

struct FieldItemHelp: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.openURL) private var openURL

    let item: LifeItem

    /// One piece of state for both sheets, and one `.sheet` modifier below.
    ///
    /// Two `.sheet` modifiers on the same view is not a thing SwiftUI
    /// supports: the second silently displaces the first, and the *presenting*
    /// sheet — the item sheet this block lives inside — closes the moment the
    /// block appears. Which is exactly what happened, and it took a UI test
    /// dumping the accessibility tree to see it, because the symptom was the
    /// item sheet vanishing rather than anything here looking wrong.
    private enum Presenting: Identifiable {
        case calendar(FieldEventDraft)
        case shops(ShopSearch)

        var id: String {
            switch self {
            case .calendar(let draft): "calendar-\(draft.id)"
            case .shops(let search): "shops-\(search.id)"
            }
        }
    }

    @State private var presenting: Presenting?
    @State private var couldNotOpen: String?

    /// Recomputed from the item rather than held: refiling a thing from Buys
    /// to Watchlist in the picker above should change what this offers, in the
    /// same gesture.
    private var actions: [FieldItemAction] {
        FieldItemSteps.actions(
            for: item,
            isModelAvailable: FieldItemVoice.isAvailable
        )
    }

    private var plan: FieldItemPlan? {
        guard let plan = store.itemPlan, plan.itemID == item.id else {
            return nil
        }
        return plan
    }

    var body: some View {
        // The anti-Clippy gate. Absence is the default and the common case.
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                FieldLabel(
                    plan == nil ? "What I can open" : "Fifteen minutes of it",
                    color: .fieldInk(.monoLabelQuiet)
                )
                .padding(.top, 18)
                .padding(.bottom, 13)

                if let plan {
                    planned(plan)
                } else {
                    offered
                }

                if let couldNotOpen {
                    FieldReasoning(
                        text: couldNotOpen,
                        accent: store.identity.color(for: item.owner)
                    )
                    .padding(.top, 13)
                }
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.help")
            .sheet(item: $presenting) { what in
                switch what {
                case .calendar(let draft):
                    FieldEventEditor(draft: draft, store: EKEventStore()) { _ in
                        // Nothing is marked done here. This sheet put a draft
                        // in front of somebody; whether the errand happened is
                        // not something the app watched.
                        presenting = nil
                    }
                    .ignoresSafeArea()
                case .shops(let search):
                    FieldShopSheet(search: search)
                }
            }
            // Cancels when the sheet closes. `FieldItemVoice` returns nil on
            // the resulting `CancellationError`, and the guard below means a
            // generation that outran the dismissal writes nothing.
            .task(id: thinkingID) {
                guard let id = thinkingID, id == item.id else { return }
                let steps = await FieldItemVoice.plan(for: item, minutes: 15)
                guard !Task.isCancelled else { return }
                store.planFinished(steps, for: id)
            }
            .onDisappear { store.clearPlan() }
        }
    }

    private var thinkingID: String? {
        guard let plan = store.itemPlan, plan.isThinking else { return nil }
        return plan.itemID
    }

    // MARK: What is on offer

    private var offered: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(actions) { action in
                if case .askFor(let what) = action {
                    // Not a button. The app naming the one thing it would need
                    // in order to be useful, with the search still right there
                    // underneath it.
                    FieldReasoning(
                        text: "I don't know the \(what), so the search will be "
                            + "a broad one. Adding it to the title sharpens it.",
                        accent: store.identity.color(for: item.owner)
                    )
                    .accessibilityIdentifier(action.identifier)
                } else {
                    button(action)
                }
            }
        }
    }

    private func button(_ action: FieldItemAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action.label) { perform(action) }
                .buttonStyle(FieldOutlinedButtonStyle())
                // On the button rather than the stack: a UI test asserting
                // this feature is absent has to be able to ask for a button by
                // identifier, and a wrapping container does not answer.
                .accessibilityIdentifier(action.identifier)
                .accessibilityHint(action.destination ?? "")

            if let destination = action.destination {
                Text(destination)
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityHidden(true)
            }
        }
    }

    private func perform(_ action: FieldItemAction) {
        couldNotOpen = nil
        switch action {
        case .webSearch(_, let query):
            open(FieldSearchLink.web(query))
        case .maps(_, let query):
            open(FieldSearchLink.maps(query))
        case .retailerSearch(let label, let query):
            presenting = .shops(ShopSearch(label: label, query: query))
        case .calendarDraft:
            presenting = .calendar(
                FieldOutreach.draft(for: item, now: store.now)
            )
        case .plan:
            store.planStarted(for: item.id)
        case .askFor:
            break
        }
    }

    /// `openURL`'s completion rather than `canOpenURL`, for the same reason
    /// `FieldOutreachConfirmation` uses it: asking permission to ask is a
    /// query about what else is installed on somebody's phone.
    private func open(_ url: URL?) {
        guard let url else { return }
        openURL(url) { accepted in
            if !accepted {
                couldNotOpen = "This phone can't open that."
            }
        }
    }

    // MARK: The plan

    private func planned(_ plan: FieldItemPlan) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if plan.isThinking {
                Text("Working it out.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.legend))
            } else {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                    Text(step)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                }

                FieldReasoning(
                    text: "I wrote this on your phone, from the words on this "
                        + "thing. Nobody else has it yet.",
                    accent: store.identity.color(for: item.owner)
                )

                HStack(spacing: 11) {
                    Button("Keep it on this") { store.keepPlan(on: item.id) }
                        .buttonStyle(FieldFilledButtonStyle())
                        // `field_life_items` is couple-scoped and realtime-
                        // published, so this is a share and the hint says so.
                        .accessibilityHint(
                            "Saves it onto this thing, where you can both "
                                + "see it."
                        )
                        .accessibilityIdentifier("field.item.help.keep")

                    Button("Let it go") { store.clearPlan() }
                        .buttonStyle(FieldQuietButtonStyle())
                }
            }
        }
    }
}

// MARK: - Which shop

/// What is being looked for, as something `.sheet(item:)` will accept.
struct ShopSearch: Identifiable, Hashable {
    var id: String { "\(label)-\(query)" }
    let label: String
    let query: String
}

/// The one screen in this feature that asks a question, because picking a shop
/// is the actual question. Nothing is preselected and nothing is recommended —
/// the app has no prices, no stock, and no opinion, and it says so once, here,
/// where the shops actually are.
struct FieldShopSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let search: ShopSearch

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                FieldLabel("Where to look")
                    .padding(.bottom, 13)

                Text(search.query)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                ForEach(FieldRetailer.ordered()) { retailer in
                    Button(retailer.name) {
                        if let url = retailer.url(searching: search.query) {
                            openURL(url)
                        }
                        dismiss()
                    }
                    .buttonStyle(FieldQuietButtonStyle())
                    .accessibilityIdentifier("field.item.shop.\(retailer.rawValue)")
                }

                Text("I don't take a cut from any of these, and I don't know "
                    + "what they have. Each one opens its own search.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Spacer(minLength: 0)
            }
            .padding(.top, 48)
            .padding(.horizontal, FieldMetrics.screenSide)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.item.shop")
    }
}
