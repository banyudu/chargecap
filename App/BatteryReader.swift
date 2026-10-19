import Foundation
import IOKit.ps

struct BatterySnapshot {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool

    static let unknown = BatterySnapshot(percent: 0, isCharging: false, isPluggedIn: false)
}

enum BatteryReader {
    static func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as NSArray? else {
            return .unknown
        }

        for case let source as CFTypeRef in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = description[kIOPSTypeKey as String] as? String
            if let type, type != (kIOPSInternalBatteryType as String) {
                continue
            }

            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let sourceState = description[kIOPSPowerSourceStateKey as String] as? String
            let pluggedIn = sourceState == (kIOPSACPowerValue as String)

            return BatterySnapshot(percent: percent, isCharging: charging, isPluggedIn: pluggedIn)
        }

        return .unknown
    }
}
