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
            FieldPalette.bgElevated.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if let item {
                    VStack(alignment: .leading, spacing: 0) {
                        header(item)
                            .padding(.bottom, FieldMetrics.sectionGap)

                        if isImported {
                            imported(item)
                        } else {
                            whereItLives(item)
                                .padding(.bottom, FieldMetrics.sectionGap)

                            if item.category.carriesDates {
                                when(item)
                                    .padding(.bottom, FieldMetrics.sectionGap)
                            }

                            // Draws nothing for most items, and that is the
                            // designed state — see `FieldItemSteps.actions`.
                            // Deliberately inside the `else`: an imported
                            // event is somebody else's record and this offers
                            // nothing on one.
                            FieldItemHelp(item: item)

                            removeIt
                        }
                    }
                    .padding(.top, 48)
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.bottom, 60)
                }
            }
        }
        .overlay(alignment: .topTrailing) { doneButton }
        .preferredColorScheme(.dark)
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
                store.remove(itemID)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(
                "It goes for both of you, from every screen, and there is no "
                    + "undo."
            )
        }
        .accessibilityIdentifier("field.item")
    }

    private var isImported: Bool { itemID.hasPrefix("cal:") }

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
                selectedTint: store.identity.color(for: item.owner)
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

            FieldLabel("When", color: .fieldInk(.monoLabelQuiet))
                .padding(.top, 18)
                .padding(.bottom, 13)

            if isPickingDay {
                dayPicker(item)
            } else {
                FieldFlowLayout(spacing: 8, lineSpacing: 8) {
                    FieldChip(
                        "TODAY",
                        isSelected: isOn(item, offsetFromToday: 0),
                        tint: store.identity.color(for: item.owner)
                    ) {
                        store.redate(itemID, to: store.now)
                    }
                    .accessibilityIdentifier("field.item.today")

                    FieldChip(
                        "TOMORROW",
                        isSelected: isOn(item, offsetFromToday: 1),
                        tint: store.identity.color(for: item.owner)
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
            .tint(store.identity.color(for: item.owner))
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

    // MARK: Somebody else's calendar

    /// An imported event is a date the app is *reading*, not something it
    /// holds. The calendar permission string promises "I never add, change, or
    /// delete anything", so this screen offers none of the three and says why.
    private func imported(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldReasoning(
                text: "This came from the calendar on your phone. Only that "
                    + "calendar can move it or take it off.",
                accent: store.identity.personB.color
            )
            .padding(.top, 18)
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
