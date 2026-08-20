import Foundation
import Testing
@testable import WE

/// The invariant: private material may order a person's own view, but it may
/// never bring a surface into existence for one of them and not the other.
///
/// Presence is conspicuous in a way that ordering is not. If a room, a chapter,
/// or a capability can be conjured by a row only one person can see, then the
/// other is living in a space whose shape they cannot account for — and asking
/// about it is asking about the private thing. So the rule is enforced where it
/// cannot be forgotten: `FieldSharedPresenceContext.init` filters, and there is
/// no other way to build one.
@Suite("Adaptation symmetry")
struct FieldAdaptationSymmetryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func theSharedContextDropsPrivateItemsOnConstruction() {
        let context = FieldSharedPresenceContext(
            now: now,
            lifeItems: [
                item("shared-one", visibility: .shared),
                item("mine", visibility: .private),
                item("shared-two", visibility: .shared),
            ],
            clusters: [],
            horizons: []
        )
        #expect(context.lifeItems.map(\.id) == ["shared-one", "shared-two"])
    }

    /// An item written before solo visibility shipped, or by a backend with no
    /// database behind it, has no visibility at all. It must read as shared —
    /// the column default — rather than silently vanishing from every shared
    /// surface the couple already had.
    @Test
    func anItemWithNoRecordedVisibilityCounts() {
        #expect(item("old", visibility: nil).isSharedPresence)
        let context = FieldSharedPresenceContext(
            now: now,
            lifeItems: [item("old", visibility: nil)],
            clusters: [],
            horizons: []
        )
        #expect(context.lifeItems.count == 1)
    }

    /// The property that matters, stated directly: adding private material
    /// changes nothing a `.shared` derivation produces.
    @Test
    func addingPrivateMaterialChangesNoSharedOutput() {
        let shared = [
            item("a", visibility: .shared),
            item("b", visibility: .shared),
            item("c", visibility: .shared),
        ]
        let withPrivate = shared + [
            item("x", visibility: .private),
            item("y", visibility: .private),
        ]

        let journey = journey(referencing: ["a", "b", "c", "x", "y"])
        let without = SharedJourneyCapabilityPolicy.eligible(
            for: journey, context: context(shared)
        )
        let with = SharedJourneyCapabilityPolicy.eligible(
            for: journey, context: context(withPrivate)
        )
        #expect(without == with)
    }

    /// Every derivation declares which kind it is. This is the roster: if a new
    /// namespace appears without a `presence`, it will not compile into this
    /// list, and a new `.shared` one arrives here to be reasoned about rather
    /// than shipping unexamined.
    @Test
    func everyDerivationDeclaresWhoseEyesItsOutputLandsIn() {
        #expect(FieldTodaySelector.presence == .personal)
        #expect(FieldTimely.presence == .personal)
        #expect(FieldDeferral.presence == .personal)
        #expect(FieldMomentScheduler.presence == .personal)
        #expect(FieldClassifier.presence == .personal)
        #expect(FieldLearning.presence == .personal)
        #expect(FieldGrouping.presence == .personal)
        #expect(FieldCategoryDigest.presence == .personal)

        #expect(FieldPromotion.presence == .shared)
        #expect(FieldOccasion.presence == .shared)
        #expect(SharedJourneyCapabilityPolicy.presence == .shared)
    }

    // MARK: Thresholds

    @Test
    func aThresholdKeepsAtOneFewerThanItEarnsAt() {
        let threshold = FieldThreshold(earnsAt: 3)
        #expect(threshold.keepsAt == 2)
        #expect(!threshold.isMet(count: 2, hasEarned: false))
        #expect(threshold.isMet(count: 3, hasEarned: false))
        #expect(threshold.isMet(count: 2, hasEarned: true))
        #expect(!threshold.isMet(count: 0, hasEarned: true))
    }

    /// Nothing survives on zero. A surface with nothing behind it recedes
    /// rather than lingering as an empty frame.
    @Test
    func nothingKeepsItsPlaceOnAnEmptySet() {
        for earnsAt in 2...6 {
            #expect(!FieldThreshold(earnsAt: earnsAt).isMet(
                count: 0, hasEarned: true
            ))
        }
    }

    // MARK: Keys

    /// The keys travel to a table both people can read. A title in one would
    /// be a disclosure channel wearing a bookkeeping costume, and the column's
    /// check constraint refuses the shape anyway.
    @Test
    func anAdaptationKeyCarriesNoContent() {
        let key = FieldAdaptationKey.capability(
            "criteria", journeyID: "11111111-1111-1111-1111-111111111111"
        )
        #expect(key == "capability:criteria:11111111-1111-1111-1111-111111111111")
        #expect(!key.contains(" "))
    }

    // MARK: Fixtures

    private func context(_ items: [LifeItem]) -> FieldSharedPresenceContext {
        FieldSharedPresenceContext(
            now: now, lifeItems: items, clusters: [], horizons: []
        )
    }

    private func item(_ id: String, visibility: FieldVisibility?) -> LifeItem {
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
