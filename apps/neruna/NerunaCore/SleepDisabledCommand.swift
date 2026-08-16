public enum SleepDisabledCommand: Sendable {
    public static let pmsetPath = "/usr/bin/pmset"

    public static func arguments(keepAwakeWithLidClosed: Bool) -> [String] {
        ["-a", "disablesleep", keepAwakeWithLidClosed ? "1" : "0"]
    }

    public static let sleepNowArguments = ["sleepnow"]
}

public enum SleepDisabledStatus: Sendable {
    public static func isDisabled(pmsetOutput: String) -> Bool? {
        let pattern = /SleepDisabled\s*(\d+)/
        guard let match = pmsetOutput.firstMatch(of: pattern) else {
            return nil
        }
        return match.1 != "0"
    }
}
