import XCTest
@testable import ViftyCore

final class FanInfoReaderTests: XCTestCase {
    func testReadsHardwareModeAndTargetRPM() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: [0x0c, 0x80]),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [1]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(5000))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].hardwareMode, .forced)
        XCTAssertEqual(fans[0].hardwareModeKey, "F0Md")
        XCTAssertEqual(fans[0].targetRPM, 5000)
        XCTAssertEqual(fans[0].minimumRPM, 1400)
        XCTAssertEqual(fans[0].maximumRPM, 6000)
        XCTAssertTrue(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertTrue(fans[0].controlEligibility.canRestoreOSManagedMode)
        XCTAssertTrue(fans[0].controlEligibility.reasons.isEmpty)
    }

    func testMissingModeAndTargetStayNil() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans[0].hardwareMode, nil)
        XCTAssertEqual(fans[0].hardwareModeKey, nil)
        XCTAssertEqual(fans[0].targetRPM, nil)
        XCTAssertFalse(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertFalse(fans[0].controlEligibility.canRestoreOSManagedMode)
        XCTAssertEqual(
            Set(fans[0].controlEligibility.reasons),
            Set([.missingModeKey, .missingTargetKey])
        )
    }

    func testReadsLowercaseModeKeyWhenUppercaseModeKeyIsMissing() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000)),
            "F0md": SMCValue(key: "F0md", dataType: "ui8 ", bytes: [3])
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans[0].hardwareMode, .system)
        XCTAssertEqual(fans[0].hardwareModeKey, "F0md")
    }

    func testMissingTargetBlocksFixedButAllowsModeOnlyAutoRecovery() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [1])
        ]

        let fan = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }.first

        XCTAssertEqual(fan?.targetRPM, nil)
        XCTAssertFalse(fan?.controlEligibility.canApplyFixedRPM == true)
        XCTAssertTrue(fan?.controlEligibility.canRestoreOSManagedMode == true)
        XCTAssertEqual(fan?.controlEligibility.reasons, [.missingTargetKey])
    }

    func testMissingBoundsRemainDisplayableButCannotAuthorizeFixedRPM() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].minimumRPM, 1200)
        XCTAssertEqual(fans[0].maximumRPM, 6000)
        XCTAssertFalse(fans[0].controllable)
        XCTAssertFalse(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertTrue(fans[0].controlEligibility.canRestoreOSManagedMode)
        XCTAssertEqual(
            Set(fans[0].controlEligibility.reasons),
            Set([.missingMinimumRPM, .missingMaximumRPM])
        )
    }

    func testMissingFanCountKeepsDiscoveredTelemetryReadOnly() {
        let values: [String: SMCValue] = [
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans.map(\.id), [0])
        XCTAssertEqual(fans[0].currentRPM, 2400)
        XCTAssertFalse(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertFalse(fans[0].controlEligibility.canRestoreOSManagedMode)
        XCTAssertEqual(fans[0].controlEligibility.reasons, [.missingFanCount])
    }

    func testInvalidFanIDAndRangeAreNeverWriteEligible() {
        let eligibility = SMCFanInfoReader.controlEligibility(
            fanID: 10,
            fanCountIsTrusted: true,
            minimumRPM: 6000,
            maximumRPM: 1400,
            hardwareMode: .automatic,
            hardwareModeKey: "F0Md",
            targetKeyIsReadable: true
        )

        XCTAssertFalse(eligibility.canApplyFixedRPM)
        XCTAssertFalse(eligibility.canRestoreOSManagedMode)
        XCTAssertEqual(Set(eligibility.reasons), Set([.invalidFanID, .invalidRPMRange]))
    }

    func testFractionalFanCountCannotAuthorizeWrites() {
        var fractionalCount = Float(1.5)
        let values: [String: SMCValue] = [
            "FNum": SMCValue(
                key: "FNum",
                dataType: "flt ",
                bytes: withUnsafeBytes(of: &fractionalCount) { Array($0) }
            ),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2_400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1_400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6_000)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2_400))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans.map(\.id), [0])
        XCTAssertFalse(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertFalse(fans[0].controlEligibility.canRestoreOSManagedMode)
        XCTAssertTrue(fans[0].controlEligibility.reasons.contains(.missingFanCount))
    }

    func testFractionalModeAndTargetRemainReadOnlyInsteadOfTruncating() {
        var fractionalMode = Float(0.5)
        let fractionalTarget = SMCValue(
            key: "F0Tg",
            dataType: "fpe2",
            bytes: [0x25, 0x81]
        )
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2_400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1_400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6_000)),
            "F0Md": SMCValue(
                key: "F0Md",
                dataType: "flt ",
                bytes: withUnsafeBytes(of: &fractionalMode) { Array($0) }
            ),
            "F0Tg": fractionalTarget
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertNil(fans[0].hardwareMode)
        XCTAssertNil(fans[0].targetRPM)
        XCTAssertFalse(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertFalse(fans[0].controlEligibility.canRestoreOSManagedMode)
        XCTAssertEqual(
            Set(fans[0].controlEligibility.reasons),
            Set([.missingModeKey, .missingTargetKey])
        )
    }

    func testNonFiniteRPMTelemetryDoesNotTrapOrAuthorizeWrites() {
        var notANumber = Float.nan
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(
                key: "F0Ac",
                dataType: "flt ",
                bytes: withUnsafeBytes(of: &notANumber) { Array($0) }
            ),
            "F0Mn": SMCValue(
                key: "F0Mn",
                dataType: "flt ",
                bytes: withUnsafeBytes(of: &notANumber) { Array($0) }
            ),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6_000)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [0]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2_400))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans[0].currentRPM, 0)
        XCTAssertFalse(fans[0].controlEligibility.canApplyFixedRPM)
        XCTAssertTrue(fans[0].controlEligibility.reasons.contains(.missingMinimumRPM))
    }
}
