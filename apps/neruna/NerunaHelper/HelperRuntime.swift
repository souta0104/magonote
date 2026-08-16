import Darwin
import Foundation
import NerunaCore

final class HelperRuntime: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: HelperEnvironment
    private var previouslyKeepingAwake: Bool?

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
            try applyIncoming(desired: .on)
        case .applyOff:
            try requireRoot()
            try applyIncoming(desired: .off)
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

    private func applyIncoming(desired: DesiredAwakeState) throws {
        if let incoming = try readStdinConfiguration() {
            try writeConfiguration(incoming)
        } else {
            var configuration = try readConfiguration()
            if desired == .on, configuration.desired == .off {
                configuration.enabledAt = Date()
            }
            if desired == .off {
                configuration.enabledAt = nil
                configuration.batteryGuardLatched = false
            }
            configuration.desired = desired
            try writeConfiguration(configuration)
        }
        try applyGate(sleepNowOnTransition: false)
    }

    private func readStdinConfiguration() throws -> AwakeConfiguration? {
        if isatty(FileHandle.standardInput.fileDescriptor) != 0 {
            return nil
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return try AwakeConfiguration.parse(fileContents: text)
    }

    private func writeConfiguration(_ configuration: AwakeConfiguration) throws {
        let url = URL(fileURLWithPath: NerunaPaths.desiredStatePath)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try configuration.fileContents().write(to: url, atomically: true, encoding: .utf8)
    }

    private func readConfiguration() throws -> AwakeConfiguration {
        let url = URL(fileURLWithPath: NerunaPaths.desiredStatePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return AwakeConfiguration()
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try AwakeConfiguration.parse(fileContents: contents)
    }

    private func applyGate(sleepNowOnTransition: Bool) throws {
        let keepingAwake = try makeGate().apply(
            sleepNowOnTransition: sleepNowOnTransition,
            previouslyKeepingAwake: previouslyKeepingAwake
        )
        previouslyKeepingAwake = keepingAwake
    }

    private func makeGate() -> SleepGate {
        SleepGate(
            readConfiguration: { [self] in
                try self.readConfiguration()
            },
            readPower: { [environment] in
                environment.currentPower()
            },
            writeConfiguration: { [self] configuration in
                try self.writeConfiguration(configuration)
            },
            setKeepAwake: { [environment] keepAwake in
                try environment.setKeepAwakeWithLidClosed(keepAwake)
            },
            sleepNow: { [environment] in
                try environment.sleepNow()
            }
        )
    }

    private func printStatus() throws {
        let configuration = try readConfiguration()
        let policy = SleepPreventionPolicy(
            configuration: configuration,
            power: environment.currentPower(),
            now: Date()
        )
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
        let batteryText = policy.power.batteryPercent.map(String.init) ?? "unknown"

        print("desired=\(configuration.desired.rawValue)")
        print("reason=\(policy.reason.label)")
        print("battery=\(batteryText)")
        print("onBattery=\(policy.power.isOnBattery)")
        print("sleepDisabled=\(sleepDisabledText)")
    }

    private func runDaemon() throws {
        try applyGate(sleepNowOnTransition: false)
        environment.startPeriodicRefresh(interval: 5) { [self] in
            do {
                try applyGate(sleepNowOnTransition: true)
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

private extension SleepPreventionReason {
    var label: String {
        switch self {
        case .off:
            "off"
        case .keepingAwake:
            "keepingAwake"
        case .batteryLow:
            "batteryLow"
        case .durationExpired:
            "durationExpired"
        }
    }
}
