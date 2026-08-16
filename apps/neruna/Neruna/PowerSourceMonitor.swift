import Foundation
import IOKit.ps

final class PowerSourceMonitor: @unchecked Sendable {
    var onChange: (@Sendable () -> Void)?

    private var source: CFRunLoopSource?
    private var box: HandlerBox?

    func start() {
        let box = HandlerBox { [weak self] in
            self?.onChange?()
        }
        self.box = box

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else {
                return
            }
            Unmanaged<HandlerBox>.fromOpaque(context).takeUnretainedValue().handler()
        }

        guard let loopSource = IOPSNotificationCreateRunLoopSource(
            callback,
            Unmanaged.passUnretained(box).toOpaque()
        )?.takeRetainedValue() else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), loopSource, .commonModes)
        source = loopSource
    }
}

private final class HandlerBox: @unchecked Sendable {
    let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}
