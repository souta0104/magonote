import AppKit
import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct MagonoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore: SessionStore
    @State private var captureController: CaptureController

    init() {
        let sessionStore = SessionStore()
        _sessionStore = State(initialValue: sessionStore)
        _captureController = State(
            initialValue: CaptureController(sessionStore: sessionStore)
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(sessionStore)
                .environment(captureController)
                .task {
                    sessionStore.start()
                }
        } label: {
            Image(systemName: captureController.iconState.symbolName)
                .accessibilityLabel(captureController.iconState.accessibilityLabel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(sessionStore)
                .environment(captureController)
                .task {
                    sessionStore.start()
                }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()

        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc
    private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else {
            return
        }

        GIDSignIn.sharedInstance.handle(url)
    }
}

private struct MenuBarContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(CaptureController.self) private var captureController

    var body: some View {
        if !sessionStore.isSignedIn {
            Text("設定から Google にサインインしてください")
        } else if !captureController.isAccessibilityTrusted {
            Text("設定から Accessibility を許可してください")
        }

        Button("今すぐキャプチャ") {
            Task {
                await captureController.capture()
            }
        }
        .disabled(captureController.isCapturing)

        if let message = captureController.lastMessage {
            Text(message)
        }

        Divider()
        SettingsLink {
            Text("設定…")
        }

        Button("Magonote を終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
