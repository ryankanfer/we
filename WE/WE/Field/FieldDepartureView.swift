//
//  FieldDepartureView.swift
//  WE
//
//  The one quiet moment after a partner deletes their account.
//
//  It exists because the alternative is worse in both directions. Saying
//  nothing means the mark silently loses a circle, a name disappears from
//  every item, and the person is left to work out from the evidence whether
//  their partner left or the app broke. Saying it more than once means the
//  product raises the subject on a schedule of its own choosing, forever.
//
//  So: told once, on the next open, and then never again. The pattern is
//  `yours_owner_state.taught_in_promise` — CIRCLE.md:52, "a symbol can become
//  wordless after it is learned, not before." `acknowledge_departure()` is
//  what makes the "once" true, and it is called on dismissal rather than on
//  appearance, so a person who force-quits mid-sentence is told again rather
//  than never.
//
//  What it deliberately does not do: name the partner, offer to restore
//  anything, ask how they feel, or suggest a next step. It states what is
//  true about their data and gets out of the way.
//

import SwiftUI

@MainActor
struct FieldDepartureView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel("Your space")
                        .padding(.bottom, 18)

                    Text("This is yours now.")
                        .font(FieldType.pageHeadline)
                        .foregroundStyle(.fieldInk(.headline))
                        .fieldLineHeight(1.16, size: 32)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 20)

                    // The two facts that matter, and only those. The first is
                    // the one people do not expect and would otherwise have to
                    // discover by scrolling and hoping.
                    Text(
                        "Your partner deleted their account. What the two of "
                            + "you built together is still here — every item, "
                            + "every season, everything you filed."
                    )
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)

                    Text(
                        "What was only theirs went with them. Their name has "
                            + "come off what they wrote."
                    )
                    .font(FieldType.body)
                    .foregroundStyle(.fieldInk(.sectionSubtitle))
                    .fieldLineHeight(1.6, size: 14.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, FieldMetrics.sectionGapLoose)

                    FieldRuleLine()
                        .padding(.bottom, 18)

                    Button("Continue") {
                        // Recorded on the way out, not on the way in: a
                        // person who never finished reading this should see
                        // it again rather than never.
                        Task {
                            await session.acknowledgeDeparture()
                            dismiss()
                        }
                    }
                    .buttonStyle(FieldOutlinedButtonStyle())
                    .disabled(session.isWorking)
                    .accessibilityIdentifier("field.departure.continue")
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("field.departure")
        .interactiveDismissDisabled()
    }
}
