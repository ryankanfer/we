//
//  WECeremonySessionTests.swift
//  WETests
//
//  Two people, one couple, in one process.
//
//  There is deliberately no API by which a client can read, write, or infer a
//  partner's acknowledgement — that is the whole point of the owner-only RLS
//  and the bare-boolean aggregate. So a test cannot arrange the second person
//  through the thing under test, and the shared state is modelled here
//  instead, exactly where it would come from in life. The same reasoning, and
//  the same shape, as `FieldRESTStub.Store.partnerMarked(_:on:)` in
//  `FieldBackendConformanceTests` and `FieldMemoryBackend.partnerMarkedDays`.
//
//  What this proves without a network: that a beat does not resolve on one
//  phone, that a killed app resumes on the beat it was left on, and that
//  eligibility is a fact of its own rather than something read out of the
//  absence of rows. The literal two-simulator seam is proven in
//  `FieldTwoSimulatorContractTests`, which needs live credentials and runs
//  nightly.
//

import Testing
@testable import WE

// MARK: - The couple, shared between two clients

/// The rows both people write to, and the rules the server applies to them.
private final class FakeCeremonyServer: @unchecked Sendable {
    /// Acknowledgements, by person. Nothing here is reachable from a client
    /// except through the two calls below.
    private var acknowledgements: [String: Set<WEBeat>] = [:]

    /// Live membership, the way `ceremony_beat_is_kept` counts it.
    let members: [String]
    var ceremonyRequired: Bool

    /// Reads and writes the client is allowed to attempt but that fail.
    var failsEverything = false

    init(members: [String], ceremonyRequired: Bool) {
        self.members = members
        self.ceremonyRequired = ceremonyRequired
    }

    func mine(_ person: String) -> Set<WEBeat> {
        acknowledgements[person] ?? []
    }

    func keep(_ beat: WEBeat, as person: String) {
        acknowledgements[person, default: []].insert(beat)
    }

    /// A beat is kept when *every* live member has acknowledged it. The
    /// caller learns one bit and cannot tell "neither of us" from "me and not
    /// them", which is the property the whole design turns on.
    func kept() -> Set<WEBeat> {
        guard !members.isEmpty else { return [] }
        return Set(
            WEBeat.allCases.filter { beat in
                members.allSatisfy { acknowledgements[$0]?.contains(beat) == true }
            }
        )
    }
}

private struct FakeCeremonyError: Error {}

/// One person's phone.
private struct FakeCeremonyClient: WECeremonyBackend {
    let server: FakeCeremonyServer
    let person: String

    func myAcknowledgements() async throws -> Set<WEBeat> {
        if server.failsEverything { throw FakeCeremonyError() }
        return server.mine(person)
    }

    func keptBeats() async throws -> Set<WEBeat> {
        if server.failsEverything { throw FakeCeremonyError() }
        return server.kept()
    }

    func keepBeat(_ beat: WEBeat) async throws {
        if server.failsEverything { throw FakeCeremonyError() }
        server.keep(beat, as: person)
    }

    func ceremonyIsRequired() async throws -> Bool {
        if server.failsEverything { throw FakeCeremonyError() }
        return server.ceremonyRequired
    }
}

private func couple(
    required: Bool
) -> (server: FakeCeremonyServer, ryan: FakeCeremonyClient, dylan: FakeCeremonyClient) {
    let server = FakeCeremonyServer(
        members: ["ryan", "dylan"],
        ceremonyRequired: required
    )
    return (
        server,
        FakeCeremonyClient(server: server, person: "ryan"),
        FakeCeremonyClient(server: server, person: "dylan")
    )
}

// MARK: - Eligibility

@Suite("A couple performs the ceremony only if it is theirs to perform")
@MainActor
struct WECeremonyEligibilityTests {

