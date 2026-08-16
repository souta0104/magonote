import Foundation
import NerunaCore

struct PrivilegedSleepControlError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

struct PrivilegedSleepControl: Sendable {
    func ensureInstalled() throws {
        if canCallHelper() {
            return
        }
        try HelperInstaller.install()
        guard canCallHelper() else {
            throw PrivilegedSleepControlError(
                message: "管理者権限の helper を導入できませんでした"
            )
        }
    }

    func apply(configuration: AwakeConfiguration) throws {
        let invocation: HelperInvocation = configuration.desired == .on ? .applyOn : .applyOff
        _ = try runHelper(invocation, stdin: try configuration.fileContents())
    }

    private func canCallHelper() -> Bool {
        (try? runHelper(.status)) != nil
    }

    @discardableResult
    private func runHelper(_ invocation: HelperInvocation, stdin: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", NerunaPaths.helperPath, invocation.argument]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if stdin != nil {
            process.standardInput = Pipe()
        }
        try process.run()
        if let stdin, let input = process.standardInput as? Pipe {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try input.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let errorOutput = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw PrivilegedSleepControlError(
                message: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "neruna-helper を実行できませんでした"
                    : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}
