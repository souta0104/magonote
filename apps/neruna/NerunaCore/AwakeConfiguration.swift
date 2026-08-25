import Foundation

public struct AwakeConfiguration: Codable, Equatable, Sendable {
    public var desired: DesiredAwakeState
    public var batteryThresholdPercent: Int?
    public var durationLimitSeconds: Int?
    public var enabledAt: Date?
    public var batteryGuardLatched: Bool

    public static let defaultBatteryThresholdPercent = 15
    public static let batteryResumeHysteresisPercent = 5
    public static let batteryPresets = [5, 10, 15, 20, 30]
    public static let durationHourPresets = [1, 2, 4, 6, 8, 12, 24]
    public static let durationHoursRange = 1...72
    public static let batteryPercentRange = 1...100

    public init(
        desired: DesiredAwakeState = .off,
        batteryThresholdPercent: Int? = Self.defaultBatteryThresholdPercent,
        durationLimitSeconds: Int? = nil,
        enabledAt: Date? = nil,
        batteryGuardLatched: Bool = false
    ) {
        self.desired = desired
        self.batteryThresholdPercent = Self.sanitizedBatteryThreshold(batteryThresholdPercent)
        self.durationLimitSeconds = Self.sanitizedDurationSeconds(durationLimitSeconds)
        self.enabledAt = enabledAt
        self.batteryGuardLatched = batteryGuardLatched
    }

    public var durationLimitHours: Int? {
        guard let durationLimitSeconds else {
            return nil
        }
        return durationLimitSeconds / 3600
    }

    public static func sanitizedBatteryThreshold(_ value: Int?) -> Int? {
        guard let value, batteryPercentRange.contains(value) else {
            return nil
        }
        return value
    }

    public static func sanitizedDurationSeconds(_ value: Int?) -> Int? {
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    public static func seconds(hours: Int?) -> Int? {
        guard let hours, durationHoursRange.contains(hours) else {
            return nil
        }
        return hours * 3600
    }

    public static func parse(fileContents: String) throws -> AwakeConfiguration {
        let trimmed = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == DesiredAwakeState.on.rawValue || trimmed == DesiredAwakeState.off.rawValue {
            return AwakeConfiguration(
                desired: DesiredAwakeState(fileContents: trimmed),
                batteryThresholdPercent: defaultBatteryThresholdPercent
            )
        }
        return try decoder.decode(AwakeConfiguration.self, from: Data(trimmed.utf8))
    }

    public func fileContents() throws -> String {
        let data = try Self.encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AwakeConfigurationError.encodingFailed
        }
        return text + "\n"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum AwakeConfigurationError: Error {
    case encodingFailed
}
