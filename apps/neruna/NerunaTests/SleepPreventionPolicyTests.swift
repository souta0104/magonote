import NerunaCore
import XCTest

final class SleepPreventionPolicyTests: XCTestCase {
    func testKeepsAwakeWithLidClosedWheneverEnabled() {
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: true).shouldKeepAwakeWithLidClosed,
            true
        )
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: false).shouldKeepAwakeWithLidClosed,
            false
        )
    }

    func testPreventsIdleSleepWheneverEnabled() {
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: true).shouldPreventIdleSleep,
            true
        )
        XCTAssertEqual(
            SleepPreventionPolicy(isEnabled: false).shouldPreventIdleSleep,
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
    func testAppliesPolicyFromDesiredState() throws {
        let state = GateState(desired: .on)

        let gate = SleepGate(
            readDesired: { state.desired },
            setKeepAwakeWithLidClosed: { state.applied = $0 }
        )

        try gate.apply()
        XCTAssertEqual(state.applied, true)

        state.desired = .off
        try gate.apply()
        XCTAssertEqual(state.applied, false)
    }
}

private final class GateState: @unchecked Sendable {
    var desired: DesiredAwakeState
    var applied: Bool?

    init(desired: DesiredAwakeState) {
        self.desired = desired
    }
}

final class SleepPreventionStatusTextTests: XCTestCase {
    func testDescribesEachPolicy() {
        XCTAssertEqual(
            SleepPreventionStatusText.text(for: SleepPreventionPolicy(isEnabled: false)),
            "オフ。蓋を閉じるとスリープします"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.text(for: SleepPreventionPolicy(isEnabled: true)),
            "オン。蓋を閉じても起きています"
        )
    }

    func testPicksSymbolForEachPolicy() {
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(for: SleepPreventionPolicy(isEnabled: false)),
            "moon.zzz"
        )
        XCTAssertEqual(
            SleepPreventionStatusText.symbolName(for: SleepPreventionPolicy(isEnabled: true)),
            "cup.and.saucer.fill"
        )
    }
}
