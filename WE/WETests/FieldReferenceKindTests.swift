//
//  FieldReferenceKindTests.swift
//  WETests
//
//  The client and the server have to agree on how a subject is spelled.
//
//  They did not. `refresh_shared_journey_question` wrote `field_question`,
//  `rhythm`, and `ours_item`; `FieldReference.Kind` declared `question` and had
//  no constant for the other two. Three of the five trigger kinds could never
//  resolve, for the whole life of the feature.
//
//  Nothing caught it because an unresolvable reference is dropped without a
//  trace — the same silence that protects a private row. That silence is
//  correct and worth keeping, which is exactly why the agreement has to be
//  proven somewhere other than at runtime.
//
//  This reads the migration rather than restating it. A test that hardcoded
//  the same list twice would agree with itself while both halves drifted.
//

import Foundation
import Testing
@testable import WE

struct FieldReferenceKindTests {
    /// Every literal the migration writes as a `subject_kind`.
    private static func kindsWrittenByTheServer() throws -> Set<String> {
        let migration = try repositoryRoot()
            .appending(path: "supabase/migrations")
            .appending(path: "20260808120000_shared_journeys_v1.sql")
        let sql = try String(contentsOf: migration, encoding: .utf8)

        // The candidate CTE spells the first branch `'horizon'::text as
        // subject_kind` and the union branches as a bare literal in the
        // matching column position. Both forms are picked up by scanning the
        // quoted literal that precedes each scope value.
        var kinds: Set<String> = []
        let pattern = /'([a-z_]+)'(?:::text)?\s+as subject_kind/
        for match in sql.matches(of: pattern) {
            kinds.insert(String(match.1))
        }
        // The union branches omit the alias, so pull them from the shape of
        // the select list: `'<trigger>:' || x.id::text,` then id, then kind.
        let branch = /\|\|\s*[a-z]+\.id::text,\s*\n\s*[a-z]+\.id::text,\s*\n\s*'([a-z_]+)',/
        for match in sql.matches(of: branch) {
            kinds.insert(String(match.1))
        }
        return kinds
    }

    private static func repositoryRoot() throws -> URL {
        // The test bundle lives deep inside DerivedData, so walk up from this
        // file's own location instead.
        var url = URL(filePath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }

    @Test
    func everyServerSubjectKindHasAClientConstant() throws {
        let written = try Self.kindsWrittenByTheServer()
        // Pinned, not merely non-empty. This test reads SQL with a regex, and
        // a reformat that broke the match would otherwise leave it passing
        // over nothing — the vacuous-green failure mode that let the original
        // vocabulary drift survive in the first place.
        #expect(
            written.count == 5,
            "expected 5 server subject kinds, parsed \(written.sorted())"
        )

        let known = Set(FieldReference.Kind.all)
        let unknown = written.subtracting(known)
        #expect(
            unknown.isEmpty,
            "server writes subject kinds the client cannot name: \(unknown.sorted())"
        )
    }

    @Test
    func theTriggerVocabularyIsSpelledExactlyAsTheServerWritesIt() {
        // Pinned individually so a rename on either side reads as a diff on
        // this line rather than as a surface that quietly stops appearing.
        #expect(FieldReference.Kind.fieldQuestion == "field_question")
        #expect(FieldReference.Kind.rhythm == "rhythm")
        #expect(FieldReference.Kind.oursItem == "ours_item")
        #expect(FieldReference.Kind.horizon == "horizon")
        #expect(FieldReference.Kind.cluster == "cluster")
    }
}
