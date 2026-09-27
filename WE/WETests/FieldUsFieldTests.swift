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

    private static func item(
        _ id: String,
        visibility: FieldVisibility = .shared
    ) -> LifeItem {
        LifeItem(
            id: id,
            title: "Item \(id)",
            category: .care,
            owner: .shared,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false,
            visibility: visibility
        )
    }

    private static func state(
        horizons: [FieldHorizon] = [],
        evidence: [FieldEvidence] = [],
        rhythms: [FieldRhythm] = [],
        anchors: [FieldAnchor] = [],
        lifeItems: [LifeItem]? = nil
    ) -> FieldState {
        var state = FieldState.seed
        state.horizons = horizons
        state.evidence = evidence
        state.rhythms = rhythms
        state.anchors = anchors
        // A linked id only counts when it resolves to something shared, so
        // every horizon test has to say what those ids actually are.
        state.lifeItems = lifeItems
            ?? horizons.flatMap(\.linkedLifeItemIDs).map { item($0) }
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

    private static func field(_ weights: [Int]) -> [FieldMention] {
        weights.enumerated().map { index, weight in
            FieldMention(
                id: "m-\(index)",
                text: "M\(index)",
                kind: .horizon,
                owner: .shared,
                weight: weight,
                support: [],
                provenance: nil
            )
        }
    }

    @Test
    func theHeaviestThingAlwaysGetsTheLargestStep() {
        for total in 1...12 {
            let steps = FieldUsMentions.steps(
                for: Self.field((0..<total).map { total - $0 })
            )
            #expect(steps.first == 0)
        }
    }

    @Test
    func stepsNeverRunOffTheEndOfTheRamp() {
        for total in 1...40 {
            let steps = FieldUsMentions.steps(
                for: Self.field((0..<total).map { total - $0 })
            )
            for step in steps {
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
            for step in FieldUsMentions.steps(
                for: Self.field((0..<total).map { total - $0 })
            ) {
                #expect(step >= previous)
                previous = step
            }
        }
    }

    /// A short field should not skip straight to the smallest type.
    @Test
    func aFieldOfThreeUsesTheTopOfTheRamp() {
        #expect(FieldUsMentions.steps(for: Self.field([3, 2, 1])) == [0, 1, 2])
    }

    /// The header promises size means frequency. It used to key the step to
    /// array index, so two subjects with identical evidence rendered at
    /// visibly different sizes because of their first letter.
    @Test
    func equalEvidenceGetsEqualSize() {
        let steps = FieldUsMentions.steps(for: Self.field([9, 4, 4, 4, 1]))
        #expect(steps[1] == steps[2])
        #expect(steps[2] == steps[3])
        #expect(steps[0] < steps[1])
        #expect(steps[3] < steps[4])
    }

    /// Adding something unrelated must not resize the things around it. Only a
    /// new *distinct* weight changes the ramp, and then only by one step.
    @Test
    func addingAnotherThingOfAWeightAlreadyPresentResizesNothing() {
        let before = FieldUsMentions.steps(for: Self.field([9, 4, 1]))
        let after = FieldUsMentions.steps(for: Self.field([9, 4, 4, 1]))
        #expect(after == [before[0], before[1], before[1], before[2]])
    }

    /// Nothing distinguishes them, so nothing is emphasised over anything
    /// else. A whole page at the top step would not be "equal", it would be
    /// shouting.
    @Test
    func aFieldWhereEverythingWeighsTheSameIsFlatAndQuiet() {
        let steps = FieldUsMentions.steps(for: Self.field([2, 2, 2, 2]))
        #expect(Set(steps).count == 1)
        #expect(steps[0] == FieldUsMentions.sizes.count / 2)
    }

    /// One word is not a hierarchy.
    @Test
    func aFieldOfOneTakesTheTopStep() {
        #expect(FieldUsMentions.steps(for: Self.field([7])) == [0])
        #expect(FieldUsMentions.steps(for: []).isEmpty)
    }

    /// Every table the view indexes into has to be as long as the ramp, or a
    /// field with five distinct steps traps at runtime.
    @Test
    func everyRampTableIsTheSameLength() {
        #expect(FieldUsMentions.inks.count == FieldUsMentions.sizes.count)
        #expect(FieldType.usFieldSteps.count == FieldUsMentions.sizes.count)
        #expect(!FieldUsMentions.offsets.isEmpty)
    }

    // MARK: What may be counted

    /// A size is a channel. A private item making a word on a shared screen
    /// visibly bigger would tell one person that the other has something,
    /// without either of them choosing to say so.
    @Test
    func aPrivateItemDoesNotMakeAWordBigger() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                horizons: [
                    Self.horizon("japan", title: "Japan,", linked: ["p", "s"]),
                ],
                lifeItems: [
                    Self.item("p", visibility: .private),
                    Self.item("s"),
                ]
            )
        )

        #expect(mentions[0].weight == 1)
        #expect(mentions[0].support == ["Item s"])
    }

    /// A reference to something that is not there is not evidence of
    /// anything, and it must not be counted as though it were.
    @Test
    func aLinkThatResolvesToNothingCountsForNothing() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                horizons: [
                    Self.horizon("japan", title: "Japan,", linked: ["gone"]),
                ],
                lifeItems: []
            )
        )
        #expect(mentions[0].weight == 0)
    }

    /// The same thing listed twice is one thing pointing at it, not two.
    @Test
    func aDuplicatedLinkIsCountedOnce() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                horizons: [
                    Self.horizon("japan", title: "Japan,", linked: ["a", "a"]),
                ]
            )
        )
        #expect(mentions[0].weight == 1)
    }

    /// Every line offered as an explanation is a record both of them can
    /// already reach.
    @Test
    func theExplanationIsMadeOfSharedRecords() {
        let mentions = FieldUsMentions.mentions(
            in: Self.state(
                horizons: [
                    Self.horizon("japan", title: "Japan,", linked: ["a"]),
                ],
                evidence: [Self.evidence("e1", horizonID: "japan")]
            )
        )
        #expect(mentions[0].support == ["Item a", "Something happened."])
        #expect(mentions[0].weight == mentions[0].support.count)
    }
}
