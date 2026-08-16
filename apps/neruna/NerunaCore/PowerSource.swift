import IOKit.ps

public enum PowerSource: Sendable {
    public static func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        guard let raw = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() else {
            return false
        }
        return (raw as String) == "AC Power"
    }
}
