import AppKit
import Foundation
import NerunaCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class SleepPreventionController {
    private static let configurationDefaultsKey = "awakeConfiguration"
    private static let legacyEnabledDefaultsKey = "isEnabled"

    private(set) var configuration: AwakeConfiguration
    private(set) var power: PowerSnapshot
    private(set) var now: Date
    private(set) var launchesAtLogin: Bool
    private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let assertion: IdleSleepAssertion
    private let privilegedControl: PrivilegedSleepControl
    private let clamshellMonitor: ClamshellMonitor
    private var didStart = false
    private var previouslyKeepingAwake: Bool?
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        assertion: IdleSleepAssertion = IdleSleepAssertion(),
        privilegedControl: PrivilegedSleepControl = PrivilegedSleepControl(),
        clamshellMonitor: ClamshellMonitor = ClamshellMonitor()
    ) {
        self.defaults = defaults
        self.assertion = assertion
        self.privilegedControl = privilegedControl
        self.clamshellMonitor = clamshellMonitor
        self.configuration = Self.loadConfiguration(from: defaults)
        self.power = PowerSnapshotReader.current()
        self.now = Date()
        self.launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    var isEnabled: Bool {
        configuration.desired == .on
    }

    var policy: SleepPreventionPolicy {
        SleepPreventionPolicy(configuration: configuration, power: power, now: now)
    }

    var menuSymbolName: String {
        SleepPreventionStatusText.symbolName(for: policy)
    }

    var menuAccessibilityLabel: String {
        statusText
    }

    var statusText: String {
        SleepPreventionStatusText.text(for: policy)
    }

    var batteryGuardMenuTitle: String {
        if let threshold = configuration.batteryThresholdPercent {
            return "電池が \(threshold)% を下回ったら寝る"
        }
        return "電池が少なくても起き続ける"
    }

    var durationGuardMenuTitle: String {
        if let hours = configuration.durationLimitHours {
            return "\(hours) 時間たったら寝る"
        }
        return "時間制限なし"
    }

    func start() async {
        guard !didStart else {
            return
        }
        didStart = true

        if configuration.desired == .on, configuration.enabledAt == nil {
            configuration.enabledAt = Date()
            persistConfiguration()
        }

        if launchesAtLogin == false {
            setLaunchAtLogin(true)
        }

        await applyCurrentState()
        startClamshellMonitor()
        startRefreshLoop()
    }

    func toggleEnabled() async {
        if isEnabled {
            configuration.desired = .off
            configuration.enabledAt = nil
            configuration.batteryGuardLatched = false
        } else {
            configuration.desired = .on
            configuration.enabledAt = Date()
            configuration.batteryGuardLatched = false
        }
        persistConfiguration()
        await applyCurrentState()
    }

    func setBatteryThreshold(_ percent: Int?) async {
        configuration.batteryThresholdPercent = AwakeConfiguration.sanitizedBatteryThreshold(percent)
        if configuration.batteryThresholdPercent == nil {
            configuration.batteryGuardLatched = false
        }
        persistConfiguration()
        await applyCurrentState()
    }

    func setDurationHours(_ hours: Int?) async {
        configuration.durationLimitSeconds = AwakeConfiguration.seconds(hours: hours)
        persistConfiguration()
        await applyCurrentState()
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLogin(!launchesAtLogin)
    }

    func quit() async {
        configuration.desired = .off
        configuration.enabledAt = nil
        configuration.batteryGuardLatched = false
        persistConfiguration()
        assertion.release()
        refreshTask?.cancel()
        do {
            try privilegedControl.apply(configuration: configuration)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        NSApplication.shared.terminate(nil)
    }

    private func startClamshellMonitor() {
        clamshellMonitor.onClosed = { [weak self] in
            Task { @MainActor in
                self?.turnDisplayOffIfKeepingProcessesAwake()
            }
        }
        clamshellMonitor.start()
    }

    private func turnDisplayOffIfKeepingProcessesAwake() {
        guard policy.shouldKeepAwake else {
            return
        }
        DisplaySleep.request()
    }

    private func startRefreshLoop() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                await self?.refresh()
            }
        }
    }

    private func refresh() async {
        power = PowerSnapshotReader.current()
        now = Date()
        await applyCurrentState()
    }

    private func applyCurrentState() async {
        power = PowerSnapshotReader.current()
        now = Date()

        let currentPolicy = policy
        let next = currentPolicy.advancing()
        if next != configuration {
            configuration = next
            persistConfiguration()
        }

        if previouslyKeepingAwake == true, !currentPolicy.shouldKeepAwake {
            triggerSleepNow()
        }
        previouslyKeepingAwake = currentPolicy.shouldKeepAwake

        await applyIdleAssertion()

        do {
            try privilegedControl.ensureInstalled()
            try privilegedControl.apply(configuration: configuration)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyIdleAssertion() async {
        do {
            if policy.shouldPreventIdleSleep {
                try assertion.acquire(reason: "neruna.prevent-idle-sleep")
            } else {
                assertion.release()
            }
            if lastErrorMessage?.hasPrefix("アイドル睡眠") == true {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func triggerSleepNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SleepDisabledCommand.pmsetPath)
        process.arguments = SleepDisabledCommand.sleepNowArguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persistConfiguration() {
        if let text = try? configuration.fileContents() {
            defaults.set(text, forKey: Self.configurationDefaultsKey)
        }
    }

    private static func loadConfiguration(from defaults: UserDefaults) -> AwakeConfiguration {
        if let text = defaults.string(forKey: configurationDefaultsKey),
           let configuration = try? AwakeConfiguration.parse(fileContents: text)
        {
            return configuration
        }

        if defaults.object(forKey: legacyEnabledDefaultsKey) != nil {
            return AwakeConfiguration(
                desired: defaults.bool(forKey: legacyEnabledDefaultsKey) ? .on : .off
            )
        }

        return AwakeConfiguration(desired: .on)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            lastErrorMessage = nil
        } catch {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            lastErrorMessage = error.localizedDescription
        }
    }
}
