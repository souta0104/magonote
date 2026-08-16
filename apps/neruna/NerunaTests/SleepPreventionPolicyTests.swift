import Foundation
import NerunaCore
import XCTest

final class SleepPreventionPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testKeepsAwakeWhenEnabledWithoutGuards() {
        let policy = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: nil,
                enabledAt: now
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 8),
            now: now
        )

        XCTAssertEqual(policy.reason, .keepingAwake)
        XCTAssertEqual(policy.shouldKeepAwakeWithLidClosed, true)
    }

    func testSleepsWhenBatteryIsBelowThresholdOnBattery() {
        let policy = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: 15,
                enabledAt: now
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 14),
            now: now
        )

        XCTAssertEqual(policy.reason, .batteryLow)
        XCTAssertEqual(policy.shouldKeepAwake, false)
        XCTAssertEqual(policy.advancing().batteryGuardLatched, true)
    }

    func testDoesNotTripBatteryGuardOnACPower() {
        let policy = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: 15,
                enabledAt: now
            ),
            power: PowerSnapshot(isOnBattery: false, batteryPercent: 10),
            now: now
        )

        XCTAssertEqual(policy.reason, .keepingAwake)
        XCTAssertEqual(policy.advancing().batteryGuardLatched, false)
    }

    func testKeepsBatteryGuardLatchedUntilHysteresisClears() {
        let latched = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: 15,
                enabledAt: now,
                batteryGuardLatched: true
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 17),
            now: now
        )

        XCTAssertEqual(latched.reason, .batteryLow)
        XCTAssertEqual(latched.advancing().batteryGuardLatched, true)

        let cleared = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: 15,
                enabledAt: now,
                batteryGuardLatched: true
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 20),
            now: now
        )

        XCTAssertEqual(cleared.reason, .keepingAwake)
        XCTAssertEqual(cleared.advancing().batteryGuardLatched, false)
    }

    func testSleepsWhenDurationExpiresAndTurnsDesiredOff() {
        let policy = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: nil,
                durationLimitSeconds: 3600,
                enabledAt: now.addingTimeInterval(-3600)
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 80),
            now: now
        )

        XCTAssertEqual(policy.reason, .durationExpired)
        XCTAssertEqual(policy.shouldKeepAwake, false)

        let next = policy.advancing()
        XCTAssertEqual(next.desired, .off)
        XCTAssertNil(next.enabledAt)
    }

    func testKeepsAwakeBeforeDurationExpires() {
        let policy = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: nil,
                durationLimitSeconds: 3600,
                enabledAt: now.addingTimeInterval(-3599)
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 80),
            now: now
        )

        XCTAssertEqual(policy.reason, .keepingAwake)
        XCTAssertEqual(policy.remainingDuration, 1)
    }

    func testUnknownBatteryPercentDoesNotTripGuard() {
        let policy = SleepPreventionPolicy(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: 15,
                enabledAt: now
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: nil),
            now: now
        )

        XCTAssertEqual(policy.reason, .keepingAwake)
    }
}

final class SleepDisabledCommandTests: XCTestCase {
    func testBuildsPmsetArguments() {
        XCTAssertEqual(
            SleepDisabledCommand.arguments(keepAwakeWithLidClosed: true),
            ["-a", "disablesleep", "1"]
        )
        XCTAssertEqual(
            SleepDisabledCommand.arguments(keepAwakeWithLidClosed: false),
            ["-a", "disablesleep", "0"]
        )
        XCTAssertEqual(SleepDisabledCommand.sleepNowArguments, ["sleepnow"])
    }

    func testParsesSleepDisabledFromPmsetOutput() {
        XCTAssertEqual(
            SleepDisabledStatus.isDisabled(pmsetOutput: "SleepDisabled         0\n"),
            false
        )
        XCTAssertEqual(
            SleepDisabledStatus.isDisabled(pmsetOutput: "SleepDisabled0\n"),
            false
        )
        XCTAssertEqual(
            SleepDisabledStatus.isDisabled(pmsetOutput: "System-wide power settings:\n SleepDisabled         1\n"),
            true
        )
        XCTAssertNil(SleepDisabledStatus.isDisabled(pmsetOutput: "sleep 1\n"))
    }
}

final class HelperInvocationTests: XCTestCase {
    func testParsesSingleVerb() {
        XCTAssertEqual(HelperInvocation(arguments: ["apply-on"]), .applyOn)
        XCTAssertEqual(HelperInvocation(arguments: ["apply-off"]), .applyOff)
        XCTAssertEqual(HelperInvocation(arguments: ["run"]), .run)
        XCTAssertEqual(HelperInvocation(arguments: ["status"]), .status)
    }

    func testRejectsUnknownOrExtraArguments() {
        XCTAssertNil(HelperInvocation(arguments: []))
        XCTAssertNil(HelperInvocation(arguments: ["apply-on", "extra"]))
        XCTAssertNil(HelperInvocation(arguments: ["enable"]))
    }
}

final class DesiredAwakeStateTests: XCTestCase {
    func testReadsOnAndTreatsEverythingElseAsOff() {
        XCTAssertEqual(DesiredAwakeState(fileContents: "on\n"), .on)
        XCTAssertEqual(DesiredAwakeState(fileContents: "on"), .on)
        XCTAssertEqual(DesiredAwakeState(fileContents: "off\n"), .off)
        XCTAssertEqual(DesiredAwakeState(fileContents: ""), .off)
        XCTAssertEqual(DesiredAwakeState(fileContents: "maybe"), .off)
    }

