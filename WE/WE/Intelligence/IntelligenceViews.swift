import SwiftUI
import PhotosUI
import EventKit
import EventKitUI

struct WEPrivacyLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: text == "Only me" ? "lock" : "person.crop.circle.badge.checkmark")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct WEArtifactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FieldStore.self) private var field
    @State private var intelligence = WEIntelligenceStore.shared
    @State private var query = ""
    @State private var selected: UUID?
    @State private var capture = false
    @State private var recovery = false
    var body: some View {
        NavigationStack {
            List {
                if let message = intelligence.message { Section { Text(message); Button("Retry") { intelligence.reload(); Task { await intelligence.synchronize() } } } }
                if !intelligence.issues.isEmpty { Button("Needs attention · \(intelligence.issues.count)") { recovery = true } }
                if query.isEmpty {
                    ForEach(intelligence.records) { record in artifactRow(record, reason: nil) }
                } else {
                    ForEach(WESemanticSearch.matches(query, eligible: intelligence.searchDocuments)) { match in
                        if let id = UUID(uuidString: match.id.id), let record = intelligence.ledger.records[id] { artifactRow(record, reason: match.reason) }
                    }
                }
                if intelligence.records.isEmpty { Text("Save a thought, link, or image. Only you can see it until you review and share a version.") }
            }
            .modifier(WEIntelligenceSurfaceStyle())
            .navigationTitle("Saved in Life")
            .searchable(text: $query, prompt: "Find something you saved")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Bring it in", systemImage: "plus") { capture = true } }
            }
            .sheet(isPresented: $capture) { WEPrivateCaptureView() }
            .sheet(isPresented: $recovery) { WERecoveryCenter().environment(field) }
            .sheet(item: Binding(get: { selected.map { WEArtifactSelection(id: $0) } }, set: { selected = $0?.id })) { selection in
                WEArtifactDetail(id: selection.id).environment(field)
            }
            .task { intelligence.reload(); await intelligence.synchronize() }
            .refreshable { await intelligence.synchronize() }
        }
    }
    private func artifactRow(_ record: WEArtifactRecord, reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(record.content.title) { selected = record.id }.font(.headline)
            WEPrivacyLabel(text: field.privacyLabel(for: record.content))
            Text(intelligence.syncing ? "Syncing privately" : record.syncLabel).font(.caption)
            if let reason { DisclosureGroup("Why this?") { Text(reason).font(.subheadline) } }
            if let explanation = record.content.timing?.explanation { Text(explanation).font(.caption) }
        }.padding(.vertical, 5)
    }
}
struct WEArtifactSelection: Identifiable { let id: UUID }

struct WEPrivateCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photos: [PhotosPickerItem] = []
    @State private var kind: WEPrivateItemKind = .saved
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Only me") {
                    Picker("Save as", selection: $kind) {
                        ForEach(WEPrivateItemKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("A thought or HTTPS link", text: $text, axis: .vertical).lineLimit(3...10).accessibilityIdentifier("intelligence.capture.text")
                    PhotosPicker("Choose images", selection: $photos, maxSelectionCount: 5, matching: .images)
                    if !photos.isEmpty { Text("\(photos.count) images selected") }
                    Text("Saved privately on this phone first. Understanding and sharing are separate choices.").font(.footnote)
                }
                if let message { Text(message) }
                Button(saving ? "Saving…" : "Save privately") { Task { await save() } }.accessibilityIdentifier("intelligence.capture.save").disabled(saving || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty))
            }
            .modifier(WEIntelligenceSurfaceStyle())
            .navigationTitle("Bring it in")
            .toolbar { Button("Cancel") { dismiss() }.disabled(saving) }
        }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            var candidates: [IncomingShareCandidate] = []
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let url = URL(string: trimmed), IncomingShareParser.canonicalHTTPSURL(url) != nil { candidates.append(.webURL(url, label: "Link")) }
                else { candidates.append(.text(trimmed, label: "Thought")) }
            }
            var total = 0
            for photo in photos {
                guard let bytes = try await photo.loadTransferable(type: Data.self) else { throw IncomingShareError.corruptImage }
                total += bytes.count
                guard total <= WEShareConstants.maximumSourceBytes else { throw IncomingShareError.imageTooLarge }
                let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try bytes.write(to: file, options: [.atomic, .completeFileProtection])
                defer { try? FileManager.default.removeItem(at: file) }
                candidates.append(.image(try ShareImageNormalizer().preserve(fileAt: file), label: "Image"))
            }
            let store = WEIntelligenceStore.shared
            let id = try store.capture(candidates)
            store.edit(id) { $0.kind = kind }
            Task { await store.synchronize() }
            dismiss()
        } catch { message = "Nothing was confirmed saved. \(error.localizedDescription)" }
    }
}

