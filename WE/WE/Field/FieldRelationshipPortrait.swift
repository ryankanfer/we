import SwiftUI

struct FieldPortraitConcept: Identifiable {
    enum Territory { case emerging, established }
    var id: String
    var title: String
    var territory: Territory
    var significance: Double
    var evidence: [String]
    var itemIDs: [String]
}

@MainActor enum FieldRelationshipPortrait {
    private static let generic: Set<String> = ["meeting", "dinner", "work", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "notes", "saved"]
    static func concepts(in state: FieldState, now: Date) -> [FieldPortraitConcept] {
        let mentions = FieldUsMentions.mentions(in: state)
        var result = mentions.compactMap { mention -> FieldPortraitConcept? in
            guard !generic.contains(mention.text.lowercased()), mention.text.count <= 48 else { return nil }
            let title = mention.text.hasPrefix("The ") ? String(mention.text.dropFirst(4)) : mention.text
            let established = mention.kind == .anchor || (mention.kind == .rhythm && mention.weight >= 3)
            let rhythm = state.rhythms.first { "rhythm-" + $0.id == mention.id }
            let recent = rhythm?.lastOccurred.map { now.timeIntervalSince($0) <= 30 * 86400 } == true
            let ids = state.horizons.first { "horizon-" + $0.id == mention.id }?.linkedLifeItemIDs ?? []
            let sharedIDs = ids.filter { id in state.lifeItems.contains { $0.id == id && $0.isSharedPresence } }
            return .init(id: mention.id, title: title.trimmingCharacters(in: .punctuationCharacters), territory: established ? .established : .emerging,
                significance: log2(Double(max(0, mention.weight)) + 1) + (established ? 2 : 0) + (recent ? 0.5 : 0),
                evidence: mention.support.isEmpty ? ["A shared possibility you saved."] : mention.support,
                itemIDs: sharedIDs)
        }
        var titles = Set(result.map { $0.title.lowercased() })
        for item in state.lifeItems.filter({ $0.isSharedPresence && !$0.isDone && (FieldItemPurpose.resolve($0) != .task || $0.category == .trips || $0.timing != nil) }).sorted(by: { $0.id < $1.id }) {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstWord = title.lowercased().split(separator: " ").first.map(String.init) ?? ""
            guard !["send", "call", "clear", "decide", "pay", "buy"].contains(firstWord), title.count >= 3, title.count <= 48, !generic.contains(title.lowercased()), titles.insert(title.lowercased()).inserted else { continue }
            result.append(.init(id: "life-" + item.id, title: title, territory: .emerging,
                significance: item.objectTiming?.includes(now) == true ? 1.5 : 1,
                evidence: ["An open idea or plan saved in your shared Life.", item.detail].compactMap { $0 }, itemIDs: [item.id]))
        }
        return Array(result.sorted { $0.significance == $1.significance ? $0.title < $1.title : $0.significance > $1.significance }.prefix(16))
    }
}

