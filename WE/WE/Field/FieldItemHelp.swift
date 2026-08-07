//
//  FieldItemHelp.swift
//  WE
//
//  Purpose-specific lookup for every LIFE category.
//
//  Selecting a purpose does not search. It opens an exact disclosure first,
//  and only the final destination button allows the reviewed query to leave.
//

import SwiftUI

struct FieldItemHelp: View {
    @Environment(FieldStore.self) private var store

    let item: LifeItem

    @State private var request: FieldLookupRequest?

    private var choices: [FieldLookupChoice] {
        FieldLookupPolicy.choices(for: item)
    }

    /// Nothing on screen when there is nothing to offer — no header, no rule
    /// line, no reassuring footer over an empty row of chips. A section that
    /// appears for every item and is useful for some of them teaches people to
    /// stop reading it.
    var body: some View {
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                FieldRuleLine()

                FieldLabel(
                    "Where to look",
                    color: .fieldInk(.monoLabelQuiet)
                )
                .padding(.top, 18)
                .padding(.bottom, 13)

                FieldFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(choices) { choice in
                        FieldChip(choice.label) {
                            request = FieldLookupRequest(
                                choice: choice,
                                title: item.title,
                                sourceURL: item.sourceURL
                            )
                        }
                        .accessibilityIdentifier(
                            "field.item.lookup.\(choice.id)"
                        )
                    }
                }

                // "Searched" was true when every chip built a query. One of
                // them now opens a link instead, and the promise has to cover
                // both without overstating either.
                Text("Nothing opens until you review exactly what it sends.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 13)
            }
            .padding(.bottom, FieldMetrics.sectionGap)
            .accessibilityIdentifier("field.item.help")
            .sheet(item: $request) { request in
                FieldLookupReview(
                    request: request,
                    accent: store.identity.color(for: item.owner)
                )
            }
        }
    }
}

private struct FieldLookupReview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let request: FieldLookupRequest
    let accent: Color

    @State private var clarification = ""
    @State private var couldNotOpen: String?

    private var disclosure: WEOutboundDisclosure {
        FieldLookupPolicy.disclosure(
            for: request,
            clarification: clarification
        )
    }

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()

            VStack(spacing: 0) {
                fixedHeader

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        introduction

                        // No query is built for a saved link, so a
                        // clarification would have nowhere to go. A text field
                        // that changes nothing is worse than no text field.
                        if request.choice.destination != .source {
                            clarificationField
                        }

                        exactDisclosure

                        if request.choice.destination == .shops {
                            shopDestinations
                        } else {
                            openButton
                        }

                        if request.choice.id.hasPrefix("money.") {
                            neutralMoneyNote
                        }

                        if let couldNotOpen {
                            FieldReasoning(text: couldNotOpen, accent: accent)
                        }
                    }
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.top, 22)
                    .padding(.bottom, 50)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("field.item.lookup.review")
    }

    private var fixedHeader: some View {
        HStack {
            FieldLabel("Exact review")
            Spacer(minLength: 12)
            Button("DONE ✕") { dismiss() }
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.legend))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, FieldMetrics.screenSide)
        .frame(minHeight: 56)
        .background(
            reduceTransparency
                ? FieldPalette.bgElevated
                : FieldPalette.bgElevated.opacity(0.97)
        )
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.choice.label.capitalized)
                .font(FieldType.cardTitle)
                .foregroundStyle(.fieldInk(.headline))

            // Opening a saved link still sends a request to that site. The
            // honest claim is not "nothing leaves" — it is that WE composed
            // nothing to send.
            Text(
                request.choice.destination == .source
                    ? "WE will open the original link you saved. No new "
                        + "search query is created or sent by WE."
                    : "Only the words shown below leave WE."
            )
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var clarificationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional clarification")
                .font(FieldType.sectionLabel)
                .foregroundStyle(.fieldInk(.monoLabel))

            TextField(
                "Add only what this lookup needs",
                text: $clarification,
                axis: .vertical
            )
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.headline))
            .lineLimit(1...4)
            .textInputAutocapitalization(.sentences)
            .padding(12)
            .background(
                FieldPalette.ink.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .onChange(of: clarification) { _, value in
                if value.count > 80 {
                    clarification = String(value.prefix(80))
                }
            }
            .accessibilityIdentifier("field.item.lookup.clarification")
        }
    }

    private var exactDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldRuleLine()

            FieldLabel("Leaves this phone")

            disclosureRow("Destination", disclosure.destination)
            disclosureRow("Fields", disclosure.fields.joined(separator: ", "))

            VStack(alignment: .leading, spacing: 5) {
                Text(
                    request.choice.destination == .source
                        ? "EXACT LINK"
                        : "EXACT QUERY"
                )
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.headerMeta))

                Text(disclosure.query)
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.headline))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("field.item.lookup.query")
            }
        }
    }

    private func disclosureRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(FieldType.dateCount)
                .tracking(FieldTracking.dateCount)
                .foregroundStyle(.fieldInk(.headerMeta))
            Text(value)
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.quietListItem))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openButton: some View {
        Button("OPEN \(disclosure.destination.uppercased())") {
            let url: URL? = switch request.choice.destination {
            case .web:
                FieldSearchLink.web(disclosure.query)
            case .maps:
                FieldSearchLink.maps(disclosure.query)
            case .shops:
                nil
            case .source:
                // Checked again at the point of use rather than trusted from
                // the policy that offered the chip. The guard is cheap and the
                // thing being guarded is handing a stored string to the system
                // opener.
                request.sourceURL?.scheme?.lowercased() == "https"
                    ? request.sourceURL
                    : nil
            }
            open(url)
        }
        .buttonStyle(FieldFilledButtonStyle())
        .accessibilityHint(
            request.choice.destination == .source
                ? "Opens the saved link shown above at \(disclosure.destination)."
                : "Sends the exact query shown above to \(disclosure.destination)."
        )
        .accessibilityIdentifier("field.item.lookup.open")
    }

    private var shopDestinations: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Choose the destination")

            ForEach(
                FieldRetailer.ordered(
                    preferred: [FieldRetailer.from(host: request.sourceURL?.host)]
                        .compactMap { $0 }
                )
            ) { retailer in
                Button(retailer.name) {
                    open(retailer.url(searching: disclosure.query))
                }
                .buttonStyle(FieldOutlinedButtonStyle())
                .accessibilityHint(
                    "Sends the exact query shown above to \(retailer.name)."
                )
                .accessibilityIdentifier(
                    "field.item.lookup.shop.\(retailer.rawValue)"
                )
            }

            Text(
                "WE takes no cut and makes no claim about price, stock, "
                    + "quality, or ranking."
            )
            .font(FieldType.reasoning)
            .foregroundStyle(.fieldInk(.reasoning))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        }
    }

    private var neutralMoneyNote: some View {
        Text(
            "This opens a neutral search, not financial advice or a "
                + "recommendation. Check the provider and terms yourself."
        )
        .font(FieldType.reasoning)
        .foregroundStyle(.fieldInk(.reasoning))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func open(_ url: URL?) {
        guard let url else {
            couldNotOpen = "WE could not make a safe destination for this."
            return
        }
        couldNotOpen = nil
        openURL(url) { accepted in
            if accepted {
                dismiss()
            } else {
                couldNotOpen = "This phone couldn't open that destination."
            }
        }
    }
}