struct WEArtifactDetail: View {
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(FieldStore.self) private var field
    @State private var intelligence = WEIntelligenceStore.shared
    @State private var newPlanTitle = ""
    @State private var actionMessage: String?
    @State private var deleting = false
    @State private var updatingPlanTiming = false
    @State private var sharing = false
    @State private var fetching = false
    @State private var calendar = false
    @State private var editingTiming = false
    @State private var preview: UIImage?
    @State private var selectedSource: UUID?
    private func mapsURL(_ place: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: place)]
        return components.url!
    }
    private var record: WEArtifactRecord? { intelligence.ledger.records[id] }
    private var manifest: IncomingShareManifest? { intelligence.manifests.first { $0.id == id } }
    var body: some View {
        NavigationStack {
            if let record, !record.deleted {
                Form {
                    Section {
                        WEPrivacyLabel(text: field.privacyLabel(for: record.content))
                        Text(intelligence.syncing ? "Syncing privately" : record.syncLabel)
                        TextField("Title", text: value(\.title))
                        TextField("Details", text: value(\.body), axis: .vertical)
                        TextField("Place", text: value(\.place))
                        Picker("Category", selection: value(\.category)) {
                            Text("Saved").tag("saved")
                            ForEach(ShareReviewModel.reviewCategories) { category in Text(category.rawValue.capitalized).tag(category.rawValue) }
                        }
                    }
                    if let actionMessage { Text(actionMessage).foregroundStyle(.secondary) }
                    if record.content.kind == .plan {
                        Toggle("Plan completed", isOn: Binding(get: { record.content.completed == true }, set: { completed in intelligence.edit(id) { $0.completed = completed } }))
                    }
                    timing(record)
                    understanding(record)
                    connections(record)
                    if record.content.kind == .plan {
                        Section("Saved with this plan") {
                            ForEach(intelligence.records.filter { $0.content.connectedPrivatePlanID == id }) { child in
                                NavigationLink(child.content.title) { WEArtifactDetail(id: child.id).environment(field) }
                                WEPrivacyLabel(text: field.privacyLabel(for: child.content))
                            }
                        }
                    }
                    Section("Original · Only me") {
                        if let manifest {
                            ForEach(manifest.representations) { source in
                                if let text = source.text { Text(text).textSelection(.enabled) }
                                if let url = source.url { Link("Open source: \(url.host ?? "link")", destination: url) }
                            }
                            ForEach(manifest.resources) { resource in
                                Button(resource.isOriginal == true ? "Open original image" : "Open optimized image") {
                                    selectedSource = resource.id
                                    if let context = intelligence.context,
                                       let bytes = try? ShareVaultController.shared.store.loadResource(resource, manifest: manifest, context: context) { preview = UIImage(data: bytes) }
                                }
                            }
                            if let preview { Image(uiImage: preview).resizable().scaledToFit().accessibilityLabel("Private source image") }
                        }
                    }
                    Section("Use it") {
                        if !record.content.place.isEmpty {
                            Link("Open place in Maps", destination: mapsURL(record.content.place))
                        }
                        Button("Review Calendar event") { calendar = true }.disabled(record.content.timing?.isResolved != true)
                        Text("Only the details you review in the Calendar editor leave WE.").font(.footnote)
                    }
                    Section {
                        Button("Review sharing") { sharing = true }.disabled(record.content.title.isEmpty)
                        Text("The original stays Only me. Choose exactly what your partner can see.").font(.footnote)
                        Button("Delete Everywhere", role: .destructive) { deleting = true }
                    }
                }
                .modifier(WEIntelligenceSurfaceStyle())
            .navigationTitle("Saved item")
                .toolbar { Button("Done") { Task { await intelligence.synchronize() }; dismiss() } }
                .confirmationDialog("Update the plan’s timing?", isPresented: $updatingPlanTiming, titleVisibility: .visible) {
                    Button("Use reviewed timing on the plan") {
                        if let target = record.content.connectedPlanID, let timing = record.content.timing,
                           !field.acceptTiming(timing, for: target) { actionMessage = "The timing update was not saved. Review the plan and retry." }
                    }
                } message: {
                    Text("Share \(record.content.timing?.explanation ?? "") on \(field.state.lifeItems.first { $0.id == record.content.connectedPlanID }?.title ?? "the plan") with \(field.intelligencePartnerName). Other saved details remain private.")
                }
                .confirmationDialog("Understand this link?", isPresented: $fetching, titleVisibility: .visible) {
                    Button("Understand this link") { intelligence.understand(id, fetchLink: true) }
                } message: { Text("WE will contact this public website without your browser login and understand its text on this phone. Nothing is shared with your partner.") }
                .confirmationDialog("Delete Everywhere?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete Everywhere", role: .destructive) { Task { await intelligence.deleteEverywhere(id); if intelligence.ledger.records[id]?.deleted == true { field.hideDeletedImportRepresentations(); dismiss(); await field.retryLoad() } } }
                } message: {
                    Text("Remove this import’s original, synced copies, extracted details, processing history, search data, and connections, including its shared version and attachments in your partner’s WE. The containing plan and independently authored content stay. Offline devices clear on reconnect; external exports and retained backups cannot be erased immediately.")
                }
                .sheet(isPresented: $sharing) {
                    if let manifest { ShareReviewView(manifest: manifest) { await field.retryLoad(); intelligence.reload() }.environment(field) }
                }
                .sheet(isPresented: $editingTiming) {
                    WEObjectTimingEditor(initial: record.content.timing) { timing in intelligence.edit(id) { $0.timing = timing } }
                }
                .sheet(isPresented: $calendar) { WECalendarEditor(title: record.content.title, place: record.content.place, timing: record.content.timing!) }
            } else { ContentUnavailableView("Item unavailable", systemImage: "lock"); Button("Close") { dismiss() } }
        }
    }
    private func value(_ keyPath: WritableKeyPath<WEArtifactContent, String>) -> Binding<String> {
        Binding(get: { record?.content[keyPath: keyPath] ?? "" }, set: { value in intelligence.edit(id) { $0[keyPath: keyPath] = value } })
    }
    private func timing(_ record: WEArtifactRecord) -> some View {
        Section("Timing") {
            Button("Review dates, times, or a range") { editingTiming = true }
            TextField("Date · YYYY-MM-DD", text: Binding(get: { record.content.timing?.startDay ?? "" }, set: { day in
                intelligence.edit(id) { $0.timing = WEObjectTiming(precision: WEObjectTiming.day(day) == nil ? .unresolved : .day, startDay: day, unresolvedText: WEObjectTiming.day(day) == nil ? day : nil) }
            }))
            if let reason = record.content.timing?.explanation { Text(reason).font(.footnote) }
            Text("Leave uncertain dates blank. A date does not imply a booking or a time.").font(.footnote)
        }
    }
    private func understanding(_ record: WEArtifactRecord) -> some View {
        Section("Understanding · Only me") {
            Toggle("Allow on-device understanding", isOn: Binding(get: { record.content.processingConsent }, set: { enabled in
                intelligence.edit(id) { $0.processingConsent = enabled; $0.authorizationID = UUID(); $0.job = nil }
            }))
            if !WEIntelligenceCapabilities.enrichmentEnabled { Text("Understanding is temporarily paused. You can still save and edit every detail.").font(.footnote) }
            if let job = record.content.job { Text(job.failure ?? "Understanding: \(job.state.rawValue)").font(.footnote) }
            Button("Understand saved content") { intelligence.understand(id) }.disabled(!record.content.processingConsent || !WEIntelligenceCapabilities.enrichmentEnabled)
            if manifest?.representations.contains(where: { $0.url != nil }) == true {
                Button("Understand this link") { fetching = true }.disabled(!record.content.processingConsent || !WEIntelligenceCapabilities.enrichmentEnabled)
                Picker("Link category", selection: Binding(get: { record.content.linkCategory?.rawValue ?? "" }, set: { raw in intelligence.edit(id) { $0.linkCategory = WELinkCategory(rawValue: raw) } })) {
                    Text("Unresolved").tag("")
                    ForEach(WELinkCategory.allCases, id: \.self) { Text($0.label.capitalized).tag($0.rawValue) }
                }
                if let category = record.content.linkCategory, intelligence.ruleEligible(category), !intelligence.ledger.trustedCategories.contains(category) {
                    Button("Always understand \(category.label) links") { intelligence.setRule(category, enabled: true) }
                    Text("Only links already identified as \(category.label) will be retrieved automatically. Change this in Account.").font(.footnote)
                }
            }
            if let reason = record.content.automaticFetchReason { Text(reason).font(.footnote) }
            ForEach(record.content.suggestions) { suggestion in
                VStack(alignment: .leading) {
                    Text("\(suggestion.field.rawValue.capitalized): \(suggestion.value)")
                    DisclosureGroup("Why this?") {
                        ForEach(record.content.evidence.filter { suggestion.evidenceIDs.contains($0.id) }) { Text($0.text).font(.footnote) }
                    }
                    Button(suggestion.accepted ? "Accepted" : "Use suggestion") { intelligence.accept(suggestion, for: id) }.disabled(suggestion.accepted)
                    if !suggestion.accepted {
                        Button("Dismiss suggestion") { intelligence.edit(id) { $0.suggestions.removeAll { $0.id == suggestion.id } } }
                    }
                }
            }
        }
    }
    private func connections(_ record: WEArtifactRecord) -> some View {
        Section("Connect to a plan · Only me until shared") {
            Picker("Plan", selection: Binding(get: { record.content.connectedPlanID ?? "" }, set: { destination in intelligence.edit(id) { $0.connectedPlanID = destination.isEmpty ? nil : destination } })) {
                Text("Leave unattached").tag("")
                ForEach(field.intelligenceEligibleLifeItems) { item in Text(item.title + " · " + field.privacyLabel(for: item)).tag(item.id) }
            }
            if record.content.connectedPlanID != nil, record.content.timing?.isResolved == true {
                Button("Review timing update for this plan") { updatingPlanTiming = true }
            }
            let documents = field.intelligenceEligibleLifeItems.map { WESearchDocument(id: .init(kind: .lifeItem, id: $0.id), title: $0.title, text: $0.detail ?? "", visibility: $0.objectVisibility, permitsSemantic: record.content.processingConsent) }
            ForEach(Array(WESemanticSearch.matches(record.content.title, eligible: documents).prefix(3))) { match in
                Button("Connect to \(match.document.title)") { intelligence.edit(id) { $0.connectedPlanID = match.id.id } }
                DisclosureGroup("Why this?") { Text(match.reason).font(.footnote) }
            }
            Picker("Only me plan", selection: Binding(get: { record.content.connectedPrivatePlanID?.uuidString ?? "" }, set: { destination in
                intelligence.edit(id) { $0.connectedPrivatePlanID = UUID(uuidString: destination); if !destination.isEmpty { $0.connectedPlanID = nil } }
            })) {
                Text("None").tag("")
                ForEach(intelligence.records.filter { $0.id != id && $0.content.kind == .plan }) { plan in Text(plan.content.title).tag(plan.id.uuidString) }
            }
            TextField("New plan name", text: $newPlanTitle)
            Button("Create a plan · Only me") {
                do {
                    let planID = try intelligence.capture([.text(newPlanTitle, label: "Plan")])
                    intelligence.edit(planID) { $0.kind = .plan; $0.title = newPlanTitle }
                    intelligence.edit(id) { $0.connectedPrivatePlanID = planID; $0.connectedPlanID = nil }
                    newPlanTitle = ""
                } catch { actionMessage = "The plan was not saved. Your item is still here; try again." }
            }.disabled(newPlanTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Connecting this item does not change the plan’s dates or share your original. An Only me plan connection stays private.").font(.footnote)
        }
    }
}

