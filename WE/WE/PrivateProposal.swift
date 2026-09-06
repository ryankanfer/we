//
//  PrivateProposal.swift
//  WE
//
//  The private proposal record and its owner-only projection.
//
//  These types used to live in `SoftStartCoordinator.swift`, alongside the
//  pre-account funnel that produced them. That funnel is gone — the signed-out
//  screen is now `WelcomeView` — but the records themselves are a real backend
//  feature: `Repository.claimPrivateProposal` writes them, and `ProfileView`
//  reads them back through `SavedPrivateProposal`. They outlive the screen that
//  first created them, so they live here on their own.
//

import Foundation

nonisolated enum ProposalPreparationMethod: String, Codable, Sendable {
    case onDeviceModel
    case deterministicFallback
}

nonisolated struct OfferedTopic: Codable, Hashable, Sendable {
    let title: String
    let question: String
    let options: [String]
}

nonisolated struct PrivateProposal: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceNote: String
    let title: String
    let offeredTopic: OfferedTopic
    let preparationMethod: ProposalPreparationMethod
    let createdAt: Date

    init(
        id: UUID,
        sourceNote: String,
        title: String,
        offeredTopic: OfferedTopic,
        preparationMethod: ProposalPreparationMethod,
        createdAt: Date
    ) {
        self.id = id
        self.sourceNote = sourceNote
        self.title = title
        self.offeredTopic = offeredTopic
        self.preparationMethod = preparationMethod
        self.createdAt = createdAt
    }
}

/// The owner-only projection of a proposal after it has been claimed by an
/// account. The private source note is deliberately absent so routine reads
/// cannot bring raw private input back into app state.
nonisolated struct SavedPrivateProposal: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let offeredTopic: OfferedTopic
    let preparationMethod: ProposalPreparationMethod
    let preparedAt: String

    init(
        id: String,
        title: String,
        offeredTopic: OfferedTopic,
        preparationMethod: ProposalPreparationMethod,
        preparedAt: String
    ) {
        self.id = id
        self.title = title
        self.offeredTopic = offeredTopic
        self.preparationMethod = preparationMethod
        self.preparedAt = preparedAt
    }

    init(serverID: String, proposal: PrivateProposal) {
        self.init(
            id: serverID,
            title: proposal.title,
            offeredTopic: proposal.offeredTopic,
            preparationMethod: proposal.preparationMethod,
            preparedAt: ISO8601DateFormatter().string(
                from: proposal.createdAt
            )
        )
    }
}
