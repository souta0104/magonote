import Foundation

public enum DesiredAwakeState: String, Sendable {
    case on
    case off

    public init(fileContents: String) {
        let trimmed = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
        self = trimmed == Self.on.rawValue ? .on : .off
    }

    public var fileContents: String {
        rawValue + "\n"
    }
}
