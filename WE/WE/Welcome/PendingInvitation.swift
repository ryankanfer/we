//
//  PendingInvitation.swift
//  WE
//
//  A join code, held from before there is an account until there is a session
//  to spend it on.
//
//  `WelcomeView` can collect a code from someone who has no account at all, and
//  `joinCouple(code:)` needs a session — so the code has to wait. It cannot wait
//  in memory: `signUp` may land in `.verificationPending`, which means an email
//  round trip, which means the process can die in between. So it waits in
//  `UserDefaults`.
//
//  Normalisation lives here and only here. Both the text field in
//  `JoinWithCodeView` and the `we://join/CODE` deep link route through `hold`,
//  so a typed code and a tapped link can never disagree about what a code is.
//

import Foundation
import Combine

@MainActor
final class PendingInvitation: ObservableObject {
    /// Uppercase, alphanumeric, at most 16 characters — or nil.
    @Published private(set) var code: String?

    static let defaultsKey = "we.pendingInvitationCode"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        code = defaults.string(forKey: Self.defaultsKey)
            .flatMap(Self.normalized)
    }

    /// Trims the code to what the backend accepts and holds it. A code that
    /// normalises to nothing clears the hold rather than storing an empty
    /// string, so `code != nil` always means "there is something to redeem".
    func hold(_ rawCode: String) {
        guard let normalized = Self.normalized(rawCode) else {
            clear()
            return
        }
        code = normalized
        defaults.set(normalized, forKey: Self.defaultsKey)
    }

    func clear() {
        code = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// The single definition of a join code's shape, matched to the field in
    /// `PairingView` that has always done this inline.
    nonisolated static func normalized(_ rawCode: String) -> String? {
        let value = String(
            rawCode
                .uppercased()
                .filter { $0.isLetter || $0.isNumber }
                .prefix(16)
        )
        return value.isEmpty ? nil : value
    }
}
