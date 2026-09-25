//
//  WELexiconTests.swift
//  WETests
//
//  One word per idea, and the retired ones stay retired.
//
//  The app was confusing partly because it had more words than things: Yours
//  was a place, Us was a place, "WE" was the app, a tab and a button, and a
//  private thing was "Only Me", "Your side", "Your space" or "Just me"
//  depending on the screen. The simplification settled the words:
//
//    Today · + · Life     the two places, and the way in
//    Where we're headed   goals, at the top of Life
//    Decide on this together   a shared decision
//    Only me              anything private
//    What WE may notice   the consent toggles
//    Put away             hidden but kept
//
//  This reads the app's Swift sources and fails if a retired phrase appears
//  inside a string literal — which is where on-screen words live. Comments
//  are skipped: explaining why a word was retired has to be allowed to name
//  it. Code identifiers are not strings, so a type called `FieldUsField` is
//  not a violation; a label reading "Us" would be.
//
//  "Yours stays yours." is allowed on purpose. It is a line of the Promise
//  and still true — privacy survived Yours — and its beat id is a database
//  value. What is banned is Yours as a *place*.
//

import Foundation
import Testing

@Suite("One word per idea")
struct WELexiconTests {
    /// Retired phrases, and what replaced each. Case-sensitive: "Only Me"
    /// is banned, "Only me" is the word.
    static let retired: [(phrase: String, instead: String)] = [
        ("Only Me", "Only me"),
        ("Just me", "Only me"),
        ("Your side", "Only me, or your account"),
        ("Your space", "a plain description"),
        ("YOURS", "Only me — Yours is not a place any more"),
        ("Open Yours", "Only me"),
        ("in Yours", "Only me"),
        ("Choose yours", "nothing — colour choice is gone"),
        ("OPEN US", "OPEN"),
        ("Life or Us", "Life"),
        ("Next: Us", "Next: Where we're headed"),
        ("Discuss this together", "Decide on this together"),
        ("Tell WE anything", "Say something"),
        ("TELL WE ANYTHING", "Say something"),
        ("When WE interrupts", "What WE may notice"),
        ("Private intake", "From elsewhere"),
        ("In this room", "In {group}"),
        ("Set down", "Put away"),
        ("Chat stays", "Decide on this together"),
    ]

    /// Bare labels that used to name a place, matched as the whole literal.
    static let retiredLabels: Set<String> = ["US", "Us", "YOURS", "Yours", "NOW", "Chat"]

    /// The app's sources, found relative to this file.
    static func appSources() throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WETests
            .deletingLastPathComponent()   // WE
            .appendingPathComponent("WE")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Every string literal on every non-comment line.
    static func literals(in text: String) -> [(line: Int, value: String)] {
        let pattern = try! NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#)
        var found: [(Int, String)] = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//") else { continue }
            let range = NSRange(raw.startIndex..., in: raw)
            for match in pattern.matches(in: raw, range: range) {
                if let r = Range(match.range(at: 1), in: raw) {
                    found.append((index + 1, String(raw[r])))
                }
            }
        }
        return found
    }

    @Test
    func noRetiredPhraseIsOnScreen() throws {
        let sources = try Self.appSources()
        #expect(sources.count > 50, "found \(sources.count) sources — the path is wrong")

        var violations: [String] = []
        for (path, text) in sources {
            for (line, value) in Self.literals(in: text) {
                for (phrase, instead) in Self.retired where value.contains(phrase) {
                    violations.append("\(path):\(line) \"\(value)\" — use \(instead)")
                }
                if Self.retiredLabels.contains(value) {
                    violations.append("\(path):\(line) \"\(value)\" — a retired place name")
                }
            }
        }
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }

    /// The scanner itself: it must catch a banned phrase and ignore comments,
    /// or a green result means nothing.
    @Test
    func theScannerCatchesALiteralAndIgnoresAComment() {
        let sample = """
        // Yours used to be a place; "Only Me" was its label.
        Text("Only Me")
        Label("US", systemImage: "circle")
        """
        let values = Self.literals(in: sample).map(\.value)
        #expect(values == ["Only Me", "US", "circle"])
        #expect(Self.retired.contains { values[0].contains($0.phrase) })
        #expect(Self.retiredLabels.contains(values[1]))
    }
}