struct WERecoveryCenter: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FieldStore.self) private var field
    @State private var intelligence = WEIntelligenceStore.shared
    @State private var selected: WEArtifactSelection?
    @State private var sharedConflict: WESharedEditConflict?
    @State private var sharedIssue: String?
    var body: some View {
        NavigationStack {
            List {
                if let message = intelligence.message { Text(message) }
                if let sharedIssue { Text(sharedIssue) }
                ForEach(field.state.lifeItems.filter { field.deliveryStates[$0.id] == .needsAttention }) { item in
                    Section(item.title) {
                        Text("A saved Life edit needs attention. Your changes remain on this phone.")
                        Button("Review shared edits") {
                            Task {
                                do { sharedConflict = try await field.reviewSharedEdit(itemID: item.id) }
                                catch { sharedIssue = "Reconnect to review the current shared version. Your pending edit has been kept." }
                            }
                        }
                        Button("Retry delivery") { Task { await field.retryDelivery(for: item.id) } }
                    }
                }
                ForEach(intelligence.issues) { record in
                    Section(record.deleted ? "Deletion pending" : record.content.title) {
                        Text(record.failure ?? record.content.job?.failure ?? record.syncLabel)
                        if let remote = record.remoteConflict {
                            Text("On this phone: \(record.content.title)\n\(record.content.body)")
                            Text("This phone’s details: \(record.content.place) · \(record.content.timing?.explanation ?? "No date") · \(record.content.category)")
                            Text("Synced version: \(remote.title)\n\(remote.body)")
                            Text("Synced details: \(remote.place) · \(remote.timing?.explanation ?? "No date") · \(remote.category)")
                            Button("Keep this phone’s edits") { intelligence.resolveConflict(record.id, keepLocal: true) }
                            Button("Use synced version") { intelligence.resolveConflict(record.id, keepLocal: false) }
                        }
                        if !record.deleted { Button("Open and review") { selected = .init(id: record.id) } }
                        Button("Retry sync") { Task { await intelligence.synchronize() } }
                    }
                }
                Section("On-device understanding") {
                    Toggle("Allow understanding for new saved items", isOn: Binding(get: { intelligence.ledger.localUnderstandingForNewItems == true }, set: intelligence.setLocalUnderstandingDefault))
                    Text("This allows local processing only. Website retrieval still requires a separate grant or category rule.").font(.footnote)
                }
                Section("Trusted link categories") {
                    ForEach(WELinkCategory.allCases, id: \.self) { category in
                        Toggle("Automatically understand \(category.label)", isOn: Binding(get: { intelligence.ledger.trustedCategories.contains(category) }, set: { intelligence.setRule(category, enabled: $0) }))
                            .disabled(!intelligence.ruleEligible(category) && !intelligence.ledger.trustedCategories.contains(category))
                    }
                    Text("Rules become available after three different links in a category have been understood with your explicit permission. These rules permit public webpage retrieval, never sharing. Unknown links still ask first.").font(.footnote)
                }
                if intelligence.issues.isEmpty && intelligence.message == nil { Text("No saved imports need attention.") }
            }
            .modifier(WEIntelligenceSurfaceStyle())
            .navigationTitle("Needs attention")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(item: $selected) { WEArtifactDetail(id: $0.id).environment(field) }
            .sheet(item: $sharedConflict) { conflict in
                NavigationStack {
                    Form {
                        Section("On this phone") { Text(conflict.local.title); Text(conflict.local.detail ?? ""); Text(conflict.local.objectTiming?.explanation ?? "No date"); Text(conflict.local.isDone ? "Completed" : "Open") }
                        Section("Current shared version") { Text(conflict.remote.title); Text(conflict.remote.detail ?? ""); Text(conflict.remote.objectTiming?.explanation ?? "No date"); Text(conflict.remote.isDone ? "Completed" : "Open") }
                        Button("Keep this phone’s edits") { resolve(conflict, keepLocal: true) }
                        Button("Use current shared version") { resolve(conflict, keepLocal: false) }
                    }.modifier(WEIntelligenceSurfaceStyle())
            .navigationTitle("Review conflicting edits")
                    .toolbar { Button("Cancel") { sharedConflict = nil } }
                }
            }
            .task { intelligence.reload() }
        }
    }
    private func resolve(_ conflict: WESharedEditConflict, keepLocal: Bool) {
        Task {
            do { try await field.resolveSharedEdit(conflict, keepLocal: keepLocal); sharedConflict = nil }
            catch { sharedIssue = "The item changed again. Review the latest version; your work is still saved."; sharedConflict = nil }
        }
    }
}

