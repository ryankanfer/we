//
//  FieldLoadState.swift
//  WE
//
//  The one line the zones are allowed to say about not knowing.
//
//  `FieldStore.load()` used to `try?` twice, which meant a failed load and a
//  brand new account produced exactly the same screen: the empty state, drawn
//  with total confidence. For a couple with two years of history and no signal
//  on a train, the app said their relationship was empty. That is the worst
//  sentence this product can utter, and it was uttered by an omission.
//
//  What replaces it is deliberately almost nothing. The handoff forbids
//  spinners, banners, and counts, and it is right to: a sync indicator would
//  make the app's plumbing the subject of a screen that is meant to be about
//  two people. So there is a hairline and, at most, four words — and when the
//  load is simply working, there is nothing here at all.
//

import SwiftUI

@MainActor
struct FieldLoadStateLine: View {
    let store: FieldStore

    var body: some View {
        switch store.loadState {
        case .loading, .loaded:
            // Nothing. The overwhelmingly common case is that the app knows
            // what it is showing, and saying so is noise.
            EmptyView()

        case .stale(let date):
            line(Self.lastSeen(date, now: store.now))

        case .failed:
            // The only state with an action, because it is the only one where
            // the screen is empty and the person cannot tell why.
            Button {
                Task { await store.retryLoad() }
            } label: {
                line("Can't reach WE · Try again")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("field.loadState.retry")
        }
    }

    private func line(_ text: String) -> some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(FieldRule.watching)
                .frame(height: 1)

            Text(text)
                .font(FieldType.subLabel)
                .tracking(FieldTracking.subLabel)
                .textCase(.uppercase)
                .foregroundStyle(.fieldInk(.recessive))
        }
        .padding(.horizontal, FieldMetrics.screenSide)
        .accessibilityIdentifier("field.loadState")
    }

    /// Days, not minutes.
    ///
    /// "Last seen 4 minutes ago" invites somebody to watch a number, which is
    /// the sync indicator this is trying not to be. The question a stale
    /// screen actually raises is whether what it shows is roughly current, and
    /// that is answered in days.
    static func lastSeen(
        _ date: Date,
        now: Date,
        calendar: Calendar? = nil
    ) -> String {
        // Resolved in the body rather than as a default argument, for the
        // reason `FieldStore.init` already documents: default expressions are
        // evaluated nonisolated, and `Calendar.gregorianUS` is main-actor
        // isolated.
        let calendar = calendar ?? .gregorianUS
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        return switch days {
        case ..<1: "Last seen today"
        case 1: "Last seen yesterday"
        default: "Last seen \(days) days ago"
        }
    }
}
