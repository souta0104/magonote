public enum HelperInvocation: Equatable, Sendable {
    case applyOn
    case applyOff
    case run
    case status

    public init?(arguments: [String]) {
        guard arguments.count == 1 else {
            return nil
        }

        switch arguments[0] {
        case "apply-on":
            self = .applyOn
        case "apply-off":
            self = .applyOff
        case "run":
            self = .run
        case "status":
            self = .status
        default:
            return nil
        }
    }

    public var argument: String {
        switch self {
        case .applyOn:
            "apply-on"
        case .applyOff:
            "apply-off"
        case .run:
            "run"
        case .status:
            "status"
        }
    }
}
