import XCTest
@testable import ViftyCore

final class PowerInfoTests: XCTestCase {
    func testAdapterDetailsPreferRatedWattsAndParseUsbCPowerProfiles() {
        let snapshot = PowerInfoReader.makeSnapshot(
            powerSourceDescriptions: [[
                "Current Capacity": 72,
                "Max Capacity": 100,
                "Is Charging": true,
                "Is Charged": false,
                "Is Present": true,
                "Power Source State": "AC Power",
                "Time to Full Charge": 42,
                "BatteryHealth": "Normal"
            ]],
            smartBatteryProperties: [
                "BatteryInstalled": true,
                "ExternalConnected": true,
                "IsCharging": true,
                "FullyCharged": false,
                "Voltage": 12_120,
                "InstantAmperage": 2_360,
                "CycleCount": 81,
                "Temperature": 3_120,
                "DesignCapacity": 6_000,
                "AppleRawMaxCapacity": 5_520,
                "AppleRawCurrentCapacity": 4_200,
                "Condition": "Normal",
                "AdapterDetails": [
                    "Name": "USB-C Power Adapter",
                    "Manufacturer": "Apple Inc.",
                    "Watts": 96,
                    "AdapterVoltage": 20_000,
                    "Current": 4_700,
                    "SerialString": "ABC123",
                    "Model": "A2166",
                    "FamilyCode": 0xe0004001,
                    "UsbHvcMenu": [
                        ["MaxVoltage": 9_000, "MaxCurrent": 3_000],
                        ["MaxVoltage": 20_000, "MaxCurrent": 4_700],
                        ["MaxVoltage": 5_000, "MaxCurrent": 3_000]
                    ]
                ]
            ],
            externalAdapterDetails: nil
        )

        XCTAssertEqual(snapshot.percent, 72)
        XCTAssertTrue(snapshot.isPluggedIn)
        XCTAssertTrue(snapshot.isCharging)
        XCTAssertEqual(snapshot.timeToFullMinutes, 42)
        XCTAssertEqual(snapshot.batteryVoltageVolts ?? -1, 12.12, accuracy: 0.001)
        XCTAssertEqual(snapshot.batteryCurrentAmps ?? -1, 2.36, accuracy: 0.001)
        XCTAssertEqual(snapshot.batteryPowerWatts ?? -1, 28.6032, accuracy: 0.001)
        XCTAssertEqual(snapshot.healthPercent, 92)
        XCTAssertEqual(snapshot.adapter?.name, "USB-C Power Adapter")
        XCTAssertEqual(snapshot.adapter?.manufacturer, "Apple Inc.")
        XCTAssertEqual(snapshot.adapter?.ratedWatts, 96)
        XCTAssertEqual(snapshot.adapter?.powerWatts ?? -1, 96, accuracy: 0.001)
        XCTAssertEqual(snapshot.adapter?.family, "USB-C Power Delivery")
        XCTAssertEqual(snapshot.powerDeliveryProfiles.map { Int($0.watts.rounded()) }, [15, 27, 94])
        XCTAssertEqual(PowerDisplayFormatter.summary(for: snapshot), "96 W adapter")
        XCTAssertEqual(PowerDisplayFormatter.batteryFlow(for: snapshot), "Charging battery at 28.6 W")
    }

    func testExternalAdapterFallbackUsesNegotiatedVoltageAndCurrentWhenRatedWattsMissing() {
        let snapshot = PowerInfoReader.makeSnapshot(
            powerSourceDescriptions: [[
                "Current Capacity": 100,
                "Max Capacity": 100,
                "Is Charging": false,
                "Is Charged": true,
                "Power Source State": "AC Power"
            ]],
            smartBatteryProperties: [
                "ExternalConnected": true,
                "Voltage": 12_500,
                "Amperage": 0
            ],
            externalAdapterDetails: [
                "Name": "USB-C Monitor",
                "AdapterVoltage": 20_000,
                "Current": 3_000
            ]
        )

        XCTAssertTrue(snapshot.isCharged)
        XCTAssertEqual(snapshot.adapter?.name, "USB-C Monitor")
        XCTAssertEqual(snapshot.adapter?.powerWatts ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(PowerDisplayFormatter.summary(for: snapshot), "60 W adapter")
    }

    func testBatteryDrainComputesSignedWattsAndReadableSummary() {
        let snapshot = PowerInfoReader.makeSnapshot(
            powerSourceDescriptions: [[
                "Current Capacity": 54,
                "Max Capacity": 100,
                "Power Source State": "Battery Power",
                "Time to Empty": 185
            ]],
            smartBatteryProperties: [
                "BatteryInstalled": true,
                "ExternalConnected": false,
                "Voltage": 11_900,
                "InstantAmperage": -1_420,
                "Temperature": 2_900
            ],
            externalAdapterDetails: nil
        )

        XCTAssertFalse(snapshot.isPluggedIn)
        XCTAssertEqual(snapshot.percent, 54)
        XCTAssertEqual(snapshot.timeToEmptyMinutes, 185)
        XCTAssertEqual(snapshot.batteryPowerWatts ?? 0, -16.898, accuracy: 0.001)
        XCTAssertEqual(PowerDisplayFormatter.summary(for: snapshot), "16.9 W drain")
        XCTAssertEqual(PowerDisplayFormatter.batteryFlow(for: snapshot), "Battery draining at 16.9 W")
        XCTAssertEqual(PowerDisplayFormatter.duration(minutes: 185), "3h 5m")
    }
}