    /// The regression this whole column exists for.
    ///
    /// A couple who paired before the ceremony existed has no acknowledgement
    /// rows, and neither does a couple who paired a moment ago. If the Promise
    /// were gated on progress alone, every existing couple would be walked
    /// into The Joining on their next launch, months into a relationship.
    @Test("An existing couple never sees it, despite having no rows at all")
    func anExistingCoupleIsLeftAlone() async {
        let (server, ryan, _) = couple(required: false)
        #expect(server.kept().isEmpty, "the premise: nothing has been written")

        let session = WECeremonySession(backend: ryan)
        await session.load()

        #expect(session.phase == .notRequired)
        #expect(!session.phase.presentsPromise)
    }

    @Test("A newly paired couple must perform it")
    func aNewCoupleIsAsked() async {
        let (_, ryan, _) = couple(required: true)

        let session = WECeremonySession(backend: ryan)
        await session.load()

        #expect(session.phase.presentsPromise)
        #expect(session.phase.ceremony?.currentBeat == .yoursStaysYours)
    }

    /// Stated directly rather than left to be implied by the two tests above.
    ///
    /// Both couples here have written nothing, so the *only* thing separating
    /// them is the flag. If eligibility ever starts being inferred from the
    /// rows, these two collapse into the same answer and this fails.
    @Test("Row absence alone does not decide it")
    func absenceOfRowsDecidesNothing() async {
        let (existingServer, existingRyan, _) = couple(required: false)
        let (newServer, newRyan, _) = couple(required: true)

        #expect(existingServer.kept().isEmpty)
        #expect(newServer.kept().isEmpty)

        let existing = WECeremonySession(backend: existingRyan)
        let new = WECeremonySession(backend: newRyan)
        await existing.load()
        await new.load()

        #expect(existing.phase != new.phase, "identical rows, opposite answers")
        #expect(existing.phase == .notRequired)
        #expect(new.phase.presentsPromise)
    }

    /// A couple who performed it does not perform it again on next launch.
    @Test("A finished ceremony resolves to complete, not to beat one")
    func afinishedCeremonyStaysFinished() async {
        let (server, ryan, _) = couple(required: true)
        for beat in WEBeat.allCases {
            server.keep(beat, as: "ryan")
            server.keep(beat, as: "dylan")
        }

        let session = WECeremonySession(backend: ryan)
        await session.load()

        #expect(session.phase == .complete)
        #expect(!session.phase.presentsPromise)
    }
}

// MARK: - Two phones

@Suite("Neither phone can finish alone")
@MainActor
struct WECeremonyTwoPhoneTests {

    /// The ceremony's entire thesis, asserted.
    @Test("One phone giving a beat does not advance either phone")
    func aBeatDoesNotResolveOnOnePhone() async {
        let (_, ryan, dylan) = couple(required: true)
        let ryansPhone = WECeremonySession(backend: ryan)
        let dylansPhone = WECeremonySession(backend: dylan)
        await ryansPhone.load()
        await dylansPhone.load()

        await ryansPhone.keep(.yoursStaysYours)

        // Ryan has given it, so from his phone the beat is held.
        #expect(ryansPhone.phase.ceremony?.state(of: .yoursStaysYours) == .held)
        #expect(ryansPhone.phase.ceremony?.currentBeat == .yoursStaysYours)

        // Dylan re-reads and learns nothing. `waiting` here is the same value
        // he would see if neither of them had acted, which is the point:
        // there is no state on this device for "they have and I have not".
        await dylansPhone.refresh()
        #expect(dylansPhone.phase.ceremony?.state(of: .yoursStaysYours) == .waiting)
        #expect(dylansPhone.phase.ceremony?.currentBeat == .yoursStaysYours)
    }

