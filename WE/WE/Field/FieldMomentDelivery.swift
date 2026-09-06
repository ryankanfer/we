//
//  FieldMomentDelivery.swift
//  WE
//
//  One moment a day (6c), actually delivered.
//
//  `FieldMomentScheduler.decide` answers "would I speak right now?" and drives
//  the in-app surface. This file answers a different question — "when, and
//  with what?" — and hands the answer to the OS.
//
//  The handoff's rules are the whole design:
//
//    · One push per day, at a learned hour.
//    · No badge counts, no red dots.
//    · No second attempt.
//    · Nothing needing them means silence, not a "you're all caught up".
//
//  Delivery is local, not server-driven. The selection logic lives in Swift
//  and is tested there, and a couple's day does not need a server to know
//  when a grocery window closes. The cost is that content is fixed when it is
//  scheduled rather than when it fires, which is why every foreground and
//  every background re-plans from scratch.
//

import Foundation
import UserNotifications

/// What should be waiting, and when. Pure — no notification centre — so the
/// timing rules are testable without a simulator.
struct FieldMomentPlan: Equatable, Sendable {
    var fireDate: Date
    var statement: String
    var detail: String?
}

enum FieldMomentDelivery {
    /// One identifier, forever. Rescheduling replaces rather than adds, which
    /// is what keeps "no second attempt" true at the OS layer and not just in
    /// `decide`.
    static let requestIdentifier = "field.moment.daily"

    // MARK: Planning

    /// The next moment worth sending, or `nil` for silence.
    ///
    /// Silence is a real answer here, not a failure: if nothing needs them,
    /// the app says nothing rather than manufacturing a reason to speak.
    static func plan(
        state: FieldState,
        selection: FieldTodaySelector.Result,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> FieldMomentPlan? {
        guard case .needsYou(let moment) = selection else { return nil }

        guard
            let fireDate = nextSend(
                after: now,
                moment: state.dailyMoment,
                calendar: calendar
            )
        else { return nil }

        return FieldMomentPlan(
            fireDate: fireDate,
            statement: moment.headline,
            detail: moment.reasoning
        )
    }

    /// The next occurrence of the learned hour that is both in the future and
    /// on a day nothing has been sent.
    static func nextSend(
        after now: Date,
        moment: FieldDailyMoment,
        calendar: Calendar = .gregorianUS
    ) -> Date? {
        // Two days is enough: either today's hour is still ahead, or
        // tomorrow's is. Looking further would be inventing a queue the
        // product does not have.
        for dayOffset in 0...1 {
            guard
                let day = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: now
                ),
                let candidate = calendar.date(
                    bySettingHour: moment.sendMinute / 60,
                    minute: moment.sendMinute % 60,
                    second: 0,
                    of: day
                )
            else { continue }

            guard candidate > now else { continue }
            // Already spoken that day. There is no second attempt, ever.
            guard !moment.hasSent(on: candidate, calendar: calendar) else {
                continue
            }
            return candidate
        }
        return nil
    }

    // MARK: Permission

    /// Asked for after onboarding, never at launch. The app is supposed to
    /// earn this, and a permission sheet on first run is the opposite of
    /// earning it.
    ///
    /// `.badge` is deliberately absent — the handoff forbids badge counts, so
    /// the app should not hold the right to set one.
    @discardableResult
    static func requestAuthorization(
        center: UNUserNotificationCenter = .current()
    ) async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .sound]
            )
        } catch {
            return false
        }
    }

    // MARK: Scheduling

    /// Replaces whatever was pending with what is true now.
    ///
    /// Called on background and on foreground. Local notifications freeze
    /// their content at scheduling time, so re-planning on every transition
    /// is what keeps a moment from arriving about something already done.
    static func refresh(
        state: FieldState,
        selection: FieldTodaySelector.Result,
        now: Date,
        calendar: Calendar = .gregorianUS,
        center: UNUserNotificationCenter = .current()
    ) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [requestIdentifier]
        )

        guard
            let plan = plan(
                state: state,
                selection: selection,
                now: now,
                calendar: calendar
            )
        else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.statement
        if let detail = plan.detail {
            content.body = detail
        }
        content.sound = .default
        // No badge. Not "badge = 0" — the app never speaks in counts.

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: plan.fireDate
        )
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )

        try? await center.add(request)
    }

    /// For sign-out and account deletion: nothing should be waiting for
    /// someone who has left.
    static func cancel(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(
            withIdentifiers: [requestIdentifier]
        )
    }
}