struct WECalendarEditor: UIViewControllerRepresentable {
    let title: String
    let place: String
    let timing: WEObjectTiming
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        let store = EKEventStore(); controller.eventStore = store
        let event = EKEvent(eventStore: store); event.title = title; event.location = place
        event.isAllDay = timing.precision == .day
        event.startDate = timing.anchor
        if timing.precision == .day {
            let lastDay = WEObjectTiming.day(timing.endDay) ?? timing.anchor!
            event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: lastDay)
        } else { event.endDate = timing.end ?? timing.start }
        if let zone = timing.timeZoneID { event.timeZone = TimeZone(identifier: zone) }
        controller.event = event; controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { done() }
    }
}

struct WEPlanAttachments: View {
    let planID: String
    @Environment(FieldStore.self) private var field
    @State private var intelligence = WEIntelligenceStore.shared
    @State private var selected: WEArtifactSelection?
    @State private var shared: FieldItemReference?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(intelligence.records.filter { $0.content.connectedPlanID == planID }) { record in
                Button(record.content.title) { selected = .init(id: record.id) }
                WEPrivacyLabel(text: field.privacyLabel(for: record.content))
            }
            ForEach(field.intelligenceEligibleLifeItems.filter { $0.connectedPlanID == planID }) { item in
                Button(item.title) { shared = .init(id: item.id) }
                WEPrivacyLabel(text: field.privacyLabel(for: item))
            }
        }
        .sheet(item: $selected) { WEArtifactDetail(id: $0.id).environment(field) }
        .sheet(item: $shared) { FieldItemSheet(itemID: $0.id).environment(field) }
        .task { intelligence.reload() }
    }
}

