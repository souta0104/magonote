import Foundation

public struct SleepGate: Sendable {
    public var readConfiguration: @Sendable () throws -> AwakeConfiguration
    public var readPower: @Sendable () -> PowerSnapshot
    public var now: @Sendable () -> Date
    public var writeConfiguration: @Sendable (AwakeConfiguration) throws -> Void
    public var setKeepAwake: @Sendable (Bool) throws -> Void
    public var sleepNow: @Sendable () throws -> Void

    public init(
        readConfiguration: @escaping @Sendable () throws -> AwakeConfiguration,
        readPower: @escaping @Sendable () -> PowerSnapshot,
        now: @escaping @Sendable () -> Date = Date.init,
        writeConfiguration: @escaping @Sendable (AwakeConfiguration) throws -> Void,
        setKeepAwake: @escaping @Sendable (Bool) throws -> Void,
        sleepNow: @escaping @Sendable () throws -> Void
    ) {
        self.readConfiguration = readConfiguration
        self.readPower = readPower
        self.now = now
        self.writeConfiguration = writeConfiguration
        self.setKeepAwake = setKeepAwake
        self.sleepNow = sleepNow
    }

    @discardableResult
    public func apply(sleepNowOnTransition: Bool, previouslyKeepingAwake: Bool?) throws -> Bool {
        let configuration = try readConfiguration()
        let policy = SleepPreventionPolicy(
            configuration: configuration,
            power: readPower(),
            now: now()
        )
        let next = policy.advancing()
        if next != configuration {
            try writeConfiguration(next)
        }
        try setKeepAwake(policy.shouldKeepAwake)
        if sleepNowOnTransition, previouslyKeepingAwake == true, !policy.shouldKeepAwake {
            try sleepNow()
        }
        return policy.shouldKeepAwake
    }
}
