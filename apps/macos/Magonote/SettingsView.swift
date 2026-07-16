import AppKit
import ApplicationServices
import FirebaseAuth
import KeyboardShortcuts
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(CaptureController.self) private var captureController

    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem {
                    Label("アカウント", systemImage: "person.crop.circle")
                }

            ReaderSettingsView()
                .tabItem {
                    Label("Reader", systemImage: "doc.text")
                }

            PermissionSettingsView()
                .tabItem {
                    Label("権限", systemImage: "lock.shield")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("詳細", systemImage: "gearshape.2")
                }
        }
        .environment(sessionStore)
        .environment(captureController)
        .frame(width: 560, height: 390)
        .padding()
    }
}

private struct AccountSettingsView: View {
    @Environment(SessionStore.self) private var sessionStore
    @State private var errorMessage: String?

    var body: some View {
        Form {
            LabeledContent("状態") {
                Text(sessionStore.isSignedIn ? "サインイン済み" : "未サインイン")
            }

            if let emailAddress = sessionStore.emailAddress {
                LabeledContent("メールアドレス", value: emailAddress)
            }

            if let uid = sessionStore.uid {
                LabeledContent("UID") {
                    HStack {
                        Text(uid)
                            .textSelection(.enabled)
                        Button("コピー") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(uid, forType: .string)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                if sessionStore.isSignedIn {
                    Button("サインアウト") {
                        do {
                            try sessionStore.signOut()
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    Button("Google でサインイン") {
                        Task {
                            do {
                                try await sessionStore.signIn()
                                errorMessage = nil
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("セッションをリセット") {
                    do {
                        try sessionStore.resetSession()
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ReaderSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(
                "キャプチャのショートカット",
                name: .readerCapture
            )
        }
        .formStyle(.grouped)
    }
}

private struct PermissionSettingsView: View {
    @Environment(CaptureController.self) private var captureController
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var notificationStatus = UNAuthorizationStatus.notDetermined

    var body: some View {
        Form {
            LabeledContent("Accessibility") {
                statusLabel(
                    enabled: accessibilityTrusted,
                    enabledText: "許可済み",
                    disabledText: "未許可"
                )
            }

            HStack {
                Button("許可をリクエスト") {
                    captureController.promptForAccessibilityPermission()
                    refreshAccessibilityStatus()
                }
                Button("システム設定を開く") {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ) else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
            }

            LabeledContent("通知") {
                statusLabel(
                    enabled: notificationStatus == .authorized,
                    enabledText: "許可済み",
                    disabledText: notificationStatus.description
                )
            }

            Button("通知をリクエスト") {
                Task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])
                    await refreshNotificationStatus()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                refreshAccessibilityStatus()
                await refreshNotificationStatus()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private func statusLabel(
        enabled: Bool,
        enabledText: String,
        disabledText: String
    ) -> some View {
        HStack {
            Circle()
                .fill(enabled ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(enabled ? enabledText : disabledText)
        }
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }
}

private struct AdvancedSettingsView: View {
    @AppStorage(APIClientFactory.serverBaseURLKey)
    private var serverBaseURL = APIClientFactory.productionBaseURL.absoluteString
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("サーバー URL", text: $serverBaseURL)

            Toggle("ログイン時に起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLaunchAtLogin(enabled: enabled)
                }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private extension UNAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            "未確認"
        case .denied:
            "拒否済み"
        case .authorized:
            "許可済み"
        case .provisional:
            "仮許可"
        case .ephemeral:
            "一時許可"
        @unknown default:
            "不明"
        }
    }
}
