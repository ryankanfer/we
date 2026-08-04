//
//  FieldEventEditor.swift
//  WE
//
//  The system's own new-event sheet, opened prefilled.
//
//  The app's calendar permission string says, in these words: "I never add,
//  change, or delete anything." That sentence is why this file is a wrapper
//  around Apple's editor rather than three lines calling `store.save(event)`.
//  The app fills the fields in; the person taps Add; if they don't, nothing
//  happened and nothing was written.
//
//  If the couple never connected a calendar, this is never reached — the act
//  falls through to the same honest copy as a missing phone number. The app
//  does not ask for calendar access at the moment somebody wanted something
//  else entirely.
//

import EventKit
import EventKitUI
import SwiftUI

struct FieldEventEditor: UIViewControllerRepresentable {
    let draft: FieldEventDraft
    let store: EKEventStore
    /// `.saved` is the one outcome the app is allowed to treat as fact:
    /// EventKit is telling it an event exists, rather than the app assuming
    /// one does.
    let onFinish: (EKEventEditViewAction) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.editViewDelegate = context.coordinator

        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.startDate.addingTimeInterval(
            TimeInterval(draft.durationMinutes) * 60
        )
        event.notes = draft.notes
        event.calendar = store.defaultCalendarForNewEvents
        controller.event = event

        return controller
    }

    func updateUIViewController(
        _ controller: EKEventEditViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onFinish: (EKEventEditViewAction) -> Void

        init(onFinish: @escaping (EKEventEditViewAction) -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onFinish(action)
        }
    }
}
