import Foundation
import SwiftUI
import Testing
@testable import WE

/// The palette gate, recomputed here rather than trusted.
///
/// Every value in `FieldSwatch` was solved against these formulas before it
/// was written down. Keeping the solve in the test means the numbers cannot
/// drift away from the reasoning that produced them: a hand-adjusted hex that
/// "looks better" and quietly fails 3:1, or a new family that lands on top of
/// an existing one, fails here rather than on somebody's phone.
struct WEPigmentTests {

    // MARK: Colour maths

    private static func components(_ color: Color) -> (Double, Double, Double) {
        let r = color.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue))
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }

    private static func contrast(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// CIELAB, so distance is perceptual rather than arithmetic. Two hexes
    /// can be far apart in RGB and look like the same colour.
    private static func lab(
        _ c: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        let r = linear(c.0), g = linear(c.1), b = linear(c.2)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func ciede2000(
        _ c1: (Double, Double, Double),
        _ c2: (Double, Double, Double)
    ) -> Double {
        let (l1, a1, b1) = lab(c1)
        let (l2, a2, b2) = lab(c2)
        let avgL = (l1 + l2) / 2
        let cc1 = (a1 * a1 + b1 * b1).squareRoot()
        let cc2 = (a2 * a2 + b2 * b2).squareRoot()
        let avgC = (cc1 + cc2) / 2
        let p7 = pow(avgC, 7)
        let g = 0.5 * (1 - (p7 / (p7 + pow(25, 7))).squareRoot())
        let a1p = (1 + g) * a1, a2p = (1 + g) * a2
        let c1p = (a1p * a1p + b1 * b1).squareRoot()
        let c2p = (a2p * a2p + b2 * b2).squareRoot()
        let avgCp = (c1p + c2p) / 2

        func degrees(_ y: Double, _ x: Double) -> Double {
            let d = atan2(y, x) * 180 / .pi
            return d < 0 ? d + 360 : d
        }
        let h1p = (c1p == 0) ? 0 : degrees(b1, a1p)
        let h2p = (c2p == 0) ? 0 : degrees(b2, a2p)

        let dLp = l2 - l1
        let dCp = c2p - c1p
        var dhp = 0.0
        if c1p * c2p != 0 {
            let d = h2p - h1p
            dhp = abs(d) <= 180 ? d : (d > 180 ? d - 360 : d + 360)
        }
        let dHp = 2 * (c1p * c2p).squareRoot() * sin(dhp * .pi / 360)

        var avgHp = h1p + h2p
        if c1p * c2p != 0 {
            avgHp = abs(h1p - h2p) <= 180
                ? (h1p + h2p) / 2
                : (h1p + h2p < 360 ? (h1p + h2p + 360) / 2 : (h1p + h2p - 360) / 2)
        }
        func cosd(_ d: Double) -> Double { cos(d * .pi / 180) }
        let t = 1 - 0.17 * cosd(avgHp - 30) + 0.24 * cosd(2 * avgHp)
            + 0.32 * cosd(3 * avgHp + 6) - 0.20 * cosd(4 * avgHp - 63)
        let dTheta = 30 * exp(-pow((avgHp - 275) / 25, 2))
        let cp7 = pow(avgCp, 7)
        let rc = 2 * (cp7 / (cp7 + pow(25, 7))).squareRoot()
        let sl = 1 + (0.015 * pow(avgL - 50, 2)) / (20 + pow(avgL - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * avgCp
        let sh = 1 + 0.015 * avgCp * t
        let rt = -rc * sin(2 * dTheta * .pi / 180)

        let kl = dLp / sl, kc = dCp / sc, kh = dHp / sh
        return (kl * kl + kc * kc + kh * kh + rt * kc * kh).squareRoot()
    }

    /// Linear light, the way light actually adds. Mixing in gamma space
    /// darkens the middle and is why naive blends look muddy.
    private static func blend(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        func toGamma(_ v: Double) -> Double {
            v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return (
            toGamma((linear(a.0) + linear(b.0)) / 2),
            toGamma((linear(a.1) + linear(b.1)) / 2),
            toGamma((linear(a.2) + linear(b.2)) / 2)
        )
    }

    // MARK: The gate

    /// Every family clears 3:1 on every ground it can be drawn on.
    ///
    /// This used to assert soft-on-black and deep-on-cream, which is what
    /// made deep and soft a role rather than a preference. V2 §3 cut the cream
    /// ground, so `deep` no longer has a page to be legible against and
    /// `color(on:)` returns `soft` for all three grounds.
    ///
    /// `deep` is kept rather than deleted — see `FieldSwatch` — but it is now
    /// unused by the app, and an unmeasured value is how a palette rots. So
    /// the gate narrows to what actually ships: soft, on every ground, at 3:1.
    @Test func everyFamilyClearsEveryGround() {
        for swatch in FieldSwatch.allCases {
            for canvas in WECanvas.allCases {
                let ratio = Self.contrast(
                    Self.components(swatch.color(on: canvas)),
                    Self.components(canvas.bg)
                )
                #expect(
                    ratio >= 3.0,
                    "\(swatch.name) on \(canvas.rawValue): \(ratio)"
                )
            }
        }
    }

    /// Every ground picks the same tone, and says so.
    ///
    /// The inverse of what this once asserted. `color(on:)` kept its signature
    /// through the cut so that the call sites keep naming their ground; this
    /// is what stops that signature from quietly growing a second answer again
    /// without the cream canvas's contrast solve behind it.
    @Test func eachGroundSelectsItsLegiblePigmentVariant() {
        for swatch in FieldSwatch.allCases {
            for canvas in WECanvas.allCases {
                #expect(swatch.color(on: canvas) == (canvas == .cream ? swatch.deep : swatch.soft))
            }
            #expect(swatch.color == swatch.soft)
        }
    }

    /// No two families are nearly the same colour.
    ///
    /// Two people whose colours are almost identical cannot tell whose
    /// anything is, which defeats the only thing person colour is allowed to
    /// encode.
    @Test func everyPairIsPerceptuallyDistinct() {
        for a in FieldSwatch.allCases {
            for b in FieldSwatch.allCases where a != b {
                let d = Self.ciede2000(
                    Self.components(a.soft),
                    Self.components(b.soft)
                )
                #expect(d >= 12, "\(a.name) and \(b.name) are \(d) apart")
            }
        }
    }

    /// The pairwise blend matrix, and the claim it makes.
    ///
    /// "Yours. Dylan's. Ours." only works if the third thing is a third
    /// thing. Where the blend sits closer than CIEDE2000 8 to a parent it
    /// reads as two colours rather than three — and `blendIsMuddy` must name
    /// exactly those pairs, no more and no fewer. A hand-maintained list that
    /// drifted from the maths would either nag people about fine pairs or
    /// quietly ship the muddy ones.
    @Test func theMuddyPairsAreExactlyTheMeasuredOnes() {
        var measured: Set<Set<FieldSwatch>> = []
        for a in FieldSwatch.allCases {
            for b in FieldSwatch.allCases where a != b {
                let ca = Self.components(a.soft)
                let cb = Self.components(b.soft)
                let mixed = Self.blend(ca, cb)
                let nearest = min(
                    Self.ciede2000(mixed, ca),
                    Self.ciede2000(mixed, cb)
                )
                if nearest < 8 { measured.insert(Set([a, b])) }
            }
        }
        for pair in measured {
            let two = Array(pair)
            #expect(
                FieldSwatch.blendIsMuddy(two[0], two[1]),
                "\(two[0].name) and \(two[1].name) blend muddily and are not flagged"
            )
        }
        for a in FieldSwatch.allCases {
            for b in FieldSwatch.allCases where a != b {
                if FieldSwatch.blendIsMuddy(a, b) {
                    #expect(
                        measured.contains(Set([a, b])),
                        "\(a.name) and \(b.name) are flagged but blend fine"
                    )
                }
            }
        }
        // Four of twenty eight. If this number moves a lot, the palette moved.
        #expect(measured.count == 4, "\(measured.count) muddy pairs")
    }

    /// The seeded pair is a fine pair, which it had better be.
    @Test func theSeededPairBlendsCleanly() {
        #expect(FieldIdentity.seed.personA == .burgundy)
        #expect(FieldIdentity.seed.personB == .sage)
        #expect(!FieldSwatch.blendIsMuddy(.burgundy, .sage))
    }

    /// What is offered when a pair is too close stays in the same family of
    /// warmth. Answering a near collision by offering somebody the opposite
    /// side of the wheel is the app overruling a choice rather than helping.
    @Test func neighboursStayNearby() {
        for swatch in FieldSwatch.allCases {
            #expect(!swatch.neighbours.isEmpty)
            #expect(!swatch.neighbours.contains(swatch))
            for neighbour in swatch.neighbours {
                #expect(
                    neighbour.palette == swatch.palette,
                    "\(swatch.name) is offered \(neighbour.name)"
                )
                #expect(
                    !FieldSwatch.blendIsMuddy(swatch, neighbour)
                        || swatch.neighbours.count > 1,
                    "\(swatch.name) has no clean way out"
                )
            }
        }
    }

    @Test func thereAreEightFamiliesInTwoGroups() {
        #expect(FieldSwatch.allCases.count == 8)
        #expect(FieldPersonPalette.warm.swatches.count == 4)
        #expect(FieldPersonPalette.cool.swatches.count == 4)
        #expect(
            Set(FieldPersonPalette.warm.swatches)
                .isDisjoint(with: Set(FieldPersonPalette.cool.swatches))
        )
        #expect(
            Set(FieldPersonPalette.warm.swatches)
                .union(FieldPersonPalette.cool.swatches)
                == Set(FieldSwatch.allCases)
        )
    }
}

