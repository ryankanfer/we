import Foundation
import Testing
@testable import WE

/// The walkthrough collects a private line and signal choices before an account
/// exists. These cover the part that matters: nothing is stored when there is
/// nothing to store, and what is stored is delivered exactly once.
struct ThresholdIntentTests {
    private func scratchDefaults() -> UserDefaults {
        let suite = "threshold.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test
    func untouchedWalkthroughStoresNothing() {
        let defaults = scratchDefaults()
        ThresholdIntent(
            privateLine: "",
            signals: ThresholdIntent.defaultSignals
        )
        .store(in: defaults)

        #expect(ThresholdIntent.pending(in: defaults) == nil)
    }

    @Test
    func aWrittenLineIsHeldForDelivery() {
        let defaults = scratchDefaults()
        ThresholdIntent(
            privateLine: "The kitchen tap again",
            signals: ThresholdIntent.defaultSignals
        )
        .store(in: defaults)

        let pending = ThresholdIntent.pending(in: defaults)
        #expect(pending?.privateLine == "The kitchen tap again")
    }

    @Test
    func changedSignalsAloneAreEnoughToStore() {
        let defaults = scratchDefaults()
        var signals = ThresholdIntent.defaultSignals
        signals[SignalKind.weeklyRhythm.rawValue] = false
        ThresholdIntent(privateLine: "", signals: signals).store(in: defaults)

        let pending = ThresholdIntent.pending(in: defaults)
        #expect(pending?.signals[SignalKind.weeklyRhythm.rawValue] == false)
    }

    @Test
    func clearingLeavesNothingToDeliverTwice() {
        let defaults = scratchDefaults()
        ThresholdIntent(
            privateLine: "Held once",
            signals: ThresholdIntent.defaultSignals
        )
        .store(in: defaults)

        ThresholdIntent.clear(in: defaults)
        #expect(ThresholdIntent.pending(in: defaults) == nil)
    }

    @Test
    func defaultSignalsMatchTheServerSeed() {
        // The database seeds three signals on and private reflections off. The
        // walkthrough must open in that same state or the first write would
        // silently change something the person never touched.
        #expect(
            ThresholdIntent.defaultSignals[SignalKind.sharedPlans.rawValue] == true
        )
        #expect(
            ThresholdIntent.defaultSignals[SignalKind.weeklyRhythm.rawValue] == true
        )
        #expect(
            ThresholdIntent.defaultSignals[SignalKind.unfinishedThreads.rawValue] == true
        )
        #expect(
            ThresholdIntent.defaultSignals[SignalKind.privateReflections.rawValue] == false
        )
    }
}
