import ActivityKit
import SwiftUI
import WidgetKit

struct WESharedRoomLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: SharedRoomActivityAttributes.self
        ) { context in
            WELiveActivityLockScreen(snapshot: context.state.snapshot)
                .activityBackgroundTint(Color.weWidgetPrivateInk)
                .activitySystemActionForegroundColor(Color.weWidgetPearl)
                .widgetURL(WEExternalSurface.todayURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("WE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.weWidgetPearl)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WEExpiryLabel(
                        expiresAt: context.state.snapshot.expiresAt
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        WEExternalContinuityMark(
                            state: context.state.snapshot.effectiveState()
                        )
                        .frame(width: 54, height: 18)

                        Text(context.state.snapshot.wording())
                            .font(.callout)
                            .lineLimit(2)
                            .foregroundStyle(Color.weWidgetPearl)
                    }
                }
            } compactLeading: {
                Text("WE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.weWidgetPearl)
            } compactTrailing: {
                WEExpiryLabel(
                    expiresAt: context.state.snapshot.expiresAt
                )
            } minimal: {
                WEExternalContinuityMark(
                    state: context.state.snapshot.effectiveState()
                )
                .padding(7)
            }
            .widgetURL(WEExternalSurface.todayURL)
            .keylineTint(Color.weWidgetChampagne)
        }
    }
}

private struct WELiveActivityLockScreen: View {
    let snapshot: ExternalSurfaceSnapshot

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.weWidgetPearl.opacity(0.72))
                Text(snapshot.wording())
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Color.weWidgetPearl)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                WEExternalContinuityMark(
                    state: snapshot.effectiveState()
                )
                .frame(width: 64, height: 20)
                WEExpiryLabel(expiresAt: snapshot.expiresAt)
            }
        }
        .padding(18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(snapshot.effectiveState().accessibilityLabel). "
                + snapshot.wording()
        )
        .accessibilityHint("Opens Today in WE")
    }
}

private struct WEExpiryLabel: View {
    let expiresAt: Date

    var body: some View {
        if expiresAt > Date() {
            Text(
                timerInterval: Date()...expiresAt,
                countsDown: true
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.weWidgetPearl.opacity(0.74))
            .accessibilityLabel("Time remaining")
        } else {
            Text("Quiet")
                .font(.caption)
                .foregroundStyle(Color.weWidgetPearl.opacity(0.74))
        }
    }
}
