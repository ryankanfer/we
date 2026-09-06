//
//  WEArrivalNotificationTests.swift
//  WETests
//
//  The one notification WE sends, and the rule it is sent under.
//
//  The rule is a product-wide one — **WE never sends a notification containing
//  news, only ones inviting presence** — and it is enforceable only if the
//  string, the payload, the table grants and the trigger all stay the shape
//  they were written in. Three of those four are outside Swift, so this suite
//  reads them the way `WECeremonyMigrationTests` reads its migration.
//

import Foundation
import Testing
@testable import WE

private func repositoryFile(_ path: String) -> String {
    // WETests/WEArrivalNotificationTests.swift -> repository root.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(path)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

@Suite("The arrival notification invites presence and reports nothing")
struct WEArrivalNotificationTests {
    private static let worker = repositoryFile(
        "supabase/functions/announce-arrival/index.ts"
    )
    private static let payload = repositoryFile(
        "supabase/functions/announce-arrival/apns.ts"
    )
    private static let migration = repositoryFile(
        "supabase/migrations/20260824140000_arrival_notification.sql"
    )

    @Test func everythingIsWhereItSaysItIs() {
        #expect(!Self.worker.isEmpty)
        #expect(!Self.payload.isEmpty)
        #expect(!Self.migration.isEmpty)
    }

    /// The sentence is sent from a server and written in the app, so it exists
    /// twice. This is what keeps the two from drifting into two different
    /// sentences, one of which nobody has ever read.
    @Test func theServerSendsTheSentenceTheAppDeclares() {
        #expect(
            Self.worker.contains(
                "ARRIVAL_NOTIFICATION = \"\(WEArrivalNotifications.sentence)\""
            ),
            "the worker's sentence is not the app's sentence"
        )
    }

    /// News is a name, a decision, a count, or anything somebody else did.
    /// Presence is an invitation to open the app.
    @Test func theSentenceCarriesNoNews() {
        let sentence = WEArrivalNotifications.sentence
        #expect(sentence.allSatisfy { !$0.isNumber })
        #expect(!sentence.contains("\\("), "nothing is interpolated into it")
        for word in ["Dylan", "Ryan", "partner", "joined", "arrived", "new"] {
            #expect(
                !sentence.lowercased().contains(word.lowercased()),
                "\(word) in \(sentence)"
            )
        }
        // The same rules the gate copy lives under, since this is copy too.
        #expect(!sentence.contains("-"))
        #expect(!sentence.contains("\u{2014}"))
    }

    /// The payload is the sentence and the sentence only.
    ///
    /// No badge — the app never speaks in counts. No sound — WE has none. No
    /// custom keys, because a payload with room in it is a payload somebody
    /// eventually puts news into.
    @Test func thePayloadHasNoRoomInIt() {
        // The line that builds the JSON, and not the prose around it: the
        // comments beside it name the things it deliberately omits.
        let built = Self.payload
            .split(separator: "\n")
            .first { $0.contains("body: JSON.stringify(") }
            .map(String.init) ?? ""
        #expect(built.contains("aps: { alert: { body } }"))
        for key in ["badge", "sound", "mutable-content", "thread", "category"] {
            #expect(!built.contains(key), "\(key) in the payload")
        }
    }

    /// One per space, forever, enforced by the database rather than by a code
    /// path remembering to check.
    @Test func anArrivalIsAnnouncedOncePerSpace() {
        #expect(
            Self.migration.contains(
                "couple_id uuid primary key references public.couples(id)"
            ),
            "the idempotency is the primary key"
        )
        #expect(Self.migration.contains("on conflict (couple_id) do nothing"))
    }

    /// No client can make the other phone speak.
    ///
    /// The only writer is a trigger on `couple_members`, which is to say a
    /// successful redemption. There is no RPC, and the queue is granted to
    /// nobody.
    @Test func onlyRedemptionCanEnqueueAnArrival() {
        #expect(
            Self.migration.contains("after insert on public.couple_members")
        )
        #expect(
            Self.migration.contains(
                "revoke all on public.arrival_notifications from anon, authenticated;"
            )
        )
        #expect(
            !Self.migration.contains(
                "grant execute on function private.enqueue_arrival"
            )
        )
        #expect(
            !Self.migration.contains("grant insert on public.arrival_notifications")
        )
    }

    /// A device belongs to a person, not to a couple.
    ///
    /// Owner only on select, singular, and no insert or update grant at all:
    /// the write goes through an RPC so that `profile_id` is never something a
    /// client chooses.
    @Test func aTokenIsReadableOnlyByItsOwner() {
        let selects = Self.migration.components(
            separatedBy: "on public.device_tokens\n  for select"
        ).count - 1
        #expect(selects == 1, "expected exactly one select policy")
        #expect(
            Self.migration.contains("using (profile_id = (select auth.uid()))")
        )
        #expect(
            Self.migration.contains(
                "revoke insert, update on public.device_tokens from anon, authenticated;"
            )
        )
    }

    /// Marked delivered before it is sent, and never reattempted.
    ///
    /// A worker that sends first announces twice the moment it is interrupted,
    /// and a retry announces yesterday's arrival to a phone that was off,
    /// which is news.
    @Test func nothingIsEverAnnouncedTwiceOrLate() {
        let claim = Self.worker.range(of: "delivered_at: new Date()")
        let send = Self.worker.range(of: "await send(")
        #expect(claim != nil && send != nil)
        if let claim, let send {
            #expect(
                claim.lowerBound < send.lowerBound,
                "the row is claimed before the push is sent"
            )
        }
        #expect(!Self.worker.contains("retry"))
        #expect(!Self.worker.contains("setTimeout"))
    }

    /// The token is written down the way APNs wants it, with no separators and
    /// no capitals.
    @Test func theTokenIsHexadecimal() {
        let token = Data([0x00, 0x0f, 0xa4, 0xff])
        #expect(WEArrivalNotifications.hex(token) == "000fa4ff")
    }
}
