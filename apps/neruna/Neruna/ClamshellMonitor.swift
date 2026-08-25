import Foundation
import IOKit

final class ClamshellMonitor: @unchecked Sendable {
    var onClosed: (@Sendable () -> Void)?

    private var service: io_object_t = 0
    private var notification: io_object_t = 0
    private var port: IONotificationPortRef?
    private var wasClosed = false

    func start() {
        wasClosed = Self.isClosed()
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return
        }

        guard let createdPort = IONotificationPortCreate(kIOMainPortDefault) else {
            return
        }
        port = createdPort
        IONotificationPortSetDispatchQueue(createdPort, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            createdPort,
            service,
            kIOGeneralInterest,
            { refcon, _, _, _ in
                guard let refcon else {
                    return
                }
                Unmanaged<ClamshellMonitor>.fromOpaque(refcon).takeUnretainedValue().handleChange()
            },
            context,
            &notification
        )
        if result != KERN_SUCCESS {
            return
        }
    }

    private func handleChange() {
        let closed = Self.isClosed()
        if closed, !wasClosed {
            onClosed?()
        }
        wasClosed = closed
    }

    static func isClosed() -> Bool {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else {
            return false
        }
        defer {
            IOObjectRelease(entry)
        }
        guard let raw = IORegistryEntryCreateCFProperty(
            entry,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return false
        }
        if let closed = raw as? Bool {
            return closed
        }
        if let number = raw as? NSNumber {
            return number.boolValue
        }
        return false
    }
}
