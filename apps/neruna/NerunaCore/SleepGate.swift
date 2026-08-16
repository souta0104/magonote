public struct SleepGate: Sendable {
    public var readDesired: @Sendable () throws -> DesiredAwakeState
    public var isOnACPower: @Sendable () -> Bool
    public var setKeepAwakeWithLidClosed: @Sendable (Bool) throws -> Void

    public init(
        readDesired: @escaping @Sendable () throws -> DesiredAwakeState,
        isOnACPower: @escaping @Sendable () -> Bool,
        setKeepAwakeWithLidClosed: @escaping @Sendable (Bool) throws -> Void
    ) {
        self.readDesired = readDesired
        self.isOnACPower = isOnACPower
        self.setKeepAwakeWithLidClosed = setKeepAwakeWithLidClosed
    }

    public func apply() throws {
        let policy = SleepPreventionPolicy(
            isEnabled: try readDesired() == .on,
            isOnACPower: isOnACPower()
        )
        try setKeepAwakeWithLidClosed(policy.shouldKeepAwakeWithLidClosed)
    }
}
