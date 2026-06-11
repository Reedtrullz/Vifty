import XCTest
@testable import ViftyCore

final class FanDisplayFormatterTests: XCTestCase {
    func testForcedFanSubtitleIncludesTarget() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3200,
            minimumRPM: 1400,
            maximumRPM: 6000,
            controllable: true,
            hardwareMode: .forced,
            targetRPM: 5000
        )

        XCTAssertEqual(FanDisplayFormatter.subtitle(for: fan), "Forced · Target 5000 RPM")
    }

    func testAutoFanSubtitleOmitsMissingTarget() {
        let fan = Fan(id: 0, name: "Left Fan", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)

        XCTAssertEqual(FanDisplayFormatter.subtitle(for: fan), "Auto")
    }

    func testSystemFanSubtitleShowsSystemMode() {
        let fan = Fan(id: 0, name: "Left Fan", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .system)

        XCTAssertEqual(FanDisplayFormatter.subtitle(for: fan), "System")
    }

    func testUnknownFanSubtitleWhenHardwareModeMissing() {
        let fan = Fan(id: 0, name: "Left Fan", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true)

        XCTAssertEqual(FanDisplayFormatter.subtitle(for: fan), "Hardware mode unknown")
    }
}
