import AppKit
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
        Button(controller.isEnabled ? "寝るな: オン" : "寝るな: オフ") {
            Task {
                await controller.toggleEnabled()
            }
        }

        Text(controller.statusText)
        Text("電源接続中だけ、蓋を閉じてもスリープしません")

        if let message = controller.lastErrorMessage {
            Text(message)
        }

        Divider()

        Button(controller.launchesAtLogin ? "ログイン時に起動: オン" : "ログイン時に起動: オフ") {
            controller.toggleLaunchAtLogin()
        }

        Divider()

        Button("寝るなを終了") {
            Task {
                await controller.quit()
            }
        }
        .keyboardShortcut("q")
    }
}
