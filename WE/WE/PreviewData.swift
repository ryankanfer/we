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
        Member(id: "dylan", name: "Dylan", hue: .sage),
    ]

    static let insights: [Insight] = [
        Insight(
            id: "saturday-plan",
            seedKey: "tonight-feel-preview",
            kind: .logistical,
            domain: .life,
            present: true,
            title: "How should tonight feel?",
            body: "Choose separately. WE will look for a shared direction without exposing either answer.",
            evidence: "A small check-in for this evening.",
            source: "A moment for tonight",
            actionTitle: "Choose what feels right",
            options: [
                "Quiet and close",
                "Easy, with no decisions",
                "Out of the house",
                "Playful and spontaneous",
                "Room to recharge",
            ]
        ),
        Insight(
            id: "weekend-shape",
            seedKey: "weekend-2026-30",
            kind: .logistical,
            domain: .us,
            present: true,
            title: "What should this weekend hold?",
            body: "Choose the shape you are quietly hoping for. WE will find the part that can belong to both of you.",
            evidence: "A little intention before the calendar fills itself.",
            source: "Your shared rhythm",
            actionTitle: "Choose what feels right",
            options: [
                "Mostly rest",
                "Something new",
                "Clear one unfinished thing",
                "See people we love",
                "Keep it unplanned",
            ]
        ),
        Insight(
            id: "lighter-week",
            seedKey: "load-2026-30",
            kind: .logistical,
            domain: .life,
            present: true,
            title: "What would make this week feel lighter?",
            body: "Answer privately. WE will suggest one adjustment without turning care into a score.",
            evidence: "Three active responsibilities are currently being carried.",
            source: "Life · current shared load",
            actionTitle: "Choose what feels right",
            options: [
                "I can take one thing",
                "Let's do one thing together",
                "Decide what can wait",
                "Keep the roles as they are",
                "Ask me directly where I have room",
            ]
        ),
        Insight(
            id: "plan-feeling",
            seedKey: "plan-plan-cabin",
            kind: .logistical,
            domain: .us,
            present: true,
            title: "How should “A quiet weekend away” feel?",
            body: "The plan already exists. This is about the quality you want to protect inside it.",
            evidence: "Coming up on August 15.",
            source: "Ahead · next shared plan",
            actionTitle: "Choose what feels right",
            options: [
                "Calm and spacious",
                "A little special",
                "Simple and practical",
                "Open to surprise",
            ]
        ),
        Insight(
            id: "august-trip",
            seedKey: "august-trip",
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
                "Set it aside for now",
            ]
        ),
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
        ),
        PlanItem(
            id: "plan-river-coffee",
            coupleID: "preview-couple",
            title: "Morning coffee by the river",
            note: "The day we left our phones in the bag.",
            scheduledOn: "2026-07-19",
            status: .completed,
            completedAt: "2026-07-19T15:00:00Z",
            createdBy: "dylan",
            updatedBy: "ryan",
            createdAt: "2026-07-16T10:00:00Z",
            updatedAt: "2026-07-19T15:00:00Z"
        ),
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
        ),
        Responsibility(
            id: "responsibility-guest-room",
            coupleID: "preview-couple",
            title: "Make the guest room feel welcoming",
            note: "Fresh sheets and the little reading lamp.",
            ownerID: nil,
            owner: .together,
            status: .completed,
            completedAt: "2026-07-21T18:30:00Z",
            createdBy: "ryan",
            updatedBy: "dylan",
            createdAt: "2026-07-18T09:00:00Z",
            updatedAt: "2026-07-21T18:30:00Z"
        ),
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
                ),
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
                let isPrivateChoice = $0.kind == .logistical
                let isInvitation = $0.id == "august-trip"
                return InsightRecord(
                    insight: $0,
                    consent: isPrivateChoice
                        ? InsightConsent(
                            insightID: $0.id,
                            visibility: .mutual,
                            ownerID: nil,
                            readiness: .accepted,
                            initiatorID: "dylan",
                            requestedAt: "2026-07-24T18:00:00Z",
                            acceptedAt: "2026-07-24T18:05:00Z",
                            resolutionType: nil,
                            resolutionChoice: nil
                        )
                        : isInvitation ? InsightConsent(
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
                    responses: isPrivateChoice
                        && $0.id == "saturday-plan"
                        ? [
                            InsightResponse(
                                insightID: $0.id,
                                profileID: "dylan",
                                status: .submitted,
                                choice: "Out of the house",
                                note: nil
                            ),
                        ]
                        : [],
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

    static let emptySnapshot: RelationshipSnapshot = {
        let base = makeSnapshot(
            plans: [],
            responsibilities: []
        )
        return RelationshipSnapshot(
            profile: base.profile,
            membership: base.membership,
            couple: base.couple,
            members: base.members,
            insights: [],
            reflections: [],
            plans: [],
            responsibilities: [],
            archives: [],
            syncedAt: base.syncedAt,
            v2: .empty
        )
    }()

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
