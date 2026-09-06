//
//  FieldProvenanceSheet.swift
//  WE
//
//  What brought this here.
//
//  Reasons have always been on screen in this app — the italic line behind a
//  person-coloured rule. What was missing was the ability to open one. A
//  sentence explaining a surface is a claim; the records behind it are the
//  evidence, and a product that rearranges itself owes people the second thing
//  and not only the first.
//
//  A reference that no longer resolves is dropped rather than shown as a
//  missing row. See `SharedJourneyCapabilityPolicy.resolve` for why the two
//  reasons it can fail must stay indistinguishable.
//

import SwiftUI

/// `Identifiable` so the sheet can be driven by `.sheet(item:)`, which is what
/// keeps the presented proof and the thing that was tapped from drifting apart.
extension FieldProvenance: Identifiable {
    var id: String {
        reason + sources.map { "\($0.kind):\($0.id)" }.joined(separator: "|")
    }
}

struct FieldProvenanceSheet: View {
    let provenance: FieldProvenance
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var subjects: [JourneySubject] {
        provenance.sources.compactMap {
            SharedJourneyCapabilityPolicy.resolve(
                $0, context: store.sharedPresenceContext
            )
        }
    }

    var body: some View {
        ZStack {
            FieldPalette.bgElevated.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                FieldLabel("What brought this here")
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("field.provenance")

                FieldReasoning(
                    text: provenance.reason,
                    accent: store.identity.personA.color
                )
                .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(subjects) { subject in
                        Text(subject.title)
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.4, size: 15)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.legend))
                        .padding(.top, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 48)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
    }
}
