public struct SleepPreventionPolicy: Equatable, Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public var shouldPreventIdleSleep: Bool {
        isEnabled
    }

    public var shouldKeepAwakeWithLidClosed: Bool {
        isEnabled
    }
}
