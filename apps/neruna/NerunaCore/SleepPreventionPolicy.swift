public struct SleepPreventionPolicy: Equatable, Sendable {
    public var isEnabled: Bool
    public var isOnACPower: Bool

    public init(isEnabled: Bool, isOnACPower: Bool) {
        self.isEnabled = isEnabled
        self.isOnACPower = isOnACPower
    }

    public var shouldPreventIdleSleep: Bool {
        isEnabled
    }

    public var shouldKeepAwakeWithLidClosed: Bool {
        isEnabled && isOnACPower
    }
}
