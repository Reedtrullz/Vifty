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
                    hardwareModeKey: "F0md",
                    targetRPM: 5000,
                    controlEligibility: FanControlEligibility(
                        canApplyFixedRPM: true,
                        canRestoreOSManagedMode: true,
                        reasons: []
                    )
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
        XCTAssertEqual(decoded?.fans.first?.hardwareModeKey, "F0md")
        XCTAssertEqual(decoded?.fans.first?.targetRPM, 5000)
        XCTAssertEqual(decoded?.fanControlProtocolVersion, 2)
        XCTAssertEqual(decoded?.fans.first?.controlEligibility, .trusted)
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
        XCTAssertEqual(decoded?.fans.first?.hardwareModeKey, nil)
        XCTAssertEqual(decoded?.fans.first?.targetRPM, nil)
        XCTAssertEqual(decoded?.fanControlProtocolVersion, 1)
        XCTAssertEqual(decoded?.fans.first?.controlEligibility, .legacyUnspecified)
    }

    func testCurrentProtocolWithoutEligibilityFailsClosed() {
        let dictionary: NSDictionary = [
            "modelIdentifier": "MacBookPro18,1",
            "isAppleSilicon": true,
            "isMacBookPro": true,
            "fanControlProtocolVersion": 2,
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

        XCTAssertNil(decoded)
    }

    func testCurrentProtocolRejectsWholeSnapshotWhenAnyFanRowIsMalformed() {
        let validFan = XPCSnapshotCoding.encode(HardwareSnapshot(
            fans: [Fan(
                id: 0,
                name: "Left Fan",
                currentRPM: 2_400,
                minimumRPM: 1_400,
                maximumRPM: 6_000,
                controllable: true,
                hardwareMode: .automatic,
                hardwareModeKey: "F0Md",
                targetRPM: 1_400,
                controlEligibility: .trusted
            )],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let fanRows = try! XCTUnwrap(validFan["fans"] as? [NSDictionary])
        let dictionary = validFan.mutableCopy() as! NSMutableDictionary
        dictionary["fans"] = fanRows + [["id": 1, "name": "Broken"] as NSDictionary]

        XCTAssertNil(XPCSnapshotCoding.decode(dictionary))
    }

    func testSnapshotRejectsWholePayloadWhenAnySensorRowIsMalformed() {
        let dictionary: NSDictionary = [
            "modelIdentifier": "MacBookPro18,1",
            "isAppleSilicon": true,
            "isMacBookPro": true,
            "fanControlProtocolVersion": 2,
            "fans": [],
            "temperatureSensors": [
                ["id": "Tp09", "name": "CPU", "celsius": 60.0, "source": "synthetic"] as NSDictionary,
                ["id": "broken", "name": "Broken"] as NSDictionary
            ]
        ]

        XCTAssertNil(XPCSnapshotCoding.decode(dictionary))
    }
}