struct FieldRelationshipPortraitSurface: View {
    @Environment(FieldStore.self) private var store
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var leadSize = 58.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: FieldPortraitConcept?
    @State private var goals = false
    @State private var opened: FieldItemReference?
    private var concepts: [FieldPortraitConcept] {
        guard WEIntelligenceCapabilities.isPreview || store.sharedIntelligenceAuthorized,
              !session.v2State.signalConsents.contains(where: { $0.signal == .sharedPlans && !$0.isEnabled }) else { return [] }
        var permitted = store.state
        permitted.lifeItems = (WEIntelligenceCapabilities.isPreview ? store.state.lifeItems : store.intelligenceEligibleLifeItems).filter(\.isSharedPresence)
        return FieldRelationshipPortrait.concepts(in: permitted, now: store.now)
    }
    var body: some View {
        FieldZoneScaffold(zone: .us, showsZoneLabel: false) {
            VStack(spacing: 22) {
                HStack {
                    Text("Us").font(FieldType.hero).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Our goals") { goals = true }.font(.subheadline).frame(minHeight: 44)
                        .accessibilityIdentifier("field.us.goals")
                }
                if concepts.isEmpty {
                    VStack(spacing: 24) {
                        Text("Us starts taking shape as you build a shared world.")
                            .font(.system(.title, design: .serif)).multilineTextAlignment(.center)
                        Button("Save something to do together") { store.go(to: .life) }
                        Button("Explore a goal") { goals = true }
                    }.padding(.vertical, 50).accessibilityIdentifier("field.us.portrait.empty")
                } else {
                    territory("SO US", concepts.filter { $0.territory == .established })
                    Rectangle().fill(WECanvas.cream.ink.opacity(0.15)).frame(height: 0.5).padding(.horizontal, 45)
                    territory("NEW TO US", concepts.filter { $0.territory == .emerging })
                }
            }.foregroundStyle(.fieldInk(.headline))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: concepts.map(\.id))
        }
        .accessibilityIdentifier("field.us.portrait")
        .onChange(of: concepts.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected.id) { self.selected = nil }
        }
        .sheet(item: $selected) { concept in
            NavigationStack {
                List {
                    Section {
                        Text(concept.title).font(.system(.largeTitle, design: .serif))
                        Text(concept.territory == .established ? "A shared agreement or recurring rhythm." : "Something entering your shared world.")
                        Text("Shared with \(store.intelligencePartnerName)").font(.caption)
                    }
                    Section("What connects it") {
                        ForEach(Array(concept.evidence.enumerated()), id: \.offset) { _, evidence in Text(evidence) }
                        ForEach(concept.itemIDs, id: \.self) { id in
                            if let item = store.intelligenceEligibleLifeItems.first(where: { $0.id == id }) {
                                Button("Open \(item.title)") { opened = .init(id: id) }
                            }
                        }
                    }
                    Section { Text("Prominence reflects shared agreements, recurring activity, connections, and known timing. WE does not infer how you feel.").font(.footnote) }
                }
                .toolbar { Button("Done") { selected = nil } }
                .sheet(item: $opened) { FieldItemSheet(itemID: $0.id).environment(store) }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $goals) {
            NavigationStack {
                FieldGoalsSurface().environment(store).environmentObject(session)
                    .toolbar { Button("Done") { goals = false } }
            }
        }
    }
    private func territory(_ label: String, _ words: [FieldPortraitConcept]) -> some View {
        VStack(spacing: 18) {
            Text(label).font(.caption).tracking(3).foregroundStyle(.fieldInk(.reasoning)).accessibilityAddTraits(.isHeader)
            if words.isEmpty {
                Text("Still taking shape.").font(.system(.title3, design: .serif)).foregroundStyle(.fieldInk(.reasoning))
            } else {
                ForEach(Array(words.prefix(2).enumerated()), id: \.element.id) { index, word in
                    wordButton(word, prominent: index == 0)
                }
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 16) {
                        ForEach(Array(words.dropFirst(2))) { word in
                            wordButton(word, prominent: false)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    FieldFlowLayout(spacing: 18, lineSpacing: 12) {
                        ForEach(Array(words.dropFirst(2))) { word in wordButton(word, prominent: false) }
                    }
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
    }
    private func wordButton(_ word: FieldPortraitConcept, prominent: Bool) -> some View {
        Button { selected = word } label: {
            Text(word.title).font(typeSize.isAccessibilitySize ? .system(.title2, design: .serif) : prominent ? .system(size: word.title.count > 16 ? leadSize * 0.72 : leadSize, design: .serif) : .system(.title2, design: .serif))
                .fontWeight(.regular).multilineTextAlignment(.center)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.6)
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityHint("Explore the shared evidence behind this concept")
            .accessibilityIdentifier("field.us.concept.\(word.id)")
    }
}

struct FieldCaptureCompletion: Equatable {
    let text: String
    let reason: String
    static func match(_ input: String, titles: [String]) -> Self? {
        guard input.count >= 3, input == input.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let matches = Set(titles).filter { $0.count <= 240 && $0.count > input.count && $0.lowercased().hasPrefix(input.lowercased()) }
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        guard let text = matches.first else { return nil }
        return .init(text: input + text.dropFirst(input.count), reason: "From a title already saved in your shared Life.")
    }
}
