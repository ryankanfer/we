import Foundation
import Testing
@testable import WE

@Suite("Shared journey capabilities")
struct SharedJourneyCapabilityPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Earning and keeping a place

    @Test
    func twoSharedSubjectsAreNotYetAPattern() {
        let journey = journey(referencing: ["a", "b"])
        #expect(capabilities(journey, items: items("a", "b")).isEmpty)
    }

    @Test
    func threeSharedSubjectsEarnCriteria() {
        let journey = journey(referencing: ["a", "b", "c"])
        #expect(capabilities(journey, items: items("a", "b", "c")) == [.criteria])
    }

    /// The hysteresis. Finishing one thing must not close the room.
    @Test
    func acapabilityThatHasBeenEarnedKeepsItsPlaceAtOneFewer() {
        let journey = journey(referencing: ["a", "b"])
        let key = SharedJourneyCapabilityPolicy.key(.criteria, journey: journey)

        #expect(capabilities(journey, items: items("a", "b")).isEmpty)
        #expect(
            capabilities(journey, items: items("a", "b"), earned: [key])
                == [.criteria]
        )
    }

    @Test
    func aSurfaceWithOneThingLeftRecedes() {
        let journey = journey(referencing: ["a"])
        let key = SharedJourneyCapabilityPolicy.key(.criteria, journey: journey)
        #expect(
            capabilities(journey, items: items("a"), earned: [key]).isEmpty
        )
    }

    // MARK: Privacy

    /// The invariant this whole kernel exists for. A private row must not be
    /// able to conjure a surface, because presence is conspicuous and the
    /// partner cannot account for it.
    @Test
    func privateItemsCannotEarnACapability() {
        let journey = journey(referencing: ["a", "b", "c"])
        var mixed = items("a", "b")
        mixed.append(item("c", visibility: .private))

        #expect(capabilities(journey, items: mixed).isEmpty)
    }

    @Test
    func aPrivateItemNeverAppearsInTheProof() {
        let journey = journey(referencing: ["a", "b", "c", "d"])
        var mixed = items("a", "b", "c")
        mixed.append(item("d", visibility: .private))

        let bindings = SharedJourneyCapabilityPolicy.eligible(
            for: journey, context: context(items: mixed)
        )
        let proven = bindings.flatMap(\.provenance.sources).map(\.id)
        #expect(!proven.contains("d"))
        #expect(proven == ["a", "b", "c"])
    }

    /// A `.shared` derivation takes no viewer, so this is really a check that
    /// the signature has not grown one.
    @Test
    func eligibilityDoesNotDependOnWhoIsLooking() {
        let journey = journey(referencing: ["a", "b", "c"])
        let shared = context(items: items("a", "b", "c"))
        #expect(
            SharedJourneyCapabilityPolicy.eligible(for: journey, context: shared)
                == SharedJourneyCapabilityPolicy.eligible(
                    for: journey, context: shared
                )
        )
    }

    // MARK: Setting down

    @Test
    func settingASurfaceDownHidesItAndKeepsItsInputs() {
        let journey = journey(referencing: ["a", "b", "c"])
        let key = SharedJourneyCapabilityPolicy.key(.criteria, journey: journey)
        let material = items("a", "b", "c")

        #expect(capabilities(journey, items: material, setDown: [key]).isEmpty)
        // The records are untouched: resolution still finds all three.
        #expect(
            SharedJourneyCapabilityPolicy.subjects(
                for: journey,
                context: context(items: material, setDown: [key])
            ).count == 3
        )
    }

    // MARK: Shape

    @Test
    func capabilitiesBeyondCriteriaAreDeclaredButNotYetEligible() {
        let journey = journey(referencing: ["a", "b", "c", "d", "e"])
        let earned = Set(JourneyCapability.allCases.map {
            SharedJourneyCapabilityPolicy.key($0, journey: journey)
        })
        let lit = capabilities(
            journey, items: items("a", "b", "c", "d", "e"), earned: earned
        )
        #expect(lit == [.criteria])
    }

    @Test
    func orderingIsStableAcrossReads() {
        let journey = journey(referencing: ["a", "b", "c"])
        let material = items("a", "b", "c")
        #expect(
            capabilities(journey, items: material)
                == capabilities(journey, items: material)
        )
    }

    @Test
    func anUnresolvableReferenceIsDroppedRatherThanRendered() {
        let journey = journey(referencing: ["a", "b", "gone"])
        let subjects = SharedJourneyCapabilityPolicy.subjects(
            for: journey, context: context(items: items("a", "b"))
        )
        #expect(subjects.map(\.reference.id) == ["a", "b"])
    }

    @Test
    func newlyEarnedNamesOnlyWhatHasNotBeenMarked() {
        let journey = journey(referencing: ["a", "b", "c"])
        let key = SharedJourneyCapabilityPolicy.key(.criteria, journey: journey)
        let material = items("a", "b", "c")

        #expect(
            SharedJourneyCapabilityPolicy.newlyEarned(
                for: journey, context: context(items: material)
            ) == [key]
        )
        #expect(
            SharedJourneyCapabilityPolicy.newlyEarned(
                for: journey, context: context(items: material, earned: [key])
            ).isEmpty
        )
    }

    // MARK: Fixtures

    private func capabilities(
        _ journey: SharedJourney,
        items: [LifeItem],
        setDown: Set<String> = [],
        earned: Set<String> = []
    ) -> [JourneyCapability] {
        SharedJourneyCapabilityPolicy.eligible(
            for: journey,
            context: context(items: items, setDown: setDown, earned: earned)
        )
        .map(\.capability)
    }

    private func context(
        items: [LifeItem],
        setDown: Set<String> = [],
        earned: Set<String> = []
    ) -> FieldSharedPresenceContext {
        FieldSharedPresenceContext(
            now: now,
            lifeItems: items,
            clusters: [],
            horizons: [],
            setDown: setDown,
            earned: earned
        )
    }

    private func items(_ ids: String...) -> [LifeItem] {
        ids.map { item($0, visibility: .shared) }
    }

    private func item(_ id: String, visibility: FieldVisibility) -> LifeItem {
        LifeItem(
            id: id,
            title: "Something \(id)",
            category: .notes,
            owner: .shared,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false,
            sourceURL: nil,
            visibility: visibility
        )
    }

    private func journey(referencing ids: [String]) -> SharedJourney {
        SharedJourney(
            id: "11111111-1111-1111-1111-111111111111",
            insightID: "question",
            directionID: "question",
            scope: .longTerm,
            title: "Our first home",
            summary: "Finding somewhere together.",
            rationale: "Grounded in what you both added.",
            evidence: [],
            nextMove: nil,
            horizonID: nil,
            status: .active,
            activatedAt: "2027-01-15T08:00:00.000Z",
            subjectReferences: ids.map {
                FieldReference(kind: FieldReference.Kind.lifeItem, id: $0)
            }
        )
    }
}

