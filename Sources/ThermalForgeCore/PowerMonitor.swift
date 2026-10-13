import Foundation
import IOKit

/// A local battery reading. Watts are net battery power, not wall/USB input power.
public struct BatteryPowerStatus: Equatable, Sendable {
    public enum State: String, Sendable {
        case battery = "On battery"
        case charging = "Charging"
        case pluggedIn = "Plugged in"
        case full = "Fully charged"
    }
    public let state: State
    public let watts: Double?
    public let adapterRatingWatts: Int?

    public static func read() -> BatteryPowerStatus? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return decode(dictionary)
    }

    static func decode(_ dictionary: [String: Any]) -> BatteryPowerStatus {
        let connected = dictionary["ExternalConnected"] as? Bool ?? false
        let charging = dictionary["IsCharging"] as? Bool ?? false
        let full = dictionary["FullyCharged"] as? Bool ?? false
        let state: State = !connected ? .battery : full ? .full : charging ? .charging : .pluggedIn
        var watts: Double?
        if let voltage = dictionary["Voltage"] as? NSNumber,
           let current = (dictionary["InstantAmperage"] ?? dictionary["Amperage"]) as? NSNumber {
            let raw = current.uint64Value
            // IORegistry reports a negative current as either a signed number or
            // an unsigned two's-complement 32/64-bit value, depending on the OS.
            let milliamps = raw <= UInt64(UInt32.max) && raw > UInt64(Int32.max)
                ? Double(Int32(bitPattern: UInt32(raw))) : Double(Int64(bitPattern: raw))
            let value = voltage.doubleValue * milliamps / 1_000_000
            if value.isFinite && abs(value) < 500 && voltage.doubleValue > 0 {
                watts = value
            }
        }
        let adapter = dictionary["AdapterDetails"] as? [String: Any]
        let rating = (adapter?["Watts"] as? NSNumber)?.intValue
        return BatteryPowerStatus(state: state, watts: watts,
                                  adapterRatingWatts: connected && (rating ?? 0) > 0 ? rating : nil)
    }
}
