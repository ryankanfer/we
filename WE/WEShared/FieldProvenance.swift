//
//  FieldProvenance.swift
//  WE
//
//  What brought this here.
//
//  Every derivation in FieldIntelligence already returns a reason string —
//  "A result without a reason is a bug, not a shortcut." That sentence covers
//  prose. It does not cover proof.
//
//  A reason says *why* in the app's own voice. Provenance adds *which records*,
//  so a person can open the explanation and land on the actual things they
//  wrote. That distinction matters most where a surface appeared on its own:
//  an adaptive view that cannot name its sources is asking to be trusted, and
//  this product does not ask.
//
//  Provenance wraps a reason rather than replacing it. Existing callers keep
//  passing a `String` to FieldReasoning and nothing about their rendering
//  changes; surfaces that can prove themselves carry the sources alongside.
//

import Foundation

/// A reason, and the records it was read from.
nonisolated struct FieldProvenance: Hashable, Sendable {
    /// The existing prose line. Rendered by `FieldReasoning` exactly as before.
    let reason: String

    /// The exact records the reason was derived from, in the order a reader
    /// should meet them. May be empty: some reasons are about the clock or an
    /// absence, and inventing a source for those would be worse than none.
    let sources: [FieldReference]

    init(reason: String, sources: [FieldReference] = []) {
        self.reason = reason
        self.sources = sources
    }

    /// Whether a "What brought this here" control should be offered at all.
    ///
    /// A disclosure that opens onto nothing teaches the opposite of what it is
    /// for, so the control is absent rather than empty.
    var isProvable: Bool { !sources.isEmpty }
}
