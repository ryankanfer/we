import Foundation

/// The complete set of presentations Us can render. Views never inspect a
/// partner response or confirmation to derive one of these states.
nonisolated enum SharedJourneyPresentation: Equatable, Sendable {
    case empty
    case question(InsightRecord)
    case held(InsightRecord)
    case proposal(InsightRecord, SharedDirection)
    /// Every living journey, most pressing first, never empty in this case.
    ///
    /// An array rather than a single journey because Us no longer holds one
    /// season at a time. Two people can be finding a home and planning a trip
    /// at once, and the more recent of those does not cancel the other.
    case active([SharedJourney])
}

/// Pure shared-journey policy. It can be tested without SwiftUI, Supabase, or
/// a model provider; adapters only supply the already-authorized snapshot.
nonisolated enum SharedJourneyPolicy {
    static func presentation(
        snapshot: RelationshipSnapshot,
        viewerID: String,
        now: Date = Date()
    ) -> SharedJourneyPresentation {
        let passed = Set(snapshot.journeyPasses.lazy
            .filter {
                $0.profileID == viewerID
                    && isRecentPass($0.passedAt, now: now)
            }
            .map(\.insightID))
        let rested = Set(snapshot.directionConfirmations.lazy
            .filter { $0.profileID == viewerID && $0.decision == .rest }
            .map(\.insightID))

        let live = snapshot.insights
            .filter { record in
                guard record.insight.present,
                      record.consent?.visibility == .mutual,
                      record.consent?.readiness == .accepted,
                      !passed.contains(record.id),
                      !rested.contains(record.id),
                      !record.dismissedBy.contains(viewerID)
                else { return false }
                return !isExpired(record.insight.expiresAt, now: now)
            }
            .sorted(by: ranksBefore)

        if let proposal = live.first(where: {
            $0.sharedDirection?.status == .proposed
        }), let direction = proposal.sharedDirection {
            return .proposal(proposal, direction)
        }

        if let held = live.first(where: { record in
            record.sharedDirection == nil
                && record.responses.contains {
                    $0.profileID == viewerID && $0.status == .submitted
                }
        }) {
            return .held(held)
        }

        if let question = live.first(where: { record in
            guard record.sharedDirection == nil else { return false }
            return !record.responses.contains {
                $0.profileID == viewerID && $0.status == .submitted
            }
        }) {
            return .question(question)
        }

        let living = snapshot.journeys
            .filter { $0.status == .active }
            .sorted(by: journeyRanksBefore)
        if !living.isEmpty { return .active(living) }

        return .empty
    }

    /// Scope first, then most recently activated. Scope leads because an
    /// immediate undertaking is the one that will be over soonest, and a
    /// long-term one keeps.
    static func journeyRanksBefore(
        _ lhs: SharedJourney,
        _ rhs: SharedJourney
    ) -> Bool {
        if lhs.scope.priority != rhs.scope.priority {
            return lhs.scope.priority < rhs.scope.priority
        }
        if lhs.activatedAt != rhs.activatedAt {
            return lhs.activatedAt > rhs.activatedAt
        }
        return lhs.id < rhs.id
    }

    static func ranksBefore(_ lhs: InsightRecord, _ rhs: InsightRecord) -> Bool {
        let left = lhs.insight.journeyScope.priority
        let right = rhs.insight.journeyScope.priority
        if left != right { return left < right }
        if lhs.insight.sort != rhs.insight.sort {
            return lhs.insight.sort < rhs.insight.sort
        }
        return lhs.id < rhs.id
    }

    static func isExpired(_ value: String?, now: Date) -> Bool {
        guard let value,
              let expiry = parseDate(value)
        else { return false }
        return expiry <= now
    }

    /// “Not now” removes pressure for the current visit and part of the day;
    /// near- and long-term questions then become available to return to. An
    /// immediate question simply reaches its own expiry first.
    static func isRecentPass(_ value: String, now: Date) -> Bool {
        guard let passedAt = parseDate(value) else { return true }
        return passedAt > now.addingTimeInterval(-12 * 60 * 60)
    }

    static func parseDate(_ value: String) -> Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let parsed = withFractions.date(from: value) { return parsed }

        let withoutFractions = ISO8601DateFormatter()
        withoutFractions.formatOptions = [.withInternetDateTime]
        return withoutFractions.date(from: value)
    }
}
