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

    // MARK: The window
    //
    // `joinCode` is never nil — the column behind it is `not null` — so the
    // code alone cannot say whether there is anything live to send. These
    // pin the field that can.

    @Test
    func aCodeWithNoExpiryIsNotAnInvitation() {
        let couple = Couple(id: "c", joinCode: "WEDEMO")
        #expect(couple.hasLiveInvitation() == false)
    }

    @Test
    func theWindowIsJudgedAgainstTheClockNotTheCode() {
        let now = Date()
        let live = Couple(
            id: "c",
            joinCode: "WEDEMO",
            invitationExpiresAt: now.addingTimeInterval(60)
        )
        let lapsed = Couple(
            id: "c",
            joinCode: "WEDEMO",
            invitationExpiresAt: now.addingTimeInterval(-1)
        )

        #expect(live.hasLiveInvitation(asOf: now))
        #expect(lapsed.hasLiveInvitation(asOf: now) == false)

        // A screen left open across the boundary must stop offering a code
        // that no longer works, so the same value flips on time alone.
        #expect(live.hasLiveInvitation(asOf: now.addingTimeInterval(120)) == false)
    }

    // MARK: Departure

    @Test
    func departureIsOwedOnlyWhenSomebodyLeftAndNobodyWasTold() {
        let neverPaired = Couple(id: "c", joinCode: "WEDEMO")
        #expect(neverPaired.owesDepartureNotice == false)

        let untold = Couple(
            id: "c",
            joinCode: "WEDEMO",
            departedAt: Date()
        )
        #expect(untold.owesDepartureNotice)

        // Both halves are required. `departedAt` alone would raise the
        // surface on every launch for the rest of the account's life.
        let told = Couple(
            id: "c",
            joinCode: "WEDEMO",
            departedAt: Date(),
            departureSeenAt: Date()
        )
        #expect(told.owesDepartureNotice == false)
    }

    // MARK: Decoding
    //
    // Postgres emits `timestamptz` with fractional seconds sometimes and
    // without them others. Guessing one gives a silent nil — which here would
    // read as "there is no invitation" and hide a live code, or as "nobody
    // left" and swallow the one quiet moment.

    @Test
    func coupleTimestampsDecodeWithAndWithoutFractionalSeconds() throws {
        func decode(_ json: String) throws -> CoupleDTO {
            try JSONDecoder().decode(CoupleDTO.self, from: Data(json.utf8))
        }

        let withFraction = try decode(
            """
            {"id":"c","join_code":"WEDEMO",
             "join_code_expires_at":"2026-08-15T10:23:45.123456+00:00",
             "departed_at":null,"departure_seen_at":null}
            """
        )
        #expect(withFraction.invitationExpiry != nil)
        #expect(withFraction.departed == nil)

        let withoutFraction = try decode(
            """
            {"id":"c","join_code":"WEDEMO",
             "join_code_expires_at":"2026-08-15T10:23:45+00:00",
             "departed_at":"2026-08-14T09:00:00+00:00",
             "departure_seen_at":null}
            """
        )
        #expect(withoutFraction.invitationExpiry != nil)
        #expect(withoutFraction.departed != nil)
        #expect(withoutFraction.departureSeen == nil)
    }

    @Test
    func aCoupleStillDecodesWhenTheNewColumnsAreAbsent() throws {
        // An older `select` list, or a cached row written before these
        // columns existed. Decoding must not start failing for that.
        let dto = try JSONDecoder().decode(
            CoupleDTO.self,
            from: Data(#"{"id":"c","join_code":"WEDEMO"}"#.utf8)
        )

        #expect(dto.joinCode == "WEDEMO")
        #expect(dto.invitationExpiry == nil)
        #expect(dto.departed == nil)
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
