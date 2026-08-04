//
//  WalkthroughView.swift
//  WE
//
//  "See how WE works" — the chooser, and the thing that hosts a journey.
//
//  A chooser rather than a five-screen carousel, for one reason: the three
//  rules are independent, and the person who taps this from the account
//  surface eighteen months in wants exactly one of them. Making them sit
//  through the other two to reach it is the app charging interest on a
//  question. Each journey ends by offering the next one, so a first run that
//  wants all three still gets all three without a decision in between.
//
//  Nothing here is skippable-once. `WalkthroughPresenter.replay()` always
//  plays, and every screen carries Skip. See that file for when it opens by
//  itself, which is: signed out, first install, and not under test.
//

import SwiftUI

struct WalkthroughView: View {
    let onFinish: () -> Void

    /// Resolved once, at the moment the walkthrough opens, and passed down.
    /// Every journey has to agree about what day it is — a journey that read
    /// `Date()` per step could cross midnight mid-explanation and start
    /// describing a different week than the one it opened with.
    @State private var now = Date()
    @State private var journey: WalkthroughJourney?

    var body: some View {
        Group {
            if let journey {
                WalkthroughJourneyView(
                    journey: journey,
                    now: now,
                    onNextJourney: { self.journey = $0 },
                    onClose: onFinish
                )
                // Identity by journey, so chaining from the end of one to the
                // start of the next rebuilds the step state instead of opening
                // the new journey on its last beat.
                .id(journey.id)
            } else {
                WalkthroughChooser(
                    now: now,
                    onChoose: { self.journey = $0 },
                    onClose: onFinish
                )
            }
        }
        // No container identifier here. `.accessibilityIdentifier` on a view
        // wrapping this much hierarchy does not label the container — it
        // stamps itself onto descendants, and both of the scaffold's buttons
        // came back identified as "walkthrough" instead of as themselves. The
        // journeys were unreachable from a test and from Voice Control alike.
    }
}

// MARK: - The chooser

struct WalkthroughChooser: View {
    var now = Date()
    let onChoose: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            FieldAmbient(
                identity: WalkthroughSeed.identity,
                hour: Calendar.gregorianUS.component(.hour, from: Date())
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
                    // No subtitle. This screen used to open with two lines
                    // explaining that the examples below were real, which is
                    // both unprovable at that point and beside the point —
                    // the examples are right there and make the case
                    // themselves.
                    FieldGateHeadline(title: "Three things\nWE does.")

                    VStack(spacing: FieldMetrics.cardGap) {
                        ForEach(WalkthroughJourney.ordered) { journey in
                            door(journey)
                        }
                    }

                    Button("Not now", action: onClose)
                        .font(FieldType.button)
                        .tracking(FieldTracking.button)
                        .foregroundStyle(.fieldInk(.monoLabelQuiet))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("walkthrough.notNow")
                }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, FieldMetrics.screenTop)
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, FieldMetrics.sectionGapLoose)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
    }

    /// The example, and four words about it.
    ///
    /// The order is deliberate: what was written comes first and gets the
    /// readable weight, the destination sits beside it in the mono voice, and
    /// the four-word title goes underneath. Somebody who reads nothing but the
    /// quoted lines has still seen the product work.
    private func door(_ journey: WalkthroughJourney) -> some View {
        let preview = WalkthroughOutcome.resolve(journey, now: now)?.preview

        return Button {
            onChoose(journey)
        } label: {
            FieldCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let preview {
                        ForEach(preview.said, id: \.self) { line in
                            Text("\u{201C}\(line)\u{201D}")
                                .font(FieldType.listItem)
                                .foregroundStyle(.fieldInk(.headline))
                                .fieldLineHeight(1.34, size: 15.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(journey.title)
                            .font(FieldType.body)
                            .foregroundStyle(.fieldInk(.sectionSubtitle))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        if let preview {
                            Text(preview.landed)
                                .font(FieldType.subLabel)
                                .tracking(FieldTracking.subLabel)
                                .foregroundStyle(.fieldInk(.monoLabelQuiet))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        // Deliberately not `.accessibilityElement(children: .combine)`. A
        // Button already publishes itself as one element with its label's text
        // combined; adding it here replaces the button's own element with a
        // synthesised one that reads correctly and no longer activates. The
        // three doors were unreachable that way, and only the UI test said so.
        .accessibilityLabel(
            "\(journey.subject). \(journey.title)."
                + (preview.map { " \($0.said.joined(separator: ". "))" } ?? "")
        )
        .accessibilityIdentifier("walkthrough.journey.\(journey.rawValue)")
    }
}

// MARK: - Hosting one journey

/// Steps through one journey and, at the end, offers the next.
///
/// The engine is asked once, in `init`, and the answer is held. Not a computed
/// property: `FieldClassifier.classify` and the two proposal functions are
/// pure but not free, and a computed one would re-derive the couple's whole
/// week on every step change merely to redraw a caption. `WalkthroughView`
/// gives this an `.id` per journey, so "once" means once per journey.
struct WalkthroughJourneyView: View {
    let journey: WalkthroughJourney
    let now: Date
    let onNextJourney: (WalkthroughJourney) -> Void
    let onClose: () -> Void

    @State private var step = 0
    private let outcome: WalkthroughOutcome?

    init(
        journey: WalkthroughJourney,
        now: Date,
        onNextJourney: @escaping (WalkthroughJourney) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.journey = journey
        self.now = now
        self.onNextJourney = onNextJourney
        self.onClose = onClose
        self.outcome = WalkthroughOutcome.resolve(journey, now: now)
    }

    var body: some View {
        switch outcome {
        case .movement(let receipt):
            WalkthroughMovement(
                receipt: receipt,
                step: $step,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case .context(let proposal):
            WalkthroughContext(
                proposal: proposal,
                step: $step,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case .memory(let proposal):
            WalkthroughMemory(
                proposal: proposal,
                now: now,
                step: $step,
                journey: journey,
                onNextJourney: onNextJourney,
                onClose: onClose
            )
        case nil:
            silence
        }
    }

    /// The rule declined to fire, so there is nothing true to show.
    ///
    /// This is not a designed state and should be unreachable —
    /// `WalkthroughTests` asserts every journey resolves. It exists because
    /// the alternative to handling `nil` is forcing it, and an explanation
    /// that crashes rather than admit it has nothing to say is the worst of
    /// the available behaviours.
    private var silence: some View {
        WalkthroughScaffold(
            label: journey.subject,
            step: 0,
            stepCount: 1,
            onClose: onClose
        ) {
            EmptyView()
        } caption: {
            WalkthroughBeat(
                label: "Nothing to show",
                line: "WE would rather say nothing than invent an example."
            )
        }
    }
}

// MARK: - The end of a journey
//
// Shared by all three, because "what now" is the same question however you got
// here, and three copies of it would drift.

/// The closing beat's footer behaviour: offer the next journey, or finish.
enum WalkthroughEnding {
    static func nextTitle(after journey: WalkthroughJourney) -> String {
        guard let next = journey.next else { return "Done" }
        return "Next: \(next.subject)"
    }
}

#Preview("Chooser") {
    WalkthroughChooser(onChoose: { _ in }, onClose: {})
}

#Preview("Walkthrough") {
    WalkthroughView(onFinish: {})
}
