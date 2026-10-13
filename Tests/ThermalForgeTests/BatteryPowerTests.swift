import Foundation
import Testing
@testable import ThermalForgeCore

@Suite("Native battery power")
struct BatteryPowerTests {
    @Test("Measured battery watts differ from adapter rating")
    func charging() {
        let snapshot = BatteryPowerStatus.decode([
            "ExternalConnected": true, "IsCharging": true,
            "Voltage": 12000, "InstantAmperage": 2000,
            "AdapterDetails": ["Watts": 100]
        ])
        #expect(snapshot.state == .charging)
        #expect(snapshot.watts == 24)
        #expect(snapshot.adapterRatingWatts == 100)
        #expect(snapshot.explanation == "Power flowing into the battery")
    }

    @Test("Discharge decodes signed and unsigned 32/64-bit currents")
    func discharging() {
        for value in [NSNumber(value: -1000), NSNumber(value: UInt32(bitPattern: -1000)),
                      NSNumber(value: UInt64(bitPattern: -1000))] {
            let snapshot = BatteryPowerStatus.decode([
                "ExternalConnected": false, "Voltage": 12000, "Amperage": value
            ])
            #expect(snapshot.state == .battery)
            #expect(snapshot.watts == -12)
            #expect(snapshot.explanation == "Power supplied by the battery")
        }
    }

    @Test("Plugged in without charging and missing power stay explicit")
    func incomplete() {
        let snapshot = BatteryPowerStatus.decode(["ExternalConnected": true])
        #expect(snapshot.state == .pluggedIn)
        #expect(snapshot.watts == nil)
        #expect(snapshot.explanation == "Connected · net battery power")
        #expect(BatteryPowerStatus.decode(["ExternalConnected": true, "FullyCharged": true]).state == .full)
    }
}
