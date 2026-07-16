import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let readerCapture = Self(
        "readerCapture",
        default: .init(.c, modifiers: [.control, .option, .command])
    )
}
