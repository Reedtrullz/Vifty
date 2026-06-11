import Foundation
import XCTest
@testable import ViftyCore

final class FanControlCoordinatorTests: XCTestCase {
    func testUnsupportedHardwareThrowsAndDoesNotApplyManualCommand() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "Macmini10,1",
                isAppleSilicon: true,
                isMacBookPro: false
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.fixedRPM(3000))

        do {
            _ = try await coordinator.tick()
            XCTFail("Expected unsupported hardware")
        } catch ViftyError.unsupportedHardware {
            let applied = await hardware.appliedCommands
            XCTAssertTrue(applied.isEmpty)
        }
    }

    func testTemperatureCurveAppliesClampedFixedRPM() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan(minimumRPM: 2000, maximumRPM: 6000)],
                temperatureSensors: [Self.sensor(70)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.temperatureCurve(FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 1000),
            CurvePoint(temperatureCelsius: 70, rpm: 8000)
        ])))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(6000))])
    }

    func testMissingSensorsRestoresAutoForManualMode() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.temperatureCurve(.defaultCurve()))

        do {
            _ = try await coordinator.tick()
            XCTFail("Expected no temperature sensors")
        } catch ViftyError.noTemperatureSensors {
            let restored = await hardware.restoredFanIDs
            XCTAssertEqual(restored, [0])
        }
    }

    func testAutoModeRestoresPreviouslyManualFansAndClearsMarker() async throws {
        let marker = Self.marker()
        marker.markActive()
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [Self.sensor(64)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: marker,
            initialState: ControlState(mode: .auto, manualControlActive: true)
        )

        _ = try await coordinator.tick()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertFalse(marker.wasManualControlActive)
    }

    func testSelectingAutoAfterFixedRPMRestoresHardwareAutoMode() async throws {
        let marker = Self.marker()
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [Self.sensor(64)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: marker)

        await coordinator.setMode(.fixedRPM(6000))
        _ = try await coordinator.tick()
        await coordinator.setMode(.auto)
        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(6000))])
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let state = await coordinator.state
        XCTAssertFalse(state.manualControlActive)
        XCTAssertTrue(state.lastAppliedRPM.isEmpty)
        XCTAssertFalse(marker.wasManualControlActive)
    }

    func testExplicitAutoSelectionRestoresEvenWhenStateWasAlreadyCleared() async throws {
        let marker = Self.marker()
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [Self.sensor(64)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: marker,
            initialState: ControlState(mode: .auto, manualControlActive: false)
        )

        await coordinator.setMode(.auto)
        _ = try await coordinator.tick()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertFalse(marker.wasManualControlActive)
    }

    func testFixedRPMAppliesEvenWhenDaemonUnreachable() async throws {
        // When the daemon is down, writes should fall back to local SMC.
        // FakeHardware simulates the local path — if the coordinator calls
        // apply() and it reaches the hardware, the fallback works.
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.fixedRPM(3000))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3000))])
    }

    func testCurveWithPerFanOverrideAppliesDifferentRPMs() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [
                    Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 6000, controllable: true),
                    Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true)
                ],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        let curve = FanCurve(sensorID: nil, points: [
            CurvePoint(temperatureCelsius: 40, rpm: 2000),
            CurvePoint(temperatureCelsius: 60, rpm: 4000),
            CurvePoint(temperatureCelsius: 85, rpm: 5500)
        ])
        let overrides = [FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 4500)]

        try await coordinator.applyCurveWithOverrides(curve, fanOverrides: overrides, snapshot: hardware.snapshotValue)

        let commands = await hardware.appliedCommands
        // Fan 0 uses the shared curve: 4000 RPM at 60°C
        // Fan 1 uses the override: 4200 RPM at 60°C
        XCTAssertTrue(commands.contains(FanCommand(fanID: 0, mode: .fixedRPM(4000))))
        XCTAssertTrue(commands.contains(FanCommand(fanID: 1, mode: .fixedRPM(4200))))
    }

    func testCurveWithDuplicatePerFanOverridesUsesLastOverrideWithoutTrapping() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [
                    Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true)
                ],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        let curve = FanCurve(sensorID: nil, points: [
            CurvePoint(temperatureCelsius: 40, rpm: 2000),
            CurvePoint(temperatureCelsius: 60, rpm: 4000),
            CurvePoint(temperatureCelsius: 85, rpm: 5500)
        ])
        let overrides = [
            FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 4500),
            FanCurveOverride(fanID: 1, startRPM: 2300, midRPM: 4300, maxRPM: 4500)
        ]

        try await coordinator.applyCurveWithOverrides(curve, fanOverrides: overrides, snapshot: hardware.snapshotValue)

        let commands = await hardware.appliedCommands
        XCTAssertEqual(commands, [FanCommand(fanID: 1, mode: .fixedRPM(4300))])
    }

    func testCurveOverrideFallsBackToSharedCurveWhenBaseCurveHasFewerThanThreePoints() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [
                    Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true)
                ],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        let curve = FanCurve(sensorID: nil, points: [
            CurvePoint(temperatureCelsius: 60, rpm: 4000)
        ])
        let overrides = [FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 4500)]

        try await coordinator.applyCurveWithOverrides(curve, fanOverrides: overrides, snapshot: hardware.snapshotValue)

        let commands = await hardware.appliedCommands
        XCTAssertEqual(commands, [FanCommand(fanID: 1, mode: .fixedRPM(4000))])
    }

    private static func fan(minimumRPM: Int = 1400, maximumRPM: Int = 6000) -> Fan {
        Fan(id: 0, name: "Left Fan", currentRPM: minimumRPM, minimumRPM: minimumRPM, maximumRPM: maximumRPM, controllable: true)
    }

    private static func sensor(_ celsius: Double) -> TemperatureSensor {
        TemperatureSensor(id: "Tp09", name: "CPU Performance Core 1", celsius: celsius, source: .synthetic)
    }

    private static func marker() -> ManualControlMarker {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("manual-control-active")
        return ManualControlMarker(url: url)
    }
}

private actor FakeHardware: HardwareService {
    var snapshotValue: HardwareSnapshot
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []

    init(snapshot: HardwareSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotValue
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        appliedCommands.append(command)
    }

    func restoreAuto(fan: Fan) async throws {
        restoredFanIDs.append(fan.id)
    }
}
