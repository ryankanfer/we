#if DEBUG
import SwiftUI

/// Uses the production views with fictional, encrypted, account-isolated captures.
/// The existing preview mode prevents network synchronization and uses the
/// in-memory publication backend. No real account or couple is required.
struct WEIntelligencePrototype: View {
    @StateObject private var session = AppSession(repository: PreviewRepository())
    @State private var field = FieldStore()
    @State private var ready = false
    @State private var failure: String?
    var body: some View {
        Group {
            if ready { WEArtifactsView().environment(field).environmentObject(session) }
            else if let failure { ContentUnavailableView("Preview unavailable", systemImage: "lock", description: Text(failure)) }
            else { ProgressView("Preparing fictional examples") }
        }
        .task {
            guard WEIntelligenceCapabilities.isPreview else { failure = "Open this in the preview scheme."; return }
            do {
                await session.restoreIfNeeded()
                try ShareVaultController.shared.activate(accountID: "intelligence-interactive-preview", hueToken: "sage")
                let store = WEIntelligenceStore.shared; store.reload()
                if store.records.isEmpty {
                    let dinner = try store.capture([.text("Restaurant reservation. Dinner on 2026-10-16. Place: Garden Room.", label: "Reservation")])
                    let evidence = WEExtractionEvidence(text: "2026-10-16")
                    store.edit(dinner) {
                        $0.title = "Dinner at the Garden Room"; $0.place = "Garden Room"; $0.linkCategory = .restaurants
                        $0.evidence = [evidence]
                        $0.suggestions = [.init(field: .timing, value: "2026-10-16", evidenceIDs: [evidence.id])]
                    }
                    let link = try store.capture([.webURL(URL(string: "https://example.com/events")!, label: "Event link")])
                    store.edit(link) { $0.title = "An event to look into"; $0.linkCategory = .events }
                    let failed = try store.capture([.text("A weekend away, sometime next month", label: "Plan")])
                    store.edit(failed) { $0.title = "A weekend away"; $0.kind = .plan }
                    store.recordFailure(failed, message: "Understanding was interrupted. Open this plan to retry or edit it manually.")
                }
                ready = true
            } catch { failure = error.localizedDescription }
        }
    }
}

#Preview("Intelligence · capture, review and recovery") {
    WEIntelligencePrototype()
}
#Preview("Intelligence · largest text") {
    WEIntelligencePrototype().environment(\.dynamicTypeSize, .accessibility5)
}
#endif
