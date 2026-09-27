import Foundation
import NaturalLanguage

enum FieldGoalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case trip = "Trip", savings = "Savings", readiness = "Life change", other = "Something else"
    var id: String { rawValue }
}
struct FieldGoalMilestone: Codable, Hashable, Identifiable, Sendable {
    var id = UUID().uuidString
    var title: String
    var done = false
}
struct FieldGoalPlan: Codable, Hashable, Sendable {
    var revision = UUID().uuidString
    var kind: FieldGoalKind = .other
    var target: Double = 0
    var saved: Double = 0
    var currency = "USD"
    var milestones: [FieldGoalMilestone] = []
    var notes = ""
    // Loaded from authenticated approval rows, never written as plan metadata.
    var approvedOwners: [FieldOwner] = []
    var isBuilding: Bool { Set(approvedOwners).contains(.a) && Set(approvedOwners).contains(.b) }
    var valid: Bool { target.isFinite && saved.isFinite && target >= 0 && saved >= 0 && notes.count <= 8000 && milestones.count <= 40 }
}
struct FieldGoalSuggestion: Identifiable {
    var id: String
    var title: String
    var kind: FieldGoalKind
    var items: [LifeItem]
    var existingGoalID: String?
}

enum FieldGoalSuggestions {
    static func suggestions(items: [LifeItem], goals: [FieldHorizon]) -> [FieldGoalSuggestion] {
        // Private items are removed before any language analysis takes place.
        let shared = items.filter { $0.isSharedPresence && !$0.isDone && !$0.id.hasPrefix("cal:") }
        var buckets: [String: [LifeItem]] = [:]
        var seen = Set<String>()
        for item in shared {
            let normalized = item.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
            guard seen.insert(normalized).inserted else { continue }
            for key in topics(item.title + " " + (item.detail ?? ""), category: item.category) {
                buckets[key, default: []].append(item)
            }
        }
        return buckets.compactMap { key, evidence in
            guard evidence.count >= 3 else { return nil }
            let existing = goals.first { topics($0.title, category: .trips).contains(key) }
            let newItems = evidence.filter { !(existing?.linkedLifeItemIDs.contains($0.id) ?? false) }
            guard !newItems.isEmpty else { return nil }
            let kind: FieldGoalKind = key == "a home of our own" ? .savings : key == "getting a dog" ? .readiness : .trip
            let title = key == "a home of our own" || key == "getting a dog" ? key.prefix(1).uppercased() + key.dropFirst() : key.capitalized + " trip"
            return FieldGoalSuggestion(id: key, title: title, kind: kind, items: newItems, existingGoalID: existing?.id)
        }.sorted { $0.items.count == $1.items.count ? $0.id < $1.id : $0.items.count > $1.items.count }
    }

    static func topics(_ text: String, category: LifeCategory) -> Set<String> {
        let lower = text.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        // Clear negative intent is not positive evidence for a goal.
        guard !["don't want", "do not want", "don’t want", "not going", "not ready", "can’t go", "cannot go", "not interested", "cancelled", "canceled"].contains(where: lower.contains) else { return [] }
        if !words.isDisjoint(with: ["dog", "puppy", "puppies"]) && ["get a", "getting a", "adopt", "ready for", "want a", "would love a", "planning for"].contains(where: lower.contains) { return ["getting a dog"] }
        if lower.contains("a home of our own") || lower.contains("down payment") || lower.contains("buy a home") || lower.contains("buying a home") { return ["a home of our own"] }
        guard category == .trips || !words.isDisjoint(with: ["trip", "travel", "visit", "going", "go", "holiday", "vacation", "flights", "hotel"]) else { return [] }
        var places = Set<String>()
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .placeName { places.insert(String(text[range]).lowercased()) }
            return true
        }
        // Keep common destination aliases together even without a language model asset.
        if !words.isDisjoint(with: ["japan", "tokyo", "kyoto", "osaka"]) {
            places.subtract(["tokyo", "kyoto", "osaka"])
            places.insert("japan")
        }
        return places
    }
}
