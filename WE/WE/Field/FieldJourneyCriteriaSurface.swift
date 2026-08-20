//
//  FieldJourneyCriteriaSurface.swift
//  WE
//
//  "What we're looking for" — the first view a journey can grow.
//
//  It reads. It does not own anything, it does not write anything, and it holds
//  no copy of what it shows: every line here is a live read through a
//  `FieldReference` at the record the couple already wrote somewhere else. Take
//  the underlying item away and the line goes with it, which is the behaviour a
//  lens should have and a container should not.
//

import SwiftUI

struct FieldJourneyCriteriaSurface: View {
    let journey: SharedJourney
    /// Whether this is the first capability this person has ever met.
    let isFirst: Bool

    @Environment(FieldStore.self) private var store

    private var subjects: [JourneySubject] {
        SharedJourneyCapabilityPolicy.subjects(
            for: journey, context: store.sharedPresenceContext
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst {
                // Said once, in place, at the moment the thing appears —
                // rather than in a tour before it exists.
                Text("A useful view appeared")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.legend))
                    .padding(.bottom, 6)
                Text("This was gathered from things you both already shared.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
            }

            FieldLabel("What we're looking for")
                .padding(.bottom, 16)
                .accessibilityIdentifier("field.journey.criteria")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(subjects) { subject in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject.title)
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.4, size: 15)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = subject.detail, !detail.isEmpty {
                            Text(detail)
                                .font(FieldType.reasoning)
                                .foregroundStyle(.fieldInk(.reasoning))
                                .fieldLineHeight(1.5, size: 13)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
