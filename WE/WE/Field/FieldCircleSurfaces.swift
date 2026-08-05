//
//  FieldCircleSurfaces.swift
//  WE
//
//  The circle — the two screens the mark can lead to.
//
//  The teaching, which happens once and is not optional, and the room, which
//  happens whenever both of them have said they are open.
//
//  What is deliberately absent from both: any indication of what the partner
//  has or has not done, any record that the room was opened, any capture, any
//  way to keep what was said. The room is a place to look at one question
//  together and then close. If either person wants to keep something from it,
//  they write it privately and may later offer it through the consent flow
//  that already exists — see `YoursSurface`. There is no new path from here.
//

import SwiftUI

// MARK: - Taught once

/// Required, not optional.
///
/// The tap is invisible by design, which means that without this the honest
/// reading of a first tap is "it didn't work" — and the natural response to
/// that is to tap again, and then to ask why nothing is happening. An
/// uninstructed mark becomes covert pressure on the other person. So: what the
/// tap means, that nothing is shown to your partner, and that there is nothing
/// to wait for. Then never again, the same discipline as `YoursTeachingSheet`.
struct FieldCircleTeachingSheet: View {
    /// The couple's own two colours, not a stand-in pair. The sheet is
    /// explaining *their* mark, and the mark is the blend of the two swatches
    /// they chose — drawing default clay and slate here would teach somebody
    /// to look for a shape they do not have.
    let identity: FieldIdentity
    let onSeen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FieldIntelligenceMark(
                identity: identity,
                diameter: 22,
                ringDiameter: 56
            )
            .frame(height: 56)

            Text(FieldCircleCopy.teachingTitle)
                .font(FieldType.pageHeadline)
                .foregroundStyle(.fieldInk(.headline))
                .fixedSize(horizontal: false, vertical: true)

            Text(FieldCircleCopy.teachingBody)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.fieldInk(.sectionSubtitle))
                .fieldLineHeight(1.6, size: 15)
                .fixedSize(horizontal: false, vertical: true)

            Button(FieldCircleCopy.teachingDismiss) { onSeen() }
                .buttonStyle(FieldOutlinedButtonStyle())
        }
        .padding(FieldMetrics.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FieldPalette.bg)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .accessibilityIdentifier("field.circle.teaching")
    }
}

// MARK: - The room

/// One prompt, on both screens, in the same words.
///
/// There is no text field here and there is not going to be one. WE does not
/// collect two answers, compare them, or announce a match — the invariant at
/// `20260729193000_private_answers_shared_directions.sql:130-133` is that a
/// shared result may never vary with answer content or answer equality,
/// because "you matched" plus your own answer discloses your partner's. The
/// room honours it by having nothing to compare. The conversation happens
/// between the two of them, out loud, and the app is not in it.
struct FieldCircleRoom: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let identity: FieldIdentity
    let prompt: String
    let onClose: () -> Void

    /// Drives the bloom. One shot on appear — the mark opening outward is the
    /// only animation here, and it is what makes the room feel like something
    /// that arrived rather than a screen that was pushed.
    @State private var hasBloomed = false

    private var bloomScale: CGFloat {
        reduceMotion ? 1 : (hasBloomed ? 1 : 0.72)
    }

    var body: some View {
        ZStack {
            FieldPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 30) {
                    FieldIntelligenceMark(
                        identity: identity,
                        diameter: 30,
                        ringDiameter: 110
                    )
                    .frame(height: 110)
                    .scaleEffect(bloomScale)
                    .opacity(hasBloomed ? 1 : 0)

                    VStack(spacing: 18) {
                        Text(FieldCircleCopy.bloomTitle)
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(.fieldInk(.sectionSubtitle))
                            .multilineTextAlignment(.center)

                        Text(prompt)
                            .font(FieldType.pageHeadline)
                            .foregroundStyle(.fieldInk(.headline))
                            .fieldLineHeight(1.2, size: 32)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(hasBloomed ? 1 : 0)
                }
                .padding(.horizontal, FieldMetrics.screenSide)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    Button(FieldCircleCopy.close) { onClose() }
                        .buttonStyle(FieldOutlinedButtonStyle())
                        .accessibilityIdentifier("field.circle.close")

                    Text(FieldCircleCopy.noResidue)
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.legend))
                }
                .padding(.horizontal, FieldMetrics.screenSide)
                .padding(.bottom, 50)
                .opacity(hasBloomed ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(
                reduceMotion ? nil : .easeOut(duration: 0.9)
            ) {
                hasBloomed = true
            }
        }
        // One element, announced as one thing. Read as three separate labels
        // this is a title, a question, and a button; read as one it is what
        // actually happened — the two of them arrived here together.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(FieldCircleCopy.bloomTitle) \(prompt)")
        .accessibilityIdentifier("field.circle.room")
    }
}
