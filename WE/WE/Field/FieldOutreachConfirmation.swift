//
//  FieldOutreachConfirmation.swift
//  WE
//
//  What the app found, before it does anything with it.
//
//  The app is about to act outward on somebody's behalf, and the last decision
//  belongs to them. So this screen shows two things and then stops: the number,
//  and where the number came from. Those are the two facts you would want
//  before your phone starts ringing somebody — the second one especially,
//  because "from Maps" and "from your contacts" are different kinds of
//  confidence, and a wrong number is the one failure here that cannot be
//  taken back.
//
//  Nothing is preselected when there are several. Picking for you is how the
//  app would be wrong on your behalf, quietly.
//

import SwiftUI

struct FieldOutreachConfirmation: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.openURL) private var openURL

    let request: FieldOutreachRequest

    /// Set when the phone refused the URL — the simulator has no dialler, and
    /// neither does an iPad. Shown rather than swallowed, with the number
    /// still on screen to copy.
    @State private var couldNotOpen: String?

    var body: some View {
        ZStack {
            FieldPalette.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                FieldLabel(headerLabel, color: .fieldInk(.monoLabelQuiet))

                Text(headline)
                    .font(FieldType.listItemLarge)
                    .foregroundStyle(.fieldInk(.headline))
                    .fixedSize(horizontal: false, vertical: true)

                switch request.state {
                case .found: candidates
                case .foundNothing: nothingFound
                case .needsContactsPermission: contactsNotAsked
                }

                if let couldNotOpen {
                    Text(couldNotOpen)
                        .font(FieldType.receiptReasoning)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fieldLineHeight(1.65, size: 13.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button("Not now") { store.dismissOutreach() }
                    .buttonStyle(FieldQuietButtonStyle())
                    .accessibilityIdentifier("field.outreach.dismiss")
            }
            .padding(.top, FieldMetrics.screenTop)
            .padding(.horizontal, FieldMetrics.takeoverSide)
            .padding(.bottom, FieldMetrics.takeoverBottom)
        }
        .accessibilityIdentifier("field.outreach.confirm")
    }

    private var headerLabel: String {
        switch request.state {
        case .found: "BEFORE I DO"
        case .foundNothing, .needsContactsPermission: "WHAT I HAVE"
        }
    }

    private var headline: String {
        switch request.state {
        case .found:
            return FieldOutreach.headline(for: destination(for: request.candidates[0]))
        case .foundNothing:
            return "I don't have a number for \(request.query.text)."
        case .needsContactsPermission:
            return "I haven't looked in your contacts."
        }
    }

    // MARK: What was found

    private var candidates: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(request.candidates) { target in
                Button {
                    open(target)
                } label: {
                    FieldCard(accent: store.identity.personA.color) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(target.name)
                                .font(FieldType.listItem)
                                .foregroundStyle(.fieldInk(.headline))

                            if let display = display(for: target) {
                                Text(display)
                                    .font(FieldType.dateCount)
                                    .tracking(FieldTracking.dateCount)
                                    .foregroundStyle(.fieldInk(.dateCount))
                            }

                            // The provenance, always. A number with no
                            // account of where it came from is a number the
                            // app is asking to be trusted on, and it has not
                            // earned that.
                            Text(target.provenance)
                                .font(FieldType.receiptReasoning)
                                .foregroundStyle(.fieldInk(.reasoning))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field.outreach.candidate")
            }

            // Said out loud, because the app went and asked something on
            // their behalf and they should know it did.
            if request.query.kind == .place {
                Text("I asked Maps for \"\(request.query.text)\". Nothing else "
                     + "about this left the phone.")
                    .font(FieldType.receiptReasoning)
                    .foregroundStyle(.fieldInk(.metadataProse))
                    .fieldLineHeight(1.65, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: When there is nothing

    private var nothingFound: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(
                "I looked \(request.query.kind == .person ? "in your contacts" : "on Maps") "
                + "and didn't find one I'm sure about. I'm not going to guess "
                + "at a number."
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.reasoning))
            .fieldLineHeight(1.6, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 11) {
                if request.query.kind == .place {
                    Button("Search Maps") { searchMaps() }
                        .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
                }

                Button("Mark it done") {
                    store.dismissOutreach()
                    store.complete(request.id)
                }
                .buttonStyle(FieldOutlinedButtonStyle(tint: nil))
                .accessibilityIdentifier("field.outreach.complete")
            }
        }
    }

    private var contactsNotAsked: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("I only look when you ask me to, and I only look for the one "
                 + "name. I don't read the rest of your address book.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.6, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)

            Button("Look in my contacts") {
                Task { await store.grantContactsAndRetry() }
            }
            .buttonStyle(FieldFilledButtonStyle())
            .accessibilityIdentifier("field.outreach.grantContacts")
        }
    }

    // MARK: Doing it

    private func destination(for target: FieldTarget) -> FieldOutreach.Destination {
        guard let item = store.state.lifeItems.first(where: {
            $0.id == request.id
        }) else {
            return .unresolved(request.act, target: target.name)
        }
        return FieldOutreach.destination(
            act: request.act,
            item: item,
            target: target,
            now: store.now
        )
    }

    private func display(for target: FieldTarget) -> String? {
        switch destination(for: target) {
        case .call(_, let display, _),
             .message(_, let display, _),
             .email(_, let display, _):
            display
        default:
            nil
        }
    }

    /// The one place anything actually leaves the app.
    ///
    /// `openURL`'s completion rather than `canOpenURL`: asking permission to
    /// ask is a query about what else is installed on somebody's phone, and
    /// the failure is worth handling honestly anyway.
    private func open(_ target: FieldTarget) {
        let destination = destination(for: target)
        guard let url = url(of: destination) else { return }

        openURL(url) { accepted in
            if accepted {
                store.outreachDidOpen(request, target: target)
            } else {
                couldNotOpen = "This phone can't open that. "
                    + (display(for: target).map {
                        "It's \($0) if you want to copy it."
                    } ?? "")
            }
        }
    }

    private func url(of destination: FieldOutreach.Destination) -> URL? {
        switch destination {
        case .call(let url, _, _), .message(let url, _, _), .email(let url, _, _):
            url
        default:
            nil
        }
    }

    /// Apple's own search, with the words that were already said. Nothing is
    /// invented and nothing is claimed.
    ///
    /// Built through `FieldSearchLink` rather than here, so this and the item
    /// sheet's OPEN IN MAPS are one implementation with one test — and so the
    /// one-query-item rule covers both.
    private func searchMaps() {
        guard let url = FieldSearchLink.maps(request.query.text) else { return }
        openURL(url)
        store.dismissOutreach()
    }
}
