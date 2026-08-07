//
//  FieldCategoryRoom.swift
//  WE
//
//  One Life category, read closely.
//
//  Life itself enumerates nothing — "an early version put the full Reminders
//  list inline and it swamped the page" — so the detail lives one tap behind
//  each category word, in here.
//
//  The room could make the same mistake at smaller scale. A reason under every
//  row is a wall whatever the font size, so it splits: the few things that
//  earned an explanation get one, and everything else is a list of titles. The
//  page decides where the line falls, using the same threshold Today uses, so
//  a calm category simply renders calm and there is nothing to configure.
//

import SwiftUI

struct FieldCategoryRoom: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let category: LifeCategory

    /// The row somebody tapped. Local `@State` for the same reason
    /// `FieldLifeZone.openCategory` is — it is ephemeral to this screen, and a
    /// hand-built `Binding` over an `@Observable` property does not drive
    /// `.sheet(item:)` reliably.
    @State private var openItem: FieldItemReference?

    /// Which question the destination sheet is asking. `nil` when it is
    /// closed — the two acts share one sheet because they are one act with two
    /// sentences around it, and a second sheet would be a second set of naming
    /// rules to keep in step.
    @State private var groupAction: FieldGroupAction?

    private var digest: FieldCategoryDigest.Result {
        store.digest(for: category)
    }

    /// What "move everything" would actually move — asked of the store rather
    /// than counted here, because the rule about which items travel with their
    /// group belongs next to the move that applies it.
    ///
    /// Not `digest.total`, which counts only the open ones: a finished errand
    /// left behind would keep a deleted group alive the moment somebody
    /// reopened it.
    private var movableCount: Int {
        store.movableCount(in: category)
    }

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGap)

                    if digest.isEmpty {
                        emptyState
                    } else {
                        pressing
                        quiet
                    }
                }
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .overlay(alignment: .topTrailing) { controls }
        .preferredColorScheme(.dark)
        .sheet(item: $openItem) { reference in
            FieldItemSheet(itemID: reference.id)
                .environment(store)
        }
        .sheet(item: $groupAction) { action in
            FieldGroupDestinationSheet(
                category: category,
                action: action,
                count: movableCount
            )
            .environment(store)
        }
        .accessibilityIdentifier("field.room.\(category.rawValue)")
    }

    // MARK: The two controls
    //
    // The ✕ used to sit on Done, and it cannot now that this corner can also
    // delete the group: a glyph that means "close" beside a menu that means
    // "get rid of this" is one mis-tap from an act nobody intended. Done is a
    // word, and the other thing is behind a menu that names what it does.

    private var controls: some View {
        HStack(spacing: 0) {
            groupMenu
            doneButton
        }
        .padding(.trailing, FieldMetrics.screenSide)
    }

    /// Adapts to what the group is, because the two are not the same act.
    ///
    /// A grown group can be renamed, and is deleted by being emptied — there
    /// is no separate "delete", because a category is derived from the items
    /// that carry it, so moving the last one out *is* the deletion. Offering
    /// both would be two words for one gesture, and would invite the reading
    /// that one of them leaves the empty heading behind.
    ///
    /// A built-in cannot be renamed — the seven words are the floor the app is
    /// built on — and cannot be deleted at all. It can only be set down, and
    /// only once nothing is in it.
    private var groupMenu: some View {
        Menu {
            if !category.isBuiltIn {
                Button("Rename…") { groupAction = .rename }
            }

            Button("Move everything to…") { groupAction = .moveEverything }
                .disabled(movableCount == 0)

            if category.isBuiltIn {
                Section {
                    Button("Put away") { putAway() }
                        .disabled(movableCount > 0)
                } footer: {
                    // Says why it cannot be done rather than presenting a dead
                    // control with no explanation. A container never sets its
                    // contents down with it.
                    Text(
                        movableCount == 0
                            ? "Hides \(category.word) from Life for both of you."
                            : "Move these \(movableCount) things first."
                    )
                }
            }
        } label: {
            Text("•••")
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.recessive))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityHint("What you can do to \(category.word) itself")
        .accessibilityIdentifier("field.room.menu")
    }

    /// Putting a group away closes the room with it. Staying would leave the
    /// couple looking at a page for something that is no longer on Life, with
    /// Done as the only way out of it.
    private func putAway() {
        guard store.putAway(category) else { return }
        dismiss()
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("DONE")
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.legend))
                .padding(.vertical, FieldMetrics.screenSide)
                .padding(.leading, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityIdentifier("field.room.done")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                FieldLabel(category.word)
                Spacer()
                if digest.total > 0 {
                    Text("\(digest.total) OPEN")
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.headerMeta))
                }
            }

            // Only the written line, never the derived fallback. The fallback
            // is the first two titles joined, and those titles are the first
            // two rows below it — printing it here says the same thing twice
            // in one screen.
            if let written = store.writtenSubtitles[category] {
                Text(written)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The explained band

    @ViewBuilder
    private var pressing: some View {
        ForEach(digest.pressing) { row in
            // A plain `Button` so the row looks exactly as it did — no
            // highlight, no chevron. The same move `FieldLifeZone.categoryRow`
            // makes: the page stays a list of things, and what you can do to
            // one of them is behind it.
            Button {
                openItem = FieldItemReference(id: row.item.id)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 11) {
                        FieldDot(
                            owner: row.item.owner,
                            identity: store.identity,
                            size: FieldDotSize.list,
                            baselineNudge: 7
                        )

                        Text(row.item.title)
                            .font(FieldType.listItemLarge)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.25, size: 18)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }

                    if let reason = row.reason {
                        Text(reason)
                            .font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .padding(.leading, 22)
                    }
                }
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [row.item.title, row.reason]
                    .compactMap { $0 }
                    .joined(separator: ". ")
            )
            .accessibilityHint("Opens this, to move it or take it off")
            .accessibilityIdentifier("field.room.row")
        }
    }

    // MARK: The quiet band
    //
    // Titles only, and a tighter rhythm. No dates, no reasons, no counts —
    // these are the things that are simply in the category, and saying more
    // about them would be saying it for the sake of it.

    @ViewBuilder
    private var quiet: some View {
        if !digest.groups.isEmpty {
            // Past the density threshold the room organises itself. The
            // headings are derived, never stored, and there is still exactly
            // one word for this category on Life — see `FieldGrouping`.
            ForEach(digest.groups) { group in
                FieldLabel(
                    group.heading,
                    font: FieldType.subLabel,
                    tracking: FieldTracking.subLabel,
                    color: .fieldInk(.recessive)
                )
                .padding(.top, FieldMetrics.sectionGap)
                .padding(.bottom, 4)

                ForEach(group.items) { item in
                    quietRow(item)
                }
            }
        } else if !digest.quiet.isEmpty {
            FieldLabel(
                digest.pressing.isEmpty ? "In this room" : "Quiet below here",
                font: FieldType.subLabel,
                tracking: FieldTracking.subLabel,
                color: .fieldInk(.recessive)
            )
            .padding(.top, FieldMetrics.sectionGap)
            .padding(.bottom, 4)

            ForEach(digest.quiet) { item in
                quietRow(item)
            }
        }
    }

    private func quietRow(_ item: LifeItem) -> some View {
        Button {
            openItem = FieldItemReference(id: item.id)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                FieldDot(
                    owner: item.owner,
                    identity: store.identity,
                    size: FieldDotSize.list,
                    baselineNudge: 6
                )

                Text(item.title)
                    .font(FieldType.listItem)
                    .foregroundStyle(.fieldInk(.quietListItem))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityHint("Opens this, to move it or take it off")
        .accessibilityIdentifier("field.room.row")
    }

    // MARK: Nothing here

    /// A real state, not a failure. The app says so plainly and does not
    /// suggest filling it.
    private var emptyState: some View {
        Text("Nothing in \(category.word.lowercased()) needs you.")
            .font(FieldType.pageHeadline)
            .foregroundStyle(.fieldInk(.headline))
            .fieldLineHeight(1.16, size: 32)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.room.empty")
    }
}

