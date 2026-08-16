import AppKit
import Foundation
import NerunaCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class SleepPreventionController {
    private static let enabledDefaultsKey = "isEnabled"

    private(set) var isEnabled: Bool
    private(set) var launchesAtLogin: Bool
    private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let assertion: IdleSleepAssertion
    private let privilegedControl: PrivilegedSleepControl
    private var didStart = false

    init(
        defaults: UserDefaults = .standard,
        assertion: IdleSleepAssertion = IdleSleepAssertion(),
        privilegedControl: PrivilegedSleepControl = PrivilegedSleepControl()
    ) {
        self.defaults = defaults
        self.assertion = assertion
        self.privilegedControl = privilegedControl
        if defaults.object(forKey: Self.enabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        }
        self.launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    var policy: SleepPreventionPolicy {
        SleepPreventionPolicy(isEnabled: isEnabled)
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

    func start() async {
        guard !didStart else {
            return
        }
        didStart = true

        if launchesAtLogin == false {
            setLaunchAtLogin(true)
        }

        await applyCurrentState()
    }

    func toggleEnabled() async {
        isEnabled.toggle()
        persistEnabled()
        await applyCurrentState()
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLogin(!launchesAtLogin)
    }

    func quit() async {
        isEnabled = false
        persistEnabled()
        assertion.release()
        do {
            try privilegedControl.apply(desired: .off)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        NSApplication.shared.terminate(nil)
    }

    private func applyCurrentState() async {
        persistEnabled()
        await applyIdleAssertion()

        do {
            try privilegedControl.ensureInstalled()
            try privilegedControl.apply(desired: isEnabled ? .on : .off)
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

    private func persistEnabled() {
        defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
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
