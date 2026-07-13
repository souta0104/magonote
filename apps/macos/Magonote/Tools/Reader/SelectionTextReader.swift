import AppKit
import Carbon.HIToolbox

@MainActor
protocol SelectionTextReading {
    func read() async -> String?
}

@MainActor
struct PasteboardSelectionTextReader: SelectionTextReading {
    private let pasteboard: NSPasteboard
    private let pollingAttempts: Int
    private let pollingInterval: Duration
    private let postCopyShortcut: () -> Bool

    init(
        pasteboard: NSPasteboard = .general,
        pollingAttempts: Int = 20,
        pollingInterval: Duration = .milliseconds(50)
    ) {
        self.init(
            pasteboard: pasteboard,
            pollingAttempts: pollingAttempts,
            pollingInterval: pollingInterval,
            postCopyShortcut: Self.postCopyShortcut
        )
    }

    init(
        pasteboard: NSPasteboard,
        pollingAttempts: Int,
        pollingInterval: Duration,
        postCopyShortcut: @escaping () -> Bool
    ) {
        self.pasteboard = pasteboard
        self.pollingAttempts = pollingAttempts
        self.pollingInterval = pollingInterval
        self.postCopyShortcut = postCopyShortcut
    }

    func read() async -> String? {
        let initialChangeCount = pasteboard.changeCount

        guard postCopyShortcut() else {
            return nil
        }

        for _ in 0..<pollingAttempts {
            try? await Task.sleep(for: pollingInterval)
            guard !Task.isCancelled else {
                return nil
            }

            guard pasteboard.changeCount != initialChangeCount else {
                continue
            }

            guard
                let text = pasteboard.string(forType: .string),
                !text.isEmpty
            else {
                return nil
            }

            return text
        }

        return nil
    }

    private static func postCopyShortcut() -> Bool {
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
}
