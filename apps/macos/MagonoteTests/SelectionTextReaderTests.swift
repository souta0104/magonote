@testable import Magonote
import AppKit
import XCTest

@MainActor
final class SelectionTextReaderTests: XCTestCase {
    func testReturnsCopiedTextAndLeavesItOnPasteboard() async {
        let pasteboard = makePasteboard()
        pasteboard.setString("before", forType: .string)

        let reader = makeReader(pasteboard: pasteboard) {
            pasteboard.clearContents()
            pasteboard.setString("selected text", forType: .string)
        }

        let text = await reader.read()

        XCTAssertEqual(text, "selected text")
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "selected text"
        )
    }

    func testReturnsNilWhenCopyDoesNotUpdatePasteboard() async {
        let pasteboard = makePasteboard()
        pasteboard.setString("before", forType: .string)
        let reader = makeReader(pasteboard: pasteboard) {}

        let text = await reader.read()

        XCTAssertNil(text)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testReturnsNilWhenCopyProducesNoString() async {
        let pasteboard = makePasteboard()
        pasteboard.setString("before", forType: .string)

        let reader = makeReader(pasteboard: pasteboard) {
            pasteboard.clearContents()
        }

        let text = await reader.read()

        XCTAssertNil(text)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testReturnsNilWhenCopyShortcutCannotBePosted() async {
        let pasteboard = makePasteboard()
        pasteboard.setString("before", forType: .string)
        let reader = PasteboardSelectionTextReader(
            pasteboard: pasteboard,
            pollingAttempts: 1,
            pollingInterval: .milliseconds(0),
            postCopyShortcut: { false }
        )

        let text = await reader.read()

        XCTAssertNil(text)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(UUID().uuidString)
        )
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeReader(
        pasteboard: NSPasteboard,
        copy: @escaping () -> Void
    ) -> PasteboardSelectionTextReader {
        PasteboardSelectionTextReader(
            pasteboard: pasteboard,
            pollingAttempts: 1,
            pollingInterval: .milliseconds(0),
            postCopyShortcut: {
                copy()
                return true
            }
        )
    }
}
