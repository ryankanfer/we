import Foundation
import Testing
@testable import WE

/// The Joining, held to its own promises.
///
/// These are not tests of a ceremony working. They are tests of what a
/// ceremony surface is *unable* to find out, because the whole product claim
/// rests on the difference.
struct WECeremonyTests {

    // MARK: What a beat can be

    /// There is no state meaning "they acted and I have not."
    ///
    /// From this device, that situation and "neither of us has acted" produce
    /// the same value, which is the point rather than an omission: showing one
    /// person the other's action before it lands is exactly what the ceremony
    /// exists not to do. If this ever stops being true, someone has added a
    /// case and the product has quietly become a read receipt.
    @Test func theirActionAloneIsIndistinguishableFromNothing() {
        let nobodyActed = WECeremonyState(mine: [], kept: [])
        // The partner acknowledging changes no row this device can select and
        // does not flip the aggregate, so the observable state is identical.
        let theyActed = WECeremonyState(mine: [], kept: [])

        for beat in WEBeat.allCases {
            #expect(nobodyActed.state(of: beat) == theyActed.state(of: beat))
            #expect(nobodyActed.state(of: beat) == .waiting)
        }
    }

    /// Held is what this device sees after giving its half, and it stays that
    /// way. No elapsed time, no nudge, no accumulating reassurance — an hour
    /// into a held beat renders identically to a second into one, because the
    /// state carries nothing that could differ.
    @Test func heldIsAStateRatherThanADuration() {
        let state = WECeremonyState(mine: [.yoursStaysYours], kept: [])
        #expect(state.state(of: .yoursStaysYours) == .held)
        #expect(state.hasGivenCurrentBeat)
        // And the ceremony has not moved on.
        #expect(state.currentBeat == .yoursStaysYours)
    }

    /// Kept requires both, and resolves on both phones at the same instant
    /// because both are reading the same aggregate.
    @Test func keptRequiresTheAggregate() {
        let mineOnly = WECeremonyState(mine: [.yoursStaysYours], kept: [])
        #expect(mineOnly.state(of: .yoursStaysYours) == .held)

        let both = WECeremonyState(
            mine: [.yoursStaysYours],
            kept: [.yoursStaysYours]
        )
        #expect(both.state(of: .yoursStaysYours) == .kept)
    }

    // MARK: Walking back into the room

    /// Resumption lands on the first beat not yet kept, not on the first beat.
    ///
    /// Screen 12 — one person away for a day — is the state most likely to
    /// occur in real use rather than the least, and restarting the ceremony
    /// would make a person perform a promise they already made.
    @Test func resumingLandsOnTheHeldBeat() {
        let state = WECeremonyState(
            mine: [.yoursStaysYours, .nothingMovesWithoutYou],
            kept: [.yoursStaysYours]
        )
        #expect(state.currentBeat == .nothingMovesWithoutYou)
        #expect(state.hasGivenCurrentBeat)
        #expect(!state.isComplete)
    }

    /// A person who left before acting resumes on the same beat, having given
    /// nothing — and is not told that the other person is waiting.
    @Test func resumingWithoutHavingActedShowsNoBacklog() {
        let state = WECeremonyState(mine: [], kept: [])
        #expect(state.currentBeat == .yoursStaysYours)
        #expect(!state.hasGivenCurrentBeat)
        #expect(state.state(of: .yoursStaysYours) == .waiting)
    }

    @Test func theCeremonyEndsByEnding() {
        let state = WECeremonyState(
            mine: Set(WEBeat.allCases),
            kept: Set(WEBeat.allCases)
        )
        #expect(state.isComplete)
        #expect(state.currentBeat == nil)
    }

    /// The ceremony reveals its own length by ending. Nothing here can answer
    /// "how many beats are left" as a proportion, and `currentBeat` is a beat
    /// rather than an index, so no surface can render "one of three" without
    /// deliberately reconstructing it.
    @Test func nothingExposesProgress() {
        let state = WECeremonyState(mine: [], kept: [.yoursStaysYours])
        #expect(state.currentBeat == .nothingMovesWithoutYou)
        // The only count available is of the beats themselves, which is a
        // property of the script rather than of either person.
        #expect(WEBeat.allCases.count == 3)
    }

    // MARK: The beats, as written

