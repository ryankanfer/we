import SwiftUI
import WidgetKit

private struct WEExternalSurfaceEntry: TimelineEntry {
    let date: Date
    let snapshot: ExternalSurfaceSnapshot
}

private struct WEExternalSurfaceProvider: TimelineProvider {
    private let store = ExternalSurfaceStore()

    func placeholder(in context: Context) -> WEExternalSurfaceEntry {
        WEExternalSurfaceEntry(
            date: Date(),
            snapshot: ExternalSurfaceSnapshot(
                displayState: .quiet,
                expiresAt: Date().addingTimeInterval(60 * 60)
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WEExternalSurfaceEntry) -> Void
    ) {
        let now = Date()
        completion(
            WEExternalSurfaceEntry(
                date: now,
                snapshot: store.read(now: now) ?? .quiet(now: now)
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WEExternalSurfaceEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = store.read(now: now) ?? .quiet(now: now)
        let entry = WEExternalSurfaceEntry(date: now, snapshot: snapshot)
        guard snapshot.expiresAt > now else {
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(now.addingTimeInterval(60 * 60))
                )
            )
            return
        }

        // A second entry changes the surface at the exact expiry boundary;
        // WidgetKit does not have to wait for a later provider refresh.
        let quietEntry = WEExternalSurfaceEntry(
            date: snapshot.expiresAt,
            snapshot: .quiet(now: snapshot.expiresAt)
        )
        completion(
            Timeline(
                entries: [entry, quietEntry],
                policy: .after(
                    snapshot.expiresAt.addingTimeInterval(60 * 60)
                )
            )
        )
    }
}

struct WEAmbientWidget: Widget {
    let kind = "WEAmbientWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WEExternalSurfaceProvider()
        ) { entry in
            WEExternalSurfaceView(entry: entry)
                .widgetURL(WEExternalSurface.todayURL)
        }
        .configurationDisplayName("WE")
        .description("Quiet shared reassurance, without opening WE.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
        .contentMarginsDisabled()
    }
}

private struct WEExternalSurfaceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEExternalSurfaceEntry

    var body: some View {
        WEAmbientWidgetSurface(
            snapshot: entry.snapshot,
            date: entry.date,
            family: family,
            backgroundPresentation: .widgetHost
        )
    }
}
