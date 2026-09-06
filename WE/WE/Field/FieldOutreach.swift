//
//  FieldOutreach.swift
//  WE
//
//  What the verb on the button actually does.
//
//  "Book it" has always been a description of something the person would then
//  go and do somewhere else. The app read the sentence, worked out what was
//  being asked for, printed a word — and threw the reading away. So the button
//  named an act it could not perform, and the person went to find the number
//  themselves.
//
//  This is the reading, kept: an act (`FieldAct`), a target the *system*
//  vouched for, and a destination. Nothing here opens anything — every
//  function is pure, takes what is known and returns where it would go, and
//  the view is the only thing that acts. That split is what makes it possible
//  to say, and to test, that the app cannot dial anybody without a person
//  having read a number on a screen first.
//
//  Two rules hold the whole file up:
//
//    1. A number is never invented. It comes from this phone's contacts or
//       from Maps, and it arrives with the name of wherever it came from
//       attached, because that is what a person needs in order to disagree.
//    2. Nothing is auto-dialled, auto-sent, or auto-booked. The app fills the
//       thing in; the person is the one who does it.
//

import Foundation

// MARK: - Who or what

/// Something the app can actually reach, and where it learned about it.
struct FieldTarget: Hashable, Sendable, Identifiable {
    enum Source: Hashable, Sendable {
        /// This phone's address book.
        case contacts
        /// Apple Maps — a business listing, with an address to prove which
        /// one it is.
        case maps

        var word: String {
            switch self {
            case .contacts: "your contacts"
            case .maps: "Maps"
            }
        }
    }

    var name: String
    var phoneNumber: String?
    var emailAddress: String?
    /// Only ever set for a place. It is the line under the name, so a person
    /// can see it is the right Hudson Vet before their phone rings one.
    var address: String?
    var source: Source

    var id: String { "\(source)-\(name)-\(phoneNumber ?? emailAddress ?? "")" }

    /// "From Maps · 1 Hudson St" — the provenance, in the app's own voice.
    var provenance: String {
        guard let address, source == .maps else {
            return "From \(source.word)."
        }
        return "From \(source.word) · \(address)"
    }
}

/// What to go looking for, and where it is sensible to look.
struct FieldTargetQuery: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case person
        case place
    }

    var text: String
    var kind: Kind
}

// MARK: - A calendar event, as a draft

/// What the system's new-event sheet opens prefilled with.
///
/// A draft and never an event: the app does not write to anybody's calendar,
/// and the permission string it shipped with says so. Apple's own sheet is
/// what turns this into a real event, and only when somebody taps Add.
struct FieldEventDraft: Hashable, Sendable, Identifiable {
    var id: String { "\(title)-\(startDate.timeIntervalSince1970)" }

    /// The item's own title, verbatim. The app does not retitle somebody's
    /// evening for them.
    var title: String
    var startDate: Date
    /// An hour, which is a guess — and a guess the person can change in
    /// Apple's own field before they save it, which is the only reason it is
    /// allowed to be one.
    var durationMinutes: Int
    /// The item's detail, verbatim, or nothing. Never a sentence the app
    /// wrote on their behalf.
    var notes: String?
}

// MARK: - URLs

enum FieldDial {
    /// Digits and a leading `+`, and nothing else.
    ///
    /// Built only from a number the *system* handed over — Contacts or Maps —
    /// never from a model, and never from free text somebody typed into a
    /// note. A number this app cannot source is a number this app does not
    /// dial.
    static func normalised(_ number: String) -> String? {
        var digits = ""
        for (index, character) in number.enumerated() {
            if character.isNumber {
                digits.append(character)
            } else if character == "+", index == 0 || digits.isEmpty {
                digits.append("+")
            }
        }
        // Seven is the shortest thing that is plausibly a phone number.
        // Anything shorter is a house number that wandered into the field.
        guard digits.filter(\.isNumber).count >= 7 else { return nil }
        return digits
    }

    static func telURL(_ number: String) -> URL? {
        normalised(number).flatMap { URL(string: "tel:\($0)") }
    }

    /// No prefilled body, ever. A message the couple did not write is the app
    /// putting words in their mouth, and it would be sent under their name.
    static func smsURL(_ number: String) -> URL? {
        normalised(number).flatMap { URL(string: "sms:\($0)") }
    }

    /// Subject only, and only the thing's own title. Same rule as the body:
    /// the app can say what the mail is about because the person already
    /// said it, and it cannot say anything else.
    static func mailtoURL(_ address: String, subject: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        if let subject, !subject.isEmpty {
            components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        }
        return components.url
    }
}

// MARK: - What the screen is waiting on

