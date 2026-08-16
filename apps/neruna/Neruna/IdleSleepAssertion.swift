import Foundation
import IOKit.pwr_mgt

struct IdleSleepAssertionError: LocalizedError {
    var status: IOReturn

    var errorDescription: String? {
        "アイドル睡眠を止められませんでした (\(status))"
    }
}

final class IdleSleepAssertion: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var assertionID: IOPMAssertionID = 0
    nonisolated(unsafe) private var isActive = false

    func acquire(reason: String) throws {
        try lock.withLock {
            if isActive {
                return
            }

            var identifier: IOPMAssertionID = 0
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &identifier
            )
            guard status == kIOReturnSuccess else {
                throw IdleSleepAssertionError(status: status)
            }
            assertionID = identifier
            isActive = true
        }
    }

    func release() {
        lock.withLock {
            guard isActive else {
                return
            }
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
        }
    }

    deinit {
        release()
    }
}
