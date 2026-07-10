import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KeyboardShortcuts
import MagonoteKit
import Observation
import UserNotifications

@MainActor
@Observable
final class CaptureController {
    private(set) var iconState = MenuBarIconState.idle
    private(set) var isCapturing = false
    private(set) var lastMessage: String?

    private let sessionStore: SessionStore
    private var feedbackResetTask: Task<Void, Never>?

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        KeyboardShortcuts.onKeyUp(for: .readerCapture) { [weak self] in
            Task { @MainActor in
                await self?.capture()
            }
        }
    }

    func capture() async {
        guard !isCapturing else {
            return
        }

        isCapturing = true
        defer {
            isCapturing = false
        }

        await requestNotificationAuthorizationIfNeeded()

        do {
            let result = try await performCapture()
            await showFeedback(
                state: .success,
                message: "\(result.sourceAppName) から \(result.characterCount.formatted()) 文字をキャプチャ"
            )
        } catch let error as CaptureError {
            await showFeedback(state: .failure, message: error.message)
        } catch let error as APIError {
            await showFeedback(
                state: .failure,
                message: CaptureError.network(error).message
            )
        } catch {
            await showFeedback(
                state: .failure,
                message: CaptureError.network(.network(error)).message
            )
        }
    }

    func promptForAccessibilityPermission() {
        let options = [
            "AXTrustedCheckOptionPrompt" as CFString: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func performCapture() async throws -> CaptureResult {
        guard isAccessibilityTrusted else {
            promptForAccessibilityPermission()
            throw CaptureError.notTrusted
        }

        guard sessionStore.isSignedIn else {
            throw CaptureError.notSignedIn
        }

        let sourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        guard postCopyShortcut() else {
            snapshot.restore(to: pasteboard)
            throw CaptureError.nothingSelected
        }

        do {
            let text = try await waitForSelectedText(
                on: pasteboard,
                after: initialChangeCount
            )
            snapshot.restore(to: pasteboard)

            let newDocument = NewDocument(
                text: text,
                sourceAppName: sourceAppName,
                sourceMachineName: Host.current().localizedName
                    ?? ProcessInfo.processInfo.hostName,
                capturedAt: .now
            )
            _ = try await APIClientFactory.makeClient().createDocument(newDocument)

            return CaptureResult(
                sourceAppName: sourceAppName,
                characterCount: text.count
            )
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }
    }

    private func postCopyShortcut() -> Bool {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: false
            )
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func waitForSelectedText(
        on pasteboard: NSPasteboard,
        after initialChangeCount: Int
    ) async throws -> String {
        for _ in 0 ..< 20 {
            try await Task.sleep(for: .milliseconds(50))

            guard pasteboard.changeCount != initialChangeCount else {
                continue
            }

            guard
                let text = pasteboard.string(forType: .string),
                !text.isEmpty
            else {
                throw CaptureError.nothingSelected
            }

            return text
        }

        throw CaptureError.nothingSelected
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }

        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func showFeedback(
        state: MenuBarIconState,
        message: String
    ) async {
        iconState = state
        lastMessage = message
        feedbackResetTask?.cancel()

        let content = UNMutableNotificationContent()
        content.title = "Magonote Reader"
        content.body = message
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )

        feedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else {
                return
            }
            self?.iconState = .idle
        }
    }
}

enum MenuBarIconState {
    case idle
    case success
    case failure

    var symbolName: String {
        switch self {
        case .idle:
            "hand.point.up.left"
        case .success:
            "checkmark.circle"
        case .failure:
            "exclamationmark.circle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle:
            "Magonote"
        case .success:
            "キャプチャ成功"
        case .failure:
            "キャプチャ失敗"
        }
    }
}

enum CaptureError: Error {
    case notTrusted
    case notSignedIn
    case nothingSelected
    case network(APIError)

    var message: String {
        switch self {
        case .notTrusted:
            "Accessibility の許可が必要です"
        case .notSignedIn:
            "Google へのサインインが必要です"
        case .nothingSelected:
            "選択中のテキストを取得できませんでした"
        case let .network(error):
            "保存に失敗しました: \(error.userFacingMessage)"
        }
    }
}

private struct CaptureResult {
    let sourceAppName: String
    let characterCount: Int
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

private extension APIError {
    var userFacingMessage: String {
        switch self {
        case .unauthorized:
            "認証が必要です"
        case .forbidden:
            "このアカウントは許可されていません"
        case .notFound:
            "保存先が見つかりません"
        case let .validation(message):
            message
        case let .server(status, _):
            "サーバーエラー (HTTP \(status))"
        case .network:
            "ネットワークに接続できません"
        case .decoding:
            "サーバーの応答を読み取れません"
        }
    }
}
