import SwiftUI

/// Settings and explanations used by a signed-in account. These routes use
/// the same live store as the zones and never construct sample state.
enum FieldAccountSurface: String, Identifiable, CaseIterable {
    case presence = "Presence"
    case moment = "One moment a day"
    case deferral = "What I'm watching"
    case corrections = "What I've changed"
    case seasons = "Past seasons"

    var summary: String {
        switch self {
        case .presence: "Shared away windows and what WE is holding."
        case .moment: "Adjust the time, or skip today’s moment."
        case .deferral: "Review topics WE is waiting to bring up."
        case .corrections: "See how your corrections shape WE’s responses."
        case .seasons: "Revisit the seasons you’ve closed together."
        }
    }

    var canvas: WECanvas { self == .moment ? .ground : .cream }

    var id: String { rawValue }
    var accessibilityID: String {
        switch self {
        case .presence: "presence"
        case .moment: "moment"
        case .deferral: "deferral"
        case .corrections: "corrections"
        case .seasons: "seasons"
        }
    }
}

struct FieldAccountSurfaceView: View {
    let surface: FieldAccountSurface
    @Environment(FieldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch surface {
                case .presence: FieldPresenceView()
                case .moment: FieldDailyMomentView()
                case .deferral: FieldDeferralView(showsDoneButton: false, canvas: .cream)
                case .corrections:
                    ScrollView {
                        FieldCorrectionSummary(showsEmptyState: true).padding(24)
                    }
                case .seasons: FieldPastSeasonsView()
                }
            }
            .font(FieldType.body)
            .foregroundStyle(.fieldInk(.headline))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(surface.canvas.bg)
            .navigationTitle(surface.rawValue)
            .toolbarBackground(surface.canvas.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(surface.canvas == .cream ? .light : .dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("field.account.surface.done")
                }
            }
        }
        .environment(\.weCanvas, surface.canvas)
        .preferredColorScheme(surface.canvas == .cream ? .light : .dark)
        .tint(store.identity.personA.color(on: surface.canvas))
        .presentationBackground(surface.canvas.bg)
        .presentationDragIndicator(.visible)
    }
}

struct FieldCorrectionSummary: View {
    @Environment(FieldStore.self) private var store
    var showsEmptyState = false

    var body: some View {
        if !store.behaviourChanges.isEmpty || showsEmptyState {
            VStack(alignment: .leading, spacing: 12) {
                Text("What I've changed").font(FieldType.weLifeSection)
                    .foregroundStyle(.fieldInk(.headline))
                    .accessibilityAddTraits(.isHeader)
                if store.behaviourChanges.isEmpty {
                    Text("Nothing to report yet. When your corrections change how WE responds, you'll see that here.")
                        .font(FieldType.reasoning)
                        .foregroundStyle(.fieldInk(.reasoning))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(store.behaviourChanges.prefix(3)) { change in
                        Text(change.change).font(FieldType.reasoning)
                            .foregroundStyle(.fieldInk(.reasoning))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("field.us.corrections")
        }
    }
}

struct FieldPastSeasonsView: View {
    @Environment(FieldStore.self) private var store
    private var closed: [FieldSeason] {
        store.state.seasons.filter { !$0.isOpen }.sorted {
            ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast)
        }
    }

    var body: some View {
        List {
            Group {
                if closed.isEmpty {
                    Text("No past seasons yet. When you close a season together, you can return to it here.")
                        .accessibilityIdentifier("field.seasons.empty")
                } else {
                    ForEach(closed) { season in
                        NavigationLink {
                            FieldSeasonClosedView(season: season)
                                .environment(store)
                                .environment(\.weCanvas, WECanvas.ground)
                                .toolbarColorScheme(.dark, for: .navigationBar)
                                .toolbarBackground(WECanvas.ground.bg, for: .navigationBar)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(season.name)
                                Text(season.spanLabel()).font(FieldType.body)
                                    .foregroundStyle(.fieldInk(.metadataProse))
                            }
                        }
                    }
                }
            }
            .listRowBackground(WECanvas.cream.bgElevated)
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("field.seasons")
    }
}
