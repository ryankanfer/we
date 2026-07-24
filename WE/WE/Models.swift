//
//  Models.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import Foundation

enum MemberHue: String, Codable, Sendable {
    case burgundy
    case sage
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
    let options: [String]
}
