//
//  FieldTargetResolver.swift
//  WE
//
//  Where a number comes from.
//
//  The one thing this app is allowed to ask the world, and it asks two places:
//  this phone's address book for a person, and Apple Maps for a business. Both
//  hand back a number somebody else is accountable for. Neither is a guess.
//
//  The alternative was a model producing digits from a sentence, which is
//  worth naming plainly: an on-device model has no phone directory, so it does
//  not recall a number, it composes something shaped like one. Dialling that
//  is a failure the person cannot undo and would have no way to see coming.
//  The model's job here is at most to point at a word that is already in the
//  sentence; the number always comes from a system that has one.
//
//  Every resolver returns an empty array rather than throwing. Finding nobody
//  is an answer, and the screen for it is written.
//

import Contacts
import Foundation
import MapKit

protocol FieldTargetResolver: Sendable {
    /// Every plausible match, best first — and nothing at all rather than a
    /// guess.
    func resolve(_ query: FieldTargetQuery) async -> [FieldTarget]
}

// MARK: - The address book

/// This phone's contacts, for the one name that was asked about.
///
/// It never enumerates the address book. `predicateForContacts(matchingName:)`
/// asks for a name and gets that name — which is what makes the permission
/// string honest, so the shape of this call is load-bearing and there is a
/// test that says so.
struct FieldContactsResolver: FieldTargetResolver {
    /// Whether asking is worth it. Authorization is requested at the tap, not
    /// at launch — a couples app asking for the address book on day one, for
    /// a reason it cannot yet explain, deserves the no it would get.
    static var isAuthorized: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: true
        default: false
        }
    }

    static var wasAsked: Bool {
        CNContactStore.authorizationStatus(for: .contacts) != .notDetermined
    }

    static func request(store: CNContactStore = CNContactStore()) async -> Bool {
        (try? await store.requestAccess(for: .contacts)) ?? false
    }

    var store: CNContactStore = CNContactStore()

    func resolve(_ query: FieldTargetQuery) async -> [FieldTarget] {
        guard query.kind == .person, Self.isAuthorized else { return [] }

        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
        ] as [CNKeyDescriptor]

        let contacts = (try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: query.text),
            keysToFetch: keys
        )) ?? []

        return contacts.compactMap { contact in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !name.isEmpty else { return nil }

            return FieldTarget(
                name: name,
                phoneNumber: contact.phoneNumbers.first?.value.stringValue,
                emailAddress: contact.emailAddresses.first?.value as String?,
                address: nil,
                source: .contacts
            )
        }
    }
}

// MARK: - Maps

/// A business, and the address that proves which one.
///
/// Regionless: the app does not ask for location, so this is whatever Maps
/// thinks is near enough. That is exactly why the address is shown on the
/// confirmation rather than kept for the app's own use — the person is the
/// one who knows whether it is their vet.
struct FieldPlacesResolver: FieldTargetResolver {
    func resolve(_ query: FieldTargetQuery) async -> [FieldTarget] {
        guard query.kind == .place else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.text
        request.resultTypes = [.pointOfInterest]

        guard let response = try? await MKLocalSearch(request: request).start()
        else { return [] }

        return response.mapItems.prefix(4).compactMap { item in
            guard let phone = item.phoneNumber, let name = item.name else {
                return nil
            }
            return FieldTarget(
                name: name,
                phoneNumber: phone,
                emailAddress: nil,
                address: item.placemark.thoroughfare.map { street in
                    [item.placemark.subThoroughfare, street]
                        .compactMap { $0 }
                        .joined(separator: " ")
                },
                source: .maps
            )
        }
    }
}

// MARK: - The two of them

/// A person is never looked for on Maps, and a place is never looked for in
/// the address book.
///
/// "Mom" is not a business, and searching for her by that word is how an app
/// ends up offering a stranger's number with somebody's mother's name over
/// it.
struct FieldResolvers: FieldTargetResolver {
    var contacts: any FieldTargetResolver = FieldContactsResolver()
    var places: any FieldTargetResolver = FieldPlacesResolver()

    func resolve(_ query: FieldTargetQuery) async -> [FieldTarget] {
        switch query.kind {
        case .person: await contacts.resolve(query)
        case .place: await places.resolve(query)
        }
    }
}

/// Finds nobody, always.
///
/// The reference conformance, the way `FieldMemoryBackend` is: previews and
/// the gallery must never reach out of the process, and a screenshot run must
/// never depend on what is in the machine's address book.
struct FieldNoTargetResolver: FieldTargetResolver {
    func resolve(_ query: FieldTargetQuery) async -> [FieldTarget] { [] }
}
