import XCTest
@testable import ViftyCore
@testable import ViftyFanControlSafety

final class LocalFanHelperClientTests: XCTestCase {
    func testFixedRPMPreflightsEveryValueAndReturnsConfirmedReceipt() throws {
        let smc = FakeSMCConnection(values: Self.controlValues())
        let client = LocalFanHelperClient(smcFactory: { smc })

        let receipt = try client.apply(
            FanCommand(fanID: 0, mode: .fixedRPM(3_200)),
            fan: Self.fan()
        )

        XCTAssertEqual(Array(smc.events.prefix(3)), [.read("F0Md"), .read("F0Tg"), .read("Ftst")])
        XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "F0Tg"])
        XCTAssertEqual(smc.writes[0].bytes, [1])
        XCTAssertEqual(smc.writes[1].bytes, SMCDecoding.encodeFPE2(3_200))
        XCTAssertEqual(receipt.requestedMode, .forced)
        XCTAssertEqual(receipt.observedMode, .forced)
        XCTAssertEqual(receipt.observedTargetRPM, 3_200)
        XCTAssertTrue(receipt.forceTestDisabled)
        XCTAssertFalse(receipt.recoveryConfirmed)
        XCTAssertTrue(receipt.warnings.isEmpty)
    }

    func testFixedRPMUsesLowercaseModeKeyWhenUppercaseModeKeyIsMissing() throws {
        let smc = FakeSMCConnection(values: [
            "F0md": Self.modeValue(key: "F0md", mode: 0),
            "F0Tg": Self.targetValue(rpm: 1_400)
        ])
        let client = LocalFanHelperClient(smcFactory: { smc })

        let receipt = try client.apply(
            FanCommand(fanID: 0, mode: .fixedRPM(3_200)),
            fan: Self.fan(hardwareModeKey: "F0md")
        )

        XCTAssertEqual(smc.writes.map(\.key), ["F0md", "F0Tg"])
        XCTAssertEqual(receipt.observedMode, .forced)
        XCTAssertEqual(receipt.observedTargetRPM, 3_200)
    }

    func testUnsupportedTargetLayoutFailsPreflightWithZeroWrites() {
        let smc = FakeSMCConnection(values: [
            "F0Md": Self.modeValue(mode: 0),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "ui8 ", bytes: [42]),
            "Ftst": Self.forceTestValue(0)
        ])
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3_200)),
                fan: Self.fan()
            )
        ) { error in
            guard case ViftyError.helperRejected(let message) = error else {
                return XCTFail("Expected helperRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported fan target layout"))
        }
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testReportedModeKeyMustBelongToTheRequestedFan() {
        let smc = FakeSMCConnection(values: Self.controlValues())
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3_200)),
                fan: Self.fan(hardwareModeKey: "F1Md")
            )
        ) { error in
            guard case ViftyError.helperRejected(let message) = error else {
                return XCTFail("Expected helperRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("invalid mode key F1Md"))
        }
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testAutoWithUnsupportedTargetLayoutUsesModeOnlyRecovery() throws {
        let smc = FakeSMCConnection(values: [
            "F0Md": Self.modeValue(mode: 1),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "ui8 ", bytes: [42]),
            "Ftst": Self.forceTestValue(0)
        ])
        let client = LocalFanHelperClient(smcFactory: { smc })

        let receipt = try client.restoreAuto(fan: Self.recoveryOnlyFan())

        XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "Ftst"])
        XCTAssertEqual(receipt.observedMode, .automatic)
        XCTAssertNil(receipt.observedTargetRPM)
        XCTAssertTrue(receipt.recoveryConfirmed)
        XCTAssertTrue(receipt.warnings.contains { $0.contains("unsupported layout") })
    }

    func testTargetFailureAfterForcedAttemptsCompleteCleanupAndReportsConfirmedRecovery() {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 0, targetRPM: 1_800))
        smc.failNextWrite(to: "F0Tg", with: TestFailure("target write failed"))
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(4_500)),
                fan: Self.fan(minimumRPM: 1_400)
            )
        ) { error in
            guard let mutation = error as? FanMutationError else {
                return XCTFail("Expected FanMutationError, got \(error)")
            }
            XCTAssertEqual(mutation.code, .mutationFailed)
            XCTAssertTrue(mutation.primaryError.contains("target write failed"))
            XCTAssertTrue(mutation.receipt.recoveryConfirmed)
            XCTAssertEqual(mutation.receipt.observedMode, .automatic)
            XCTAssertEqual(mutation.receipt.observedTargetRPM, 1_400)
            XCTAssertTrue(mutation.receipt.forceTestDisabled)
        }

        XCTAssertEqual(
            smc.writes.map(\.key),
            ["F0Md", "F0Tg", "F0Md", "F0Tg", "Ftst"]
        )
        XCTAssertEqual(smc.writes[2].bytes, [0])
        XCTAssertEqual(smc.writes[3].bytes, SMCDecoding.encodeFPE2(1_400))
        XCTAssertEqual(smc.writes[4].bytes, [0])
    }

    func testFixedReadbackMismatchFailsAndRunsCleanup() {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 0))
        smc.ignoreNextWrite(to: "F0Md")
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3_600)),
                fan: Self.fan()
            )
        ) { error in
            guard let mutation = error as? FanMutationError else {
                return XCTFail("Expected FanMutationError, got \(error)")
            }
            XCTAssertEqual(mutation.code, .readbackMismatch)
            XCTAssertTrue(mutation.primaryError.contains("expected Forced at 3600 RPM"))
            XCTAssertTrue(mutation.receipt.recoveryConfirmed)
            XCTAssertEqual(mutation.receipt.observedMode, .automatic)
        }

        XCTAssertEqual(
            smc.writes.map(\.key),
            ["F0Md", "F0Tg", "F0Md", "F0Tg", "Ftst"]
        )
    }

    func testProtectedModeUnlockDisablesForceTestAndConfirmsReadback() throws {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 3))
        smc.failNextWrite(to: "F0Md", with: TestFailure("protected"))
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        let receipt = try client.apply(
            FanCommand(fanID: 0, mode: .fixedRPM(4_500)),
            fan: Self.fan()
        )

        XCTAssertEqual(
            smc.writes.map(\.key),
            ["F0Md", "Ftst", "F0Md", "F0Tg", "Ftst"]
        )
        XCTAssertEqual(smc.writes[1].bytes, [1])
        XCTAssertEqual(smc.writes[4].bytes, [0])
        XCTAssertEqual(receipt.observedMode, .forced)
        XCTAssertTrue(receipt.forceTestDisabled)
    }

    func testUnlockTimeoutAndCleanupFailureReturnRecoveryUnconfirmedWithoutWallTime() {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 1))
        for index in 1...5 {
            smc.failNextWrite(to: "F0Md", with: TestFailure("mode failure \(index)"))
        }
        let clock = ManualMonotonicClock()
        let client = LocalFanHelperClient(
            smcFactory: { smc },
            unlockTimeoutSeconds: 0.2,
            unlockRetryIntervalSeconds: 0.1,
            monotonicNow: { clock.now },
            sleep: { clock.advance(by: $0) }
        )

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(4_500)),
                fan: Self.fan()
            )
        ) { error in
            guard let mutation = error as? FanMutationError else {
                return XCTFail("Expected FanMutationError, got \(error)")
            }
            XCTAssertEqual(mutation.code, .recoveryUnconfirmed)
            XCTAssertTrue(mutation.primaryError.contains("remained protected"))
            XCTAssertTrue(mutation.cleanupErrors.contains { $0.contains("Auto mode cleanup failed") })
            XCTAssertTrue(mutation.cleanupErrors.contains { $0.contains("observed Forced") })
            XCTAssertFalse(mutation.receipt.recoveryConfirmed)
            XCTAssertEqual(mutation.receipt.observedMode, .forced)
        }

        XCTAssertEqual(clock.now, 0.2, accuracy: 0.000_1)
        XCTAssertEqual(clock.sleepCalls, [0.1, 0.1])
        XCTAssertEqual(smc.writes.filter { $0.key == "F0Md" }.count, 5)
        XCTAssertTrue(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [0] })
    }

    func testCleanupContinuesAfterAutoAndTargetCleanupFailures() {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 1))
        smc.failNextWrite(to: "F0Tg", with: TestFailure("primary target failure"))
        smc.failNextWrite(to: "F0Tg", with: TestFailure("cleanup target failure"))
        smc.succeedNextWrite(to: "F0Md")
        smc.failNextWrite(to: "F0Md", with: TestFailure("cleanup auto failure"))
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(4_500)),
                fan: Self.fan()
            )
        ) { error in
            guard let mutation = error as? FanMutationError else {
                return XCTFail("Expected FanMutationError, got \(error)")
            }
            XCTAssertEqual(mutation.code, .recoveryUnconfirmed)
            XCTAssertTrue(mutation.cleanupErrors.contains { $0.contains("Auto mode cleanup failed") })
            XCTAssertTrue(mutation.cleanupErrors.contains { $0.contains("Target hygiene failed") })
        }

        XCTAssertEqual(Array(smc.writes.suffix(3)).map(\.key), ["F0Md", "F0Tg", "Ftst"])
        XCTAssertEqual(smc.writes.last?.bytes, [0])
    }

    func testRestoreAutoAcceptsSystemManagedReadback() throws {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 3))
        smc.ignoreNextWrite(to: "F0Md")
        let client = LocalFanHelperClient(smcFactory: { smc })

        let receipt = try client.restoreAuto(fan: Self.fan())

        XCTAssertEqual(receipt.requestedMode, .automatic)
        XCTAssertEqual(receipt.observedMode, .system)
        XCTAssertTrue(receipt.forceTestDisabled)
        XCTAssertTrue(receipt.recoveryConfirmed)
    }

    func testRestoreAutoAllowsMissingTargetKey() throws {
        let smc = FakeSMCConnection(values: [
            "F0Md": Self.modeValue(mode: 1)
        ])
        let client = LocalFanHelperClient(smcFactory: { smc })

        let receipt = try client.restoreAuto(fan: Self.recoveryOnlyFan())

        XCTAssertEqual(smc.writes.map(\.key), ["F0Md"])
        XCTAssertEqual(receipt.observedMode, .automatic)
        XCTAssertNil(receipt.observedTargetRPM)
        XCTAssertTrue(receipt.forceTestDisabled)
        XCTAssertTrue(receipt.recoveryConfirmed)
        XCTAssertTrue(receipt.warnings.contains { $0.contains("mode-only") })
    }

    func testRestoreAutoDoesNotRequireFixedRPMRangeOrControllableFlag() throws {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 1))
        let client = LocalFanHelperClient(smcFactory: { smc })

        let receipt = try client.restoreAuto(
            fan: Self.fan(
                minimumRPM: 6_000,
                maximumRPM: 1_400,
                controllable: false,
                eligibility: FanControlEligibility(
                    canApplyFixedRPM: false,
                    canRestoreOSManagedMode: true,
                    reasons: [.invalidRPMRange]
                )
            )
        )

        XCTAssertEqual(receipt.observedMode, .automatic)
        XCTAssertTrue(receipt.recoveryConfirmed)
        XCTAssertFalse(smc.writes.contains { $0.key == "F0Tg" })
    }

    func testRestoreAutoNeverWritesSynthesizedMinimumRPM() throws {
        let smc = FakeSMCConnection(values: Self.controlValues(mode: 1, targetRPM: 4_500))
        let client = LocalFanHelperClient(smcFactory: { smc })
        let fan = Self.fan(
            minimumRPM: 1_200,
            maximumRPM: 6_000,
            controllable: false,
            eligibility: FanControlEligibility(
                canApplyFixedRPM: false,
                canRestoreOSManagedMode: true,
                reasons: [.missingMinimumRPM]
            )
        )

        let receipt = try client.restoreAuto(fan: fan)

        XCTAssertEqual(receipt.observedMode, .automatic)
        XCTAssertNil(receipt.observedTargetRPM)
        XCTAssertFalse(smc.writes.contains { $0.key == "F0Tg" })
        XCTAssertTrue(receipt.warnings.contains { $0.contains("no trusted minimum RPM") })
    }

    func testRecoveryOnlyEligibilityCannotApplyFixedRPM() {
        let smc = FakeSMCConnection(values: Self.controlValues())
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3_200)),
                fan: Self.recoveryOnlyFan()
            )
        ) { error in
            XCTAssertEqual(error as? ViftyError, .noControllableFans)
        }
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testRestoreAutoRejectsMissingModeEligibilityBeforeSMCAccess() {
        let smc = FakeSMCConnection(values: [:])
        let client = LocalFanHelperClient(smcFactory: { smc })
        let fan = Self.fan(eligibility: .legacyUnspecified)

        XCTAssertThrowsError(try client.restoreAuto(fan: fan)) { error in
            guard case ViftyError.helperRejected(let message) = error else {
                return XCTFail("Expected helperRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("lacks trusted mode telemetry"))
        }
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testApplyRejectsMismatchedAndInvalidFanIDsBeforeSMCAccess() {
        let smc = FakeSMCConnection(values: [:])
        let client = LocalFanHelperClient(smcFactory: { smc })

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 1, mode: .fixedRPM(3_200)),
                fan: Self.fan()
            )
        )
        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: -1, mode: .fixedRPM(3_200)),
                fan: Self.fan(id: -1)
            )
        )
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    private static func controlValues(
        mode: UInt8 = 0,
        targetRPM: Int = 1_400,
        forceTest: UInt8 = 0
    ) -> [String: SMCValue] {
        [
            "F0Md": modeValue(mode: mode),
            "F0Tg": targetValue(rpm: targetRPM),
            "Ftst": forceTestValue(forceTest)
        ]
    }

    private static func modeValue(
        key: String = "F0Md",
        mode: UInt8
    ) -> SMCValue {
        SMCValue(key: key, dataType: "ui8 ", bytes: [mode])
    }

    private static func targetValue(rpm: Int) -> SMCValue {
        SMCValue(
            key: "F0Tg",
            dataType: "fpe2",
            bytes: SMCDecoding.encodeFPE2(rpm)
        )
    }

    private static func forceTestValue(_ value: UInt8) -> SMCValue {
        SMCValue(key: "Ftst", dataType: "ui8 ", bytes: [value])
    }

    private static func recoveryOnlyFan() -> Fan {
        fan(
            controllable: false,
            eligibility: FanControlEligibility(
                canApplyFixedRPM: false,
                canRestoreOSManagedMode: true,
                reasons: [.missingTargetKey]
            )
        )
    }

    private static func fan(
        id: Int = 0,
        minimumRPM: Int = 1_400,
        maximumRPM: Int = 6_000,
        controllable: Bool = true,
        hardwareModeKey: String? = "F0Md",
        eligibility: FanControlEligibility = .trusted
    ) -> Fan {
        Fan(
            id: id,
            name: "Left Fan",
            currentRPM: minimumRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            controllable: controllable,
            hardwareMode: .automatic,
            hardwareModeKey: hardwareModeKey,
            targetRPM: minimumRPM,
            controlEligibility: eligibility
        )
    }
}

