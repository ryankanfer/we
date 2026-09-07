//
//  FieldItemSheet.swift
//  WE
//
//  One filed thing, and the three things you can do to it.
//
//  Filing used to be one-way. A receipt could be corrected before it was sent,
//  and after that an item's word and its day were fixed forever — so a typo, a
//  thing filed under the wrong heading, or a plan that was cancelled stayed on
//  the page until somebody ticked it off as though it had happened.
//
//  This is the surface that fixes that, and it is one surface rather than two
//  because the category room and the calendar are asking the same question
//  about the same object. Reached by tapping a row in either.
//
//  It asks nothing the app can answer itself: no confirm on a move, because a
//  move is reversible in the same gesture; a confirmation on the removal,
//  because that one is not.
//

import SwiftUI

/// The row somebody tapped, as something `.sheet(item:)` will accept.
///
/// An id rather than the `LifeItem` itself, deliberately: the sheet mutates
/// the item on every control, and a value captured at presentation would go
/// stale the moment it did.
struct FieldItemReference: Identifiable, Hashable {
    let id: String
}

struct FieldItemSheet: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let itemID: String

    @State private var asksToRemove = false
    @State private var isPickingDay = false

    /// Read live from the store rather than captured at presentation. Every
    /// control here mutates the item, and a copy taken when the sheet opened
    /// would render the state before the tap.
    private var item: LifeItem? {
        store.state.lifeItems.first { $0.id == itemID }
    }

    var body: some View {
        ZStack {
            WECanvas.cream.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if let item {
                    VStack(alignment: .leading, spacing: 0) {
                        header(item)
                            .padding(.bottom, FieldMetrics.sectionGap)

                        delivery

                        if let error = store.itemSaveError {
                            Text(error).font(FieldType.body)
                                .padding(.bottom, 20)
                                .accessibilityIdentifier("field.item.saveError")
                        }

                        standing(item)

                        whereItLives(item)
                            .padding(.bottom, FieldMetrics.sectionGap)

                        if item.category.carriesDates {
                            when(item)
                                .padding(.bottom, FieldMetrics.sectionGap)
                        }

                        FieldItemHelp(item: item)

                        removeIt
                    }
                    .padding(.top, 48)
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.bottom, 60)
                }
            }
        }
        .overlay(alignment: .topTrailing) { doneButton }
        .preferredColorScheme(.light)
        .environment(\.weCanvas, WECanvas.cream)
        .animation(.fieldZone(reduceMotion), value: item?.category)
        .animation(.fieldZone(reduceMotion), value: item?.dueOn)
        .animation(.fieldZone(reduceMotion), value: isPickingDay)
        // The item can leave from underneath this — the partner completes it,
        // or removing it succeeds. A sheet over nothing is not a state.
        .onChange(of: item == nil) { _, gone in
            if gone { dismiss() }
        }
        .confirmationDialog(
            "Remove this?",
            isPresented: $asksToRemove,
            titleVisibility: .visible
        ) {
            Button("Remove it", role: .destructive) {
                if store.remove(itemID) { dismiss() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(
                "It goes for both of you, from every screen, and there is no "
                    + "undo."
            )
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("DONE ✕")
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.legend))
                .padding(FieldMetrics.screenSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityIdentifier("field.item.done")
    }

    // MARK: The thing itself

    private func header(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(item.category.word)

            HStack(alignment: .top, spacing: 11) {
                FieldDot(
                    owner: item.owner,
                    identity: store.identity,
                    size: FieldDotSize.prominentList,
                    baselineNudge: 8
                )

                Text(item.title)
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.25, size: 18)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            Text(whose(item))
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.headerMeta))
        }
    }

    private func whose(_ item: LifeItem) -> String {
        let owner = store.identity.name(for: item.owner).uppercased()
        guard let dueOn = item.dueOn else { return owner }
        return "\(owner) · \(DateFormatter.fieldDayMonth.string(from: dueOn).uppercased())"
    }

    // MARK: Whether the other phone has it

    /// Where this item's writing has got to, in one line.
    ///
    /// All three states are drawn, including the ordinary one. Drawing nothing
    /// when a write has landed reads as "shared" only to somebody who already
    /// knows that is the convention; to everybody else it is indistinguishable
    /// from a screen that has no opinion, which is the ambiguity this is here
    /// to remove.
    ///
    /// It says where the writing is, never why the network is unhappy: an
    /// error code is a fact about infrastructure, and the person is being
    /// asked one question, which is whether to try again.
    ///
    /// It also says nothing about who can *see* the item. Delivery and
    /// visibility are different facts, and an earlier draft of this copy read
    /// "Shared. They can see this.", which would tell somebody looking at a
    /// private item that their partner could read it because a row reached the
    /// server. Whether a thing is private is answered by `visibility`, on the
    /// item, and nowhere near this.
    @ViewBuilder
    private var delivery: some View {
        if store.canReportDelivery {
            deliveryLine
        }
    }

    @ViewBuilder
    private var deliveryLine: some View {
        switch store.deliveryState(for: itemID) {
        case .shared:
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                Text("Saved beyond this phone.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.delivery.shared")

        case .savedLocally:
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                Text("Saved on this phone only, for now.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.delivery.local")

        case .needsAttention:
            VStack(alignment: .leading, spacing: 14) {
                FieldRuleLine()

                Text("Saved on this phone only. It has not got any further yet.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Button {
                    Task { await store.retryDelivery(for: itemID) }
                } label: {
                    Text("Try again")
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.headline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field.item.delivery.retry")
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.delivery.blocked")
        }
    }

    // MARK: Where it stands
    //
    // Two facts Life sorts on that were previously invisible here, which is
    // how the sorting became unarguable-with. A person who could see "waiting
    // on someone else" on the Life screen had no way to find out *why* the app
    // thought so, and no way to say otherwise.

    @ViewBuilder
    private func standing(_ item: LifeItem) -> some View {
        if item.isAwaitingSomeoneElse {
            VStack(alignment: .leading, spacing: 14) {
                FieldRuleLine()

                Text("You said you'd reached out. Life is holding it as "
                     + "somebody else's move.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                // The way back. A voicemail nobody returned is not somebody
                // else having the next move for the rest of the year, and the
                // only person who can say so is the one who left it.
                Button {
                    store.reclaimOutreach(itemID)
                } label: {
                    Text("It's still on me")
                        .font(FieldType.listItem)
                        .foregroundStyle(.fieldInk(.headline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field.item.reclaim")
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.waiting")
        } else if FieldStrata.windowHasClosed(item, now: store.now) {
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                // Stated, not silently absorbed. The window is gone; whether
                // the thing still matters is not the app's call, and the two
                // controls that settle it — the date, and Remove it — are
                // already on this page.
                Text("That window has closed.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.35, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.windowClosed")
        }
    }

    // MARK: Where it lives

    private func whereItLives(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldCategoryPicker(
                options: store.correctionCategories,
                choose: { store.refile(itemID, to: $0) },
                name: { store.refile(itemID, toNewCategory: $0) },
                title: "Where it lives",
                selected: item.category,
                selectedTint: store.identity.color(for: item.owner, on: .cream)
            )
            .padding(.top, 18)
        }
    }

    // MARK: When
    //
    // A date is the whole of what makes an item rank, surface, and fall due —
    // see `LifeItem.pressure(now:)`. So this is not a detail field: it is the
    // control that moves something on and off the calendar and out of Today.

    private func when(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("When", ink: .labelQuiet)
                .padding(.top, 18)
                .padding(.bottom, 13)

            if isPickingDay {
                dayPicker(item)
            } else {
                FieldFlowLayout(spacing: 8, lineSpacing: 8) {
                    FieldChip(
                        "TODAY",
                        isSelected: isOn(item, offsetFromToday: 0),
                        tint: store.identity.color(for: item.owner, on: .cream)
                    ) {
                        store.redate(itemID, to: store.now)
                    }
                    .accessibilityIdentifier("field.item.today")

                    FieldChip(
                        "TOMORROW",
                        isSelected: isOn(item, offsetFromToday: 1),
                        tint: store.identity.color(for: item.owner, on: .cream)
                    ) {
                        store.redate(itemID, to: tomorrow)
                    }

                    FieldChip("PICK A DAY") { isPickingDay = true }
                        .accessibilityIdentifier("field.item.pickDay")

                    // Only offered when there is a date to take off. "No date"
                    // beside a thing that never had one is a control that does
                    // nothing, which is how a page starts feeling like a form.
                    if item.dueOn != nil {
                        FieldChip("NO DATE") { store.redate(itemID, to: nil) }
                            .accessibilityIdentifier("field.item.noDate")
                    }
                }
            }
        }
    }

    private func dayPicker(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            DatePicker(
                "The day",
                selection: Binding(
                    get: { item.dueOn ?? store.now },
                    set: { store.redate(itemID, to: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(store.identity.color(for: item.owner, on: .cream))
            .accessibilityIdentifier("field.item.dayPicker")

            Button("Back to the days") { isPickingDay = false }
                .buttonStyle(FieldQuietButtonStyle())
        }
    }

    private func isOn(_ item: LifeItem, offsetFromToday days: Int) -> Bool {
        guard let dueOn = item.dueOn,
              let day = Calendar.gregorianUS.date(
                  byAdding: .day,
                  value: days,
                  to: store.now
              )
        else { return false }
        return Calendar.gregorianUS.isDate(dueOn, inSameDayAs: day)
    }

    private var tomorrow: Date {
        Calendar.gregorianUS.date(byAdding: .day, value: 1, to: store.now)
            ?? store.now
    }

    // MARK: Removing it

    private var removeIt: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            Button("Remove it") { asksToRemove = true }
                .buttonStyle(FieldQuietButtonStyle())
                .padding(.top, 8)
                .accessibilityHint(
                    "Removes this for both of you. There is no undo."
                )
                .accessibilityIdentifier("field.item.remove")
        }
    }

}

#Preview {
    let store = FieldStore()
    return FieldItemSheet(
        itemID: store.state.lifeItems.first?.id ?? ""
    )
    .environment(store)
}
