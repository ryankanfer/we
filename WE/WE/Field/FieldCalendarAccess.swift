//
//  FieldCalendarAccess.swift
//  WE
//
//  The calendar half of the cold start (6f).
//
//  "That's all I need. Connect a calendar and I'll work the rest out by
//  watching." Three questions and a calendar is the entire setup — the
//  intelligence is supposed to earn everything else by observation, so this
//  reads and never writes.
//
//  Declining is a first-class outcome, not an error. The app works without a
//  calendar; it just learns more slowly.
//

import EventKit
import Foundation

enum FieldCalendarAccess {
    enum Outcome: Equatable, Sendable {
        case granted
        /// They said no, or the system said no on their behalf. Either way
        /// the app carries on — "every request the app makes offers a way to
        /// decline it."
        case declined
    }

    /// iOS 17+ requires *full* access to read events. Write-only access
    /// cannot see anything, which is exactly the wrong shape for an app that
    /// only wants to look.
    static func request(
        store: EKEventStore = EKEventStore()
    ) async -> Outcome {
        do {
            return try await store.requestFullAccessToEvents()
                ? .granted
                : .declined
        } catch {
            return .declined
        }
    }

    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: Reading

    /// Events in the next `days`, as Life items.
    ///
    /// Every one is `.inferred` and carries its `eventIdentifier`, so a second
    /// import updates rather than duplicates. Without that key a weekly
    /// refresh would silently triple the Calendar category.
    static func upcomingItems(
        from now: Date,
        days: Int = 30,
        store: EKEventStore = EKEventStore(),
        calendar: Calendar = .gregorianUS
    ) -> [LifeItem] {
        guard isAuthorized,
              let end = calendar.date(byAdding: .day, value: days, to: now)
        else { return [] }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: end,
            calendars: nil
        )

        return store.events(matching: predicate)
            .filter { !$0.isAllDay || $0.startDate != nil }
            .compactMap { event in
                guard let identifier = event.eventIdentifier,
                      let title = event.title?.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ),
                      !title.isEmpty
                else { return nil }

                return LifeItem(
                    id: "cal:\(identifier)",
                    title: title,
                    category: .calendar,
                    owner: .shared,
                    dueOn: event.startDate,
                    // A calendar event is a date, not a window that closes.
                    // Giving it a cut-off would let it outrank a real one.
                    closesAt: nil,
                    clusterID: nil,
                    source: .inferred,
                    detail: nil,
                    isTimeCritical: false,
                    isDone: false
                )
            }
    }
}