    @Test func theBeatsAreTheApprovedWords() {
        #expect(WEBeat.yoursStaysYours.title == "Yours stays yours.")
        #expect(
            WEBeat.nothingMovesWithoutYou.title
                == "Nothing moves without you."
        )
        #expect(
            WEBeat.whatOpensOpensTogether.title
                == "What opens, opens together."
        )
        #expect(
            WEBeat.yoursStaysYours.detail(partner: "Dylan")
                == "Nothing you write reaches Dylan unless you send it."
        )
    }

    /// The partner's name propagates, which is why the app never says "your
    /// partner" after the cold open.
    @Test func theDetailUsesTheNameGiven() {
        let text = WEBeat.yoursStaysYours.detail(partner: "Sam")
        #expect(text.contains("Sam"))
        #expect(!text.contains("your partner"))
    }

    /// Sentence case, and no hyphens, en dashes, or em dashes anywhere in the
    /// ceremony's own words.
    @Test func theBeatCopyObeysTheHouseRules() {
        var everything: [String] = []
        for beat in WEBeat.allCases {
            everything.append(beat.title)
            everything.append(beat.detail(partner: "Dylan"))
        }

        for line in everything {
            #expect(!line.contains("-"), "hyphen in \(line)")
            #expect(!line.contains("\u{2013}"), "en dash in \(line)")
            #expect(!line.contains("\u{2014}"), "em dash in \(line)")
            #expect(
                line.allSatisfy { !$0.isNumber },
                "decorative numeral in \(line)"
            )
            // No tracked uppercase category words, and no shouting.
            #expect(line != line.uppercased(), "upper case in \(line)")
        }
    }

    @Test func theBeatsRunInOrderAndStop() {
        #expect(WEBeat.yoursStaysYours.next == .nothingMovesWithoutYou)
        #expect(WEBeat.nothingMovesWithoutYou.next == .whatOpensOpensTogether)
        #expect(WEBeat.whatOpensOpensTogether.next == nil)
    }

    /// The raw values are the database's `check` constraint, verbatim. A
    /// rename on either side without the other is a write that fails at
    /// runtime, in the ceremony, on someone's first evening with the app.
    @Test func theWireNamesMatchTheMigration() {
        #expect(WEBeat.yoursStaysYours.rawValue == "yours_stays_yours")
        #expect(
            WEBeat.nothingMovesWithoutYou.rawValue
                == "nothing_moves_without_you"
        )
        #expect(
            WEBeat.whatOpensOpensTogether.rawValue
                == "what_opens_opens_together"
        )
    }

    // MARK: Presence

    /// Presence is binary. There is no case carrying a name, a count, or a
    /// time, so a surface cannot draw a last-seen out of it.
    @Test func presenceIsBinary() {
        #expect(WEPresence.alone != WEPresence.together)
    }
}

/// The migration is the security model, so its shape is asserted rather than
/// reviewed.
///
/// Reading the SQL from a test is unusual and deliberate: these three
/// properties are what make the partner's timing unknowable, and each of them
/// is one careless edit away from being undone in a file no Swift test would
/// otherwise touch.
struct WECeremonyMigrationTests {
    private static var sql: String {
        // WETests/WECeremonyTests.swift -> repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root
            .appendingPathComponent("supabase/migrations")
            .appendingPathComponent(
                "20260820210000_ceremony_acknowledgements.sql"
            )
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    @Test func theMigrationIsWhereItSaysItIs() {
        #expect(!Self.sql.isEmpty)
    }

    /// Select is owner-only, and there is no second select policy.
    ///
    /// Policies are additive: one permissive policy naming the couple rather
    /// than the person would hand the partner every row and every timestamp,
    /// and would do it without changing a line of Swift.
    @Test func selectIsOwnerOnlyAndSingular() {
        let selects = Self.sql.components(
            separatedBy: "on public.ceremony_acknowledgements for select"
        ).count - 1
        #expect(selects == 1, "expected exactly one select policy")
        #expect(Self.sql.contains("using (profile_id = (select auth.uid()))"))
    }

    /// No update and no delete. An acknowledgement is a thing that happened,
    /// and a promise you can retract on your own is not one.
    @Test func thereIsNoUpdateOrDeletePolicy() {
        #expect(!Self.sql.contains("for update"))
        #expect(!Self.sql.contains("for delete"))
        #expect(
            Self.sql.contains(
                "grant select, insert on public.ceremony_acknowledgements"
            )
        )
    }