/// Owner-visible temporal projection; private artifacts never enter FieldState.
struct WEPrivateTimeItems: View {
    var day: Date? = nil
    @Environment(FieldStore.self) private var field
    @State private var intelligence = WEIntelligenceStore.shared
    @State private var selected: WEArtifactSelection?
    private var timed: [WEArtifactRecord] {
        intelligence.records.filter { record in
            guard record.content.publishedItemID == nil, record.content.completed != true else { return false }
            if day == nil, record.content.kind == .plan, record.content.timing == nil,
               let created = intelligence.manifests.first(where: { $0.id == record.id })?.createdAt,
               field.now.timeIntervalSince(created) >= 30 * 86_400 { return true }
            guard let timing = record.content.timing, timing.isResolved else { return false }
            if let day { return timing.includes(day) }
            guard let anchor = timing.anchor else { return false }
            let difference = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: field.now), to: Calendar.current.startOfDay(for: anchor)).day ?? 100
            return (-30...7).contains(difference) || timing.includes(field.now)
        }.sorted { ($0.content.timing?.anchor ?? .distantFuture) < ($1.content.timing?.anchor ?? .distantFuture) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(timed) { record in
                Button(record.content.title) { selected = .init(id: record.id) }
                WEPrivacyLabel(text: "Only me")
                DisclosureGroup("Why this?") {
                    Text(WETimeRelevance.reason(for: record.content.timing, now: field.now) ?? record.content.timing?.explanation ?? "This plan has been open for at least a month. You can keep it, update it, or mark it complete.").font(.footnote)
                }
            }
        }
        .sheet(item: $selected) { WEArtifactDetail(id: $0.id).environment(field) }
    }
}

