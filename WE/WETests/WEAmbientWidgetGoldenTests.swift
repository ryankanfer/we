import SwiftUI
import UIKit
import WidgetKit
import XCTest
@testable import WE

/// Pixel contracts for the content WE owns inside its home-screen widgets.
///
/// These intentionally stop at the WidgetKit boundary. SpringBoard supplies
/// the system corner mask, gallery chrome, margins, and tinted rendering; the
/// reference canvas paints WE's real container background behind the exact
/// family-specific content used by the extension.
final class WEAmbientWidgetGoldenTests: XCTestCase {
    private enum GoldenError: Error {
        case renderingFailed(String)
    }

    private struct Fixture {
        let name: String
        let family: WidgetFamily
        let size: CGSize
        let state: ExternalSurfaceDisplayState
    }

    @MainActor
    func testHomeWidgetContentSurfaces() throws {
        let now = Date(timeIntervalSince1970: 1_755_086_400)
        let fixtures = [
            Fixture(
                name: "golden.widget.system-small.quiet.png",
                family: .systemSmall,
                size: CGSize(width: 170, height: 170),
                state: .quiet
            ),
            Fixture(
                name: "golden.widget.system-small.room-available.png",
                family: .systemSmall,
                size: CGSize(width: 170, height: 170),
                state: .roomAvailable
            ),
            Fixture(
                name: "golden.widget.system-medium.quiet.png",
                family: .systemMedium,
                size: CGSize(width: 364, height: 170),
                state: .quiet
            ),
            Fixture(
                name: "golden.widget.system-medium.room-available.png",
                family: .systemMedium,
                size: CGSize(width: 364, height: 170),
                state: .roomAvailable
            ),
        ]

        for fixture in fixtures {
            let snapshot = ExternalSurfaceSnapshot(
                displayState: fixture.state,
                expiresAt: now.addingTimeInterval(60 * 60),
                now: now
            )
            let surface = WEAmbientWidgetSurface(
                snapshot: snapshot,
                date: now,
                family: fixture.family,
                backgroundPresentation: .referenceCanvas
            )
            .frame(width: fixture.size.width, height: fixture.size.height)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))

            let renderer = ImageRenderer(content: surface)
            renderer.proposedSize = ProposedViewSize(fixture.size)
            renderer.scale = 3
            renderer.isOpaque = true

            guard let image = renderer.uiImage else {
                throw GoldenError.renderingFailed(fixture.name)
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
