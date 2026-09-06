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
            evidence: "Dinner and the rest of the evening are still unshaped.",
            source: "Life · tonight's open plan",
            actionTitle: "Choose what feels right",
            options: [
                "Quiet and close",
                "Easy, with no decisions",
                "Out of the house",
                "Playful and spontaneous",
            ],
            journeyScope: .immediate,
            triggerProvenance: .upcomingPlan,
            subjectReferences: [
                JourneySubjectReference(kind: "plan", id: "plan-sunday"),
            ],
            expiresAt: ISO8601DateFormatter.we.string(
                from: Date().addingTimeInterval(JourneyScope.immediate.lifetime)
            ),
            contextSnapshot: JourneyContextSnapshot(
                evidence: [
                    "Dinner and the rest of the evening are still unshaped.",
                ],
                frozenAt: ISO8601DateFormatter.we.string(from: Date())
            ),
            sort: 0
        ),
        Insight(
            id: "weekend-shape",
            seedKey: "weekend-2026-30",
            kind: .logistical,
            domain: .us,
            present: false,
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
            present: false,
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
            present: false,
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

    static let journeyHeldSnapshot = journeyFixture(
        records: [
            journeyQuestionRecord(
                responses: [
                    InsightResponse(
                        insightID: "saturday-plan",
                        profileID: "ryan",
                        status: .submitted,
                        choice: "Quiet and close",
                        note: "Private"
                    ),
                ]
            ),
        ]
    )

    static let journeyProposalSnapshot = journeyFixture(
        records: [
            journeyQuestionRecord(
                direction: SharedDirection(
                    insightID: "saturday-plan",
                    key: "preview-synthesized-v1",
                    eyebrow: "A DIRECTION TO CHOOSE",
                    title: "Leave the evening spacious",
                    message: "The open plan supports a gentle beginning.",
                    symbol: "circle.circle",
                    createdAt: ISO8601DateFormatter.we.string(from: Date()),
                    summary: "Leave the evening spacious.",
                    rationale: "The open plan supports a gentle beginning.",
                    proposedActions: [
                        ProposedJourneyAction(
                            id: "make-space",
                            kind: .lifeItem,
                            title: "Make space for the evening",
                            category: "plans",
                            detail: nil,
                            dueOn: nil
                        ),
                    ],
                    synthesisVersion: "preview-v1",
                    expiresAt: ISO8601DateFormatter.we.string(
                        from: Date().addingTimeInterval(86_400)
                    ),
                    status: .proposed
                )
            ),
        ]
    )

    static let journeyActiveSnapshot = journeyFixture(
        records: [],
        journeys: [
            SharedJourney(
                id: "preview-journey",
                insightID: "saturday-plan",
                directionID: "saturday-plan",
                scope: .immediate,
                title: "Leave the evening spacious",
                summary: "Begin gently and keep the rest open.",
                rationale: "The evening was still unshaped.",
                evidence: [
                    "Dinner and the rest of the evening were still unshaped.",
                ],
                nextMove: "Make space for the evening",
                horizonID: nil,
                status: .active,
                activatedAt: ISO8601DateFormatter.we.string(from: Date())
            ),
        ]
    )

    private static func journeyQuestionRecord(
        responses: [InsightResponse] = [],
        direction: SharedDirection? = nil
    ) -> InsightRecord {
        let question = insights.first { $0.id == "saturday-plan" }!
        return InsightRecord(
            insight: question,
            consent: InsightConsent(
                insightID: question.id,
                visibility: .mutual,
                ownerID: nil,
                readiness: .accepted,
                initiatorID: nil,
                requestedAt: nil,
                acceptedAt: ISO8601DateFormatter.we.string(from: Date()),
                resolutionType: nil,
                resolutionChoice: nil
            ),
            responses: responses,
            sharedDirection: direction,
            dismissedBy: [],
            declinedBy: []
        )
    }

    private static func journeyFixture(
        records: [InsightRecord],
        journeys: [SharedJourney] = []
    ) -> RelationshipSnapshot {
        let base = makeSnapshot()
        return RelationshipSnapshot(
            profile: base.profile,
            membership: base.membership,
            couple: base.couple,
            members: base.members,
            insights: records,
            reflections: [],
            plans: base.plans,
            responsibilities: base.responsibilities,
            archives: [],
            syncedAt: base.syncedAt,
            v2: .empty,
            journeys: journeys
        )
    }

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

    /// One person, with an invitation actually out.
    ///
    /// The scenario is named for waiting, and until now its couple carried no
    /// `invitationExpiresAt` at all — so `hasLiveInvitation()` was false and
    /// every screen built on it rendered the withdrawn branch. A test
    /// asserting the send button was reachable could not have passed, because
    /// the send button only exists while there is something live to send.
    static let waitingSnapshot: RelationshipSnapshot = {
        let base = makeSnapshot(
            members: [members[0]],
            plans: [],
            responsibilities: []
        )
        return RelationshipSnapshot(
            profile: base.profile,
            membership: base.membership,
            couple: Couple(
                id: "preview-couple",
                joinCode: "WEDEMO",
                // Relative to now rather than a stamped date, so the fixture
                // does not quietly expire and take the tests with it.
                invitationExpiresAt: Date().addingTimeInterval(7 * 86_400)
            ),
            members: base.members,
            insights: base.insights,
            reflections: base.reflections,
            plans: base.plans,
            responsibilities: base.responsibilities,
            archives: base.archives,
            syncedAt: base.syncedAt
        )
    }()

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
