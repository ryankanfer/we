import Foundation
import SwiftUI
import Testing
@testable import WE

/// "One heavy generator at a time" is only an invariant if something enforces
/// it. These assert the enforcement rather than trusting the call sites,
/// because the failure mode — three live GPU passes for one visible screen —
/// is invisible in the simulator and only shows up as heat on a real phone.
@MainActor
struct VisualEngineCoordinatorTests {

    private func coordinator(
        quality: VisualEngineCoordinator.Quality = .high,
        visible: VisualEngineCoordinator.Surface = .hueSelection
    ) -> VisualEngineCoordinator {
        let engine = VisualEngineCoordinator(qualityOverride: quality)
        engine.visibleSurface = visible
        return engine
    }

    @Test
    func grantsALeaseToTheVisibleSurface() {
        let engine = coordinator()
        #expect(engine.acquireFilamentLease(for: .hueSelection))
        #expect(engine.holdsFilamentLease(.hueSelection))
        #expect(engine.tier(for: .hueSelection) == .filament)
    }

    @Test
    func refusesASecondLease() {
        let engine = coordinator()
        #expect(engine.acquireFilamentLease(for: .hueSelection))

        // The WE tab asking while the picker holds it — this is the case that
        // produced three live passes before the coordinator existed.
        #expect(engine.acquireFilamentLease(for: .we) == false)
        #expect(engine.holdsFilamentLease(.we) == false)
        #expect(engine.tier(for: .we) == .analytic)
    }

    @Test
    func refusesALeaseToAnOffscreenSurface() {
        let engine = coordinator(visible: .life)
        #expect(engine.acquireFilamentLease(for: .we) == false)
    }

    @Test
    func refusesALeaseUnderAPresentedCover() {
        let engine = coordinator()
        engine.modalDepth = 1
        #expect(engine.acquireFilamentLease(for: .hueSelection) == false)
    }

    @Test
    func reacquiringAHeldLeaseSucceeds() {
        let engine = coordinator()
        #expect(engine.acquireFilamentLease(for: .hueSelection))
        #expect(engine.acquireFilamentLease(for: .hueSelection))
    }

    @Test
    func releasingFreesItForAnotherSurface() {
        let engine = coordinator()
        #expect(engine.acquireFilamentLease(for: .hueSelection))

        // A surface may only release its own lease.
        engine.releaseFilamentLease(for: .we)
        #expect(engine.holdsFilamentLease(.hueSelection))

        engine.releaseFilamentLease(for: .hueSelection)
        engine.visibleSurface = .we
        #expect(engine.acquireFilamentLease(for: .we))
    }

    /// A thermal drop must reclaim a lease already granted, or a dead renderer
    /// stays attached to a surface that is no longer allowed to run one.
    @Test
    func aQualityDropReclaimsTheLease() {
        let engine = coordinator()
        #expect(engine.acquireFilamentLease(for: .hueSelection))

        engine.qualityOverride = .low
        #expect(engine.holdsFilamentLease(.hueSelection) == false)
        #expect(engine.acquireFilamentLease(for: .hueSelection) == false)
    }

    @Test
    func reduceTransparencyTurnsTheGenerativeLayerOff() {
        let engine = VisualEngineCoordinator()
        engine.visibleSurface = .hueSelection
        engine.setAccessibility(reduceMotion: false, reduceTransparency: true)

        #expect(engine.quality == .off)
        #expect(engine.acquireFilamentLease(for: .hueSelection) == false)
        #expect(engine.tier(for: .hueSelection) == .ambient)
    }

    /// A particle system has no analytic f(t), so it cannot be frozen the way
    /// the shader freezes at t = 2.4. Reduce Motion has to refuse the lease.
    @Test
    func reduceMotionRefusesTheFilamentLease() {
        let engine = VisualEngineCoordinator()
        engine.visibleSurface = .hueSelection
        engine.setAccessibility(reduceMotion: true, reduceTransparency: false)

        #expect(engine.acquireFilamentLease(for: .hueSelection) == false)
        #expect(engine.isAnimating(.hueSelection, scenePhase: .active) == false)
    }

    @Test
    func animationStopsWhenBackgroundedOrCovered() {
        let engine = coordinator()
        #expect(engine.isAnimating(.hueSelection, scenePhase: .active))
        #expect(engine.isAnimating(.hueSelection, scenePhase: .background) == false)
        #expect(engine.isAnimating(.we, scenePhase: .active) == false)

        engine.modalDepth = 1
        #expect(engine.isAnimating(.hueSelection, scenePhase: .active) == false)
    }
}
