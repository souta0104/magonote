public struct SleepGate: Sendable {
    public var readDesired: @Sendable () throws -> DesiredAwakeState
    public var setKeepAwakeWithLidClosed: @Sendable (Bool) throws -> Void

    public init(
        readDesired: @escaping @Sendable () throws -> DesiredAwakeState,
        setKeepAwakeWithLidClosed: @escaping @Sendable (Bool) throws -> Void
    ) {
        self.readDesired = readDesired
        self.setKeepAwakeWithLidClosed = setKeepAwakeWithLidClosed
    }

    public func apply() throws {
        let policy = SleepPreventionPolicy(isEnabled: try readDesired() == .on)
        try setKeepAwakeWithLidClosed(policy.shouldKeepAwakeWithLidClosed)
    }
}