// MARK: Taking a surface back up

extension SharedJourneyCapabilityPolicyTests {
    /// Set-down is couple-wide and persisted, and `takeUp` had no caller.
    /// One tap by one person removed a surface from both people for good.
    @Test
    func aSetDownSurfaceCanBeNamedSoItCanBeTakenBackUp() {
        let journey = journey(referencing: ["a", "b", "c"])
        let key = SharedJourneyCapabilityPolicy.key(.criteria, journey: journey)
        let context = context(
            items: items("a", "b", "c"), setDown: [key], earned: [key]
        )

        // It is gone from the room...
        #expect(
            SharedJourneyCapabilityPolicy
                .eligible(for: journey, context: context)
                .isEmpty
        )
        // ...but still nameable, which is what makes it recoverable.
        #expect(
            SharedJourneyCapabilityPolicy.setDown(
                for: journey, context: context
            ) == [.criteria]
        )
    }

    /// Offering to restore something that would immediately disappear again
    /// would make the gesture read as broken.
    @Test
    func aSetDownSurfaceBelowItsThresholdIsNotOfferedBack() {
        let journey = journey(referencing: ["a"])
        let key = SharedJourneyCapabilityPolicy.key(.criteria, journey: journey)
        #expect(
            SharedJourneyCapabilityPolicy.setDown(
                for: journey,
                context: context(items: items("a"), setDown: [key])
            ).isEmpty
        )
    }

    /// A surface that is not on screen still has to be nameable, or taking it
    /// back up is a guess.
    @Test
    func everyCapabilityCanBeNamed() {
        for capability in JourneyCapability.allCases {
            #expect(!SharedJourneyCapabilityPolicy.word(capability).isEmpty)
        }
    }
}
