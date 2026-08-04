//
//  InvitationTests.swift
//  WETests
//
//  The join code, from a link or a keyboard to the moment it is spent.
//
//  The thing worth protecting here is that a typed code and a tapped link
//  produce the same string. Both route through `PendingInvitation.normalized`,
//  and these tests are what keeps a second normalisation from growing back
//  somewhere else.
//

import Foundation
import Testing
@testable import WE

@MainActor
struct InvitationTests {
    /// A defaults suite per test — `PendingInvitation` persists, and tests
    /// that share `.standard` would leak codes into each other.
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "we.tests.\(UUID().uuidString)")!
        return suite
    }

    @Test
    func normalisingStripsCaseAndPunctuationAndCaps() {
        #expect(PendingInvitation.normalized("we-demo") == "WEDEMO")
        #expect(PendingInvitation.normalized("  ab 12  ") == "AB12")
        #expect(PendingInvitation.normalized("WEDEMO") == "WEDEMO")
        #expect(
            PendingInvitation.normalized(String(repeating: "A", count: 40))
                == String(repeating: "A", count: 16)
        )
    }

    @Test
    func normalisingNothingUsableIsNil() {
        #expect(PendingInvitation.normalized("") == nil)
        #expect(PendingInvitation.normalized("---") == nil)
        #expect(PendingInvitation.normalized("   ") == nil)
    }

    @Test
    func aHeldCodeSurvivesANewInstance() {
        let defaults = makeDefaults()

        let holder = PendingInvitation(defaults: defaults)
        holder.hold("we-demo")
        #expect(holder.code == "WEDEMO")

        // The sign-up round trip can outlive the process, which is the whole
        // reason this is not just a property.
        let restored = PendingInvitation(defaults: defaults)
        #expect(restored.code == "WEDEMO")
    }

    @Test
    func clearingRemovesTheCodeEverywhere() {
        let defaults = makeDefaults()

        let holder = PendingInvitation(defaults: defaults)
        holder.hold("WEDEMO")
        holder.clear()

        #expect(holder.code == nil)
        #expect(PendingInvitation(defaults: defaults).code == nil)
    }

    @Test
    func holdingAnUnusableCodeClearsRatherThanHoldingEmpty() {
        let defaults = makeDefaults()
        let holder = PendingInvitation(defaults: defaults)

        holder.hold("WEDEMO")
        holder.hold("!!!")

        // `code != nil` has to mean "there is something to redeem".
        #expect(holder.code == nil)
    }

    @Test
    func joinLinksParseFromPathAndQuery() {
        #expect(
            WEDeepLinkRouter.destination(for: URL(string: "we://join/we-demo")!)
                == .join(code: "WEDEMO")
        )
        #expect(
            WEDeepLinkRouter.destination(
                for: URL(string: "we://join?code=wedemo")!
            ) == .join(code: "WEDEMO")
        )
    }

    @Test
    func linksThatAreNotInvitationsAreLeftAlone() {
        #expect(
            WEDeepLinkRouter.destination(for: URL(string: "we://today")!)
                == .today
        )
        // A join link with no usable code is not a join link.
        #expect(
            WEDeepLinkRouter.destination(for: URL(string: "we://join")!) == nil
        )
        // Auth callbacks must fall through to the session's handler.
        #expect(
            WEDeepLinkRouter.destination(
                for: URL(string: "we://auth-callback#access_token=abc")!
            ) == nil
        )
        #expect(
            WEDeepLinkRouter.destination(
                for: URL(string: "https://example.com/join/WEDEMO")!
            ) == nil
        )
    }

    @Test
    func handleDoesNotClaimJoinLinks() {
        // `.join` mutates main-actor state the app owns, so `WEApp.open`
        // handles it before the router is consulted. If `handle` ever starts
        // returning true here, the code would be silently dropped.
        #expect(
            WEDeepLinkRouter.handle(URL(string: "we://join/WEDEMO")!) == false
        )
        #expect(WEDeepLinkRouter.handle(URL(string: "we://today")!) == true)
    }
}