    @Test("The beat resolves on both phones once both have given it")
    func bothPhonesResolveTogether() async {
        let (_, ryan, dylan) = couple(required: true)
        let ryansPhone = WECeremonySession(backend: ryan)
        let dylansPhone = WECeremonySession(backend: dylan)
        await ryansPhone.load()
        await dylansPhone.load()

        await ryansPhone.keep(.yoursStaysYours)
        await dylansPhone.keep(.yoursStaysYours)
        await ryansPhone.refresh()

        for phone in [ryansPhone, dylansPhone] {
            #expect(phone.phase.ceremony?.state(of: .yoursStaysYours) == .kept)
            #expect(phone.phase.ceremony?.currentBeat == .nothingMovesWithoutYou)
        }
    }

    /// Screen twelve: one person away for a day, the other's phone locked and
    /// relaunched. The beat that was held is the beat that comes back.
    @Test("A relaunched app resumes on the held beat")
    func arelaunchResumesWhereItWasLeft() async {
        let (server, ryan, dylan) = couple(required: true)

        // The first beat is done by both. Ryan has given the second; Dylan
        // has not.
        server.keep(.yoursStaysYours, as: "ryan")
        server.keep(.yoursStaysYours, as: "dylan")
        server.keep(.nothingMovesWithoutYou, as: "ryan")

        // Ryan's phone is killed and started again.
        let relaunched = WECeremonySession(backend: ryan)
        await relaunched.load()

        #expect(relaunched.phase.ceremony?.currentBeat == .nothingMovesWithoutYou)
        #expect(
            relaunched.phase.ceremony?.state(of: .nothingMovesWithoutYou) == .held,
            "his own acknowledgement survived the relaunch"
        )

        // And Dylan, arriving a day later, lands on the same beat without
        // being told anything about when Ryan acted.
        let dylansPhone = WECeremonySession(backend: dylan)
        await dylansPhone.load()
        #expect(dylansPhone.phase.ceremony?.currentBeat == .nothingMovesWithoutYou)
        #expect(dylansPhone.phase.ceremony?.state(of: .nothingMovesWithoutYou) == .waiting)
    }

    /// Nothing a client can call returns the partner's rows, so there is no
    /// way to derive when they acted.
    @Test("A phone cannot read the other person's acknowledgements")
    func onePhoneCannotSeeTheOther() async throws {
        let (server, ryan, _) = couple(required: true)
        server.keep(.yoursStaysYours, as: "dylan")

        #expect(try await ryan.myAcknowledgements().isEmpty)
        #expect(try await ryan.keptBeats().isEmpty)
    }
}

// MARK: - Failure

@Suite("A ceremony that cannot reach the server shows nothing, not the wrong thing")
@MainActor
struct WECeremonyFailureTests {

    @Test("A failed first read stays in loading rather than presenting")
    func afailedLoadPresentsNothing() async {
        let (server, ryan, _) = couple(required: true)
        server.failsEverything = true

        let session = WECeremonySession(backend: ryan)
        await session.load()

        #expect(session.phase == .loading)
        #expect(!session.phase.presentsPromise, "never the Promise on a guess")
    }

    /// The failure that would be worst: a couple who has finished being asked
    /// to start again because a request timed out.
    @Test("A failed read does not un-finish a finished ceremony")
    func afailedRefreshDoesNotReopenIt() async {
        let (server, ryan, _) = couple(required: false)
        let session = WECeremonySession(backend: ryan)
        await session.load()
        #expect(session.phase == .notRequired)

        server.failsEverything = true
        await session.load()

        #expect(session.phase == .notRequired, "held, rather than re-asked")
    }

    /// A dropped write costs a retry and nothing else: the beat stays held,
    /// and `keep_ceremony_beat` is idempotent so the next tick repeats it.
    @Test("A failed give leaves the beat held rather than reverting it")
    func afailedKeepStaysHeld() async {
        let (server, ryan, _) = couple(required: true)
        let session = WECeremonySession(backend: ryan)
        await session.load()

        server.failsEverything = true
        await session.keep(.yoursStaysYours)

        #expect(session.phase.ceremony?.state(of: .yoursStaysYours) == .held)
    }
}
