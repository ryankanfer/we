import Foundation
import Testing
@testable import WE

/// Us as a field (§14d).
///
/// The screen's whole claim is that size means frequency, so these assert that
/// the weight comes from things the couple actually accumulated and that the
/// ordering is stable. §4's prohibitions — nothing dated, nothing finishable —
/// are properties of the model too: there is no `isDone` here to assert
/// against, and that is the point.
struct FieldUsFieldTests {
    private static func horizon(
        _ id: String,
        title: String,
        linked: [String] = [],
        owner: FieldOwner = .shared
    ) -> FieldHorizon {
        FieldHorizon(
            id: id,
            title: title,
            window: nil,
            owner: owner,
            isPrimary: false,
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: linked,
            openQuestion: nil
        )
    }

    private static func evidence(_ id: String, horizonID: String) -> FieldEvidence {
        FieldEvidence(
            id: id,
            statement: "Something happened.",
            owner: .shared,
            horizonID: horizonID,
            occurredAt: FieldSampleData.today
        )
    }

    private static func state(
        horizons: [FieldHorizon] = [],
        evidence: [FieldEvidence] = [],
        rhythms: [FieldRhythm] = [],
        anchors: [FieldAnchor] = []
    ) -> FieldState {
        var state = FieldState.seed
        state.horizons = horizons
        state.evidence = evidence
        state.rhythms = rhythms
        state.anchors = anchors
        return state
    }

    // MARK: Where the weight comes from

    /// A horizon is weighted by what points at it, not by anything new.
    @Test
    func aHorizonWeighsWhatPointsAtIt() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                horizons: [
                    Self.horizon("japan", title: "Japan,", linked: ["a", "b"]),
                ],
                evidence: [Self.evidence("e1", horizonID: "japan")]
            )
        )

        #expect(mentions.count == 1)
        #expect(mentions[0].weight == 3)
    }

    /// Evidence pointing at a *different* horizon must not inflate this one.
    @Test
    func evidenceOnlyCountsTowardItsOwnHorizon() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                horizons: [Self.horizon("japan", title: "Japan,")],
                evidence: [Self.evidence("e1", horizonID: "elsewhere")]
            )
        )
        #expect(mentions[0].weight == 0)
    }

    /// A rhythm already counts itself.
    @Test
    func aRhythmWeighsItsOccurrences() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                rhythms: [
                    FieldRhythm(
                        id: "cook",
                        title: "The Thursday cook-in",
                        cadence: "Thursdays",
                        health: .running,
                        horizonID: nil,
                        occurrences: 14,
                        lastOccurred: nil
                    ),
                ]
            )
        )
        #expect(mentions[0].weight == 14)
    }

    /// Agreed once, and not relitigated — so it sits at the floor rather than
    /// competing with the things that keep coming up.
    @Test
    func anAnchorSitsAtTheFloor() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                anchors: [
                    FieldAnchor(
                        id: "money",
                        text: "No surprises about money.",
                        agreedAt: FieldSampleData.today
                    ),
                ]
            )
        )
        #expect(mentions[0].weight == 1)
    }

    // MARK: Ordering

    @Test
    func theFieldIsOrderedByWeightAndIsStable() {
        let built = Self.state(
            horizons: [
                Self.horizon("a", title: "Alpha", linked: ["1"]),
                Self.horizon("b", title: "Beta", linked: ["1", "2", "3"]),
                Self.horizon("c", title: "Gamma", linked: ["1"]),
            ]
        )

        let once = FieldUsMentions.mentions(in: built)
        let twice = FieldUsMentions.mentions(in: built)

        #expect(once.map(\.text) == ["Beta", "Alpha", "Gamma"])
        // Ties break on text, so the field does not reshuffle between reads.
        #expect(once.map(\.id) == twice.map(\.id))
    }

    // MARK: The five steps

    @Test
    func theHeaviestThingAlwaysGetsTheLargestStep() {
        for total in 1...12 {
            #expect(FieldUsMentions.step(forRank: 0, of: total) == 0)
        }
    }

    @Test
    func stepsNeverRunOffTheEndOfTheRamp() {
        for total in 1...40 {
            for rank in 0..<total {
                let step = FieldUsMentions.step(forRank: rank, of: total)
                #expect(step >= 0)
                #expect(step < FieldUsMentions.sizes.count)
            }
        }
    }

    /// The ramp only ever gets quieter going down the field.
    @Test
    func stepsNeverGoBackUp() {
        for total in 2...40 {
            var previous = 0
            for rank in 0..<total {
                let step = FieldUsMentions.step(forRank: rank, of: total)
                #expect(step >= previous)
                previous = step
            }
        }
    }

    /// A short field should not skip straight to the smallest type.
    @Test
    func aFieldOfThreeUsesTheTopOfTheRamp() {
        let steps = (0..<3).map { FieldUsMentions.step(forRank: $0, of: 3) }
        #expect(steps == [0, 1, 2])
    }

    /// Every table the view indexes into has to be as long as the ramp, or a
    /// field with five distinct steps traps at runtime.
    @Test
    func everyRampTableIsTheSameLength() {
        #expect(FieldUsMentions.inks.count == FieldUsMentions.sizes.count)
        #expect(FieldType.usFieldSteps.count == FieldUsMentions.sizes.count)
        #expect(!FieldUsMentions.offsets.isEmpty)
    }
}
