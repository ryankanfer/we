import Foundation

nonisolated enum PreviewData {
    static let user = AuthenticatedUser(
        id: "ryan",
        email: "ryan@example.com"
    )

    static let errorUser = AuthenticatedUser(
        id: "preview-error",
        email: "error@example.com"
    )

    static let members: [Member] = [
        Member(id: "ryan", name: "Ryan", hue: .burgundy),
        Member(id: "dylan", name: "Dylan", hue: .sage)
    ]

    static let insights: [Insight] = [
        Insight(
            id: "saturday-plan",
            kind: .logistical,
            domain: .life,
            present: true,
            title: "Saturday is filling up.",
            body: "Three errands are pointing at the same morning.",
            evidence: "The pharmacy, hardware return, and groceries all reference Saturday.",
            source: "Shared continuity",
            actionTitle: "Shape a plan",
            options: [
                "Make one efficient route",
                "Split the errands",
                "Protect part of the day"
            ]
        ),
        Insight(
            id: "august-trip",
            kind: .unresolved,
            domain: .us,
            present: true,
            title: "The August trip is still open.",
            body: "Set aside twice · last discussed 9 days ago",
            evidence: "The trip was saved twice without a shared decision.",
            source: "Shared continuity",
            actionTitle: "Open together",
            options: [
                "Choose a time to discuss it",
                "Look at the saved ideas",
                "Set it aside for now"
            ]
        )
    ]

    static let plans: [PlanItem] = [
        PlanItem(
            id: "plan-cabin",
            coupleID: "preview-couple",
            title: "A quiet weekend away",
            note: "Somewhere close enough to leave after work.",
            scheduledOn: "2026-08-15",
            status: .active,
            completedAt: nil,
            createdBy: "ryan",
            updatedBy: "dylan",
            createdAt: "2026-07-20T12:00:00Z",
            updatedAt: "2026-07-22T19:30:00Z"
        ),
        PlanItem(
            id: "plan-sunday",
            coupleID: "preview-couple",
            title: "An unhurried Sunday",
            note: nil,
            scheduledOn: nil,
            status: .active,
            completedAt: nil,
            createdBy: "dylan",
            updatedBy: "dylan",
            createdAt: "2026-07-23T10:00:00Z",
            updatedAt: "2026-07-23T10:00:00Z"
        )
    ]

    static let responsibilities: [Responsibility] = [
        Responsibility(
            id: "responsibility-groceries",
            coupleID: "preview-couple",
            title: "Keep groceries moving",
            note: "Including the Thursday list.",
            ownerID: nil,
            owner: .together,
            status: .active,
            completedAt: nil,
            createdBy: "ryan",
            updatedBy: "ryan",
            createdAt: "2026-07-18T09:00:00Z",
            updatedAt: "2026-07-21T09:00:00Z"
        ),
        Responsibility(
            id: "responsibility-vet",
            coupleID: "preview-couple",
            title: "Book the vet follow-up",
            note: nil,
            ownerID: "dylan",
            owner: .partner,
            status: .active,
            completedAt: nil,
            createdBy: "dylan",
            updatedBy: "dylan",
            createdAt: "2026-07-19T09:00:00Z",
            updatedAt: "2026-07-19T09:00:00Z"
        )
    ]

    static let archive = RelationshipArchive(
        id: "archive-one",
        ownerID: "ryan",
        endedAt: "2025-11-03T18:00:00Z",
        snapshotVersion: 1,
        snapshot: RelationshipArchiveSnapshot(
            plans: [],
            responsibilities: [],
            resolutions: [
                ArchivedResolution(
                    insightID: "archive-resolution",
                    title: "The move was held together.",
                    resolutionType: .settled,
                    resolutionChoice: "Wait until spring",
                    resolvedAt: "2025-10-10T18:00:00Z"
                )
            ]
        )
    )

    static let snapshot = makeSnapshot()

    static func makeSnapshot(
        members: [Member] = members,
        plans: [PlanItem] = plans,
        responsibilities: [Responsibility] = responsibilities,
        archives: [RelationshipArchive] = []
    ) -> RelationshipSnapshot {
        RelationshipSnapshot(
            profile: Profile(id: "ryan", name: "Ryan"),
            membership: Membership(
                coupleID: "preview-couple",
                profileID: "ryan",
                hue: .burgundy,
                hueChosenAt: "2026-07-20T12:00:00Z"
            ),
            couple: Couple(id: "preview-couple", joinCode: "WEDEMO"),
            members: members,
            insights: insights.map {
                let isInvitation = $0.id == "august-trip"
                return InsightRecord(
                    insight: $0,
                    consent: isInvitation
                        ? InsightConsent(
                            insightID: $0.id,
                            visibility: .shared,
                            ownerID: nil,
                            readiness: .requested,
                            initiatorID: "dylan",
                            requestedAt: "2026-07-24T20:00:00Z",
                            acceptedAt: nil,
                            resolutionType: nil,
                            resolutionChoice: nil
                        )
                        : nil,
                    responses: [],
                    dismissedBy: [],
                    declinedBy: []
                )
            },
            reflections: [],
            plans: plans,
            responsibilities: responsibilities,
            archives: archives,
            syncedAt: Date()
        )
    }

    static let emptySnapshot = makeSnapshot(
        plans: [],
        responsibilities: []
    )

    static let waitingSnapshot = makeSnapshot(
        members: [members[0]],
        plans: [],
        responsibilities: []
    )

    static let choosingHueSnapshot = RelationshipSnapshot(
        profile: Profile(id: "ryan", name: "Ryan"),
        membership: Membership(
            coupleID: "preview-couple",
            profileID: "ryan",
            hue: .burgundy,
            hueChosenAt: nil
        ),
        couple: Couple(id: "preview-couple", joinCode: "WEDEMO"),
        members: members,
        insights: [],
        reflections: [],
        plans: [],
        responsibilities: [],
        archives: [],
        syncedAt: Date()
    )

    static let archivedSnapshot = RelationshipSnapshot(
        profile: Profile(id: "ryan", name: "Ryan"),
        membership: nil,
        couple: nil,
        members: [],
        insights: [],
        reflections: [],
        plans: [],
        responsibilities: [],
        archives: [archive],
        syncedAt: Date()
    )
}
