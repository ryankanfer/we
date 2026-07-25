//
//  Models.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import Foundation

struct AuthenticatedUser: Identifiable, Hashable, Sendable {
    let id: String
    let email: String
}

struct Profile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

struct Couple: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let joinCode: String
}

enum MemberHue: String, Codable, Sendable {
    case burgundy
    case sage
}

struct Membership: Codable, Hashable, Sendable {
    let coupleID: String
    let profileID: String
    let hue: MemberHue
}

struct Member: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let hue: MemberHue
}

enum InsightKind: String, Codable, Sendable {
    case logistical
    case relational
    case unresolved
}

enum InsightDomain: String, Codable, Sendable {
    case life
    case us
}

struct Insight: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: InsightKind
    let domain: InsightDomain
    let present: Bool
    let title: String
    let body: String
    let evidence: String
    let source: String
    let actionTitle: String
    let options: [String]
}

enum ConsentVisibility: String, Codable, Sendable {
    case `private`
    case shared
    case mutual
}

enum ConsentReadiness: String, Codable, Sendable {
    case idle
    case requested
    case accepted
    case declined
    case withdrawn
}

enum ResolutionType: String, Codable, Sendable {
    case settled
    case released
    case leftOpen
}

struct InsightConsent: Codable, Hashable, Sendable {
    let insightID: String
    let visibility: ConsentVisibility
    let ownerID: String?
    let readiness: ConsentReadiness
    let initiatorID: String?
    let requestedAt: String?
    let acceptedAt: String?
    let resolutionType: ResolutionType?
    let resolutionChoice: String?
}

enum ResponseStatus: String, Codable, Sendable {
    case none
    case draft
    case submitted
    case revealed
}

struct InsightResponse: Codable, Hashable, Sendable {
    let insightID: String
    let profileID: String
    let status: ResponseStatus
    let choice: String?
    let note: String?
}

enum ReflectionKind: String, Codable, Sendable {
    case reflection
    case suggestion
}

struct Reflection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let coupleID: String
    let ownerID: String
    let domain: InsightDomain
    let kind: ReflectionKind
    let text: String
}

struct InsightRecord: Identifiable, Hashable, Sendable {
    let insight: Insight
    let consent: InsightConsent?
    let responses: [InsightResponse]

    var id: String { insight.id }
}

struct RelationshipSnapshot: Hashable, Sendable {
    let profile: Profile
    let membership: Membership?
    let couple: Couple?
    let members: [Member]
    let insights: [InsightRecord]
    let reflections: [Reflection]
}
