//
//  WEGateCopy.swift
//  WE
//
//  Every word the app says before the zones open.
//
//  WHY THE STRINGS LIVE HERE AND NOT IN THE VIEWS
//
//  The rules in `WEGateCopyTests` were already written — no decorative
//  numerals, no progress language, sentence case, no dashes, and never the
//  word "threshold" — and they were being applied to a **hand copied array of
//  literals** kept beside them in the test file. Which means the constraint
//  was on the copy of the copy: a view could be reworded into a violation and
//  every rule would keep passing, because none of them had ever seen a view.
//
//  So the strings moved. The views read from here, the rules read from here,
//  and `everything` is assembled from the same constants rather than retyped
//  beside them. Adding a gate string now means adding it here, which means
//  deciding it belongs — and the rules meet it on the way in.
//
//  WHAT IS DELIBERATELY NOT HERE
//
//  The three beats of The Joining. They live on `WEBeat`, where the model that
//  performs them is, and `WEPromiseViewTests` governs them with rules of its
//  own. A promise is not gate furniture.
//
//  THE NAME
//
//  Once WE has been told who the other person is, it uses their name. It never
//  says "your partner" about somebody it can name, which is why almost
//  everything here is a function of a name rather than a constant, and why the
//  unnamed forms are written out in full rather than assembled from fragments
//  around a placeholder.
//

import Foundation

enum WEGateCopy {

    // MARK: The first screen

    /// The cold open. A question rather than a description: what preceded it
    /// announced a category ("A shared space for what matters between you")
    /// and then explained the category again underneath, which is a product
    /// introducing itself to a stranger. This one is about the person they
    /// are thinking of.
    static let welcome = "Who are you making this with?"

    /// One word. It was "Start a WE space", which names the mechanism, and
    /// the mechanism is not what anybody is deciding at this moment.
    static let begin = "Begin"

    /// Not "Have an invitation?" over a button reading "Join with a code".
    /// The label and the button were the same sentence said twice, and the
    /// half that survives is the half in the person's own voice.
    static let invited = "Someone invited me"

    static let signIn = "Sign in"

    // MARK: Inviting

    static func invitationTitle(for name: String?) -> String {
        guard let name = trimmed(name) else { return "For them." }
        return "For \(name)."
    }

    static func invitationDetail(for name: String?) -> String {
        guard let name = trimmed(name) else {
            return "Send this when you're ready. They'll see your name and nothing else."
        }
        return "Send this when you're ready. \(name) will see your name and nothing else."
    }

    static let invitationWithdrawnTitle = "The invitation has\nbeen withdrawn."

    static let invitationWithdrawnDetail =
        "This code no longer opens anything. Make a new one when you are ready."

    static let inviteeNameField = "Who is this for?"

    static let withdraw = "Withdraw the invitation"

    // MARK: Waiting

    static func stillness(for name: String?) -> String {
        guard let name = trimmed(name) else { return "WE is still until they arrive." }
        return "WE is still until \(name) arrives."
    }

    // MARK: Being invited

    /// The invited person's first line, when the invitation answers.
    ///
    /// Told, not asked. Everything about this screen turns on it arriving
    /// before the code field rather than after it.
    static func waiting(for name: String) -> String { "\(name) is waiting." }

    /// The same sentence when the network has not answered, or the code is not
    /// live. Still a statement, and still true of somebody who was invited.
    static let waitingUnnamed = "Someone is waiting for you."

    static let codeField = "The code they sent you"

    /// The action under the code field. Not "Continue": progress language is
    /// the app narrating its own funnel, and this is the person offering the
    /// one thing they were given.
    static let useCode = "Use this code"

    /// The way to say no, in the invited person's own voice.
    ///
    /// Not "Not now", which promises a later that revoking does not leave, and
    /// not "Decline", which is the register of a form. It says nothing about
    /// why, because nobody owes an account of themselves for this.
    static let decline = "I would rather not."

    // MARK: The invitation, closed

    /// What the person who sent it meets on a natural return.
    ///
    /// Unattributed, on purpose. "The invitation has been withdrawn" is what
    /// they see when *they* withdrew it; this is the sentence for every other
    /// way an invitation stops being live, and it names nobody, gives no
    /// reason and carries no time. Being told no is survivable. Being told who
    /// and when, over and over, is not.
    static let invitationClosedTitle = "This invitation is closed."

    static let invitationClosedDetail =
        "You can make a new one whenever you like."

    // MARK: Arriving

    /// Three words, on both phones, about the other person. Neither phone
    /// announces its owner to its owner.
    static func arrival(of name: String) -> String { "\(name) is here." }

    // MARK: Leaving, and looking back

    /// Was "Replay the Living Confluence Promise", which names the artefact
    /// rather than the moment and asks somebody to read their own ceremony
    /// back as a document.
    static let replayPromise = "See the beginning again"

    /// Was "How WE notices". The setting is about the one thing a person
    /// actually wants control of, which is being interrupted.
    static let interruptions = "When WE interrupts you"

    // MARK: The rules' subject

    /// Every gate string, for the constraints in `WEGateCopyTests`.
    ///
    /// The named and unnamed forms of each sentence are both present, because
    /// both reach a screen and the rules apply to whichever one somebody meets.
    static let everything: [String] = [
        welcome,
        begin,
        invited,
        signIn,
        invitationTitle(for: "Dylan"),
        invitationTitle(for: nil),
        invitationDetail(for: "Dylan"),
        invitationDetail(for: nil),
        invitationWithdrawnTitle,
        invitationWithdrawnDetail,
        inviteeNameField,
        withdraw,
        stillness(for: "Dylan"),
        stillness(for: nil),
        waiting(for: "Ryan"),
        waitingUnnamed,
        codeField,
        useCode,
        decline,
        invitationClosedTitle,
        invitationClosedDetail,
        arrival(of: "Dylan"),
        replayPromise,
        interruptions,
    ]

    private static func trimmed(_ name: String?) -> String? {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