// MARK: - What the menu asked

/// The two questions the destination sheet can be open for.
///
/// `Identifiable` so it can drive `.sheet(item:)`, which is what
/// `FieldItemReference` next door exists for and for the same reason: a
/// hand-built `Binding` over an `@Observable` property does not drive it
/// reliably.
enum FieldGroupAction: String, Identifiable {
    case moveEverything
    case rename

    var id: String { rawValue }
}

// MARK: - Where does it all go?

/// One sheet for both acts, because they are one act.
///
/// Renaming a group and emptying it are the same write — every item's category
/// changes — and the only difference is which sentence is true afterwards. A
/// second sheet would mean a second copy of the naming rules, and
/// `FieldCategoryPicker` already refuses a name in the app's own voice.
private struct FieldGroupDestinationSheet: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let category: LifeCategory
    let action: FieldGroupAction
    let count: Int

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                headline

                FieldCategoryPicker(
                    // Never the group being emptied — "move everything to
                    // where it already is" is not an offer.
                    options: store.correctionCategories.filter {
                        $0 != category
                    },
                    choose: { move(to: $0) },
                    name: { rename(to: $0) },
                    cancel: { dismiss() },
                    title: action == .rename
                        ? "What should it be called?"
                        : "Where does it all go?",
                    startsNaming: action == .rename
                )

                Spacer(minLength: 0)
            }
            .padding(.top, 40)
            .padding(.horizontal, FieldMetrics.screenSide)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        // Deliberately no identifier on this root. SwiftUI propagates a
        // container's identifier down over the one on any descendant that is
        // a plain styled control rather than a composed accessibility element
        // — which is how `FieldCategoryRoom`'s own root ends up on its `•••`
        // and its Done. Naming this sheet would do the same to the picker's
        // chips, and `field.correction.option` is the identifier two other
        // flows already address them by.
    }

    /// Names the consequence before it happens, and names it as a fact rather
    /// than as a warning. A grown category with nothing in it has stopped
    /// existing — that is not a punishment for emptying it, it is what a
    /// derived category *is*.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(
                action == .rename
                    ? "Renaming \(category.word)."
                    : "\(count) \(count == 1 ? "thing is" : "things are") "
                        + "in \(category.word)."
            )
            .font(FieldType.pageHeadline)
            .foregroundStyle(.fieldInk(.headline))
            .fieldLineHeight(1.16, size: 32)
            .fixedSize(horizontal: false, vertical: true)

            if !category.isBuiltIn, action == .moveEverything {
                Text("\(category.word) will stop existing.")
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("field.group.headline")
    }

    private func move(to destination: LifeCategory) {
        store.moveGroup(category, to: destination)
        dismiss()
    }

    /// Returns the category so `FieldCategoryPicker` can tell a refused name
    /// from an accepted one and keep its own error on screen.
    private func rename(to name: String) -> LifeCategory? {
        guard let destination = store.moveGroup(
            category, toNewCategory: name
        ) else { return nil }
        dismiss()
        return destination
    }
}
