import Foundation
import NerunaCore

final class HelperRuntime: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: HelperEnvironment

    init(
        fileManager: FileManager = .default,
        environment: HelperEnvironment = LiveHelperEnvironment()
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func run(arguments: [String]) throws {
        guard let invocation = HelperInvocation(arguments: arguments) else {
            throw HelperError.invalidArguments
        }

        switch invocation {
        case .applyOn:
            try requireRoot()
            try writeDesired(.on)
            try applyGate()
        case .applyOff:
            try requireRoot()
            try writeDesired(.off)
            try applyGate()
        case .status:
            try requireRoot()
            try printStatus()
        case .run:
            try requireRoot()
            try runDaemon()
        }
    }

    private func requireRoot() throws {
        guard environment.isRoot else {
            throw HelperError.notRoot
        }
    }

    private func writeDesired(_ state: DesiredAwakeState) throws {
        let url = URL(fileURLWithPath: NerunaPaths.desiredStatePath)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try state.fileContents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readDesired() throws -> DesiredAwakeState {
        let url = URL(fileURLWithPath: NerunaPaths.desiredStatePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return .off
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return DesiredAwakeState(fileContents: contents)
    }

    private func applyGate() throws {
        try makeGate().apply()
    }

    private func makeGate() -> SleepGate {
        SleepGate(
            readDesired: { [self] in
                try self.readDesired()
            },
            isOnACPower: { [environment] in
                environment.isOnACPower()
            },
            setKeepAwakeWithLidClosed: { [environment] keepAwake in
                try environment.setKeepAwakeWithLidClosed(keepAwake)
            }
        )
    }

    private func printStatus() throws {
        let desired = try readDesired()
        let onAC = environment.isOnACPower()
        let output = try environment.pmsetCustomOutput()
        let sleepDisabled = SleepDisabledStatus.isDisabled(pmsetOutput: output)
        let sleepDisabledText = switch sleepDisabled {
        case true?:
            "1"
        case false?:
            "0"
        case nil:
            "unknown"
        }

        print("desired=\(desired.rawValue)")
        print("ac=\(onAC)")
        print("sleepDisabled=\(sleepDisabledText)")
    }

    private func runDaemon() throws {
        try applyGate()
        environment.startPowerSourceMonitor { [self] in
            do {
                try applyGate()
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
            }
        }
        environment.startPeriodicRefresh(interval: 5) { [self] in
            do {
                try applyGate()
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
            }
        }
        environment.runLoop()
    }
}

enum HelperError: LocalizedError {
    case invalidArguments
    case notRoot
    case pmsetFailed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: neruna-helper apply-on|apply-off|status|run"
        case .notRoot:
            return "neruna-helper must run as root"
        case let .pmsetFailed(status, message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "pmset exited with status \(status)"
            }
            return "pmset exited with status \(status): \(trimmed)"
        }
    }
}
