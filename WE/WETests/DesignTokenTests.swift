import Foundation
import SwiftUI
import Testing
@testable import WE

/// Contrast is the one part of the visual system that is not a matter of
/// taste, so it is asserted rather than reviewed.
///
/// Before these tokens existed, body copy on the WE surface scored between
/// 3.26:1 and 4.91:1 depending on which hue the user had chosen, and metadata
/// fell to 2.33:1 — below even the large-text floor for nine of the ten hues.
struct DesignTokenTests {
    /// WCAG 2.1 relative luminance.
    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0)
            + 0.7152 * channel(c.1)
            + 0.0722 * channel(c.2)
    }

    private static func contrast(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func over(
        _ fg: (Double, Double, Double),
        _ alpha: Double,
        _ bg: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        (
            fg.0 * alpha + bg.0 * (1 - alpha),
            fg.1 * alpha + bg.1 * (1 - alpha),
            fg.2 * alpha + bg.2 * (1 - alpha)
        )
    }

    private static let canvas = (0x17 / 255.0, 0x14 / 255.0, 0x0F / 255.0)
    private static let surface = (0x26 / 255.0, 0x23 / 255.0, 0x1E / 255.0)
    private static let ink = (0xF4 / 255.0, 0xEF / 255.0, 0xE5 / 255.0)
    private static let inkSecondary = (0xC7 / 255.0, 0xC2 / 255.0, 0xB8 / 255.0)
    private static let inkTertiary = (0x98 / 255.0, 0x92 / 255.0, 0x89 / 255.0)
    private static let inkFaint = (0x7D / 255.0, 0x78 / 255.0, 0x6F / 255.0)
    private static let privateInk = (0x17 / 255.0, 0x30 / 255.0, 0x40 / 255.0)
    private static let pearl = (0xF2 / 255.0, 0xEE / 255.0, 0xE6 / 255.0)
    private static let warmStone = (0xD8 / 255.0, 0xD0 / 255.0, 0xC4 / 255.0)
    private static let champagne = (0xC7 / 255.0, 0xA2 / 255.0, 0x58 / 255.0)
    private static let charcoal = (0x1E / 255.0, 0x30 / 255.0, 0x3A / 255.0)

    /// AA body text.
    private static let aa = 4.5
    /// AA text at 18pt or larger.
    private static let aaLarge = 3.0

    @Test
    func inkRampClearsAAOnTheSurface() {
        #expect(Self.contrast(Self.ink, Self.surface) >= Self.aa)
        #expect(Self.contrast(Self.inkSecondary, Self.surface) >= Self.aa)
        #expect(Self.contrast(Self.inkTertiary, Self.surface) >= Self.aa)
        // Faint is deliberately large-text only and must never be used for body.
        #expect(Self.contrast(Self.inkFaint, Self.surface) >= Self.aaLarge)
        #expect(Self.contrast(Self.inkFaint, Self.surface) < Self.aa)
    }

    @Test
    func inkRampClearsAAOnTheCanvas() {
        #expect(Self.contrast(Self.ink, Self.canvas) >= Self.aa)
        #expect(Self.contrast(Self.inkSecondary, Self.canvas) >= Self.aa)
        #expect(Self.contrast(Self.inkTertiary, Self.canvas) >= Self.aa)
    }

    @Test
    func journeyTextClearsAAOnBothArchitecturalPlanes() {
        let privateMetadata = Self.over(
            Self.pearl,
            0.64,
            Self.privateInk
        )
        let lightSecondaryOnPearl = Self.over(
            Self.charcoal,
            0.76,
            Self.pearl
        )
        let lightSecondaryOnWarmStone = Self.over(
            Self.charcoal,
            0.76,
            Self.warmStone
        )

        #expect(
            Self.contrast(privateMetadata, Self.privateInk) >= Self.aa
        )
        #expect(
            Self.contrast(lightSecondaryOnPearl, Self.pearl) >= Self.aa
        )
        #expect(
            Self.contrast(lightSecondaryOnWarmStone, Self.warmStone)
                >= Self.aa
        )
        #expect(
            Self.contrast(Self.privateInk, Self.champagne) >= Self.aa
        )
    }

    @Test
    func widgetTextPlaneRemainsLegibleOverItsLightestBackdrop() {
        let worstCaseTextPlane = Self.over(
            Self.privateInk,
            0.94,
            Self.warmStone
        )
        #expect(
            Self.contrast(Self.pearl, worstCaseTextPlane) >= Self.aa
        )
    }

    /// The atmosphere tints the surface differently for each personal hue.
    /// This is the case the old 0.90-opacity wash failed: body copy landed
    /// between 3.26:1 and 4.91:1, metadata between 2.33:1 and 3.23:1.
    ///
    /// Uses `atmosphereComponents`, matching what `WEAtmosphere` renders —
    /// light hues are substituted for their deepened control tone, which is
    /// the whole reason that substitution exists.
    @Test
    func inkRampSurvivesEveryHueAtmosphere() {
        for hue in WEHue.allCases {
            let components = hue.atmosphereComponents
            let tinted = Self.over(
                (components.red, components.green, components.blue),
                0.22,
                Self.canvas
            )
            let card = Self.over(Self.ink, 0.07, tinted)

            #expect(
                Self.contrast(Self.ink, card) >= Self.aa,
                "WEInk fails AA over \(hue.name)"
            )
            #expect(
                Self.contrast(Self.inkSecondary, card) >= Self.aa,
                "WEInkSecondary fails AA over \(hue.name)"
            )
            #expect(
                Self.contrast(Self.inkTertiary, card) >= Self.aaLarge,
                "WEInkTertiary fails AA-large over \(hue.name)"
            )
        }
    }

    /// `color` and `controlColor` are fill tones. `accentColor` is the only
    /// one safe as a foreground, and every hue must supply a usable one —
    /// otherwise the relationship identity silently drops out of legibility
    /// for whoever picked that colour.
    @Test
    func everyHueHasALegibleAccent() {
        for hue in WEHue.allCases {
            let a = hue.accentComponents
            #expect(
                Self.contrast((a.red, a.green, a.blue), Self.surface) >= Self.aa,
                "\(hue.name) accent fails AA on the surface"
            )
        }
    }

    /// White on a hue fill is the one place pure white is correct — every
    /// control tone must support it.
    @Test
    func whiteLabelsClearAAOnEveryControlFill() {
        for hue in WEHue.allCases {
            let c = hue.controlComponents
            #expect(
                Self.contrast((1, 1, 1), (c.red, c.green, c.blue)) >= Self.aa,
                "White label fails AA on \(hue.name) control fill"
            )
        }
    }

    /// The legacy editorial confluence reports proximity, while the
    /// trust-bearing continuity line keeps both sides visually intact.
    /// If this ordering breaks, the canvas starts lying about consent.
    @Test
    func connectionRisesMonotonicallyWithTrust() {
        let ordered: [TrustPhase] = [
            .open, .waiting, .answering, .held, .shared
        ]
        let values = ordered.map(\.confluenceConnection)
        #expect(values == values.sorted())
        #expect(TrustPhase.open.confluenceConnection < 0.25)
        #expect(TrustPhase.shared.confluenceConnection == 1)
        // A decline must not read as further along than a live invitation.
        #expect(
            TrustPhase.declined.confluenceConnection
                < TrustPhase.invited.confluenceConnection
        )
    }

    @Test
    func journeyStatesHaveDistinctNonIdentityMergingDescriptions() {
        let descriptions = WEJourneyState.allCases.map(
            \.accessibilityDescription
        )

        #expect(Set(descriptions).count == WEJourneyState.allCases.count)
        #expect(
            WEJourneyState.shared.accessibilityDescription
                .contains("two intact sides")
        )
        #expect(
            descriptions.allSatisfy {
                !$0.localizedCaseInsensitiveContains("merge")
            }
        )
    }
}