    func testWritesTrailingNewline() {
        XCTAssertEqual(DesiredAwakeState.on.fileContents, "on\n")
        XCTAssertEqual(DesiredAwakeState.off.fileContents, "off\n")
    }
}

final class AwakeConfigurationTests: XCTestCase {
    func testParsesLegacyPlainDesiredFile() throws {
        let configuration = try AwakeConfiguration.parse(fileContents: "on\n")
        XCTAssertEqual(configuration.desired, .on)
        XCTAssertEqual(
            configuration.batteryThresholdPercent,
            AwakeConfiguration.defaultBatteryThresholdPercent
        )
    }

    func testRoundTripsJSON() throws {
        let original = AwakeConfiguration(
            desired: .on,
            batteryThresholdPercent: 20,
            durationLimitSeconds: 7200,
            enabledAt: Date(timeIntervalSince1970: 1_700_000_000),
            batteryGuardLatched: true
        )

        let parsed = try AwakeConfiguration.parse(fileContents: original.fileContents())
        XCTAssertEqual(parsed.desired, original.desired)
        XCTAssertEqual(parsed.batteryThresholdPercent, 20)
        XCTAssertEqual(parsed.durationLimitSeconds, 7200)
        XCTAssertEqual(parsed.enabledAt?.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(parsed.batteryGuardLatched, true)
    }

    func testSanitizesOutOfRangeValues() {
        XCTAssertNil(AwakeConfiguration.sanitizedBatteryThreshold(0))
        XCTAssertNil(AwakeConfiguration.sanitizedBatteryThreshold(101))
        XCTAssertEqual(AwakeConfiguration.sanitizedBatteryThreshold(15), 15)
        XCTAssertNil(AwakeConfiguration.seconds(hours: 0))
        XCTAssertEqual(AwakeConfiguration.seconds(hours: 4), 14400)
    }
}

final class SleepGateTests: XCTestCase {
    func testWritesAdvancedConfigurationAndSleepsOnTransition() throws {
        let state = GateState(
            configuration: AwakeConfiguration(
                desired: .on,
                batteryThresholdPercent: 15,
                enabledAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            power: PowerSnapshot(isOnBattery: true, batteryPercent: 10)
        )

        let gate = SleepGate(
            readConfiguration: { state.configuration },
            readPower: { state.power },
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            writeConfiguration: { state.configuration = $0 },
            setKeepAwake: { state.keepAwake = $0 },
            sleepNow: { state.didSleepNow = true }
        )

        let keepingAwake = try gate.apply(sleepNowOnTransition: true, previouslyKeepingAwake: true)
        XCTAssertEqual(keepingAwake, false)
        XCTAssertEqual(state.keepAwake, false)
        XCTAssertEqual(state.didSleepNow, true)
        XCTAssertEqual(state.configuration.batteryGuardLatched, true)
    }
}

private final class GateState: @unchecked Sendable {
    var configuration: AwakeConfiguration
    var power: PowerSnapshot
    var keepAwake: Bool?
    var didSleepNow = false

    init(configuration: AwakeConfiguration, power: PowerSnapshot) {
        self.configuration = configuration
        self.power = power
    }
}

final class SleepPreventionStatusTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testDescribesOffAndAwake() {
        XCTAssertEqual(
            SleepPreventionStatusText.text(
                for: SleepPreventionPolicy(
                    configuration: AwakeConfiguration(desired: .off, batteryThresholdPercent: nil),
                    power: .unknown,
                    now: now
                )
            ),
            "オフ。蓋を閉じるとプロセスも止まります"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.text(
                for: SleepPreventionPolicy(
                    configuration: AwakeConfiguration(
                        desired: .on,
                        batteryThresholdPercent: nil,
                        enabledAt: now
                    ),
                    power: .unknown,
                    now: now
                )
            ),
            "オン。蓋を閉じてもプロセスは動きます。画面は設定どおり消えてロックします"
        )
    }

    func testDescribesBatteryLow() {
        XCTAssertEqual(
            SleepPreventionStatusText.text(
                for: SleepPreventionPolicy(
                    configuration: AwakeConfiguration(
                        desired: .on,
                        batteryThresholdPercent: 15,
                        enabledAt: now
                    ),
                    power: PowerSnapshot(isOnBattery: true, batteryPercent: 8),
                    now: now
                )
            ),
            "電池 8%。スリープします"
        )
    }

    func testPicksSymbolForAwakeAndSleeping() {
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(
                for: SleepPreventionPolicy(
                    configuration: AwakeConfiguration(desired: .on, batteryThresholdPercent: nil),
                    power: .unknown,
                    now: now
                )
            ),
            "cup.and.saucer.fill"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(
                for: SleepPreventionPolicy(
                    configuration: AwakeConfiguration(desired: .off),
                    power: .unknown,
                    now: now
                )
            ),
            "moon.zzz"
        )
    }
}

final class HelperProtocolTests: XCTestCase {
    func testAcceptsCurrentProtocol() {
        XCTAssertTrue(
            HelperProtocol.isCompatible(statusOutput: "protocol=2\ndesired=on\n")
        )
        XCTAssertTrue(
            HelperProtocol.isCompatible(statusOutput: "protocol=3\n")
        )
    }

    func testRejectsLegacyHelperStatus() {
        XCTAssertFalse(HelperProtocol.isCompatible(statusOutput: "desired=on\nsleepDisabled=0\n"))
        XCTAssertFalse(HelperProtocol.isCompatible(statusOutput: "protocol=1\n"))
        XCTAssertFalse(HelperProtocol.isCompatible(statusOutput: ""))
    }
}
