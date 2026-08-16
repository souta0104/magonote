import Foundation

public enum SleepPreventionReason: Equatable, Sendable {
    case off
    case keepingAwake
    case batteryLow
    case durationExpired
}

public struct SleepPreventionPolicy: Equatable, Sendable {
    public var configuration: AwakeConfiguration
    public var power: PowerSnapshot
    public var now: Date

    public init(configuration: AwakeConfiguration, power: PowerSnapshot, now: Date) {
        self.configuration = configuration
        self.power = power
        self.now = now
    }

    public var reason: SleepPreventionReason {
        guard configuration.desired == .on else {
            return .off
        }
        if isDurationExpired {
            return .durationExpired
        }
        if isBatteryBlocking {
            return .batteryLow
        }
        return .keepingAwake
    }

    public var shouldKeepAwake: Bool {
        reason == .keepingAwake
    }

    public var shouldPreventIdleSleep: Bool {
        shouldKeepAwake
    }

    public var shouldKeepAwakeWithLidClosed: Bool {
        shouldKeepAwake
    }

    public var remainingDuration: TimeInterval? {
        guard configuration.desired == .on,
              let seconds = configuration.durationLimitSeconds,
              let enabledAt = configuration.enabledAt
        else {
            return nil
        }
        return enabledAt.addingTimeInterval(TimeInterval(seconds)).timeIntervalSince(now)
    }

    public func advancing() -> AwakeConfiguration {
        var next = configuration

        if configuration.batteryThresholdPercent != nil {
            if !power.isOnBattery {
                next.batteryGuardLatched = false
            } else if let percent = power.batteryPercent, let threshold = configuration.batteryThresholdPercent {
                if percent < threshold {
                    next.batteryGuardLatched = true
                } else if percent >= threshold + AwakeConfiguration.batteryResumeHysteresisPercent {
                    next.batteryGuardLatched = false
                }
            }
        } else {
            next.batteryGuardLatched = false
        }

        if isDurationExpired {
            next.desired = .off
            next.enabledAt = nil
            next.batteryGuardLatched = false
        }

        return next
    }

    private var isDurationExpired: Bool {
        guard configuration.desired == .on,
              let seconds = configuration.durationLimitSeconds,
              let enabledAt = configuration.enabledAt
        else {
            return false
        }
        return now >= enabledAt.addingTimeInterval(TimeInterval(seconds))
    }

    private var isBatteryBlocking: Bool {
        guard configuration.desired == .on,
              let threshold = configuration.batteryThresholdPercent
        else {
            return false
        }
        guard power.isOnBattery else {
            return false
        }
        guard let percent = power.batteryPercent else {
            return configuration.batteryGuardLatched
        }
        if percent < threshold {
            return true
        }
        if percent >= threshold + AwakeConfiguration.batteryResumeHysteresisPercent {
            return false
        }
        return configuration.batteryGuardLatched
    }
}
