//
//  FieldSampleData.swift
//  WE
//
//  One fictional couple, exactly as the handoff specifies them.
//
//  "All copy in the prototype is built around this couple. Reuse it for
//  seeding and demos; the specificity is what makes the intelligence legible."
//
//  Ryan, 33 — content creator at a real-estate brokerage. Warm colour.
//  Dylan, 30 — brand marketing at a bank. Cool colour. Turns 31 on Aug 17.
//  They do not live together. Both leases end June 2026. A pet, Miso.
//
//  "Today" is Wed 13 Aug — which fixes the year at 2025, because the closed
//  season in 6e runs March 2025 to June 2026 and reads sixteen months.
//

import Foundation

enum FieldSampleData {
    static let today: Date = date(2025, 8, 13, hour: 9, minute: 40)

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        Calendar.gregorianUS.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        ) ?? .distantPast
    }

    // MARK: Partners

    static let identity = FieldIdentity(
        personA: .clay,
        personB: .slate,
        nameA: "Ryan",
        nameB: "Dylan"
    )

    static let partners: [FieldPartner] = [
        FieldPartner(
            id: "ryan",
            name: "Ryan",
            swatch: .clay,
            owner: .a,
            awayWindows: [
                FieldAwayWindow(
                    id: "hamptons",
                    start: date(2025, 8, 28),
                    end: date(2025, 8, 31, hour: 23, minute: 59),
                    reason: "Shooting",
                    place: "the Hamptons"
                )
            ],
            standingPreferences: ["Anything but a musical"]
        ),
        FieldPartner(
            id: "dylan",
            name: "Dylan",
            swatch: .slate,
            owner: .b,
            awayWindows: [],
            standingPreferences: []
        ),
    ]

    // MARK: Clusters
    //
    // Grouped by occasion, not by category and not by date. Every cluster
    // states why it exists.

    static let clusters: [FieldCluster] = [
        FieldCluster(
            id: "dad",
            title: "Before your dad lands",
            rationale: "These four only matter because of Friday. Clear them "
                + "together and Friday takes care of itself.",
            tint: .a,
            timeframe: "FRI",
            anchorDate: date(2025, 8, 15, hour: 16, minute: 10)
        ),
        FieldCluster(
            id: "wedding",
            title: "Wedding week",
            rationale: "Dylan's birthday and Marissa's wedding are five days "
                + "apart. Same clothes, same drive, one gift budget — one "
                + "cluster.",
            tint: .b,
            timeframe: "17–22",
            anchorDate: date(2025, 8, 22)
        ),
        FieldCluster(
            id: "upkeep",
            title: "Quiet upkeep",
            rationale: "Nothing here is urgent. I'll surface each one when its "
                + "moment comes.",
            tint: .shared,
            timeframe: "NO DATE",
            anchorDate: nil
        ),
    ]

    // MARK: Life

    static let lifeItems: [LifeItem] = [
        // Before your dad lands
        LifeItem(
            id: "dinner",
            title: "Decide dinner",
            category: .food,
            owner: .shared,
            dueOn: date(2025, 8, 15),
            closesAt: nil,
            clusterID: "dad",
            source: .inferred,
            detail: "out, or at Dylan's — both of you",
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "groceries",
            title: "Send the grocery list",
            category: .food,
            owner: .b,
            dueOn: date(2025, 8, 13),
            closesAt: date(2025, 8, 13, hour: 21),
            clusterID: "dad",
            source: .captured,
            detail: "window closes 9pm tonight",
            isTimeCritical: true,
            isDone: false
        ),
        LifeItem(
            id: "guestroom",
            title: "Clear the guest room",
            category: .home,
            owner: .a,
            dueOn: date(2025, 8, 15),
            closesAt: nil,
            clusterID: "dad",
            source: .inferred,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "filter",
            title: "Air filter",
            category: .home,
            owner: .a,
            dueOn: date(2025, 6, 15),
            closesAt: nil,
            clusterID: "dad",
            source: .captured,
            detail: "two months over — he notices",
            isTimeCritical: false,
            isDone: false
        ),

        // Wedding week
        LifeItem(
            id: "birthday",
            title: "Dylan's birthday — Sunday",
            category: .care,
            owner: .a,
            dueOn: date(2025, 8, 17),
            closesAt: nil,
            clusterID: "wedding",
            source: .captured,
            detail: "4 days",
            isTimeCritical: true,
            isDone: false
        ),
        LifeItem(
            id: "gift",
            title: "Gift for Marissa & Tom",
            category: .money,
            owner: .shared,
            dueOn: date(2025, 8, 22),
            closesAt: nil,
            clusterID: "wedding",
            source: .inferred,
            detail: "$200?",
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "rhinebeck",
            title: "Rhinebeck — drive or train",
            category: .care,
            owner: .shared,
            dueOn: date(2025, 8, 22),
            closesAt: nil,
            clusterID: "wedding",
            source: .inferred,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "suit",
            title: "Suit to the cleaner",
            category: .care,
            owner: .b,
            dueOn: date(2025, 8, 20),
            closesAt: nil,
            clusterID: "wedding",
            source: .captured,
            detail: "by 20",
            isTimeCritical: false,
            isDone: false
        ),

        // Quiet upkeep
        LifeItem(
            id: "insurance",
            title: "Renter's insurance",
            category: .home,
            owner: .shared,
            dueOn: date(2025, 9, 1),
            closesAt: nil,
            clusterID: "upkeep",
            source: .captured,
            detail: "Sep 1",
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "miso",
            title: "Miso's teeth",
            category: .care,
            owner: .b,
            dueOn: date(2025, 9, 20),
            closesAt: nil,
            clusterID: "upkeep",
            source: .captured,
            detail: "September",
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "passport",
            title: "Ryan's passport",
            // A grown category, in the seed on purpose: Life's set is open,
            // and the sample couple should look like a couple who has used
            // the app rather than one who never left the given words.
            category: LifeCategory(rawValue: "admin"),
            owner: .a,
            dueOn: date(2025, 11, 1),
            closesAt: nil,
            clusterID: "upkeep",
            source: .inferred,
            detail: "before Nov",
            isTimeCritical: false,
            isDone: false
        ),

        // Settled — these produce the resolved Today state's detail line.
        LifeItem(
            id: "friday-booked",
            title: "Friday's booked",
            category: .food,
            owner: .shared,
            dueOn: date(2025, 8, 12),
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: true
        ),
        LifeItem(
            id: "cake",
            title: "Dylan's cake is ordered",
            category: .care,
            owner: .a,
            dueOn: date(2025, 8, 12),
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: true
        ),
    ]

    // MARK: The synthesis block

    static let weekShape = "Front-loaded. Three things land before Sunday, "
        + "then it opens right up."

    static let weekReasoning = "Because Friday, Sunday and the 22nd all sit in "
        + "one nine-day stretch. After that it stays clear until September."

    static let weekMetrics: [(figure: String, label: String)] = [
        ("3", "BEFORE SUN"),
        ("$540", "COMMITTED"),
        ("Friday", "THE ONE TO SETTLE"),
    ]

    // MARK: What they have mentioned
    //
    // These used to be `OursItem`s in a second list behind a second name. They
    // are Life items with no date, which is all "appetite" ever meant: nothing
    // undated can reach Today's surfacing threshold, so a film sits in
    // Watchlist for a year without once asking anything of anybody.

    static let mentioned: [LifeItem] = [
        LifeItem(
            id: "ff",
            title: "Fast and Furious",
            category: .watchlist,
            owner: .b,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "bear",
            title: "The Bear, s4",
            category: .watchlist,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "pastlives",
            title: "Past Lives",
            category: .watchlist,
            owner: .shared,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: "Both added it, a week apart",
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "tokyostory",
            title: "Tokyo Story",
            category: .watchlist,
            owner: .b,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "steak",
            title: "Steak",
            category: .food,
            owner: .shared,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: "Both wrote it this month",
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "japan-trip",
            title: "Japan in the fall",
            category: .trips,
            owner: .shared,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "upstate",
            title: "Upstate, a weekend",
            category: .trips,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
        LifeItem(
            id: "airfilters",
            title: "Air filters",
            category: .buys,
            owner: .a,
            dueOn: nil,
            closesAt: nil,
            clusterID: nil,
            source: .captured,
            detail: nil,
            isTimeCritical: false,
            isDone: false
        ),
    ]


    static let alsoPossible = [
        "The Bear at yours, and cook.",
        "Nothing at all. That's allowed.",
    ]

    // MARK: Us

    static let horizons: [FieldHorizon] = [
        FieldHorizon(
            id: "japan",
            title: "Japan,",
            window: "spring 2027",
            owner: .shared,
            isPrimary: true,
            thesis: "Everything in Life is quietly paying for this.",
            targetDate: date(2027, 4, 1),
            linkedLifeItemIDs: ["passport", "tokyostory", "japan-trip"],
            openQuestion: FieldQuestion(
                id: "japan-season",
                prompt: "Spring or fall?",
                stakes: "It's the only thing standing between a wish and a date.",
                reasoning: "Asking today because spring fares open in "
                    + "November, Ryan's passport expires that March, and "
                    + "you've both said “sometime in 2027” four times.",
                choices: [
                    FieldChoice(id: "spring", title: "Spring", tint: .a),
                    FieldChoice(id: "fall", title: "Fall", tint: .b),
                ]
            )
        ),
        FieldHorizon(
            id: "address",
            title: "One address",
            window: nil,
            owner: .shared,
            isPrimary: false,
            thesis: nil,
            targetDate: date(2026, 6, 1),
            linkedLifeItemIDs: [],
            openQuestion: nil
        ),
        FieldHorizon(
            id: "film",
            title: "Ryan, shooting film again",
            window: nil,
            owner: .a,
            isPrimary: false,
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: [],
            openQuestion: nil
        ),
        FieldHorizon(
            id: "certified",
            title: "Dylan, certified",
            window: nil,
            owner: .b,
            isPrimary: false,
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: [],
            openQuestion: nil
        ),
        FieldHorizon(
            id: "upstate",
            title: "A place upstate",
            window: nil,
            owner: .shared,
            isPrimary: false,
            thesis: nil,
            targetDate: nil,
            linkedLifeItemIDs: [],
            openQuestion: nil
        ),
    ]

    /// "WHAT THIS WEEK DID FOR IT" — plain sentences about real events. Never
    /// a progress bar, percentage, or chart.
    static let evidence: [FieldEvidence] = [
        FieldEvidence(
            id: "payment",
            statement: "$340 went in, without either of you moving it",
            owner: .shared,
            horizonID: "japan",
            occurredAt: date(2025, 8, 11)
        ),
        FieldEvidence(
            id: "passport-started",
            statement: "Ryan's passport renewal started",
            owner: .a,
            horizonID: "japan",
            occurredAt: date(2025, 8, 12)
        ),
        FieldEvidence(
            id: "thursday",
            statement: "You cooked in on Thursday for the 41st week",
            owner: .shared,
            horizonID: "japan",
            occurredAt: date(2025, 8, 7)
        ),
    ]

    static let evidenceReasoning = "Three ordinary things. That's what a "
        + "horizon is made of."

    static let rhythms: [FieldRhythm] = [
        FieldRhythm(
            id: "cookin",
            title: "The Thursday cook-in",
            cadence: "Thursdays",
            health: .running,
            horizonID: "japan",
            occurrences: 41,
            lastOccurred: date(2025, 8, 7)
        ),
        FieldRhythm(
            id: "japanfund",
            title: "The Japan payment",
            cadence: "Monthly",
            health: .running,
            horizonID: "japan",
            occurrences: 8,
            lastOccurred: date(2025, 8, 11)
        ),
        FieldRhythm(
            id: "sundaycall",
            title: "The Sunday call",
            cadence: "Sundays",
            health: .slipping,
            horizonID: nil,
            occurrences: 0,
            lastOccurred: date(2025, 7, 20)
        ),
    ]

    static let anchors: [FieldAnchor] = [
        FieldAnchor(
            id: "money",
            text: "No surprises about money.",
            agreedAt: date(2025, 4, 2)
        ),
        FieldAnchor(
            id: "small",
            text: "We say the small thing early.",
            agreedAt: date(2025, 5, 18)
        ),
    ]

    static let threads: [FieldThread] = [
        FieldThread(
            id: "wedding-length",
            question: "A weekend wedding, or one night?",
            openedAt: date(2025, 7, 28),
            resolvedAt: nil,
            resolution: nil
        )
    ]

    static let season = FieldSeason(
        id: "two-apartments",
        name: "Two apartments, one calendar",
        startedAt: date(2025, 3, 1),
        endedAt: nil,
        narrative: nil,
        decisions: [],
        oneThingThatDidntHappen: nil
    )

    static let seasonSubtitle = "Two apartments, one calendar"

    // MARK: Today

    static let watching: [FieldWatchItem] = [
        FieldWatchItem(
            id: "gift-watch",
            text: "Marissa's wedding is in 9 days with no gift chosen. I'll "
                + "ask Saturday, when you're both free.",
            owner: .shared,
            isDeferred: false
        ),
        FieldWatchItem(
            id: "japan-watch",
            text: "Japan flights open in November. I need a season by October.",
            owner: .b,
            isDeferred: false
        ),
        FieldWatchItem(
            id: "sunday-watch",
            text: "The Sunday call has slipped three weeks. Not raising it "
                + "while your dad's here.",
            owner: .a,
            isDeferred: true
        ),
    ]

    static let resolvedHeadline = "Today is clear."
    static let resolvedDetail = "Friday's booked. The groceries went out. "
        + "Dylan's cake is ordered."

    // MARK: Capture

    static let capturedThisWeek: [FieldCapture] = [
        FieldCapture(id: "c1", text: "steak", owner: .a, capturedAt: date(2025, 8, 12)),
        FieldCapture(id: "c2", text: "fast and furious", owner: .b, capturedAt: date(2025, 8, 13)),
        FieldCapture(id: "c3", text: "gift for marissa", owner: .shared, capturedAt: date(2025, 8, 11)),
        FieldCapture(id: "c4", text: "air filter", owner: .a, capturedAt: date(2025, 8, 11)),
        FieldCapture(id: "c5", text: "japan in the fall maybe", owner: .b, capturedAt: date(2025, 8, 10)),
        FieldCapture(id: "c6", text: "miso's teeth", owner: .b, capturedAt: date(2025, 8, 10)),
        FieldCapture(id: "c7", text: "suit to the cleaner", owner: .b, capturedAt: date(2025, 8, 9)),
        FieldCapture(id: "c8", text: "call mom sunday", owner: .a, capturedAt: date(2025, 8, 9)),
        FieldCapture(id: "c9", text: "hometown", owner: .a, capturedAt: date(2025, 8, 8)),
        FieldCapture(id: "c10", text: "the bear s4", owner: .a, capturedAt: date(2025, 8, 8)),
        FieldCapture(id: "c11", text: "rhinebeck train", owner: .shared, capturedAt: date(2025, 8, 8)),
        FieldCapture(id: "c12", text: "renter's insurance", owner: .shared, capturedAt: date(2025, 8, 7)),
        FieldCapture(id: "c13", text: "guest room", owner: .a, capturedAt: date(2025, 8, 7)),
        FieldCapture(id: "c14", text: "dylan's cake", owner: .a, capturedAt: date(2025, 8, 7)),
    ]

    /// The four sample phrases the prototype cycles, kept as the classifier's
    /// few-shot set and as the demo affordance under the field.
    static let canonicalInputs = [
        "reminder to call mom sunday",
        "steak",
        "fast and furious",
        "japan in the fall maybe",
    ]

    // MARK: Deferral (6d)

    static let heldTopics: [FieldHeldTopic] = [
        FieldHeldTopic(
            id: "sunday-call",
            title: "The Sunday call",
            timing: "3 WEEKS",
            reason: "It's slipped, and it matters. But your dad is here until "
                + "Sunday and this is about your mother. I'll raise it Monday.",
            surfaceOn: date(2025, 8, 18),
            wasOverridden: false,
            wasDismissed: false
        ),
        FieldHeldTopic(
            id: "gift-number",
            title: "The wedding gift number",
            timing: "SATURDAY",
            reason: "Money conversations go better when you're in the same "
                + "room. You will be Saturday morning.",
            surfaceOn: date(2025, 8, 16),
            wasOverridden: false,
            wasDismissed: false
        ),
        FieldHeldTopic(
            id: "one-address",
            title: "One address",
            timing: "SPRING",
            reason: "Your leases end in June 2026. Nothing useful happens by "
                + "discussing it in August — I'll bring it back in March.",
            surfaceOn: date(2026, 3, 1),
            wasOverridden: false,
            wasDismissed: false
        ),
    ]

    static let standingRules: [FieldStandingRule] = [
        FieldStandingRule(
            id: "coffee",
            text: "Never money before coffee.",
            setAt: date(2025, 5, 26)
        )
    ]

    // MARK: Corrections (6a)

    static let behaviourChanges: [FieldBehaviourChange] = [
        FieldBehaviourChange(
            id: "mornings",
            observation: "You moved 3 errands out of the morning",
            change: "I stopped putting errands in front of you before 6pm.",
            outcome: "Since July 2. Nothing has been moved since.",
            accent: .a
        ),
        FieldBehaviourChange(
            id: "invention",
            observation: "You deleted “plan something fun” twice",
            change: "I don't invent plans anymore. I only suggest from what "
                + "you've actually said.",
            outcome: "That's why Friday came out of what you'd both said, not out of thin air.",
            accent: .b
        ),
        FieldBehaviourChange(
            id: "hour",
            observation: "You answer me in the morning, not at night",
            change: "I ask once, at 8:12.",
            outcome: "Your reply rate went from 40% to 91%.",
            accent: .shared
        ),
        FieldBehaviourChange(
            id: "appetite",
            observation: "You told me “not a task” four times",
            change: "Food you mention with no day on it stays undated now.",
            outcome: "“Steak” is an appetite. “Groceries” is a task. I can "
                + "tell them apart now.",
            accent: .a
        ),
    ]

    static let correctionCount = 9
    static let learningSince = date(2025, 3, 13)

    // MARK: The daily moment (6c)

    static let dailyMoment = FieldDailyMoment(
        sendMinute: 8 * 60 + 12,
        queuedCount: 8,
        hourRationale: "It's when you both actually reply. I tried evenings "
            + "for three weeks and you didn't.",
        replyRateBefore: 0.40,
        replyRateAfter: 0.91,
        lastSentOn: nil
    )

    // MARK: Presence (6b)

    static let presenceBanner = (
        statement: "Ryan's in the Hamptons until Sunday.",
        reasoning: "Shooting, so I'm not sending him anything that can wait "
            + "four days."
    )

    static let presenceMoment = FieldMoment(
        id: "miso-appointment",
        source: "FROM LIFE · CARE",
        headline: "Miso's teeth need booking.",
        reasoning: "You've handled Miso's appointments since March, and this "
            + "one has a Friday deadline. I'd normally ask you both.",
        accent: .b,
        shape: .statement,
        actions: [
            FieldMomentAction(
                id: "book",
                title: "Book it",
                weight: .filled,
                tint: nil,
                role: .act(.book)
            ),
            FieldMomentAction(
                id: "ask-ryan",
                title: "Ask Ryan anyway",
                weight: .outlined,
                tint: nil,
                role: .overrideAbsence(.a)
            ),
        ],
        addressedTo: .b,
        remainder: nil
    )

    static let holdingUntil: [(title: String, reason: String)] = [
        (
            "September's Japan payment",
            "It's a both-of-you thing. It can wait four days."
        ),
        (
            "The Rhinebeck drive",
            "You'll decide it faster in the same room."
        ),
        (
            "The gift number",
            "Money conversations go better when neither of you is working."
        ),
    ]

    static let presenceClosing = "Sunday evening, I'll bring him the three "
        + "things that waited — in one go, not four notifications."

    // MARK: A season, closed (6e)

    static let closedSeason = FieldSeason(
        id: "closed",
        name: "Two apartments, one calendar",
        startedAt: date(2025, 3, 1),
        endedAt: date(2026, 6, 30),
        narrative: "You spent sixteen months learning to run one life out of "
            + "two addresses. You cooked in on 63 Thursdays. You saved $6,120 "
            + "toward a country neither of you had seen. You met each other's "
            + "parents, twice over, and stopped asking whose turn it was to "
            + "host.",
        decisions: [
            FieldSeasonDecision(
                id: "d1",
                text: "One gift budget, agreed once, for the whole wedding season.",
                decidedOn: date(2025, 8, 16)
            ),
            FieldSeasonDecision(
                id: "d2",
                text: "Japan in the spring, not the fall.",
                decidedOn: date(2025, 10, 4)
            ),
            FieldSeasonDecision(
                id: "d3",
                text: "Thursdays are yours. Nothing gets booked over them.",
                decidedOn: date(2025, 11, 20)
            ),
        ],
        oneThingThatDidntHappen: "Ryan didn't shoot film again. It's still on "
            + "the horizon, and it's still his."
    )

    static let nextHorizonPrompt = "Name it when you're ready. I'll start "
        + "keeping notes either way."

    // MARK: Onboarding (6f)

    static let onboardingQuestions = [
        "Do you live together?",
        "What's the one thing you're saving for?",
        "Who or what else do you look after?",
    ]

    static let onboardingClosing = "That's all I need. Connect a calendar and "
        + "I'll work the rest out by watching."
}
