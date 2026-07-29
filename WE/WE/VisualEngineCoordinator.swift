import Foundation
import Metal
import Observation
import SwiftUI

/// Owns every expensive visual in the app, and grants permission to run one.
///
/// Two problems this exists to solve.
///
/// **Nobody owned the GPU.** Each generative surface built its own timeline and
/// ran independently. `TabView` keeps unselected tabs alive and their pause
/// conditions only watched `scenePhase`, so WE, Life and Ahead could each hold
/// a live full-screen pass at once — three generators for one visible screen.
/// `onDisappear` does not fire for a backgrounded tab, so no view can detect
/// this about itself. It has to be decided from above.
///
/// **Nothing watched the device.** `thermalState`, `isLowPowerModeEnabled` and
/// `accessibilityReduceTransparency` appeared nowhere in the codebase. A
/// generative system that ignores all three is a battery complaint waiting to
/// be filed.
@MainActor
@Observable
final class VisualEngineCoordinator {

    // MARK: - Quality

    enum Quality: Int, Comparable, Sendable {
        /// No generative layer. Flat canvas, or a still.
        case off
        /// Cheapest live path — the analytic shader, no bloom.
        case low
        case medium
        case high

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// What a surface is allowed to draw, once the coordinator has weighed the
    /// device, the accessibility settings and who else is asking.
    enum Tier: Equatable, Sendable {
        /// `MeshGradient`. Free, always permitted.
        case ambient
        /// The analytic `weConfluence` shader.
        case analytic
        /// The particle engine. Granted to at most one surface.
        case filament
    }

    /// Where a generative layer lives. Distinct from `AppShell.Destination`
    /// because several of these are not tabs.
    enum Surface: Hashable, Sendable {
        case we
        case life
        case ahead
        case hueSelection
        case promise
        case insightDetail
    }

    // MARK: - Metal

    /// One device and one queue for the whole app. Building `MTLCreateSystemDefaultDevice()`
    /// per view is how you end up with several command queues and no idea why
    /// memory climbed.
    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?

    // MARK: - Observed state

    /// The destination currently on screen. Mirrored from `AppShell`.
    var visibleSurface: Surface = .we

    /// Incremented by each presented sheet or cover. A surface underneath a
    /// full-screen cover is not visible no matter what the tab bar says.
    var modalDepth: Int = 0

    private(set) var quality: Quality = .high
    private(set) var leaseHolder: Surface?

    private var reduceMotion = false
    private var reduceTransparency = false

    /// Pins `quality`, bypassing the hardware ladder.
    ///
    /// The ladder reads `thermalState` and `supportsFamily(.apple8)`, which
    /// differ between a simulator, a test runner and a device — so the lease
    /// rules would be untestable without a seam. Only tests set this.
    var qualityOverride: Quality? {
        didSet { refreshQuality() }
    }

    // MARK: - Init

    init(qualityOverride: Quality? = nil) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.qualityOverride = qualityOverride

        refreshQuality()
        observe(.NSProcessInfoPowerStateDidChange)
        observe(ProcessInfo.thermalStateDidChangeNotification)
    }

    private func observe(_ name: Notification.Name) {
        NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshQuality() }
        }
    }

    // MARK: - Accessibility

    /// Pushed in from the view layer, which is where these environment values
    /// actually live.
    func setAccessibility(reduceMotion: Bool, reduceTransparency: Bool) {
        guard reduceMotion != self.reduceMotion
            || reduceTransparency != self.reduceTransparency
        else {
            return
        }
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        refreshQuality()
    }

    // MARK: - Quality ladder

    private func refreshQuality() {
        quality = resolvedQuality()

        // A surface holding a lease it can no longer honour must give it back,
        // or a thermal drop would leave a dead renderer attached.
        if quality < .medium, leaseHolder != nil {
            leaseHolder = nil
        }
    }

    private func resolvedQuality() -> Quality {
        if let qualityOverride { return qualityOverride }

        // Reduce Transparency is a request not to have content shining
        // through other content. Bloom is exactly that, so it is not a
        // quality question — it is off.
        if reduceTransparency { return .off }

        // A particle system has no analytic f(t), so it cannot be frozen the
        // way the shader freezes at t = 2.4. Under Reduce Motion the honest
        // answer is to refuse the lease and let the static path serve.
        if reduceMotion { return .low }

        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .low }

        // A15 and later. Checked by feature, never by model string.
        guard let device, device.supportsFamily(.apple8) else { return .low }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .high
        case .fair: return .medium
        case .serious: return .low
        case .critical: return .off
        @unknown default: return .medium
        }
    }

    // MARK: - Leases

    /// Ask to run the particle engine on `surface`.
    ///
    /// Granted only if the device can afford it, the surface is actually on
    /// screen, nothing is covering it, and nobody else already holds it.
    /// Re-asking while already holding it succeeds.
    @discardableResult
    func acquireFilamentLease(for surface: Surface) -> Bool {
        guard quality >= .medium else { return false }
        guard modalDepth == 0 || surface == .promise else { return false }
        guard surface == visibleSurface else { return false }
        guard leaseHolder == nil || leaseHolder == surface else { return false }

        leaseHolder = surface
        return true
    }

    func releaseFilamentLease(for surface: Surface) {
        guard leaseHolder == surface else { return }
        leaseHolder = nil
    }

    func holdsFilamentLease(_ surface: Surface) -> Bool {
        leaseHolder == surface
    }

    /// What `surface` should draw right now.
    func tier(for surface: Surface) -> Tier {
        if quality == .off { return .ambient }
        if leaseHolder == surface { return .filament }
        return .analytic
    }

    /// Whether a surface should be animating at all. This is the existing
    /// `WEConfluenceForm` pause rule — `reduceMotion || scenePhase != .active`
    /// — widened to include visibility and modal depth, and it is a floor:
    /// the form keeps its own check too.
    func isAnimating(_ surface: Surface, scenePhase: ScenePhase) -> Bool {
        guard scenePhase == .active else { return false }
        guard !reduceMotion else { return false }
        guard quality > .off else { return false }
        guard modalDepth == 0 || surface == .promise else { return false }
        return surface == visibleSurface
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var visualEngine: VisualEngineCoordinator? = nil
}
