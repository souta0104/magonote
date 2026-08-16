public enum HelperProtocol: Sendable {
    public static let version = 2

    public static func isCompatible(statusOutput: String) -> Bool {
        let pattern = /protocol=(\d+)/
        guard let match = statusOutput.firstMatch(of: pattern),
              let parsed = Int(match.1)
        else {
            return false
        }
        return parsed >= version
    }
}
