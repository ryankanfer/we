//
//  WalkthroughComponents.swift
//  WE
//
//  The parts every journey is built from.
//
//  Two rules govern this file. The first: nothing here invents a visual
//  language. The stage draws the app's own components — `FieldCard`,
//  `FieldReasoning`, the two person colours, the serif/mono split — because a
//  walkthrough drawn in its own style teaches a screen that does not exist.
//  What a person recognises here they have to recognise again on Today.
//
//  The second: the caption and the stage are separate, and the caption is
//  never inside the frame. The stage is the app speaking; the caption is us
//  explaining. Merging them is how a demo ends up putting words in the
//  product's mouth that the product never says.
//

import SwiftUI

// MARK: - The frame every journey sits in

/// The full-screen surface: a zone label, the stage, the caption, the
/// footer. Journeys supply the middle two and nothing else, so all three keep
/// the same margins, the same rhythm, and the same way out.
struct WalkthroughScaffold<Stage: View, Caption: View>: View {
    let label: String
    /// How far through, for the dots. Zero-based.
    let step: Int
    let stepCount: Int
    /// Nil on the last step of the last journey, where "next" is not a step.
    var onNext: (() -> Void)?
    var nextTitle = "Next"
    let onClose: () -> Void
    @ViewBuilder var stage: Stage
    @ViewBuilder var caption: Caption

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            FieldAmbient(
                identity: WalkthroughSeed.identity,
                hour: Calendar.gregorianUS.component(.hour, from: Date())
            )

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: FieldMetrics.sectionGap) {
                        stage
                        caption
                    }
                    .frame(maxWidth: 440, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FieldMetrics.screenSide)
                    .padding(.bottom, FieldMetrics.sectionGapLoose)
                }
                .scrollBounceBehavior(.basedOnSize)

                footer
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            FieldLabel(label)

            Spacer(minLength: 12)

            // Always reachable, on every step. An explanation you cannot leave
            // is not an explanation, it is a toll.
            Button("Skip", action: onClose)
                .font(FieldType.button)
                .tracking(FieldTracking.button)
                .foregroundStyle(.fieldInk(.monoLabelQuiet))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("walkthrough.skip")
        }
        .padding(.top, FieldMetrics.screenTop)
        .padding(.horizontal, FieldMetrics.screenSide)
        .padding(.bottom, FieldMetrics.sectionGapTight)
        .frame(maxWidth: 440, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            WalkthroughProgress(step: step, count: stepCount)

            if let onNext {
                Button(action: onNext) {
                    Text(nextTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(FieldFilledButtonStyle())
                .accessibilityIdentifier("walkthrough.next")
            } else {
                Button(action: onClose) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(FieldFilledButtonStyle())
                .accessibilityIdentifier("walkthrough.done")
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FieldMetrics.screenSide)
        .padding(.top, FieldMetrics.sectionGapTight)
        .padding(.bottom, 34)
    }
}

/// Dots, not a bar and not "3 of 5". Three steps is a short thing and
/// numbering it makes it sound long.
struct WalkthroughProgress: View {
    let step: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == step
                            ? FieldPalette.ink.opacity(0.55)
                            : FieldPalette.ink.opacity(0.18)
                    )
                    .frame(width: index == step ? 18 : 6, height: 3)
            }
        }
        // The dots are 3pt tall and the whole row is one accessibility
        // element, which the hit-region audit rightly fails. Same fix
        // `FieldChip` uses: the marks stay visually small and a transparent
        // frame gives the element Apple's 44pt minimum.
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(count)")
    }
}

// MARK: - The caption

/// Us explaining, under the stage. A mono label and one serif sentence — the
/// same two voices every zone uses for the same job.
///
/// One sentence, and there is deliberately no way to add a second. Every beat
/// carried a supporting paragraph at first and the whole thing read as an
/// essay wrapped around a screenshot; a person who has to read three sentences
/// to understand a picture is looking at the wrong picture. If a beat cannot
/// be said in one line, the stage under it is doing too much.
struct WalkthroughBeat: View {
    let label: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(label)

            Text(line)
                .font(FieldType.synthesis)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.28, size: 25)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stage pieces
//
// Each of these is a fragment of a real surface, drawn the way that surface
// draws it. They are deliberately not interactive: the walkthrough advances on
// its own button, so a tappable-looking control that does nothing never
// appears.