struct WEObjectTimingEditor: View {
    let initial: WEObjectTiming?
    let save: (WEObjectTiming?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allDay = true
    @State private var range = false
    @State private var deadline = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var zone = TimeZone.current.identifier
    @State private var explicitlySelected = false
    var body: some View {
        NavigationStack {
            Form {
                Text("Choose the date and timing you know. These are your edits, not booking details inferred by WE.").font(.footnote)
                Toggle("Date only", isOn: $allDay)
                DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: start) { _, _ in explicitlySelected = true; if end < start { end = start } }
                Toggle("Has an end", isOn: $range)
                if range { DatePicker("Ends", selection: $end, in: start..., displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]) }
                if !allDay { TextField("Time zone", text: $zone).textInputAutocapitalization(.never) }
                Toggle("This is a deadline", isOn: $deadline)
                if !explicitlySelected { Toggle("Confirm the date shown above", isOn: $explicitlySelected) }
                Button("Use this timing") {
                    var timing = WEObjectTiming(precision: allDay ? .day : .time, kind: deadline ? .deadline : .occasion)
                    if allDay {
                        timing.startDay = dateString(start); timing.endDay = range ? dateString(end) : nil
                    } else { timing.start = start; timing.end = range ? end : nil; timing.timeZoneID = zone }
                    save(timing); dismiss()
                }.disabled(!explicitlySelected || (!allDay && TimeZone(identifier: zone) == nil))
                Button("Leave timing unresolved") { save(nil); dismiss() }
            }
            .modifier(WEIntelligenceSurfaceStyle())
            .navigationTitle("Review timing")
            .toolbar { Button("Cancel") { dismiss() } }
            .onAppear {
                if let initial, initial.isResolved, let anchor = initial.anchor {
                    allDay = initial.precision == .day; start = anchor
                    end = initial.end ?? WEObjectTiming.day(initial.endDay) ?? anchor
                    range = initial.end != nil || initial.endDay != nil
                    zone = initial.timeZoneID ?? TimeZone.current.identifier
                    deadline = initial.kind == .deadline; explicitlySelected = true
                }
            }
        }
    }
    private func dateString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}

