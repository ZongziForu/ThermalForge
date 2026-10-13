import Testing
import Foundation
@testable import ThermalForgeCore

@Suite("Polling efficiency and wall-clock timing")
struct PollingEfficiencyTests {
    @Test("Different Macs use different inventories, failed metadata is retried")
    func hardwareInventories() {
        var first = SMCMetadataCache()
        first.knownKeys = ["TCHP"]
        var second = SMCMetadataCache()
        second.knownKeys = ["Tp01"]
        var calls = 0
        #expect(first.info(for: "Tp01", load: { calls += 1; return (4, "flt ") }) == nil)
        #expect(calls == 0)
        #expect(second.info(for: "Tp01", load: { calls += 1; return nil }) == nil)
        #expect(second.info(for: "Tp01", load: { calls += 1; return (4, "flt ") })?.size == 4)
        #expect(second.info(for: "Tp01", load: { calls += 1; return nil })?.size == 4)
        #expect(calls == 2)
        second = SMCMetadataCache() // Reconnection/wake invalidates the inventory.
        second.knownKeys = ["TCHP"]
        #expect(second.info(for: "Tp01", load: { calls += 1; return (4, "flt ") }) == nil)
        #expect(calls == 2)
    }

    @Test("Incomplete inventory never excludes keys and failed values invalidate metadata")
    func transientFailures() {
        var cache = SMCMetadataCache()
        #expect(cache.info(for: "TG0H", load: { (4, "flt ") })?.size == 4)
        cache.remove("TG0H")
        #expect(cache.info(for: "TG0H", load: { nil }) == nil)
        #expect(cache.info(for: "TG0H", load: { (8, "ioft") })?.size == 8)
    }

    @Test("Changing poll cadence preserves elapsed time, smoothing and per-second ramps")
    func pollIndependentTiming() {
        for step in [0.1, 0.5] {
            var timing = ThermalTiming()
            var duration: Float = 0
            var smoothed: Float = 50
            var ramp: Float = 0
            let steps = Int((20 / step).rounded())
            for index in 0...steps {
                let result = timing.advance(now: 100 + Double(index) * step)
                let dt = Float(result.elapsed)
                duration += dt
                smoothed += ThermalTiming.smoothingAlpha(elapsed: dt, timeConstant: 3) * (70 - smoothed)
                ramp += 0.04 * dt
                #expect(!result.resumed)
            }
            #expect(abs(duration - 20) < 0.001)
            #expect(abs(ramp - 0.8) < 0.001)
            #expect(abs(smoothed - (70 - 20 * exp(-20 / Float(3)))) < 0.001)
        }
    }

    @Test("Sustained trigger and cooling delay measure complete real durations")
    func dwellDurations() {
        for step in [0.1, 0.5] {
            for threshold in [4.0, 20.0] {
                var dwell = ThermalDwell()
                let steps = Int((threshold / step).rounded())
                for index in 0..<steps {
                    dwell.update(active: true, now: 100 + Double(index) * step)
                    #expect(dwell.elapsed < Float(threshold))
                }
                dwell.update(active: true, now: 100 + threshold)
                #expect(dwell.elapsed == Float(threshold))
                dwell.update(active: false, now: 101 + threshold)
                dwell.update(active: true, now: 102 + threshold)
                #expect(dwell.elapsed == 0)
            }
        }
    }

    @Test("UI and history have independent deadlines; wake cannot cause a ramp jump")
    func deadlinesAndWake() {
        var timing = ThermalTiming()
        #expect(timing.advance(now: 100).elapsed == 0)
        let half = timing.advance(now: 100.5)
        #expect(!half.uiDue && !half.monitorDue)
        let one = timing.advance(now: 101)
        #expect(one.uiDue && !one.monitorDue)
        #expect(timing.advance(now: 102).monitorDue)
        let wake = timing.advance(now: 1000)
        #expect(wake.resumed && wake.elapsed == 0 && wake.uiDue && wake.monitorDue)
        #expect(timing.advance(now: 1000.5).elapsed == 0.5)
    }
}
