//
//  YoursCopy.swift
//  WE
//
//  Everything this space says, in one place.
//
//  One place because the constraints are on the *set* rather than on any
//  individual string, and a constraint you can only check by reading the whole
//  app is a constraint nobody checks. `YoursCopyTests` asserts across this
//  file: no numeral, no count, no streak, no percentage, no overdue state, no
//  guilt language anywhere. The same shape as `FieldConstraintTests`.
//
//  Two rules that are about the code and not the wording:
//
//    The word "Yours" appears here exactly twice — `teachingTitle` and nowhere
//    else. §2 allows it once during the Promise and once on first entry, then
//    never again: no title, no navigation label, no section header, no
//    settings row. Adding a third use is a product decision, not a copy edit.
//
//    Deletion language is capped until CIRCLE.md §14 closes. See
//    `deletionAssurance`.
//

import Foundation

enum YoursCopy {
    // MARK: - Writing

    /// The invitation, and the whole thesis in six words.
    static let compose = "Write without deciding what it becomes."

    static let saved = "This will return in six weeks."

    /// The empty state. Not "no entries", not a count of zero — there is
    /// nothing to report and the sentence says so.
    static let empty = "Nothing is waiting for you."

    // MARK: - The return

    static let returnQuestion = "Still yours?"

    static let keepForNow = "Keep for now"
    static let letGo = "Let go"
    /// Available from the first save, visually secondary there. Somebody who
    /// knows on day one that a thing is permanent should not have to wait
    /// eighteen weeks to say so.
    static let keepIndefinitely = "Keep indefinitely"

    // MARK: - The second return
    //
    // Three options, no default, no pre-selection. The absence of a default is
    // load-bearing: a pre-selected answer to "should this continue" is the
    // system having an opinion about somebody's private writing.

    static let keepOnlyForMe = "Keep this only for me"
    static let prepareAnOffer = "Prepare something I could offer"
    static let letItGo = "Let it go"

    // MARK: - A week

    static let snooze = "Give me a week"

    // MARK: - Held

    static let heldDrawer = "Held"
    static let letThisReturn = "Let this return"
    static let letThisReturnDetail =
        "This will return in six weeks. If you do nothing then, it will be let go."
    static let letGoNow = "Let go now"

    /// §4. Held status must not silently transfer to newly written material.
    static let heldEditQuestion =
        "You changed something held. Should this version stay held, or return to a natural life?"
    static let updateHeld = "Update Held"

    /// Owner-initiated, never a prompt and never a scheduled audit. There is
    /// no cap on Held and no count of it: a cap turns deliberate permanence
    /// into a storage quota, and at the limit the product would be pressuring
    /// somebody to rank or delete private material.
    static let reviewHeld = "Review what I've held"

    // MARK: - Crossing

    static let prepareOffer = "Prepare an offer"
    static let send = "Send"

    // MARK: - Letting go

    /// Optional, one tap, dismissible. Declining records nothing.
    ///
    /// Asked because §13's real question is not whether releasing felt good
    /// but why — and because the answer means completely different things
    /// depending on what was released.
    static let releaseReasonPrompt = "If you want to say why"
    static let releaseReasonDecline = "Rather not say"

    // MARK: - The teaching moment
    //
    // The only place the word appears. Twice in a lifetime, then the mark
    // carries it alone — a symbol can become wordless after it is learned, not
    // before.

    static let teachingTitle = "Yours"
    static let teachingBody =
        "A place to write that no one else can reach. Nothing here is kept unless you say so."

    /// What VoiceOver announces for the mark, forever.
    ///
    /// The same word sighted users are taught, deliberately: naming the label
    /// after the furniture — "your circle", "your space" — would give sighted
    /// and unsighted users different mental models of the same product.
    static let accessibilityName = "Yours"

    // MARK: - Deletion
    //
    // CIRCLE.md §8 and §14, and this is the one string in the file that is
    // waiting on infrastructure rather than on a decision.
    //
    // Until the key service is chosen and its destruction semantics verified,
    // the product may not say a thing is gone the instant it is asked to be.
    // Supabase keeps its root key outside the database precisely so a restore
    // can bring data back — excellent disaster recovery, and the exact
    // opposite of what this design needs. Until deletion routes through a key
    // WE destroys and can prove it destroyed, "unrecoverable within 24 hours"
    // is the strongest true sentence available.
    //
    // Do not strengthen this string. A promise the infrastructure cannot
    // demonstrate is the footnote that destroys the concept.

    static let deletionAssurance = "Unrecoverable within 24 hours."

    // MARK: - Dormancy
    //
    // Disclosed once, in privacy settings, and never repeated on individual
    // entries. An entry that mentioned it would be an entry nagging about its
    // own mortality.

    static let dormancyDisclosure =
        "If you don't open WE for ninety days, anything you haven't held is let go."

    /// §5's outer bound, phrased as what it is.
    ///
    /// Never "a year of inactivity". The bound follows the entry's state, not
    /// the person's behaviour — describing it the other way would teach people
    /// that opening the space preserves their writing, which produces checking
    /// behaviour and makes absence feel dangerous.
    static let outerBoundDisclosure =
        "Anything you haven't held has a longest possible life, whether or not it reaches you."
}