@MainActor final class WEPreviewPublicationBackend: SharePublicationBackend, @unchecked Sendable {
    static let shared = WEPreviewPublicationBackend()
    private var ids: [UUID: UUID] = [:]
    private var sessions: [UUID: UUID] = [:]
    func createSession(for snapshot: FrozenPublicationSnapshot) async throws -> SharePublicationSession {
        let item = ids[snapshot.draftID] ?? UUID(); ids[snapshot.draftID] = item; sessions[snapshot.id] = item
        return .init(id: snapshot.id, uploads: snapshot.resources.map {
            .init(resourceID: $0.id, objectPath: "preview/\(snapshot.id.uuidString.lowercased())/\($0.id.uuidString.lowercased()).\($0.contentType == "image/png" ? "png" : "jpg")", sha256: $0.sha256, contentType: $0.contentType, byteCount: $0.byteCount)
        })
    }
    func upload(_ data: Data, descriptor: SharePublicationUpload) async throws {
        guard ShareCrypto.sha256(data) == descriptor.sha256 else { throw ShareVaultError.invalidDraft }
    }
    func finalize(sessionID: UUID) async throws -> UUID {
        guard let id = sessions[sessionID] else { throw SharePublicationError.invalidReview }; return id
    }
    func retire(sessionID: UUID) async { sessions[sessionID] = nil }
}

/// A small projection of accepted shared timing; this does not create new items
/// or write private ranking signals into shared adaptation.
struct WESharedTimeItems: View {
    @Environment(FieldStore.self) private var field
    @State private var selected: FieldItemReference?
    private var items: [LifeItem] {
        field.intelligenceEligibleLifeItems.filter {
            !$0.isDone && $0.timing != nil && WETimeRelevance.reason(for: $0.objectTiming, now: field.now) != nil
        }.sorted { ($0.objectTiming?.anchor ?? .distantFuture) < ($1.objectTiming?.anchor ?? .distantFuture) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.prefix(4))) { item in
                Button(item.title) { selected = .init(id: item.id) }
                WEPrivacyLabel(text: field.privacyLabel(for: item))
                DisclosureGroup("Why this?") {
                    Text(WETimeRelevance.reason(for: item.objectTiming, now: field.now) ?? "")
                        .font(.footnote)
                }
            }
        }
        .sheet(item: $selected) { FieldItemSheet(itemID: $0.id).environment(field) }
    }
}

/// Keep native forms in the same warm canvas as the Life surface that opens them.
private struct WEIntelligenceSurfaceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(WECanvas.cream.bg)
            .environment(\.weCanvas, .cream)
            .preferredColorScheme(.light)
            .tint(WECanvas.cream.ink)
    }
}
