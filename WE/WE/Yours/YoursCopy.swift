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

    /// The line inside the empty writing surface.
    ///
    /// Deliberately not "What's on your mind?" or any other question. §7's
    /// whole argument is that this space does not ask for anything, and a
    /// prompt phrased as a question is a request for an answer. This names
    /// the one guarantee instead, which is what makes the space usable.
    static let composePlaceholder = "Write here. Only you can see this."

    /// The reassurance under the dated receipt.
    ///
    /// It used to be "This will return in six weeks." — which the dated
    /// sentence beneath it already said, more precisely. Nothing is listed on
    /// this surface any more, so the receipt is doing the work the list used
    /// to: it is the only confirmation that the writing landed, and the whole
    /// thesis restated at the one moment somebody might doubt it.
    ///
    /// Not "Held" — that is a specific, deliberate state in this product, with
    /// its own drawer and its own decision. Saying it here would collapse the
    /// distinction the surface depends on.
    static let saved = "You don't need to decide what this becomes yet."

    /// Available only while the receipt is on screen.
    static let undoSave = "Undo"

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
        "A private place to write. Choose Keep indefinitely for anything you want to keep without an expiry."

    /// What VoiceOver announces for the mark, forever.
    ///
    /// The same word sighted users are taught, deliberately: naming the label
    /// after the furniture — "your circle", "your space" — would give sighted
    /// and unsighted users different mental models of the same product.
    static let accessibilityName = "Yours"

    // MARK: - Deletion
    // Describe the visible result. Backup/key destruction timing has not
    // been verified, so this screen cannot promise irrecoverability.
    static let deletionAssurance = "Letting go removes this writing from your private space."

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
        "Writing you have not held expires at most one year after its scheduled return, even if you have not read it. It may be let go sooner under the return and inactivity rules."
}
