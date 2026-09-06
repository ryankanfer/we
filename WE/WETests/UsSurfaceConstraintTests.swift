//
//  UsSurfaceConstraintTests.swift
//  WETests
//
//  Phase one of "Type Holds the Room", asserted rather than remembered.
//
//  Two of these read the source rather than the running app. That is
//  deliberate: "renders no eyebrow label" is a claim about what the file is
//  allowed to contain, and the cheapest honest way to hold a deletion in place
//  is to fail the build when it comes back. `FieldConstraintTests` does the
//  same job with `Mirror` for state; a view hierarchy has no equivalent.
//

import SwiftUI
import Testing
@testable import WE

@Suite("Us holds the room")
struct UsSurfaceConstraintTests {
    /// The Field sources, found relative to this file.
    private static func source(_ name: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let field = here
            .deletingLastPathComponent()   // WETests
            .deletingLastPathComponent()   // WE
            .appendingPathComponent("WE/Field/\(name)")
        return try String(contentsOf: field, encoding: .utf8)
    }

    private static let usSurfaces = [
        "FieldUsZone.swift",
        "FieldJourneyUsZone.swift",
    ]

    /// Rule four: no eyebrow labels. No tracked uppercase category headers.
    ///
    /// `FieldLabel` is the app's most repeated device and the other half of the
    /// robotic feel, independent of wording. Us is the first zone off it.
    @Test("Neither Us surface renders an eyebrow label")
    func usHasNoEyebrows() throws {
        for file in Self.usSurfaces {
            #expect(
                try !Self.source(file).contains("FieldLabel("),
                "\(file) reintroduced an eyebrow label"
            )
        }
    }

    /// "Choices are plain text with restrained colour traces, never poll
    /// buttons." The outlined style draws the two rectangles the approved
    /// mockup used and the direction bans.
    @Test("Us offers its choices as sentences, not boxes")
    func usHasNoPollButtons() throws {
        for file in Self.usSurfaces {
            #expect(
                try !Self.source(file).contains("FieldOutlinedButtonStyle"),
                "\(file) reintroduced a boxed choice"
            )
        }
    }

    /// The horizon is the thing the page is about. A year set in the same
    /// display size competes with it, and the decision loses.
    @Test("The primary horizon carries no numerals in its own voice")
    func primaryHorizonIsProse() {
        let horizon = FieldSampleData.horizons.first { $0.isPrimary }
        let thesis = horizon?.thesis ?? ""
        #expect(!thesis.isEmpty)
        #expect(
            thesis.rangeOfCharacter(from: .decimalDigits) == nil,
            "the horizon thesis reads as telemetry: \(thesis)"
        )
    }
}

@Suite("The colour field says nothing about timing")
struct WEColourFieldStateTests {
    /// Both ceremony states are moments rather than conditions. They play once
    /// and settle back into the shared field, so a beat held for an hour looks
    /// exactly like a beat held for a second, and the third beat is lit the
    /// same as the first.
    @Test("The two ceremony states settle back into the shared field")
    func ceremonyStatesAreTransient() {
        #expect(WEColourFieldState.oneActed(.a).settled == .shared)
        #expect(WEColourFieldState.bothLanded.settled == .shared)
        #expect(WEColourFieldState.oneActed(.a).showsBothHues)
        #expect(!WEColourFieldState.oneActed(.a).isStill)
    }

    /// The strengthening names exactly one person, and every other state names
    /// nobody. A field that could strengthen on its own would be reporting the
    /// other person's timing, which is the thing this type exists to prevent.
    @Test("Only one state strengthens a hue, and only the one it names")
    func strengtheningIsNamedAndRare() {
        #expect(WEColourFieldState.oneActed(.a).strengthens == .a)
        #expect(WEColourFieldState.oneActed(.b).strengthens == .b)
        #expect(WEColourFieldState.shared.strengthens == nil)
        #expect(WEColourFieldState.bothLanded.strengthens == nil)
        #expect(WEColourFieldState.mine(.a).strengthens == nil)
        #expect(WEColourFieldState.still.strengthens == nil)
    }

    /// Convergence belongs to the moment both acknowledgements land, and to
    /// nothing else. In particular not to one person acting: the fields moving
    /// toward each other because *this* phone acted would draw a relationship
    /// out of half of one.
    @Test("Only both landing draws the fields together")
    func convergenceBelongsToBoth() {
        #expect(WEColourFieldState.bothLanded.converges)
        #expect(!WEColourFieldState.oneActed(.a).converges)
        #expect(!WEColourFieldState.shared.converges)
        #expect(!WEColourFieldState.still.converges)
    }

    @Test("A private surface shows one hue and a shared one shows both")
    func hueCountFollowsPrivacy() {
        #expect(!WEColourFieldState.mine(.a).showsBothHues)
        #expect(WEColourFieldState.shared.showsBothHues)
        #expect(WEColourFieldState.still.isStill)
    }
}

@Suite("Display type is sized, not declared")
struct WEDisplayScaleTests {
    private let width: CGFloat = 333   // 393 less the Us margins

    @Test("A short horizon takes the display ceiling")
    func shortHorizonIsLarge() {
        let size = WEDisplayScale.hero("Japan,", width: width, typeSize: .large)
        #expect(size >= 64)
        #expect(size <= 88)
    }

    @Test("A long thought steps down rather than wrapping into a wall")
    func longThoughtStepsDown() {
        let short = WEDisplayScale.hero("Japan,", width: width, typeSize: .large)
        let long = WEDisplayScale.hero(
            "This room changes only when something real asks for a shared "
                + "direction.",
            width: width,
            typeSize: .large
        )
        #expect(long < short)
    }

    /// "At large accessibility sizes, reduce the theatrical scale, preserve
    /// reading order, and allow vertical scrolling."
    @Test("Accessibility sizes give up the drama, not the reading order")
    func accessibilitySizesReduceScale() {
        let standard = WEDisplayScale.hero("Japan,", width: width, typeSize: .large)
        let huge = WEDisplayScale.hero(
            "Japan,",
            width: width,
            typeSize: .accessibility5
        )
        #expect(huge < standard)
        #expect(huge >= 44, "never smaller than the size it replaced")
    }

    /// A single unbreakable word cannot be set wider than the column.
    @Test("A long word never exceeds the width it has")
    func longestWordBoundsTheSize() {
        let size = WEDisplayScale.hero(
            "Incomprehensibilities",
            width: width,
            typeSize: .large
        )
        #expect(size * 21 * 0.46 <= width + 1)
    }
}
