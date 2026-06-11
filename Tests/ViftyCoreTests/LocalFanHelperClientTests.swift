import XCTest
@testable import ViftyCore

final class LocalFanHelperClientTests: XCTestCase {
    func testApplyFixedRPMUsesLowercaseModeKeyWhenUppercaseModeKeyIsMissing() throws {
        let smc = FakeSMCConnection(values: [
            "F0md": SMCValue(key: "F0md", dataType: "ui8 ", bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400))
        ])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        try client.apply(
            FanCommand(fanID: 0, mode: .fixedRPM(3200)),
            fan: Self.fan()
        )

        XCTAssertEqual(smc.writes.map(\.key), ["F0md", "F0Tg"])
        XCTAssertEqual(smc.writes[0].bytes, [1])
        XCTAssertEqual(smc.writes[1].bytes, SMCDecoding.encodeFPE2(3200))
    }

    func testApplyFixedRPMUnlocksForceTestWhenProtectedModeRejectsDirectManualMode() throws {
        let smc = FakeSMCConnection(values: [
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [3]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "Ftst": SMCValue(key: "Ftst", dataType: "ui8 ", bytes: [0])
        ])
        smc.failNextWrite(to: "F0Md", with: ViftyError.smcKeyUnavailable("F0Md"))
        let client = LocalFanHelperClient(
            smcFactory: { smc },
            unlockTimeoutSeconds: 0.2,
            unlockRetryIntervalSeconds: 0
        )

        try client.apply(
            FanCommand(fanID: 0, mode: .fixedRPM(4500)),
            fan: Self.fan()
        )

        XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "Ftst", "F0Md", "F0Tg"])
        XCTAssertEqual(smc.writes[1].bytes, [1])
        XCTAssertEqual(smc.writes[2].bytes, [1])
        XCTAssertEqual(smc.writes[3].bytes, SMCDecoding.encodeFPE2(4500))
    }

    func testApplyRejectsMismatchedFanIDBeforeSMCWrites() {
        let smc = FakeSMCConnection(values: [
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400))
        ])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 1, mode: .fixedRPM(3200)),
                fan: Self.fan()
            )
        ) { error in
            guard case ViftyError.helperRejected(let message) = error else {
                return XCTFail("Expected helperRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("Fan command ID 1 does not match hardware fan ID 0"))
        }
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testApplyRejectsInvalidFanIDBeforeSMCAccess() {
        let smc = FakeSMCConnection(values: [:])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: -1, mode: .fixedRPM(3200)),
                fan: Self.fan(id: -1)
            )
        ) { error in
            guard case ViftyError.helperRejected(let message) = error else {
                return XCTFail("Expected helperRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid fan ID -1"))
        }
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testRestoreAutoRejectsInvalidFanIDBeforeSMCAccess() {
        let smc = FakeSMCConnection(values: [:])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        XCTAssertThrowsError(try client.restoreAuto(fan: Self.fan(id: 10))) { error in
            guard case ViftyError.helperRejected(let message) = error else {
                return XCTFail("Expected helperRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid fan ID 10"))
        }
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testApplyRejectsInvalidRPMRangeBeforeSMCAccess() {
        let smc = FakeSMCConnection(values: [:])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        XCTAssertThrowsError(
            try client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3200)),
                fan: Self.fan(minimumRPM: 6000, maximumRPM: 1400)
            )
        ) { error in
            XCTAssertEqual(error as? ViftyError, .noControllableFans)
        }
        XCTAssertTrue(smc.reads.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testRestoreAutoResetsForceTestWhenAvailable() throws {
        let smc = FakeSMCConnection(values: [
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [1]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(4500)),
            "Ftst": SMCValue(key: "Ftst", dataType: "ui8 ", bytes: [1])
        ])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        try client.restoreAuto(fan: Self.fan(minimumRPM: 1400))

        XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "F0Tg", "Ftst"])
        XCTAssertEqual(smc.writes[0].bytes, [0])
        XCTAssertEqual(smc.writes[1].bytes, SMCDecoding.encodeFPE2(1400))
        XCTAssertEqual(smc.writes[2].bytes, [0])
    }

    func testRestoreAutoAllowsMissingForceTestOnHardwareWithoutUnlockKey() throws {
        let smc = FakeSMCConnection(values: [
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [1]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(4500))
        ])
        let client = LocalFanHelperClient(smcFactory: { smc }, unlockRetryIntervalSeconds: 0)

        try client.restoreAuto(fan: Self.fan(minimumRPM: 1400))

        XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "F0Tg"])
    }

    private static func fan(id: Int = 0, minimumRPM: Int = 1400, maximumRPM: Int = 6000) -> Fan {
        Fan(
            id: id,
            name: "Left Fan",
            currentRPM: minimumRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            controllable: true
        )
    }
}

private final class FakeSMCConnection: SMCConnection, @unchecked Sendable {
    struct Write: Equatable {
        var key: String
        var dataType: String
        var bytes: [UInt8]
    }

    private let lock = NSLock()
    private var values: [String: SMCValue]
    private var queuedWriteFailures: [String: [Error]] = [:]
    private var recordedReads: [String] = []
    private var recordedWrites: [Write] = []

    init(values: [String: SMCValue]) {
        self.values = values
    }

    var writes: [Write] {
        lock.withLock { recordedWrites }
    }

    var reads: [String] {
        lock.withLock { recordedReads }
    }

    func failNextWrite(to key: String, with error: Error) {
        lock.withLock {
            queuedWriteFailures[key, default: []].append(error)
        }
    }

    func read(_ key: String) throws -> SMCValue {
        try lock.withLock {
            recordedReads.append(key)
            guard let value = values[key] else {
                throw ViftyError.smcKeyUnavailable(key)
            }
            return value
        }
    }

    func write(_ key: String, dataType: String, bytes: [UInt8]) throws {
        try lock.withLock {
            recordedWrites.append(Write(key: key, dataType: dataType, bytes: bytes))
            if var failures = queuedWriteFailures[key], !failures.isEmpty {
                let failure = failures.removeFirst()
                queuedWriteFailures[key] = failures
                throw failure
            }
            values[key] = SMCValue(key: key, dataType: dataType, bytes: bytes)
        }
    }
}
