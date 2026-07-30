import ActivityKit
import Combine
import Foundation
import WidgetKit

@MainActor
final class ExternalSurfaceController: ObservableObject {
    @Published private(set) var snapshot: ExternalSurfaceSnapshot
    @Published private(set) var specificWordingOptedIn: Bool

    private let store: ExternalSurfaceStore
    private var expiryTask: Task<Void, Never>?

    convenience init() {
        self.init(store: ExternalSurfaceStore())
    }

    init(store: ExternalSurfaceStore) {
        self.store = store
        specificWordingOptedIn = store.specificWordingOptedIn
        snapshot = store.read() ?? .quiet()
        Task { @MainActor [weak self] in
            await self?.reconcileLiveActivities()
        }
    }

    /// Changes the global external-surface privacy preference. Turning it off
    /// immediately rewrites both stored and active surfaces with generic copy.
    func setSpecificWordingOptIn(_ isEnabled: Bool) {
        specificWordingOptedIn = isEnabled
        store.setSpecificWordingOptIn(isEnabled)

        if !isEnabled {
            snapshot = snapshot.withoutSpecificWording()
            store.save(snapshot, allowsSpecificWording: false)
            WidgetCenter.shared.reloadAllTimelines()
            Task { await updateRunningActivities(with: snapshot) }
        }
    }

    /// Publishes only already-shared state. Callers cannot pass private answers
    /// or identity metadata because the external snapshot has no such fields.
    func publish(
        state: ExternalSurfaceDisplayState,
        expiresAt: Date,
        approvedSharedWording: ExplicitlyPermittedSharedWording? = nil
    ) {
        let next = persist(
            state: state,
            expiresAt: expiresAt,
            approvedSharedWording: approvedSharedWording
        )
        Task { await updateRunningActivities(with: next) }
    }

    /// Idempotently publishes a sanitized snapshot and keeps at most one local
    /// Live Activity. Existing activities are updated rather than duplicated.
    @discardableResult
    func publishAndEnsureLiveActivity(
        state: ExternalSurfaceDisplayState,
        expiresAt: Date,
        approvedSharedWording: ExplicitlyPermittedSharedWording? = nil
    ) async throws -> String? {
        let next = persist(
            state: state,
            expiresAt: expiresAt,
            approvedSharedWording: approvedSharedWording
        )
        let activities = Activity<SharedRoomActivityAttributes>.activities
        let content = ActivityContent(
            state: SharedRoomActivityAttributes.ContentState(snapshot: next),
            staleDate: next.expiresAt
        )

        guard next.expiresAt > Date(),
              state == .roomAvailable || state == .sharedRoomActive else {
            for activity in activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
            return nil
        }

        if let existing = activities.first {
            await existing.update(content)
            for duplicate in activities.dropFirst() {
                await duplicate.end(content, dismissalPolicy: .immediate)
            }
            return existing.id
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return nil
        }
        let activity = try Activity.request(
            attributes: SharedRoomActivityAttributes(createdAt: Date()),
            content: content,
            pushType: nil
        )
        return activity.id
    }

    func endLiveActivities() async {
        expiryTask?.cancel()
        expiryTask = nil
        let finalSnapshot = snapshot.withoutSpecificWording()
        let finalContent = ActivityContent(
            state: SharedRoomActivityAttributes.ContentState(
                snapshot: finalSnapshot
            ),
            staleDate: Date()
        )
        for activity in Activity<SharedRoomActivityAttributes>.activities {
            await activity.end(
                finalContent,
                dismissalPolicy: .immediate
            )
        }
    }

    /// Re-applies the privacy boundary after launch or foregrounding, removes
    /// expired activities, and collapses any historical duplicates.
    func reconcileLiveActivities() async {
        let activities = Activity<SharedRoomActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        let now = Date()
        let isLiveState = snapshot.displayState == .roomAvailable
            || snapshot.displayState == .sharedRoomActive
        guard snapshot.expiresAt > now, isLiveState else {
            await endLiveActivities()
            return
        }

        let content = ActivityContent(
            state: SharedRoomActivityAttributes.ContentState(
                snapshot: snapshot
            ),
            staleDate: snapshot.expiresAt
        )
        if let primary = activities.first {
            await primary.update(content)
        }
        for duplicate in activities.dropFirst() {
            await duplicate.end(content, dismissalPolicy: .immediate)
        }
        scheduleLiveActivityExpiry(at: snapshot.expiresAt)
    }

    func clear() {
        snapshot = .quiet()
        store.remove()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await endLiveActivities() }
    }

    private func persist(
        state: ExternalSurfaceDisplayState,
        expiresAt: Date,
        approvedSharedWording: ExplicitlyPermittedSharedWording?
    ) -> ExternalSurfaceSnapshot {
        let next = ExternalSurfaceSnapshot(
            displayState: state,
            expiresAt: expiresAt,
            permittedSharedWording: specificWordingOptedIn
                ? approvedSharedWording
                : nil
        )
        snapshot = next
        store.save(
            next,
            allowsSpecificWording: specificWordingOptedIn
        )
        WidgetCenter.shared.reloadAllTimelines()
        scheduleLiveActivityExpiry(at: next.expiresAt)
        return next
    }

    private func updateRunningActivities(
        with next: ExternalSurfaceSnapshot
    ) async {
        let content = ActivityContent(
            state: SharedRoomActivityAttributes.ContentState(snapshot: next),
            staleDate: next.expiresAt
        )
        for activity in Activity<SharedRoomActivityAttributes>.activities {
            await activity.update(content)
        }
    }

    private func scheduleLiveActivityExpiry(at date: Date) {
        expiryTask?.cancel()
        let seconds = max(0, date.timeIntervalSinceNow)
        let nanoseconds = UInt64(
            min(
                seconds,
                WEExternalSurface.maximumLifetime
            ) * 1_000_000_000
        )
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            await endLiveActivities()
        }
    }
}
