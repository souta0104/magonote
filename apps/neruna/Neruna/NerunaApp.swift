import AppKit
import NerunaCore
import SwiftUI

@main
struct NerunaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(appDelegate.controller)
        } label: {
            Image(systemName: appDelegate.controller.menuSymbolName)
                .accessibilityLabel(appDelegate.controller.menuAccessibilityLabel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SleepPreventionController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await controller.start()
        }
    }
}

private struct MenuBarContentView: View {
    @Environment(SleepPreventionController.self) private var controller

    var body: some View {
        Button(controller.isEnabled ? "neruna: オン" : "neruna: オフ") {
            Task {
                await controller.toggleEnabled()
            }
        }

        Text(controller.statusText)

        if let message = controller.lastErrorMessage {
            Text(message)
        }

        Divider()

        Menu(controller.batteryGuardMenuTitle) {
            Button("オフ") {
                Task {
                    await controller.setBatteryThreshold(nil)
                }
            }
            ForEach(AwakeConfiguration.batteryPresets, id: \.self) { percent in
                Button("\(percent)%") {
                    Task {
                        await controller.setBatteryThreshold(percent)
                    }
                }
            }
        }

        Menu(controller.durationGuardMenuTitle) {
            Button("オフ") {
                Task {
                    await controller.setDurationHours(nil)
                }
            }
            ForEach(AwakeConfiguration.durationHourPresets, id: \.self) { hours in
                Button("\(hours) 時間") {
                    Task {
                        await controller.setDurationHours(hours)
                    }
                }
            }
        }

        SettingsLink {
            Text("設定…")
        }

        Divider()

        Button(controller.launchesAtLogin ? "ログイン時に起動: オン" : "ログイン時に起動: オフ") {
            controller.toggleLaunchAtLogin()
        }

        Divider()

        Button("neruna を終了") {
            Task {
                await controller.quit()
            }
        }
        .keyboardShortcut("q")
    }
}
