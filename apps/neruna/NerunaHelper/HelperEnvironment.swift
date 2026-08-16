import Foundation
import IOKit.ps
import NerunaCore

protocol HelperEnvironment: Sendable {
    var isRoot: Bool { get }
    func isOnACPower() -> Bool
    func setKeepAwakeWithLidClosed(_ keepAwake: Bool) throws
    func pmsetCustomOutput() throws -> String
    func startPowerSourceMonitor(handler: @escaping @Sendable () -> Void)
    func startPeriodicRefresh(interval: TimeInterval, handler: @escaping @Sendable () -> Void)
    func runLoop()
}

final class LiveHelperEnvironment: HelperEnvironment, @unchecked Sendable {
    private var powerSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?

    var isRoot: Bool {
        geteuid() == 0
    }

    func isOnACPower() -> Bool {
        PowerSource.isOnACPower()
    }

    func setKeepAwakeWithLidClosed(_ keepAwake: Bool) throws {
        let current = try pmsetCustomOutput()
        if SleepDisabledStatus.isDisabled(pmsetOutput: current) == keepAwake {
            return
        }
        try runPmset(arguments: SleepDisabledCommand.arguments(keepAwakeWithLidClosed: keepAwake))
    }

    func pmsetCustomOutput() throws -> String {
        try runPmset(arguments: ["-g"])
    }

    func startPowerSourceMonitor(handler: @escaping @Sendable () -> Void) {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else {
                return
            }
            let box = Unmanaged<HandlerBox>.fromOpaque(context).takeUnretainedValue()
            box.handler()
        }
        let box = HandlerBox(handler: handler)
        let context = Unmanaged.passRetained(box).toOpaque()
        guard let loopSource = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue()
        else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loopSource, .commonModes)
        powerSource = loopSource
    }

    func startPeriodicRefresh(interval: TimeInterval, handler: @escaping @Sendable () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: handler)
        timer.resume()
        self.timer = timer
    }

    func runLoop() {
        RunLoop.main.run()
    }

    @discardableResult
    private func runPmset(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SleepDisabledCommand.pmsetPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let errorOutput = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw HelperError.pmsetFailed(
                status: process.terminationStatus,
                message: errorOutput.isEmpty ? output : errorOutput
            )
        }
        return output
    }
}

private final class HandlerBox: @unchecked Sendable {
    let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}
