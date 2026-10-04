//
//  FieldTodayEditorial.swift
//  WE
//
//  The sections of Today's brief, drawn. See `FieldTodayBrief` for what is
//  chosen and why; this file only decides how it reads.
//
//  Hierarchy comes from type, image scale and space, not from boxes: one
//  large serif headline, at most one large picture and one small one, and
//  hairline rules between sections. Every section is optional and the page
//  is complete without any picture at all.
//

import SwiftUI

// MARK: - Header

/// The WE mark and the date, and nothing louder.
struct TodayEditorialHeader: View {
    @Environment(FieldStore.self) private var store

    var body: some View {
        HStack(alignment: .center) {
            // The mark in the couple's own colours: the two lights at text
            // size, together, beside the name. Not WEMark, whose white
            // wordmark is drawn for dark ground and disappears on cream.
            HStack(spacing: 6) {
                WELightsMark(identity: store.viewerIdentity, reading: .together, size: 10)
                Text("WE")
                    .font(.system(.footnote, design: .serif, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.fieldInk(.headline))
            }
            Spacer(minLength: 12)
            Text(store.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(.fieldInk(.reasoning))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today, " + store.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("field.today.header")
    }
}

// MARK: - The lead, when it is a discovery or a clear day

/// A quiet day: the partner kept something, and it leads.
struct TodayDiscoveryLead: View {
    @Environment(FieldStore.self) private var store
    let entry: FieldBriefEntry
    @Binding var openItem: FieldItemReference?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                WELightsMark(identity: store.viewerIdentity, reading: .theirs, size: 9)
                Text(entry.attribution ?? "")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.fieldInk(.reasoning))
            }
            .padding(.bottom, 18)

            if let url = entry.sourceURL {
                FieldPreviewPlate(url: url, aspect: 3 / 2)
                    .padding(.bottom, 22)
            }

            WEWordReveal(
                text: entry.title,
                font: FieldType.hero,
                tracking: FieldTracking.hero,
                lineSpacing: 4
            )
            .foregroundStyle(.fieldInk(.headline))
            .padding(.bottom, 14)

            Text(entry.context)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            TodayPrimaryButton(title: "Open it") {
                openItem = FieldItemReference(id: entry.itemID)
            }
            .accessibilityHint("Opens what \(store.partnerName) kept")
            .accessibilityIdentifier("field.today.lead.open")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.today.lead.discovery")
    }
}

/// Nothing needs anyone. Said plainly, and left alone.
struct TodayClearLead: View {
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WEWordReveal(
                text: headline,
                font: FieldType.hero,
                tracking: FieldTracking.hero,
                lineSpacing: 4
            )
            .foregroundStyle(.fieldInk(.headline))

            Text(detail)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 15)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("field.today.lead.clear")
    }
}

/// The one filled button on the page.
struct TodayPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FieldType.button)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(WECanvas.surface.ink)
    }
}

// MARK: - Partner discovery

/// Something the partner kept, small. A thumbnail only when the thing came
/// from a page with a picture; otherwise their light says whose it is.
struct TodayPartnerDiscovery: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: FieldBriefEntry
    @Binding var openItem: FieldItemReference?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
            Button {
                openItem = FieldItemReference(id: entry.itemID)
            } label: {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                layout {
                    if let url = entry.sourceURL {
                        FieldPreviewPlate(url: url, aspect: 1, cornerRadius: 3, showsSite: false)
                            .frame(width: typeSize.isAccessibilitySize ? 120 : 72)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            WELightsMark(identity: store.viewerIdentity, reading: .theirs, size: 8)
                            Text(entry.attribution ?? "")
                                .font(.system(.footnote, weight: .medium))
                                .foregroundStyle(.fieldInk(.reasoning))
                        }
                        Text(entry.title)
                            .font(FieldType.listItemLarge)
                            .foregroundStyle(.fieldInk(.headline))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.context)
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.sectionSubtitle))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                }
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens it")
            .accessibilityIdentifier("field.today.discovery")
        }
    }
}

// MARK: - Looking ahead

/// One dated thing after today. The calendar is one tap from here, because
/// a person looking ahead is the person most likely to want the month.
struct TodayLookingAhead: View {
    @Environment(FieldStore.self) private var store
    let entry: FieldBriefEntry
    @Binding var openItem: FieldItemReference?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
            HStack(alignment: .firstTextBaseline) {
                FieldLabel("Looking ahead")
                Spacer()
                Button {
                    store.openCalendar()
                } label: {
                    Label("Calendar", systemImage: "calendar")
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(.fieldInk(.reasoning))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the month")
                .accessibilityIdentifier("field.today.calendar")
            }
            .padding(.top, 6)

            Button {
                openItem = FieldItemReference(id: entry.itemID)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(FieldType.listItemLarge)
                            .foregroundStyle(.fieldInk(.headline))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Text(entry.context.uppercased())
                                .font(FieldType.dateCount)
                                .tracking(FieldTracking.dateCount)
                                .foregroundStyle(.fieldInk(.dateCount))
                            if entry.isPrivate {
                                Label("Only me", systemImage: "lock")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundStyle(.fieldInk(.legend))
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.fieldInk(.legend))
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(entry.title), \(entry.context)" + (entry.isPrivate ? ". Only me." : "")
            )
            .accessibilityHint("Opens it")
            .accessibilityIdentifier("field.today.ahead")
        }
    }
}

