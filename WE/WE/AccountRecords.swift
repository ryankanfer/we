//
//  AccountRecords.swift
//  WE
//
//  What an account can look back on: a relationship that ended, read-only,
//  and proposals saved before the account existed. Opened from Account.
//

import SwiftUI

struct SavedPrivateProposalView: View {
    let proposal: SavedPrivateProposal

    var body: some View {
        ZStack {
            WEJourneyBackdrop(state: .privateState)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("ONLY ON YOUR SIDE", systemImage: "lock.fill")
                        .font(.weCaption)
                        .tracking(1.6)
                        .foregroundStyle(Color.wePearl.opacity(0.64))

                    Text(proposal.title)
                        .font(.weLargeTitle)
                        .foregroundStyle(Color.wePearl)

                    WEContinuityLine(state: .privateState)
                        .frame(height: 52)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("IF YOU CHOOSE TO OFFER")
                            .font(.weCaption)
                            .tracking(1.4)
                            .foregroundStyle(Color.wePearl.opacity(0.58))
                        Text(proposal.offeredTopic.title)
                            .font(.weTitle)
                            .foregroundStyle(Color.wePearl)
                        Text(proposal.offeredTopic.question)
                            .font(.weBody)
                            .foregroundStyle(Color.wePearl.opacity(0.76))
                        Text(
                            proposal.offeredTopic.options.joined(
                                separator: " · "
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.wePearl.opacity(0.62))
                    }
                    .padding(18)
                    .background(
                        Color.white.opacity(0.07),
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.weChampagne)
                            .frame(width: 1)
                    }

                    Label(
                        "Prepared on this iPhone and kept in owner-only storage",
                        systemImage: "iphone.gen3"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.wePearl.opacity(0.64))

                    Text(
                        "The original note is not returned to this screen. Nothing here crosses unless you separately approve an offer."
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.wePearl.opacity(0.64))
                }
                .frame(maxWidth: 430, alignment: .leading)
                .padding(26)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Private proposal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RelationshipArchiveView: View {
    let archive: RelationshipArchive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Read-only", systemImage: "lock.fill")
                    Text("This archive contains only things that were genuinely shared. Private reflections, answers, and plan approaches were excluded.")
                        .foregroundStyle(.secondary)
                }
                if !archive.snapshot.plans.isEmpty {
                    Section("Plans") {
                        ForEach(archive.snapshot.plans) { item in
                            ArchiveRow(title: item.title, detail: item.note)
                        }
                    }
                }
                if !archive.snapshot.responsibilities.isEmpty {
                    Section("Responsibilities") {
                        ForEach(archive.snapshot.responsibilities) { item in
                            ArchiveRow(title: item.title, detail: item.ownership.title)
                        }
                    }
                }
                if !archive.snapshot.resolutions.isEmpty {
                    Section("Mutual resolutions") {
                        ForEach(archive.snapshot.resolutions) { item in
                            ArchiveRow(title: item.title, detail: item.resolutionChoice ?? item.resolutionType.label)
                        }
                    }
                }
                if !archive.snapshot.anchors.isEmpty {
                    Section("Anchors") {
                        ForEach(archive.snapshot.anchors) { anchor in
                            ArchiveRow(
                                title: anchor.title,
                                detail: anchor.note
                            )
                        }
                    }
                }
                if !archive.snapshot.events.isEmpty {
                    Section("Thread") {
                        ForEach(archive.snapshot.events) { event in
                            ArchiveRow(
                                title: event.title,
                                detail: event.type.title
                            )
                        }
                    }
                }
                if !archive.snapshot.seasons.isEmpty {
                    Section("Seasons") {
                        ForEach(archive.snapshot.seasons) { season in
                            ArchiveRow(
                                title: season.title,
                                detail: season.summary
                            )
                        }
                    }
                }
                if !archive.snapshot.handoffs.isEmpty {
                    Section("Handoffs") {
                        ForEach(archive.snapshot.handoffs) { handoff in
                            ArchiveRow(
                                title: responsibilityTitle(
                                    handoff.responsibilityID
                                ),
                                detail: handoff.status.rawValue.capitalized
                            )
                        }
                    }
                }
                if isEmpty {
                    ContentUnavailableView("Nothing was archived", systemImage: "archivebox", description: Text("There were no completed shared records to retain."))
                }
            }
            .navigationTitle("Relationship archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var isEmpty: Bool {
        archive.snapshot.plans.isEmpty
            && archive.snapshot.responsibilities.isEmpty
            && archive.snapshot.resolutions.isEmpty
            && archive.snapshot.anchors.isEmpty
            && archive.snapshot.events.isEmpty
            && archive.snapshot.seasons.isEmpty
            && archive.snapshot.handoffs.isEmpty
    }

    private func responsibilityTitle(_ id: String) -> String {
        archive.snapshot.responsibilities.first {
            $0.id == id
        }?.title ?? "Shared care"
    }
}

private struct ArchiveRow: View {
    let title: String
    let detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let detail, !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

enum ArchiveDate {
    static func display(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "Past" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension ResolutionType {
    var label: String {
        switch self { case .settled: "Settled"; case .released: "Released"; case .leftOpen: "Left open" }
    }
}
