import Foundation
import Testing
@testable import ThermalForgeCore

@Suite("Summer and manual control")
struct SummerControlTests {
    @Test("Summer starts gently and progresses monotonically across the whole band")
    func summerBand() throws {
        let curve = FanProfile.summerSmooth.curve
        #expect(curve.validationError == nil)
        let start = try #require(curve.targetPercent(at: 55, fansCurrentlyRunning: false))
        #expect(abs(start - 0.17) < 0.0001)
        var previous = start
        for temperature in stride(from: Float(55), through: 75, by: 0.1) {
            let next = try #require(curve.targetPercent(at: temperature, fansCurrentlyRunning: true))
            #expect(next >= previous - 0.00001)
            #expect(next - previous < 0.006)
            previous = next
        }
        #expect(curve.targetPercent(at: 75, fansCurrentlyRunning: true) == 0.85)
        #expect(curve.targetPercent(at: 49, fansCurrentlyRunning: true) == nil)
    }

    @Test("Manual works even on a cold machine and clamps to hardware limits")
    func manual() {
        let low = FanProfile.manual(rpm: 0, minRPM: 1200, maxRPM: 7200)
        #expect(low.curve.targetPercent(at: 20, fansCurrentlyRunning: false) == Float(1200) / 7200)
        let high = FanProfile.manual(rpm: 9000, minRPM: 1200, maxRPM: 7200)
        #expect(high.curve.targetPercent(at: 80, fansCurrentlyRunning: true) == 1)
        #expect(FanProfile.selectable(id: "manual", from: [high]).id == "silent")
    }

    @Test("Legacy curves decode without the new optional floor")
    func legacyJSON() throws {
        var dictionary = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(FanProfile.summerSmooth)) as? [String: Any])
        var curve = try #require(dictionary["curve"] as? [String: Any])
        curve.removeValue(forKey: "minRPMPercent")
        dictionary["curve"] = curve
        let profile = try JSONDecoder().decode(FanProfile.self, from: JSONSerialization.data(withJSONObject: dictionary))
        #expect(profile.curve.minRPMPercent == nil)
    }

    @Test("Custom profiles restore, reserved identities cannot replace core modes")
    func customFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let custom = FanProfile(id: "summer-custom", name: "Custom", curve: FanProfile.summerSmooth.curve)
        try custom.save(in: directory)
        try FanProfile(id: "smart", name: "Imposter", curve: custom.curve).save(in: directory)
        let profiles = FanProfile.loadAll(from: directory)
        #expect(FanProfile.selectable(id: custom.id, from: profiles) == custom)
        #expect(!profiles.contains { $0.name == "Imposter" })
    }

    @Test("Invalid floor and unreachable control thresholds are rejected")
    func invalidCurve() {
        #expect(FanProfile.Curve(maxRPMPercent: 0.6, minRPMPercent: 0.8).validationError != nil)
        #expect(FanProfile.Curve(startTemp: 96, ceilingTemp: 100).validationError != nil)
    }
}
