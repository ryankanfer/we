//
//  FieldCrossingView.swift
//  WE
//
//  What crosses, and what does not. Phase 2a's last half.
//
//  The database half of 2a made every solo-era row private to whoever wrote it
//  and gave crossing exactly one door — `field_share_solo_history()`, scoped
//  server-side to the caller. This is the screen that opens it.
//
//  The app said "You can keep what you began here" to somebody using it alone.
//  This is the moment that sentence is either kept or quietly withdrawn, so the
//  screen is built around one rule: **it names what will cross, in full, before
//  anything does.** Same rule as the outreach confirmation and the feedback
//  payload — the app shows what leaves before it leaves.
//
//  Two things it deliberately is not:
//
//  It is not a per-record review. Forty checkboxes on the day you pair is not
//  consent, it is an inbox, and the honest thing to review is the shape of what
//  crosses rather than each row of it.
//
//  It is not dismissible by accident. Both answers are real and both are
//  remembered — declining has to be as durable as accepting, or "keep it to
//  myself" silently means "ask me again tomorrow".
//

import SwiftUI

// MARK: - Remembering the answer

/// Whether this person has already decided, for this couple, on this device.
///
/// `UserDefaults` rather than a column, because the decision is only ever asked
/// once and the server already records its outcome in the rows themselves.
/// Keyed by user *and* couple for the same reason the outbox is: a person who
/// leaves one relationship and begins another is owed the question again.
///
/// Registered in `WELocalData`, so signing out forgets it along with
/// everything else — otherwise the next person to use this phone inherits an
/// answer they never gave.
@MainActor
struct FieldCrossingDecision {
    static let defaultsPrefix = "we.crossingAnswered."

    let userID: String
    let coupleID: String
    var defaults: UserDefaults = .standard

    var key: String { "\(Self.defaultsPrefix)\(userID).\(coupleID)" }

    var wasAnswered: Bool { defaults.bool(forKey: key) }

    func remember() { defaults.set(true, forKey: key) }
}

// MARK: - The screen

@MainActor
struct FieldCrossingView: View {
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decision: FieldCrossingDecision

    @State private var isWorking = false

    /// Set when the crossing was asked for and did not happen. The screen
    /// stays up: the question is still unanswered, and saying so is the only
    /// honest thing to do with a tap that moved nothing.
    @State private var didNotCross = false

    private var count: Int { store.soloHistoryCount ?? 0 }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    crosses
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    doesNotCross
                        .padding(.bottom, FieldMetrics.sectionGapLoose)

                    actions
                }
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("field.crossing")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldLabel("Before you share a side")

            Text("You wrote \(count) \(count == 1 ? "thing" : "things") here "
                 + "on your own.")
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.16, size: 32)
                .fixedSize(horizontal: false, vertical: true)

            Text("None of it has crossed. It won't unless you say so — and if "
                 + "you'd rather keep it, that's a real answer and I won't ask "
                 + "again.")
                .font(FieldType.body)
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 14.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Named by kind rather than listed row by row. The shape is what a person
    /// can actually hold in their head; forty titles is a scroll, not consent.
    private var crosses: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("What would cross")
                .padding(.top, 20)
                .padding(.bottom, 8)

            line("The things you filed, and what you typed to file them")
            line("Corrections you made to how I sort things")
            line("Rules you set, and what you asked me to hold back")
        }
    }

    private var doesNotCross: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()

            FieldLabel("What stays yours")
                .padding(.top, 20)
                .padding(.bottom, 8)

            line("Anything you write from here on that you keep to yourself")
            line("When you're away, and everything about where you are")

            Text("Your partner's side works the same way. Nothing they wrote "
                 + "alone has crossed to you either.")
                .font(FieldType.reasoning)
                .foregroundStyle(.fieldInk(.reasoning))
                .fieldLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.metadataProse))
            .fieldLineHeight(1.5, size: 14.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .overlay(alignment: .top) { FieldRuleLine(color: FieldRule.row) }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRuleLine()
                .padding(.bottom, 20)

            Button(isWorking ? "Bringing it across…" : "Bring it across") {
                isWorking = true
                didNotCross = false
                Task {
                    let shared = await store.shareSoloHistory(
                        decision: decision
                    )
                    isWorking = false
                    // Only a crossing that happened closes this. On failure
                    // the store has recorded nothing, so the cover stays and
                    // the button is still the same offer.
                    if shared == nil {
                        didNotCross = true
                    } else {
                        dismiss()
                    }
                }
            }
            .buttonStyle(FieldOutlinedButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("field.crossing.share")
            .padding(.bottom, didNotCross ? 10 : 14)

            if didNotCross {
                Text("That didn't cross — nothing moved, and I haven't taken "
                     + "this as your answer. Try again when you're back on.")
                    .font(FieldType.reasoning)
                    .foregroundStyle(.fieldInk(.reasoning))
                    .fieldLineHeight(1.5, size: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("field.crossing.failed")
                    .padding(.bottom, 14)
            }

            // Equal weight in wording, quieter in style — the same treatment
            // "no" gets everywhere else in the app. It is a real answer, not
            // the way out of a dialog.
            Button("Keep it to myself") {
                store.keepSoloHistoryPrivate(decision: decision)
                dismiss()
            }
            .buttonStyle(FieldQuietButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("field.crossing.keep")
        }
    }
}
