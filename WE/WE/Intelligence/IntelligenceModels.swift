import Foundation

/// Visibility is independent of ownership, category, or navigation destination.
nonisolated enum WEObjectVisibility: String, Codable, Sendable { case onlyMe, shared }

nonisolated struct WEObjectReference: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case artifact, lifeItem, reflection }
    var kind: Kind
    var id: String
}

nonisolated struct WEObjectTiming: Codable, Hashable, Sendable {
    enum Precision: String, Codable, Sendable { case day, time, unresolved }
    enum Kind: String, Codable, Sendable { case occasion, deadline }
    var precision: Precision = .unresolved
    var kind: Kind = .occasion
    /// ISO calendar dates stay dates. They are never converted through UTC midnight.
    var startDay: String?
    var endDay: String?
    var start: Date?
    var end: Date?
    var timeZoneID: String?
    var unresolvedText: String?

    var isResolved: Bool {
        switch precision {
        case .day: return Self.day(startDay) != nil && (endDay == nil || (Self.day(endDay) != nil && Self.day(endDay)! >= Self.day(startDay)!))
        case .time: return start != nil && timeZoneID.flatMap(TimeZone.init(identifier:)) != nil && (end == nil || end! >= start!)
        case .unresolved: return false
        }
    }
    static func day(_ value: String?, calendar: Calendar = .current) -> Date? {
        guard let value, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }
    var anchor: Date? { precision == .day ? Self.day(startDay) : (isResolved ? start : nil) }
    var explanation: String? {
        if precision == .unresolved { return unresolvedText.map { "Timing needs review: \($0)" } }
        if let startDay, precision == .day { return "Date you accepted: \(startDay)" }
        return start.map { "Time you accepted: \($0.formatted())" }
    }
}

protocol WETimeProvider {
    func timing(for reference: WEObjectReference) -> WEObjectTiming?
}

extension LifeItem {
    var objectVisibility: WEObjectVisibility { visibility == .private ? .onlyMe : .shared }
    var privacyLabel: String { objectVisibility == .onlyMe ? "Only me" : "Shared with your partner" }
    var objectTiming: WEObjectTiming? {
        if let timing { return timing }
        if let closesAt { return WEObjectTiming(precision: .time, kind: .deadline, start: closesAt, timeZoneID: TimeZone.current.identifier) }
        guard let dueOn else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: dueOn)
        return WEObjectTiming(precision: .day, startDay: String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
    }
}

nonisolated struct WEExtractionEvidence: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var resourceID: UUID?
    var text: String
    /// Vision's normalized bottom-left coordinate space.
    var bounds: [Double]?
    /// UTF-16 range within the supplied text or recognized image line.
    var textRangeUTF16: [Int]?
}

nonisolated struct WEUnderstandingSuggestion: Codable, Hashable, Sendable, Identifiable {
    enum Field: String, Codable, Sendable { case title, place, category, timing }
    var id: UUID = UUID()
    var field: Field
    var value: String
    var evidenceIDs: [UUID]
    var accepted: Bool = false
}

nonisolated enum WELinkCategory: String, Codable, CaseIterable, Sendable {
    case restaurants, events, realEstate
    var label: String { self == .realEstate ? "real estate" : rawValue }
}

nonisolated struct WEProcessingJob: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable { case pending, processing, completed, failed }
    var id: UUID = UUID()
    var sourceRevision: Int
    var processorVersion = 1
    var state: State = .pending
    var authorizationID: UUID
    var failure: String?
}

nonisolated enum WEPrivateItemKind: String, Codable, CaseIterable, Sendable { case saved, thought, reflection, plan }

nonisolated struct WEArtifactContent: Codable, Hashable, Sendable {
    var kind: WEPrivateItemKind? = .saved
    var completed: Bool?
    var connectedPrivatePlanID: UUID?
    var title: String
    var body = ""
    var category = "saved"
    var place = ""
    var timing: WEObjectTiming?
    var connectedPlanID: String?
    var publishedItemID: String?
    var publishedRevision: Int?
    var revision = 1
    var processingConsent = false
    var authorizationID = UUID()
    var job: WEProcessingJob?
    var evidence: [WEExtractionEvidence] = []
    var suggestions: [WEUnderstandingSuggestion] = []
    var linkCategory: WELinkCategory?
    var explicitLinkGrants: Set<String> = []
    var automaticFetchReason: String?
    var visibilityLabel: String { publishedItemID == nil ? "Only me" : "Original: Only me · Reviewed version: Shared" }
}