// MARK: - Proposals

/// Suggestions that need the other person. A proposal stays a proposal
/// until they answer; nothing here decides anything on its own.
struct TodayProposals: View {
    @Environment(FieldStore.self) private var store
    let messageIDs: [String]
    @Binding var openItem: FieldItemReference?

    private var messages: [FieldChatMessage] {
        messageIDs.compactMap { id in store.chatMessages.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
            FieldLabel("To decide together")
                .padding(.top, 18)
                .padding(.bottom, 6)
            ForEach(messages) { message in
                row(message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ message: FieldChatMessage) -> some View {
        let mine = message.sender == store.speaker
        let title = message.context.flatMap(store.chatContextTitle) ?? message.body
        let itemID = message.context?.kind == "life" ? message.context?.id : nil

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            WELightsMark(identity: store.viewerIdentity, reading: .leaning, size: 8)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let itemID { openItem = FieldItemReference(id: itemID) }
                } label: {
                    Text(title)
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(.headline))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .disabled(itemID == nil)

                Text(mine
                     ? "You suggested it. Waiting for \(store.partnerName)."
                     : "\(store.identity.name(for: message.sender)) suggested it.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
            }
            Spacer(minLength: 8)
            if !mine {
                Button("Agree") {
                    Task { await store.confirmConversationDecision(message) }
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.fieldInk(.headline))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Agree to \(title)")
                .accessibilityIdentifier("field.today.agree")
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(mine ? "field.today.proposal.mine" : "field.today.proposal")
    }
}

// MARK: - The rest of today, and the way in

/// What the brief did not have room for, one tap away. The page is short
/// on purpose; it is never short by hiding something that needs doing.
struct TodayRemainder: View {
    @Environment(FieldStore.self) private var store
    let moreItemIDs: [String]
    @Binding var showsDeferral: Bool
    @State private var showsMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !moreItemIDs.isEmpty {
                line(
                    moreItemIDs.count == 1
                        ? "One more thing today"
                        : "\(moreItemIDs.count.spelled.capitalized) more things today",
                    identifier: "field.today.more"
                ) { showsMore = true }
            }
            if !store.heldTopics.isEmpty {
                line(
                    FieldDayCopy.holding(count: store.heldTopics.count),
                    identifier: "field.today.holding"
                ) { showsDeferral = true }
            }
        }
        .sheet(isPresented: $showsMore) {
            FieldDayItemList(title: "Today", itemIDs: moreItemIDs)
                .environment(store)
        }
    }

    private func line(_ text: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.headline))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.fieldInk(.legend))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Where the page ends: keep something, or ask about something kept.
struct TodayCaptureBar: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.weCanvas) private var canvas

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                keep
                ask
            }
            VStack(alignment: .leading, spacing: 10) {
                keep
                ask
            }
        }
        .padding(.top, 8)
    }

    private var keep: some View {
        Button {
            store.composerOpen = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityHidden(true)
                Text("Keep something")
                    .font(FieldType.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.fieldInk(.headline))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Capsule().strokeBorder(canvas.ink.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("field.today.keep")
    }

    private var ask: some View {
        Button {
            store.askOpen = true
        } label: {
            Label("Ask WE", systemImage: "magnifyingglass")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.fieldInk(.headline))
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Capsule().fill(canvas.ink.opacity(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ask about something either of you kept. Only you see it.")
        .accessibilityIdentifier("field.today.ask")
    }
}

// MARK: - A short list of items

/// More of today, or any other short list, opened from a line on Today.
struct FieldDayItemList: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let title: String
    let itemIDs: [String]
    @State private var openItem: FieldItemReference?

    var body: some View {
        NavigationStack {
            List(itemIDs, id: \.self) { id in
                if let item = store.state.lifeItems.first(where: { $0.id == id }) {
                    Button {
                        openItem = FieldItemReference(id: id)
                    } label: {
                        HStack {
                            FieldDot(owner: item.owner, isPrivate: item.visibility == .private, identity: store.identity)
                            Text(item.title).foregroundStyle(.fieldInk(.headline))
                            if item.visibility == .private {
                                Spacer()
                                Label("Only me", systemImage: "lock")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.fieldInk(.legend))
                                    .accessibilityLabel("Only me")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { Button("Done") { dismiss() } }
        }
        .sheet(item: $openItem) { FieldItemSheet(itemID: $0.id).environment(store) }
    }
}
