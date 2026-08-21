import Foundation
import SwiftUI
import Testing
@testable import WE

/// The stillness, held to the one property that makes it the stillness.
///
/// A golden image proves it looks right once. These prove it cannot start
/// accumulating, which is the failure mode that would arrive later, in a
/// reasonable-looking commit, from somebody trying to be helpful.
struct WEStillnessTests {

    /// Day thirty is day one.
    ///
    /// The view takes a line, an owner, an identity, and a withdrawal. There
    /// is no date, no interval, no attempt count, and no session — so there is
    /// nothing a thirty-day-old screen could render differently from a
    /// one-second-old one. Adding any of those to the initialiser is the
    /// change this test exists to make somebody argue for.
    @Test func nothingTimeVaryingCanReachTheScreen() {
        let first = WEStillness(
            line: "WE is still until Dylan arrives.",
            identity: .seed,
            withdrawal: "Withdraw the invitation",
            onWithdraw: {}
        )
        let thirtyDaysLater = WEStillness(
            line: "WE is still until Dylan arrives.",
            identity: .seed,
            withdrawal: "Withdraw the invitation",
            onWithdraw: {}
        )
        #expect(first.line == thirtyDaysLater.line)
        #expect(first.owner == thirtyDaysLater.owner)
        #expect(first.withdrawal == thirtyDaysLater.withdrawal)
    }

    /// The line is one sentence and says nothing about how long.
    @Test func theLineCarriesNoDuration() {
        let line = "WE is still until Dylan arrives."
        #expect(line.allSatisfy { !$0.isNumber })
        for word in ["waiting", "still waiting", "yet", "since", "ago",
                     "minutes", "hours", "days", "resend", "remind"] {
            #expect(
                !line.lowercased().contains(word),
                "the stillness must not say \(word)"
            )
        }
    }

    /// A screen with genuinely no exit is a trap rather than a promise, so
    /// the withdrawal is optional in the type but present in practice.
    @Test func theWithdrawalIsAvailable() {
        let withOut = WEStillness(
            line: "WE is still until Dylan arrives.",
            identity: .seed,
            withdrawal: "Withdraw the invitation",
            onWithdraw: {}
        )
        #expect(withOut.withdrawal != nil)
        #expect(withOut.onWithdraw != nil)
    }

    /// Waiting for someone is a private moment, so the field is one person's
    /// hue. Mutual stillness is the same screen with a shared field, which is
    /// why the owner is a parameter and not a constant.
    @Test func theFieldIsOnePersonsHueByDefault() {
        let view = WEStillness(line: "x", identity: .seed)
        #expect(view.owner == .a)
    }
}

/// The gate's replaced copy, governed the way `YoursCopy` is.
///
/// The correct voice already existed in `Yours` and never reached the front
/// door; the gate screens had no constraint test and drifted into the register
/// of the specification documents that produced them.
struct WEGateCopyTests {
    /// Everything the invitation and stillness screens can now say.
    /// Hand-maintained, so adding a string means deciding it belongs.
    private static let everything = [
        "For Dylan.",
        "For them.",
        "Send this when you're ready. Dylan will see your name and nothing else.",
        "Send this when you're ready. They'll see your name and nothing else.",
        "Who is this for?",
        "WE is still until Dylan arrives.",
        "WE is still until they arrive.",
        "Withdraw the invitation",
    ]

    /// The word "threshold" does not appear on any surface anybody reads.
    ///
    /// It survives fine as internal geometry naming in `WEJourneyVisuals`. In
    /// a headline it is the specification talking.
    @Test func nothingSaysThreshold() {
        for line in Self.everything {
            #expect(!line.lowercased().contains("threshold"), "\(line)")
        }
    }

    /// No hyphens, en dashes, or em dashes.
    @Test func thereAreNoDashes() {
        for line in Self.everything {
            #expect(!line.contains("-"), "\(line)")
            #expect(!line.contains("\u{2013}"), "\(line)")
            #expect(!line.contains("\u{2014}"), "\(line)")
        }
    }

    /// No decorative numerals, and no progress language. The ceremony reveals
    /// its own length by ending.
    @Test func thereIsNoProgressLanguage() {
        for line in Self.everything {
            #expect(line.allSatisfy { !$0.isNumber }, "\(line)")
            for word in ["step", "of three", "next", "continue", "progress",
                         "setting up", "almost", "finish"] {
                #expect(!line.lowercased().contains(word), "\(word) in \(line)")
            }
        }
    }

    /// Sentence case. The one deliberate uppercase exception in the product is
    /// the navigation, and "WE" is the product's own name.
    @Test func itIsSentenceCase() {
        for line in Self.everything {
            let shouty = line
                .split(separator: " ")
                .filter { $0.count > 2 && $0 == $0.uppercased() }
                .filter { $0 != "WE" }
            #expect(shouty.isEmpty, "\(shouty) in \(line)")
        }
    }

    /// Once WE has been told the name, it never says "your partner" again.
    @Test func theNamedFormNeverSaysPartner() {
        for line in Self.everything where line.contains("Dylan") {
            #expect(!line.lowercased().contains("partner"), "\(line)")
        }
    }
}
