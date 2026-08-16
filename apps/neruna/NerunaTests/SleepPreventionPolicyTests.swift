import NerunaCore
import XCTest

final class SleepPreventionPolicyTests: XCTestCase {
    func testKeepsAwakeWithLidClosedOnlyWhenEnabledOnACPower() {
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: true, isOnACPower: true).shouldKeepAwakeWithLidClosed,
            true
        )
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: true, isOnACPower: false).shouldKeepAwakeWithLidClosed,
            false
        )
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: false, isOnACPower: true).shouldKeepAwakeWithLidClosed,
            false
        )
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: false, isOnACPower: false).shouldKeepAwakeWithLidClosed,
            false
        )
    }

    func testPreventsIdleSleepWheneverEnabled() {
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: true, isOnACPower: false).shouldPreventIdleSleep,
            true
        )
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: false, isOnACPower: true).shouldPreventIdleSleep,
            false
        )
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

final class SleepGateTests: XCTestCase {
    func testAppliesPolicyFromDesiredStateAndPowerSource() throws {
        let state = GateState(desired: .on, onAC: true)

        let gate = SleepGate(
            readDesired: { state.desired },
            isOnACPower: { state.onAC },
            setKeepAwakeWithLidClosed: { state.applied = $0 }
        )

        try gate.apply()
        XCTAssertEqual(state.applied, true)

        state.onAC = false
        try gate.apply()
        XCTAssertEqual(state.applied, false)

        state.desired = .off
        state.onAC = true
        try gate.apply()
        XCTAssertEqual(state.applied, false)
    }
}

private final class GateState: @unchecked Sendable {
    var desired: DesiredAwakeState
    var onAC: Bool
    var applied: Bool?

    init(desired: DesiredAwakeState, onAC: Bool) {
        self.desired = desired
        self.onAC = onAC
    }
}

final class SleepPreventionStatusTextTests: XCTestCase {
    func testDescribesEachPolicy() {
        XCTAssertEqual(
            SleepPreventionStatusText.text(
                for: SleepPreventionPolicy(isEnabled: false, isOnACPower: true)
            ),
            "オフ。蓋を閉じるとスリープします"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.text(
                for: SleepPreventionPolicy(isEnabled: true, isOnACPower: true)
            ),
            "電源接続中。蓋を閉じても起きています"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.text(
                for: SleepPreventionPolicy(isEnabled: true, isOnACPower: false)
            ),
            "電池駆動中。蓋を閉じるとスリープします"
        )
    }

    func testPicksSymbolForEachPolicy() {
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(
                for: SleepPreventionPolicy(isEnabled: false, isOnACPower: true)
            ),
            "moon.zzz"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(
                for: SleepPreventionPolicy(isEnabled: true, isOnACPower: true)
            ),
            "cup.and.saucer.fill"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(
                for: SleepPreventionPolicy(isEnabled: true, isOnACPower: false)
            ),
            "cup.and.saucer"
        )
    }
}
