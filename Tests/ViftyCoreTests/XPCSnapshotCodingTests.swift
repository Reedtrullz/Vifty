import XCTest
@testable import ViftyCore

final class XPCSnapshotCodingTests: XCTestCase {
    func testFanHardwareModeAndTargetRoundTrip() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 3200,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 5000
                )
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let encoded = XPCSnapshotCoding.encode(snapshot)
        let decoded = XPCSnapshotCoding.decode(encoded)

        XCTAssertEqual(decoded?.fans.first?.hardwareMode, .forced)
        XCTAssertEqual(decoded?.fans.first?.targetRPM, 5000)
    }

    func testOlderSnapshotsWithoutFanHardwareFieldsStillDecode() {
        let dictionary: NSDictionary = [
            "modelIdentifier": "MacBookPro18,1",
            "isAppleSilicon": true,
            "isMacBookPro": true,
            "fans": [
                [
                    "id": 0,
                    "name": "Left Fan",
                    "currentRPM": 2400,
                    "minimumRPM": 1400,
                    "maximumRPM": 6000,
                    "controllable": true
                ] as NSDictionary
            ],
            "temperatureSensors": []
        ]

        let decoded = XPCSnapshotCoding.decode(dictionary)

        XCTAssertEqual(decoded?.fans.first?.hardwareMode, nil)
        XCTAssertEqual(decoded?.fans.first?.targetRPM, nil)
    }
}
