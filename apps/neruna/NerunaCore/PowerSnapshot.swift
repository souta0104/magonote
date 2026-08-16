import IOKit.ps

public struct PowerSnapshot: Equatable, Sendable {
    public var isOnBattery: Bool
    public var batteryPercent: Int?

    public init(isOnBattery: Bool, batteryPercent: Int?) {
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
    }

    public static let unknown = PowerSnapshot(isOnBattery: false, batteryPercent: nil)
}

public enum PowerSnapshotReader: Sendable {
    public static func current() -> PowerSnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unknown
        }

        let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        let isOnBattery = providing == "Battery Power"
        let percent = batteryPercent(from: snapshot)
        return PowerSnapshot(isOnBattery: isOnBattery, batteryPercent: percent)
    }

    private static func batteryPercent(from snapshot: CFTypeRef) -> Int? {
        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any]
            else {
                continue
            }
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
               maxCapacity > 0
            {
                return Swift.min(100, Swift.max(0, (current * 100) / maxCapacity))
            }
            if let current = description[kIOPSCurrentCapacityKey] as? Int {
                return Swift.min(100, Swift.max(0, current))
            }
        }
        return nil
    }
}