/// An outward action, held while somebody looks at it.
struct FieldOutreachRequest: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable {
        /// Something was found. It is on screen, and nothing has happened
        /// yet.
        case found
        /// Nobody was found. The common case, and it has its own copy.
        case foundNothing
        /// The address book has never been asked for. Asked here, at the tap,
        /// because this is the first moment the app can say why it wants it.
        case needsContactsPermission
    }

    /// The life item's id. Everything that follows is about that one thing.
    let id: String
    var act: FieldAct
    var itemTitle: String
    var query: FieldTargetQuery
    var candidates: [FieldTarget]
    var state: State
}

/// The one question the app asks afterwards.
struct FieldOutcomeQuestion: Identifiable, Hashable, Sendable {
    let id: String
    /// "You called the vet. Is that one done?"
    var question: String
}

extension FieldAct {
    /// What the app can honestly say it just did — which is that it opened
    /// something, not that anything was achieved.
    func pastTense(target: String?) -> String {
        let who = target ?? "them"
        switch self {
        case .call: return "You called \(who). Is that one done?"
        case .message: return "You texted \(who). Is that one done?"
        case .email: return "You emailed \(who). Is that one done?"
        case .book: return "You called \(who) to book it. Is that one done?"
        case .schedule, .pay, .order, .none:
            return "Is that one done?"
        }
    }
}

// MARK: - Where it goes

enum FieldOutreach {
    /// What tapping the verb should do, once everything knowable is known.
    enum Destination: Hashable, Sendable {
        case call(URL, display: String, target: FieldTarget)
        case message(URL, display: String, target: FieldTarget)
        case email(URL, display: String, target: FieldTarget)
        /// The system's new-event sheet, prefilled.
        case calendarDraft(FieldEventDraft)
        /// Nothing outward to do. The verb marks the thing done, as it always
        /// has.
        case complete
        /// The act was clear and the target was not. The common case, and a
        /// designed state rather than a failure — see the copy in
        /// `FieldOutreachConfirmation`.
        case unresolved(FieldAct, target: String?)
    }

    /// Pure. Takes the act, the thing, and whatever was found; returns where
    /// it would go. Opens nothing.
    static func destination(
        act: FieldAct,
        item: LifeItem,
        target: FieldTarget?,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> Destination {
        switch act {
        case .none, .pay, .order:
            // Real acts with no honest destination on this phone. Paying a
            // bill means somebody's banking app, and the app has no idea
            // which — offering to open the wrong one is worse than not
            // offering. The button does what it always did.
            return .complete

        case .schedule, .book:
            // Booking is a call when there is somebody to call — that is what
            // booking a vet actually is — and a calendar draft when there is
            // not.
            if act == .book, let target, let number = target.phoneNumber,
               let url = FieldDial.telURL(number) {
                return .call(url, display: number, target: target)
            }
            return .calendarDraft(draft(for: item, now: now, calendar: calendar))

        case .call:
            guard let target, let number = target.phoneNumber,
                  let url = FieldDial.telURL(number)
            else { return .unresolved(act, target: target?.name) }
            return .call(url, display: number, target: target)

        case .message:
            guard let target, let number = target.phoneNumber,
                  let url = FieldDial.smsURL(number)
            else { return .unresolved(act, target: target?.name) }
            return .message(url, display: number, target: target)

        case .email:
            guard let target, let address = target.emailAddress,
                  let url = FieldDial.mailtoURL(address, subject: item.title)
            else { return .unresolved(act, target: target?.name) }
            return .email(url, display: address, target: target)
        }
    }

    /// The event, as far as the app can honestly fill it in.
    ///
    /// A time the thing closes is a real time. A day with no time on it opens
    /// at nine, which is a guess — but it is a guess made visible in Apple's
    /// own editor before anything is saved, rather than a guess written into
    /// somebody's calendar behind their back.
    static func draft(
        for item: LifeItem,
        now: Date,
        calendar: Calendar = .gregorianUS
    ) -> FieldEventDraft {
        let start: Date = {
            if let closesAt = item.closesAt { return closesAt }
            if let dueOn = item.dueOn {
                return calendar.date(
                    bySettingHour: 9,
                    minute: 0,
                    second: 0,
                    of: dueOn
                ) ?? dueOn
            }
            return calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        }()

        return FieldEventDraft(
            title: item.title,
            startDate: start,
            durationMinutes: 60,
            notes: item.detail
        )
    }

    /// The headline over the confirmation. Present tense and specific,
    /// because the next tap makes it true.
    static func headline(for destination: Destination) -> String {
        switch destination {
        case .call(_, _, let target): "Calling \(target.name)"
        case .message(_, _, let target): "Texting \(target.name)"
        case .email(_, _, let target): "Emailing \(target.name)"
        case .calendarDraft: "Putting it on the calendar"
        case .complete: "Marking it done"
        case .unresolved(_, let name):
            name.map { "I don't have a number for \($0)." }
                ?? "I don't know who to reach for this."
        }
    }
}
