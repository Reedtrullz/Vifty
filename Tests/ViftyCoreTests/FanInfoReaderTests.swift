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
        XCTAssertEqual(fans[0].targetRPM, 5000)
        XCTAssertEqual(fans[0].minimumRPM, 1400)
        XCTAssertEqual(fans[0].maximumRPM, 6000)
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
        XCTAssertEqual(fans[0].targetRPM, nil)
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
    }
}
