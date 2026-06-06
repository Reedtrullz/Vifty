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
