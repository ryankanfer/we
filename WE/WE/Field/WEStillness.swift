//
//  WEStillness.swift
//  WE
//
//  The signature screen.
//
//  What sat here was a lobby: held proposals, an invitation, a join code
//  field, archives, and a sign out. Every piece of that furniture invites
//  treating WE as a private notes app with a partner slot, which is the one
//  thing it must never be. The product's claim is that it does not work as
//  one person, and a furnished waiting room is the app quietly admitting it
//  does.
//
//  So there is one line, an ambient field, and a way out that does not ask to
//  be looked at. No tips, no what to expect, no meanwhile you could, no
//  partial dashboard, no saved on your side card.
//
//  It has to feel like devotion rather than a spinner. If it reads as an
//  empty state, the direction has failed — this is a screen somebody may look
//  at for two days, and it should be worth looking at for two days.
//
//  DAY THIRTY IS DAY ONE
//
//  Nothing here accumulates. No elapsed time, no "still waiting", no nudge,
//  no offer to resend, no counter that grows. That is not an oversight to be
//  filled in later: any accumulating reassurance converts devotion into
//  anxiety, and the whole position rests on refusing it. The golden test
//  asserts the screen is unchanged after thirty days, so the decision is
//  enforced rather than remembered.
//

import SwiftUI

struct WEStillness: View {
    /// The line. One sentence, and the only thing on the page.
    let line: String

    /// Whose hue the field carries.
    ///
    /// Waiting for someone to arrive is a private moment, so it is one
    /// person's colour. Mutual stillness, when it comes, is the same screen
    /// with a shared field, which is why this is a parameter rather than a
    /// constant.
    var owner: FieldOwner = .a
    var identity: FieldIdentity

    /// The way out. Deliberately last, deliberately quiet, and deliberately
    /// present: a screen with genuinely no exit is a trap rather than a
    /// promise.
    var withdrawal: String?
    var onWithdraw: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            WECanvas.dark.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                WEDisplayText(line, role: .hero)

                Spacer(minLength: 0)

                if let withdrawal, let onWithdraw {
                    // Plain serif, not the tracked uppercase mono the quiet
                    // button style draws. On a screen that is one serif
                    // sentence, a shouted mono label is the loudest thing
                    // present, which is the opposite of recessive — and the
                    // navigation is the only uppercase the direction allows.
                    //
                    // Recessive, but not hidden: it must not compete with the
                    // line, and putting it behind a gesture would make
                    // leaving feel furtive.
                    WEEditorialAction(withdrawal, action: onWithdraw)
                        .accessibilityIdentifier("we.stillness.withdraw")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FieldMetrics.usSide)
            .padding(.bottom, FieldMetrics.screenBottom(at: typeSize))

            // Taller than the bar's field, because this one has to carry the
            // screen rather than sit under it. The gradient originates below
            // the display edge, so a short frame crops away the part that
            // reads as light and leaves only the dim outer edge — which looks
            // like a smudge rather than like a room with someone in it.
            WEColourField(state: .mine(owner), identity: identity, height: 168)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
        }
        .environment(\.weCanvas, .dark)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("we.stillness")
    }
}

#Preview("Stillness") {
    WEStillness(
        line: "WE is still until Dylan arrives.",
        identity: .seed,
        withdrawal: "Withdraw the invitation",
        onWithdraw: {}
    )
}
