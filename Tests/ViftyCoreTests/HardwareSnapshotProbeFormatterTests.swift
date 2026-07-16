import XCTest
@testable import ViftyCore

final class HardwareSnapshotProbeFormatterTests: XCTestCase {
    func testProbeOutputIncludesFanHardwareModeRawValueAndTargetRPM() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 3_200,
                    minimumRPM: 1_400,
                    maximumRPM: 6_000,
                    controllable: true,
                    hardwareMode: .forced,
                    hardwareModeKey: "F0Md",
                    targetRPM: 5_000
                )
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 58.44, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        let output = HardwareSnapshotProbeFormatter.string(for: snapshot)

        XCTAssertTrue(output.contains("model=MacBookPro18,3 appleSilicon=true macBookPro=true"))
        XCTAssertTrue(output.contains("fan[0] name=\"Left Fan\" rpm=3200 min=1400 max=6000 controllable=true hardwareMode=Forced hardwareModeRawValue=1 hardwareModeKey=F0Md targetRPM=5000"))
        XCTAssertTrue(output.contains("canApplyFixedRPM=true canRestoreOSManagedMode=true controlIneligibilityReasons=none"))
        XCTAssertTrue(output.contains("temp[Tp09] name=\"CPU Proximity\" celsius=58.4 source=SMC"))
    }

    func testProbeOutputMarksMissingFanHardwareTelemetryExplicitly() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 1,
                    name: "Right Fan",
                    currentRPM: 2_200,
                    minimumRPM: 1_500,
                    maximumRPM: 7_200,
                    controllable: true
                )
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        let output = HardwareSnapshotProbeFormatter.string(for: snapshot)

        XCTAssertTrue(output.contains("fan[1] name=\"Right Fan\" rpm=2200 min=1500 max=7200 controllable=true hardwareMode=unknown hardwareModeRawValue=nil hardwareModeKey=nil targetRPM=nil"))
        XCTAssertTrue(output.contains("canApplyFixedRPM=true canRestoreOSManagedMode=true controlIneligibilityReasons=none"))
    }

    func testProbeOutputDistinguishesModeOnlyRestoreEligibilityFromFixedRPMEligibility() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 2_200,
                    minimumRPM: 1_500,
                    maximumRPM: 7_200,
                    controllable: false,
                    hardwareMode: .automatic,
                    hardwareModeKey: "F0Md",
                    controlEligibility: FanControlEligibility(
                        canApplyFixedRPM: false,
                        canRestoreOSManagedMode: true,
                        reasons: [.missingTargetKey]
                    )
                )
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let output = HardwareSnapshotProbeFormatter.string(for: snapshot)

        XCTAssertTrue(output.contains("controllable=false hardwareMode=Auto hardwareModeRawValue=0 hardwareModeKey=F0Md"))
        XCTAssertTrue(output.contains("canApplyFixedRPM=false canRestoreOSManagedMode=true controlIneligibilityReasons=missingTargetKey"))
    }
}