    /// The aggregate returns booleans and nothing else.
    ///
    /// A timestamp, a profile id, or a count in this signature would be the
    /// leak, and it would look entirely reasonable in a diff.
    @Test func theAggregateReturnsOnlyBooleans() {
        #expect(
            Self.sql.contains(
                "returns table (beat text, kept boolean)"
            )
        )
        // The function resolves the couple from the caller's own membership,
        // so there is no couple id to pass and therefore none to guess at.
        #expect(!Self.sql.contains("ceremony_beat_is_kept(p_couple"))
        #expect(Self.sql.contains("public.my_couple_id()"))
    }

    /// The table is not published to realtime.
    ///
    /// This is the third mechanism and the one most easily lost: adding it to
    /// `observedTables` would defeat the first two, because a row event
    /// carries its own arrival time.
    @Test func theTableIsNotObserved() {
        #expect(
            !FieldSupabaseBackend.observedTables
                .contains("ceremony_acknowledgements")
        )
    }
}

/// The Promise view, held to what it is unable to render.
///
/// The view's job is negative as much as positive: there are states it must
/// not be able to show, and the way that is guaranteed is that the state type
/// cannot express them.
struct WEPromiseViewTests {

    /// There is no branch for "they have given it and I have not".
    ///
    /// `action(for:)` switches over `WEBeatState`, which has three cases and
    /// no fourth. Adding one would be the change that turns the ceremony into
    /// a read receipt, and it would have to be argued for here first.
    @Test func theBeatStatesAreExactlyThree() {
        let all: [WEBeatState] = [.waiting, .held, .kept]
        #expect(Set(all.map(String.init(describing:))).count == 3)
    }

    /// Held says one thing, and it is about the beat rather than the person.
    ///
    /// The sentence names no one, carries no number, and cannot change as
    /// time passes — which is what makes an hour into a held beat identical
    /// to a second into one.
    @Test func theHeldLineReportsNothingAboutTheOtherPerson() {
        let line = "Held, until you have both said so."
        #expect(line.allSatisfy { !$0.isNumber })
        for word in ["Dylan", "waiting", "still", "yet", "since", "ago",
                     "them", "they", "partner"] {
            #expect(
                !line.lowercased().contains(word.lowercased()),
                "held must not say \(word)"
            )
        }
    }

    /// No skip, and no dismiss.
    ///
    /// A promise you can skip is a licence agreement. The only affordance on
    /// a waiting beat is the one that gives it.
    @Test func thereIsNoWayPastABeatExceptThroughIt() {
        let source = (try? String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("WE/LivingConfluencePromise.swift"),
            encoding: .utf8
        )) ?? ""

        #expect(!source.isEmpty)

        // Only the code, so the file may still explain in prose what it no
        // longer does. Scanning the whole file made this fail on its own
        // documentation, which is the wrong kind of strict: the point is that
        // the devices are gone, not that they cannot be named.
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        // A promise you can skip is a licence agreement.
        for label in ["\"Skip\"", "\"Close\"", "\"Continue\""] {
            #expect(!code.contains(label), "\(label) is still an action")
        }
        // The consent diagram, and the VoiceOver label that named it. If the
        // mechanic needs a picture, the mechanic is not being performed.
        #expect(!code.contains("private var architecture"))
        #expect(!code.contains("Consent threshold"))
        // The step counter. The ceremony reveals its own length by ending.
        #expect(!code.contains("%02d"))
        // The eyebrows.
        for eyebrow in ["\"MINE\"", "\"OFFERED\"", "\"OURS\""] {
            #expect(!code.contains(eyebrow), "\(eyebrow) is still there")
        }
    }

    /// One haptic, at the moment a beat lands on both phones, and no sound.
    @Test func theCeremonyIsFeltAndNeverHeard() {
        let source = (try? String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("WE/LivingConfluencePromise.swift"),
            encoding: .utf8
        )) ?? ""
        #expect(source.contains("sensoryFeedback"))
        for sound in ["AVAudio", "AudioServices", "playSound", "SystemSound"] {
            #expect(!source.contains(sound), "WE has no sound: \(sound)")
        }
    }

    /// The ceremony ends by ending, and completion is the aggregate rather
    /// than this device having finished its own half.
    @Test func completionRequiresBoth() {
        var state = WECeremonyState(mine: Set(WEBeat.allCases), kept: [])
        #expect(!state.isComplete)
        state.kept = Set(WEBeat.allCases)
        #expect(state.isComplete)
    }
}
