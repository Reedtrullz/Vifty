import XCTest
@testable import ViftyCore

final class FanStatusTests: XCTestCase {
    func testFanHardwareModeDecodesKnownSMCValues() {
        XCTAssertEqual(FanHardwareMode(rawValue: 0), .automatic)
        XCTAssertEqual(FanHardwareMode(rawValue: 1), .forced)
        XCTAssertEqual(FanHardwareMode(rawValue: 3), .system)
        XCTAssertEqual(FanHardwareMode(rawValue: 7), .unknown(7))
        XCTAssertNil(FanHardwareMode(rawValue: nil))
    }

    func testFanStoresHardwareModeAndTargetRPM() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3200,
            minimumRPM: 1400,
            maximumRPM: 6000,
            controllable: true,
            hardwareMode: .forced,
            hardwareModeKey: "F0Md",
            targetRPM: 5000
        )

        XCTAssertEqual(fan.hardwareMode, .forced)
        XCTAssertEqual(fan.hardwareModeKey, "F0Md")
        XCTAssertEqual(fan.targetRPM, 5000)
    }
}
