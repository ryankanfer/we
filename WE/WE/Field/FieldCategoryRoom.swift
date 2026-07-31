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

    private var digest: FieldCategoryDigest.Result {
        store.digest(for: category)
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
        .overlay(alignment: .topTrailing) { doneButton }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.room.\(category.rawValue)")
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
            .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [row.item.title, row.reason]
                    .compactMap { $0 }
                    .joined(separator: ". ")
            )
        }
    }

    // MARK: The quiet band
    //
    // Titles only, and a tighter rhythm. No dates, no reasons, no counts —
    // these are the things that are simply in the category, and saying more
    // about them would be saying it for the sake of it.

    @ViewBuilder
    private var quiet: some View {
        if !digest.quiet.isEmpty {
            FieldLabel(
                digest.pressing.isEmpty ? "In this room" : "Quiet below here",
                font: FieldType.subLabel,
                tracking: FieldTracking.subLabel,
                color: .fieldInk(.recessive)
            )
            .padding(.top, FieldMetrics.sectionGap)
            .padding(.bottom, 4)

            ForEach(digest.quiet) { item in
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
                .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.title)
            }
        }
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
