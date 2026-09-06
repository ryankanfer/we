import Foundation
import Testing
@testable import WE

@Suite("Shared journey policy")
struct SharedJourneyPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func ranksImmediateBeforeNearAndLongTerm() {
        let snapshot = snapshot(insights: [
            record("long", scope: .longTerm),
            record("near", scope: .nearTerm),
            record("now", scope: .immediate),
        ])

        guard case .question(let selected) = SharedJourneyPolicy.presentation(
            snapshot: snapshot,
            viewerID: "ryan",
            now: now
        ) else {
            Issue.record("Expected one question")
            return
        }
        #expect(selected.id == "now")
    }

    @Test
    func aSubmittedAnswerBecomesHeldWithoutPartnerStatus() {
        let mine = InsightResponse(
            insightID: "question",
            profileID: "ryan",
            status: .submitted,
            choice: "Keep it open",
            note: "private"
        )
        let partner = InsightResponse(
            insightID: "question",
            profileID: "dylan",
            status: .submitted,
            choice: "Choose a day",
            note: nil
        )
        let onlyMine = snapshot(insights: [
            record("question", responses: [mine]),
        ])
        let bothExistOnServer = snapshot(insights: [
            record("question", responses: [mine, partner]),
        ])

        #expect(phase(onlyMine) == "held")
        #expect(phase(bothExistOnServer) == "held")
    }

    @Test
    func onePrivateAcceptanceCannotActivate() {
        var value = snapshot(insights: [
            record("question", direction: proposal("question")),
        ])
        value.directionConfirmations = [
            DirectionConfirmation(
                insightID: "question",
                profileID: "ryan",
                decision: .choose,
                decidedAt: "2027-01-15T08:00:00.000Z"
            ),
        ]

        #expect(phase(value) == "proposal")
        #expect(value.journeys.isEmpty)
    }

    @Test
    func aPrivatePassAndExpiryBothRemovePressure() {
        var passed = snapshot(insights: [record("question")])
        passed.journeyPasses = [
            JourneyPass(
                insightID: "question",
                profileID: "ryan",
                passedAt: "2027-01-15T08:00:00.000Z"
            ),
        ]
        #expect(phase(passed) == "empty")

        let expired = snapshot(insights: [
            record("old", expiresAt: "2020-01-01T00:00:00.000Z"),
        ])
        #expect(phase(expired) == "empty")
    }

    @Test
    func anOlderPrivatePassAllowsAReturnWithoutLeakingAnything() {
        var value = snapshot(insights: [record("question")])
        value.journeyPasses = [
            JourneyPass(
                insightID: "question",
                profileID: "ryan",
                passedAt: "2020-01-01T00:00:00Z"
            ),
        ]

        #expect(phase(value) == "question")
    }

    @Test
    func activatedJourneyShowsOnlyItsNextMoveAndEvidence() {
        var value = snapshot(insights: [])
        value.journeys = [
            SharedJourney(
                id: "journey",
                insightID: "question",
                directionID: "question",
                scope: .nearTerm,
                title: "A quieter weekend",
                summary: "Leave part of it open.",
                rationale: "Grounded in the plan.",
                evidence: ["One", "Two", "Three"],
                nextMove: "Choose the first hour",
                horizonID: nil,
                status: .active,
                activatedAt: "2027-01-15T08:00:00.000Z"
            ),
        ]
        #expect(phase(value) == "active")
    }

    /// Us no longer holds one season at a time. Two people can be finding a
    /// home and planning a trip at once, and the more recent does not cancel
    /// the older one.
    @Test
    func journeysCoexistAndAreOrderedDeterministically() {
        var value = snapshot(insights: [])
        value.journeys = [
            journey("later", scope: .longTerm, at: "2027-03-01T08:00:00.000Z"),
            journey("soonest", scope: .immediate, at: "2027-01-01T08:00:00.000Z"),
            journey("middle", scope: .nearTerm, at: "2027-02-01T08:00:00.000Z"),
        ]

        guard case .active(let living) = SharedJourneyPolicy.presentation(
            snapshot: value, viewerID: "ryan", now: now
        ) else {
            Issue.record("Expected living journeys")
            return
        }
        #expect(living.map(\.id) == ["soonest", "middle", "later"])
    }

    @Test
    func aCompletedJourneyIsNotLiving() {
        var value = snapshot(insights: [])
        var done = journey("done", scope: .nearTerm, at: "2027-01-01T08:00:00.000Z")
        done.status = .completed
        value.journeys = [done]
        #expect(phase(value) == "empty")
    }

    private func journey(
        _ id: String,
        scope: JourneyScope,
        at activatedAt: String
    ) -> SharedJourney {
        SharedJourney(
            id: id,
            insightID: id,
            directionID: id,
            scope: scope,
            title: "A journey",
            summary: "Somewhere together.",
            rationale: "Grounded in the plan.",
            evidence: [],
            nextMove: nil,
            horizonID: nil,
            status: .active,
            activatedAt: activatedAt
        )
    }

    private func phase(_ snapshot: RelationshipSnapshot) -> String {
        switch SharedJourneyPolicy.presentation(
            snapshot: snapshot,
            viewerID: "ryan",
            now: now
        ) {
        case .empty: "empty"
        case .question: "question"
        case .held: "held"
        case .proposal: "proposal"
        case .active: "active"
        }
    }

    private func record(
        _ id: String,
        scope: JourneyScope = .nearTerm,
        responses: [InsightResponse] = [],
        direction: SharedDirection? = nil,
        expiresAt: String = "2099-01-01T00:00:00.000Z"
    ) -> InsightRecord {
        InsightRecord(
            insight: Insight(
                id: id,
                seedKey: "journey:\(id)",
                kind: .unresolved,
                domain: .us,
                present: true,
                title: "What shape should this take?",
                body: "Choose privately.",
                evidence: "A real shared plan is still open.",
                source: "Life",
                actionTitle: "Choose",
                options: ["Keep it open", "Choose a day"],
                journeyScope: scope,
                triggerProvenance: .unresolvedChoice,
                subjectReferences: [],
                expiresAt: expiresAt,
                contextSnapshot: JourneyContextSnapshot(
                    evidence: ["A real shared plan is still open."],
                    frozenAt: "2027-01-15T08:00:00.000Z"
                )
            ),
            consent: InsightConsent(
                insightID: id,
                visibility: .mutual,
                ownerID: nil,
                readiness: .accepted,
                initiatorID: nil,
                requestedAt: nil,
                acceptedAt: "2027-01-15T08:00:00.000Z",
                resolutionType: nil,
                resolutionChoice: nil
            ),
            responses: responses,
            sharedDirection: direction,
            dismissedBy: [],
            declinedBy: []
        )
    }

    private func proposal(_ id: String) -> SharedDirection {
        SharedDirection(
            insightID: id,
            key: "synthesized-v1",
            eyebrow: "A DIRECTION TO CHOOSE",
            title: "Leave part of it open",
            message: "The shared evidence supports a smaller beginning.",
            symbol: "circle.circle",
            createdAt: "2027-01-15T08:00:00.000Z",
            summary: "Leave part of it open.",
            rationale: "The shared evidence supports a smaller beginning.",
            proposedActions: [],
            synthesisVersion: "test-v1",
            expiresAt: "2099-01-01T00:00:00.000Z",
            status: .proposed
        )
    }

    private func snapshot(insights: [InsightRecord]) -> RelationshipSnapshot {
        RelationshipSnapshot(
            profile: Profile(id: "ryan", name: "Ryan"),
            membership: Membership(
                coupleID: "couple",
                profileID: "ryan",
                hue: .burgundy,
                hueChosenAt: "2027-01-01T00:00:00Z"
            ),
            couple: Couple(id: "couple", joinCode: "WE"),
            members: PreviewData.members,
            insights: insights,
            reflections: [],
            plans: [],
            responsibilities: [],
            archives: [],
            syncedAt: now
        )
    }
}