private struct TestFailure: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private final class ManualMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval = 0
    private var intervals: [TimeInterval] = []

    var now: TimeInterval {
        lock.withLock { current }
    }

    var sleepCalls: [TimeInterval] {
        lock.withLock { intervals }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            intervals.append(interval)
            current += interval
        }
    }
}

private final class FakeSMCConnection: SMCConnection, @unchecked Sendable {
    struct Write: Equatable {
        let key: String
        let dataType: String
        let bytes: [UInt8]
    }

    enum Event: Equatable {
        case read(String)
        case write(String)
    }

    private enum WriteBehavior {
        case succeed
        case fail(any Error)
        case ignore
    }

    private let lock = NSLock()
    private var values: [String: SMCValue]
    private var queuedWriteBehaviors: [String: [WriteBehavior]] = [:]
    private var recordedReads: [String] = []
    private var recordedWrites: [Write] = []
    private var recordedEvents: [Event] = []

    init(values: [String: SMCValue]) {
        self.values = values
    }

    var writes: [Write] {
        lock.withLock { recordedWrites }
    }

    var reads: [String] {
        lock.withLock { recordedReads }
    }

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func failNextWrite(to key: String, with error: any Error) {
        lock.withLock {
            queuedWriteBehaviors[key, default: []].append(.fail(error))
        }
    }

    func ignoreNextWrite(to key: String) {
        lock.withLock {
            queuedWriteBehaviors[key, default: []].append(.ignore)
        }
    }

    func succeedNextWrite(to key: String) {
        lock.withLock {
            queuedWriteBehaviors[key, default: []].append(.succeed)
        }
    }

    func read(_ key: String) throws -> SMCValue {
        try lock.withLock {
            recordedReads.append(key)
            recordedEvents.append(.read(key))
            guard let value = values[key] else {
                throw ViftyError.smcKeyUnavailable(key)
            }
            return value
        }
    }

    func write(_ key: String, dataType: String, bytes: [UInt8]) throws {
        try lock.withLock {
            recordedWrites.append(Write(key: key, dataType: dataType, bytes: bytes))
            recordedEvents.append(.write(key))
            if var behaviors = queuedWriteBehaviors[key], !behaviors.isEmpty {
                let behavior = behaviors.removeFirst()
                queuedWriteBehaviors[key] = behaviors
                switch behavior {
                case .succeed:
                    break
                case .fail(let error):
                    throw error
                case .ignore:
                    return
                }
            }
            values[key] = SMCValue(key: key, dataType: dataType, bytes: bytes)
        }
    }
}