/// What somebody typed, as the capture field shows it.
struct WalkthroughSaid: View {
    let text: String
    var owner: FieldOwner = .a

    private var accent: Color {
        WalkthroughSeed.identity.color(for: owner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(
                "\(WalkthroughSeed.identity.name(for: owner)) said",
                font: FieldType.subLabel,
                tracking: FieldTracking.subLabel,
                color: .fieldInk(.monoLabelQuiet),
                isHeader: false
            )

            Text(text)
                .font(FieldType.captureInput)
                .foregroundStyle(.fieldInk(.headline))
                .fieldLineHeight(1.4, size: 17)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(accent.opacity(0.7))
                        .frame(height: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An item as Life draws it: the title, the category, and — when the app has
/// a reason — the italic line behind a person-coloured rule.
struct WalkthroughFiled: View {
    let title: String
    let category: LifeCategory
    var dueOn: Date?
    var reasoning: String?
    var owner: FieldOwner = .a
    /// Drawn dashed while the app is only proposing it.
    var isProposed = false

    private var accent: Color {
        WalkthroughSeed.identity.color(for: owner)
    }

    var body: some View {
        FieldCard(accent: isProposed ? nil : accent, dashed: isProposed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(FieldType.listItemLarge)
                        .foregroundStyle(.fieldInk(.headline))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(category.rawValue.uppercased())
                        .font(FieldType.subLabel)
                        .tracking(FieldTracking.subLabel)
                        .foregroundStyle(.fieldInk(.monoLabelQuiet))
                }

                if let dueOn {
                    Text(DateFormatter.fieldDayMonth.string(from: dueOn).uppercased())
                        .font(FieldType.dateCount)
                        .tracking(FieldTracking.dateCount)
                        .foregroundStyle(.fieldInk(.legend))
                }

                if let reasoning {
                    FieldReasoning(text: reasoning, accent: accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The app asking, drawn as Today draws a question: the prompt, what is at
/// stake, the reasoning, and exactly two answers.
///
/// The choices are shown, not offered. Which answer a person would give is the
/// subject of the next beat in every journey that uses this, and letting them
/// pick here would mean the explanation forks — three journeys becoming six,
/// with the interesting half of each one unread.
struct WalkthroughAsk: View {
    let question: FieldQuestion

    var body: some View {
        FieldCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(question.prompt)
                    .font(FieldType.cardTitle)
                    .foregroundStyle(.fieldInk(.headline))
                    .fieldLineHeight(1.3, size: 19)
                    .fixedSize(horizontal: false, vertical: true)

                if !question.stakes.isEmpty {
                    Text(question.stakes)
                        .font(FieldType.body)
                        .foregroundStyle(.fieldInk(.sectionSubtitle))
                        .fieldLineHeight(1.55, size: 14.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !question.reasoning.isEmpty {
                    FieldReasoning(
                        text: question.reasoning,
                        accent: WalkthroughSeed.identity.personA.color
                    )
                }

                HStack(spacing: 10) {
                    ForEach(question.choices) { choice in
                        Text(choice.title)
                            .font(FieldType.button)
                            .tracking(FieldTracking.button)
                            .foregroundStyle(.fieldInk(.headline))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                WalkthroughSeed.identity
                                    .color(for: choice.tint)
                                    .opacity(0.16)
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: FieldMetrics.cardRadius,
                                    style: .continuous
                                )
                                .stroke(
                                    WalkthroughSeed.identity
                                        .color(for: choice.tint)
                                        .opacity(0.45),
                                    lineWidth: 1
                                )
                            }
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: FieldMetrics.cardRadius,
                                    style: .continuous
                                )
                            )
                    }
                }
                // Shown, not offered — so they must not read as controls.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Two answers: "
                        + question.choices.map(\.title).joined(separator: ", ")
                )
            }
        }
    }
}

#Preview("Components") {
    ZStack {
        FieldPalette.bg.ignoresSafeArea()

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                WalkthroughSaid(text: WalkthroughSeed.capture)

                WalkthroughFiled(
                    title: "The Greek restaurant Dylan mentioned",
                    category: .food,
                    reasoning: "Dylan brought it up; nothing in Food has a date."
                )

                WalkthroughBeat(
                    label: "What happened",
                    line: "It went to Food, and it said why."
                )
            }
            .padding(30)
        }
    }
    .preferredColorScheme(.dark)
}