nonisolated struct WEArtifactWrite: Codable, Sendable {
    var id = UUID()
    var expectedVersion: Int
    var content: WEArtifactContent
}

nonisolated struct WEArtifactRecord: Codable, Sendable, Identifiable {
    var id: UUID
    var content: WEArtifactContent
    var syncedContent: WEArtifactContent?
    var serverVersion = 0
    var pending: WEArtifactWrite?
    var remoteConflict: WEArtifactContent?
    var conflictVersion: Int?
    var deleted = false
    var deletedPublishedItemID: String?
    var deletionConfirmed = false
    var failure: String?
    var syncLabel: String {
        if deleted { return deletionConfirmed ? "Deleted from WE" : "Deletion pending" }
        if remoteConflict != nil { return "Review conflicting edits" }
        if failure != nil { return "Needs retry" }
        if pending != nil || serverVersion == 0 || syncedContent != content { return "Saved on this phone" }
        return "Synced privately"
    }
}

nonisolated struct WEArtifactLedger: Codable {
    var version = 1
    var localUnderstandingForNewItems: Bool? = false
    var records: [UUID: WEArtifactRecord] = [:]
    var trustedCategories: Set<WELinkCategory> = []
    var dismissedCategories: Set<WELinkCategory> = []
}

extension FieldStore {
    /// New intelligence surfaces fail closed for shared content on an uncertain load.
    var intelligenceEligibleLifeItems: [LifeItem] {
        state.lifeItems.filter { item in
            if item.visibility == .private { return true }
            if case .loaded = loadState { return sharedIntelligenceAuthorized }
            return false
        }
    }
}

extension WELinkCategory {
    static func classify(_ suppliedText: String) -> WELinkCategory? {
        let text = suppliedText.lowercased()
        let matches: [WELinkCategory] = [
            text.contains("restaurant") || text.contains("dinner reservation") ? .restaurants : nil,
            text.contains("event ticket") || text.contains("concert") ? .events : nil,
            text.contains("real estate") || text.contains("property listing") ? .realEstate : nil
        ].compactMap { $0 }
        return matches.count == 1 ? matches[0] : nil
    }
}

extension WEObjectTiming {
    func includes(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard isResolved, let anchor else { return false }
        let first = calendar.startOfDay(for: anchor)
        let last = calendar.startOfDay(for: precision == .day ? (Self.day(endDay) ?? anchor) : (end ?? anchor))
        let day = calendar.startOfDay(for: day)
        return day >= first && day <= last
    }
}


enum WEIntelligenceCapabilities {
    static var enrichmentEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "WEEnrichmentEnabled") as? Bool ?? true }
    static var automaticLinksEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "WEAutomaticLinksEnabled") as? Bool ?? true }
    static var isPreview: Bool {
        AppEnvironment.current.repositoryMode == .preview || FieldEntry.Mode.current != .live
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

struct WESharedEditConflict: Identifiable {
    var id: UUID
    var local: LifeItem
    var remote: LifeItem
}

@MainActor extension FieldStore {
    var intelligencePartnerName: String { speaker == .a ? identity.nameB : identity.nameA }
    func privacyLabel(for item: LifeItem) -> String {
        item.objectVisibility == .onlyMe ? "Only me" : "Shared with \(intelligencePartnerName)"
    }
    func privacyLabel(for content: WEArtifactContent) -> String {
        content.publishedItemID == nil ? "Only me" : "Original: Only me · Reviewed version: Shared with \(intelligencePartnerName)"
    }
}

nonisolated enum WETimeRelevance {
    static func reason(for timing: WEObjectTiming?, now: Date, calendar: Calendar = .current) -> String? {
        guard let timing, timing.isResolved, let anchor = timing.anchor else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: anchor)).day ?? Int.max
        if timing.kind == .deadline && (timing.precision == .day ? days < 0 : anchor < now) && days >= -30 {
            return "A deadline you accepted has passed. Review whether it still needs a next step."
        }
        if timing.includes(now, calendar: calendar) {
            return timing.end != nil || timing.endDay != nil ? "Today falls within the dates you accepted." : "You accepted this date for today."
        }
        if (0...7).contains(days) { return "The date you accepted is coming up within seven days." }
        return nil
    }
}
