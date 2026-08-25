import Foundation
import NerunaCore

enum HelperInstaller {
    static func install() throws {
        guard let bundledHelper = bundledHelperURL else {
            throw PrivilegedSleepControlError(message: "アプリに neruna-helper が入っていません")
        }
        guard let bundledPlist = bundledResourceURL(name: "app.soprog.magonote.neruna.helper", extension: "plist")
        else {
            throw PrivilegedSleepControlError(message: "アプリに LaunchDaemon 定義が入っていません")
        }
        guard let bundledSudoers = bundledResourceURL(name: "sudoers", extension: nil) else {
            throw PrivilegedSleepControlError(message: "アプリに sudoers が入っていません")
        }
        guard let privilegedScript = bundledResourceURL(name: "install-privileged", extension: "sh")
        else {
            throw PrivilegedSleepControlError(message: "アプリに導入スクリプトが入っていません")
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("neruna-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: staging)
        }

        let stagedHelper = staging.appendingPathComponent("neruna-helper")
        let stagedPlist = staging.appendingPathComponent("plist")
        let stagedSudoers = staging.appendingPathComponent("sudoers")
        try FileManager.default.copyItem(at: bundledHelper, to: stagedHelper)
        try FileManager.default.copyItem(at: bundledPlist, to: stagedPlist)
        try FileManager.default.copyItem(at: bundledSudoers, to: stagedSudoers)

        let script =
            "do shell script \"/bin/bash \(quoteForAppleScript(privilegedScript.path)) \(quoteForAppleScript(staging.path))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorOutput = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw PrivilegedSleepControlError(
                message: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "管理者権限の導入に失敗しました"
                    : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static var bundledHelperURL: URL? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/neruna-helper")
    }

    private static func bundledResourceURL(name: String, extension ext: String?) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static func quoteForAppleScript(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
