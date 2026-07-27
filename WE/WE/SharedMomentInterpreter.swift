import Foundation

nonisolated struct SharedMomentInterpretation: Equatable, Sendable {
    let eyebrow: String
    let title: String
    let message: String
    let symbol: String
}

nonisolated enum SharedMomentInterpreter {
    static func interpretation(
        for insight: Insight,
        mine: String?,
        partner: String?
    ) -> SharedMomentInterpretation? {
        guard let mine, let partner else { return nil }

        if mine == partner {
            return SharedMomentInterpretation(
                eyebrow: "A CLEAR YES",
                title: mine,
                message: "You arrived at the same place independently. WE kept both answers private until they were ready to open together.",
                symbol: "heart.fill"
            )
        }

        let pair = Set([normalized(mine), normalized(partner)])

        if insight.seedKey.hasPrefix("tonight-")
            || insight.seedKey == "saturday-plan"
        {
            return tonight(pair)
        }

        if insight.seedKey.hasPrefix("weekend-") {
            return weekend(pair)
        }

        if insight.seedKey.hasPrefix("load-") {
            return load(pair)
        }

        if insight.seedKey.hasPrefix("plan-") {
            return SharedMomentInterpretation(
                eyebrow: "A SHARED DIRECTION",
                title: "Keep the plan spacious",
                message: "Your answers point toward a plan with one clear anchor and enough room around it to feel like yours.",
                symbol: "calendar.badge.checkmark"
            )
        }

        return nil
    }

    private static func tonight(
        _ pair: Set<String>
    ) -> SharedMomentInterpretation {
        if contains(pair, "quiet", "easy") {
            return result(
                "Something gentle",
                "Keep the evening close and remove as many decisions as possible."
            )
        }
        if contains(pair, "quiet", "recharge") {
            return result(
                "Quiet company, room to breathe",
                "Be near each other without asking the evening to become anything more."
            )
        }
        if contains(pair, "easy", "out") {
            return result(
                "A small change of scene",
                "Something casual nearby—perhaps dinner or a walk—with an easy way home."
            )
        }
        if contains(pair, "out", "playful") {
            return result(
                "Go somewhere without overplanning it",
                "Choose one small destination and let the rest of the evening unfold."
            )
        }
        if contains(pair, "playful", "recharge") {
            return result(
                "One little spark, then rest",
                "Try something brief and different without giving away the whole evening."
            )
        }
        return result(
            "Start small and keep it flexible",
            "There is room for both answers in an evening with one gentle beginning and no pressure to continue."
        )
    }

    private static func weekend(
        _ pair: Set<String>
    ) -> SharedMomentInterpretation {
        if contains(pair, "rest", "unfinished") {
            return result(
                "Clear one thing, protect the rest",
                "Choose a single useful task, then let the weekend feel open again.",
                symbol: "sun.max.fill"
            )
        }
        if contains(pair, "new", "unplanned") {
            return result(
                "Leave room for a small adventure",
                "Pick a direction rather than an itinerary and decide the rest when you get there.",
                symbol: "sparkles"
            )
        }
        if contains(pair, "people", "rest") {
            return result(
                "Connection without a full calendar",
                "One easy social moment leaves room for the quiet part of the weekend too.",
                symbol: "person.2.fill"
            )
        }
        return result(
            "Give the weekend one anchor",
            "Choose one thing you both want, then keep the space around it deliberately unclaimed.",
            symbol: "calendar"
        )
    }

    private static func load(
        _ pair: Set<String>
    ) -> SharedMomentInterpretation {
        if contains(pair, "together", "wait") {
            return result(
                "Do one thing together; release one",
                "Shared effort and deliberate postponement can make the week lighter without silently moving the load.",
                symbol: "person.2.fill"
            )
        }
        if contains(pair, "take", "ask") {
            return result(
                "Make one handoff explicit",
                "Name one concrete responsibility and let the person with capacity claim it openly.",
                symbol: "arrow.left.arrow.right"
            )
        }
        return result(
            "Change one thing, not everything",
            "Choose the smallest visible adjustment that would make the shared load feel more intentional.",
            symbol: "scale.3d"
        )
    }

    private static func result(
        _ title: String,
        _ message: String,
        symbol: String = "circle.hexagongrid.fill"
    ) -> SharedMomentInterpretation {
        SharedMomentInterpretation(
            eyebrow: "WHERE YOU OVERLAP",
            title: title,
            message: message,
            symbol: symbol
        )
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
    }

    private static func contains(
        _ pair: Set<String>,
        _ first: String,
        _ second: String
    ) -> Bool {
        pair.contains { $0.contains(first) }
            && pair.contains { $0.contains(second) }
    }
}