/// Colours somebody already chose.
///
/// `FieldSwatch` is `Codable` and persisted, so removing a case is not a
/// refactor — it is a stored value on a device that no longer parses.
struct WEPigmentMigrationTests {

    @Test func retiredColoursDecodeIntoTheirFamily() throws {
        let decoder = JSONDecoder()
        #expect(
            try decoder.decode(FieldSwatch.self, from: Data("\"clay\"".utf8))
                == .rust
        )
        #expect(
            try decoder.decode(FieldSwatch.self, from: Data("\"slate\"".utf8))
                == .indigo
        )
    }

    /// The stored door, which is the one the backend uses. `init(rawValue:)`
    /// returns nil for a retired name and every caller had a fallback behind
    /// it, so a couple who chose clay and slate would have been sent silently
    /// to the seeded pair.
    @Test func theStoredInitialiserCarriesRetiredNames() {
        #expect(FieldSwatch(stored: "clay") == .rust)
        #expect(FieldSwatch(stored: "slate") == .indigo)
        #expect(FieldSwatch(rawValue: "clay") == nil)
        #expect(FieldSwatch(rawValue: "slate") == nil)
    }

    /// Every current family round trips, so the new ones persist rather than
    /// being offered and then lost.
    @Test func everyFamilyPersistsAndReturns() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for swatch in FieldSwatch.allCases {
            let data = try encoder.encode(swatch)
            #expect(
                try decoder.decode(FieldSwatch.self, from: data) == swatch,
                "\(swatch.name) did not survive a round trip"
            )
            #expect(FieldSwatch(stored: swatch.rawValue) == swatch)
        }
    }

    /// A whole identity, as it is actually stored.
    @Test func anIdentityFromTheOldPaletteStillLoads() throws {
        let json = """
        {"personA":"clay","personB":"slate","nameA":"Ryan","nameB":"Dylan"}
        """
        let identity = try JSONDecoder().decode(
            FieldIdentity.self,
            from: Data(json.utf8)
        )
        #expect(identity.personA == .rust)
        #expect(identity.personB == .indigo)
        #expect(identity.nameA == "Ryan")
    }

    /// Nonsense is not an old colour, and must not become an exception that
    /// locks somebody out of their own app.
    @Test func aCorruptValueFallsBackRatherThanThrowing() throws {
        let swatch = try JSONDecoder().decode(
            FieldSwatch.self,
            from: Data("\"chartreuse\"".utf8)
        )
        #expect(swatch == .burgundy)
        #expect(FieldSwatch(stored: "chartreuse") == nil)
    }

    /// The Swift mapping and the SQL migration must say the same thing.
    @Test func theMigrationMovesTheSameColoursSwiftDoes() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sql = (try? String(
            contentsOf: root
                .appendingPathComponent("supabase/migrations")
                .appendingPathComponent("20260820230000_pigment_palette.sql"),
            encoding: .utf8
        )) ?? ""

        #expect(!sql.isEmpty)
        #expect(sql.contains("when 'clay' then 'rust'"))
        #expect(sql.contains("when 'slate' then 'indigo'"))
        #expect(FieldSwatch.retired["clay"] == .rust)
        #expect(FieldSwatch.retired["slate"] == .indigo)
        #expect(FieldSwatch.retired.count == 2)

        // Every family the app can now persist must be permitted by the
        // constraint, or choosing it fails on write.
        for swatch in FieldSwatch.allCases {
            #expect(
                sql.contains("'\(swatch.rawValue)'"),
                "\(swatch.name) is not in the check constraint"
            )
        }
        // And the retired names must not be, or the migration did nothing.
        #expect(!sql.contains("check (swatch_a in ('clay'"))
    }
}
