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

    func testTemperatureCurveReappliesWhenHardwareReturnsToAuto() async throws {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 3000),
            CurvePoint(temperatureCelsius: 70, rpm: 5000)
        ])
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan(currentRPM: 4000, hardwareMode: .forced, targetRPM: 4000)],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.temperatureCurve(curve))

        _ = try await coordinator.tick()
        await hardware.clearAppliedCommands()
        await hardware.setSnapshot(HardwareSnapshot(
            fans: [Self.fan(currentRPM: 1800, hardwareMode: .automatic, targetRPM: nil)],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(
            applied,
            [FanCommand(fanID: 0, mode: .fixedRPM(4000))],
            "Until-changed curve mode must reassert the target if macOS reclaims Auto without a temperature change."
        )
    }

    func testTemperatureCurveReappliesWhenHardwareTargetDrifts() async throws {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 3000),
            CurvePoint(temperatureCelsius: 70, rpm: 5000)
        ])
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan(currentRPM: 4000, hardwareMode: .forced, targetRPM: 4000)],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.temperatureCurve(curve))

        _ = try await coordinator.tick()
        await hardware.clearAppliedCommands()
        await hardware.setSnapshot(HardwareSnapshot(
            fans: [Self.fan(currentRPM: 2200, hardwareMode: .forced, targetRPM: 2200)],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(
            applied,
            [FanCommand(fanID: 0, mode: .fixedRPM(4000))],
            "Until-changed curve mode must reassert the target if the live hardware target no longer matches Vifty."
        )
    }

    func testTemperatureCurvePeriodicallyReassertsUnchangedTarget() async throws {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 3000),
            CurvePoint(temperatureCelsius: 70, rpm: 5000)
        ])
        let startedAt = Date(timeIntervalSince1970: 100)
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan(currentRPM: 4000)],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true,
                capturedAt: startedAt
            )
        )
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: Self.marker(),
            manualReassertionInterval: 30
        )
        await coordinator.setMode(.temperatureCurve(curve))

        _ = try await coordinator.tick()
        await hardware.clearAppliedCommands()
        await hardware.setSnapshot(HardwareSnapshot(
            fans: [Self.fan(currentRPM: 4000)],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: startedAt.addingTimeInterval(20)
        ))

        _ = try await coordinator.tick()
        let beforeInterval = await hardware.appliedCommands
        XCTAssertTrue(beforeInterval.isEmpty)

        await hardware.setSnapshot(HardwareSnapshot(
            fans: [Self.fan(currentRPM: 4000)],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: startedAt.addingTimeInterval(31)
        ))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(
            applied,
            [FanCommand(fanID: 0, mode: .fixedRPM(4000))],
            "Until-changed curve mode must periodically refresh unchanged fan targets so macOS cannot silently reclaim control."
        )
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

    func testTickReturnsPostWriteHardwareForCurveAndAutoRestore() async throws {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 3_000),
            CurvePoint(temperatureCelsius: 70, rpm: 5_000)
        ])
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan(currentRPM: 1_500, hardwareMode: .automatic, targetRPM: 1_500)],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            ),
            reflectsCommandsInSnapshot: true
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())

        await coordinator.setMode(.temperatureCurve(curve))
        let curveSnapshot = try await coordinator.tick()

        XCTAssertEqual(curveSnapshot.fans.first?.hardwareMode, .forced)
        XCTAssertEqual(curveSnapshot.fans.first?.targetRPM, 4_000)

        await coordinator.setMode(.auto)
        let autoSnapshot = try await coordinator.tick()

        XCTAssertEqual(autoSnapshot.fans.first?.hardwareMode, .automatic)
        XCTAssertEqual(autoSnapshot.fans.first?.targetRPM, 1_400)
        let state = await coordinator.state
        XCTAssertEqual(state.mode, .auto)
        XCTAssertFalse(state.manualControlActive)
    }

    func testAutoSelectionPreemptsInFlightCurveWritesAndRestoresBothFans() async throws {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 3_000),
            CurvePoint(temperatureCelsius: 70, rpm: 5_000)
        ])
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [
                    Fan(id: 0, name: "Left Fan", currentRPM: 1_500, minimumRPM: 1_400, maximumRPM: 6_000, controllable: true, hardwareMode: .automatic, targetRPM: 1_500),
                    Fan(id: 1, name: "Right Fan", currentRPM: 1_600, minimumRPM: 1_500, maximumRPM: 6_200, controllable: true, hardwareMode: .automatic, targetRPM: 1_600)
                ],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            ),
            reflectsCommandsInSnapshot: true
        )
        await hardware.pauseFirstApply()
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.temperatureCurve(curve))

        let tickTask = Task { try await coordinator.tick() }
        await hardware.waitForPausedApply()
        await coordinator.setMode(.auto)
        await hardware.resumePausedApply()
        let snapshot = try await tickTask.value
        let appliedCommandCount = await hardware.appliedCommands.count
        let restoredFanIDs = await hardware.restoredFanIDs

        XCTAssertEqual(appliedCommandCount, 1)
        XCTAssertEqual(restoredFanIDs, [0, 1])
        XCTAssertEqual(snapshot.fans.map(\.hardwareMode), [.automatic, .automatic])
        let state = await coordinator.state
        XCTAssertEqual(state.mode, .auto)
        XCTAssertFalse(state.manualControlActive)
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

    func testForceAutoReturnsRestoredAfterHardwareConfirmation() async {
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

        let result = await coordinator.forceAuto()

        XCTAssertEqual(result, .restored)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [0])
    }

    func testForceAutoReturnsFailureWithoutClearingManualState() async {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan()],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        await hardware.setRestoreError(ViftyError.helperRejected("restore refused"))
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.fixedRPM(3200))

        let result = await coordinator.forceAuto()

        XCTAssertEqual(result, .failed(message: "The fan helper rejected the command: restore refused"))
        let state = await coordinator.state
        XCTAssertTrue(state.manualControlActive)
        XCTAssertEqual(state.mode, .fixedRPM(3200))
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

    func testFixedRPMWithPerFanTargetsAppliesEachFanTargetAndClampsToFanRange() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [
                    Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
                    Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
                ],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setFixedFanTargets([0: 4400, 1: 4700])
        await coordinator.setMode(.fixedRPM(3200))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [
            FanCommand(fanID: 0, mode: .fixedRPM(4296)),
            FanCommand(fanID: 1, mode: .fixedRPM(4700))
        ])
        let state = await coordinator.state
        XCTAssertEqual(state.lastAppliedRPM, [0: 4296, 1: 4700])
    }

    func testFixedRPMReappliesWhenHardwareReturnsToAuto() async throws {
        let hardware = FakeHardware(
            snapshot: HardwareSnapshot(
                fans: [Self.fan(currentRPM: 3200, hardwareMode: .forced, targetRPM: 3200)],
                temperatureSensors: [Self.sensor(60)],
                modelIdentifier: "MacBookPro18,1",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        )
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())
        await coordinator.setMode(.fixedRPM(3200))

        _ = try await coordinator.tick()
        await hardware.clearAppliedCommands()
        await hardware.setSnapshot(HardwareSnapshot(
            fans: [Self.fan(currentRPM: 1800, hardwareMode: .automatic, targetRPM: nil)],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))

        _ = try await coordinator.tick()

        let applied = await hardware.appliedCommands
        XCTAssertEqual(
            applied,
            [FanCommand(fanID: 0, mode: .fixedRPM(3200))],
            "Until-changed fixed mode must reassert the target if macOS reclaims Auto without a user change."
        )
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

    private static func fan(
        currentRPM: Int? = nil,
        minimumRPM: Int = 1400,
        maximumRPM: Int = 6000,
        hardwareMode: FanHardwareMode? = nil,
        targetRPM: Int? = nil
    ) -> Fan {
        Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: currentRPM ?? minimumRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            controllable: true,
            hardwareMode: hardwareMode,
            targetRPM: targetRPM
        )
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
    var restoreError: Error?
    let reflectsCommandsInSnapshot: Bool
    private var shouldPauseFirstApply = false
    private var applyIsPaused = false
    private var pausedApplyWaiters: [CheckedContinuation<Void, Never>] = []
    private var applyResumeContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: HardwareSnapshot, reflectsCommandsInSnapshot: Bool = false) {
        self.snapshotValue = snapshot
        self.reflectsCommandsInSnapshot = reflectsCommandsInSnapshot
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotValue
    }

    func setSnapshot(_ snapshot: HardwareSnapshot) {
        snapshotValue = snapshot
    }

    func clearAppliedCommands() {
        appliedCommands.removeAll()
    }

    func setRestoreError(_ error: Error?) {
        restoreError = error
    }

    func pauseFirstApply() {
        shouldPauseFirstApply = true
    }

    func waitForPausedApply() async {
        guard !applyIsPaused else { return }
        await withCheckedContinuation { continuation in
            pausedApplyWaiters.append(continuation)
        }
    }

    func resumePausedApply() {
        applyResumeContinuation?.resume()
        applyResumeContinuation = nil
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        appliedCommands.append(command)
        if shouldPauseFirstApply {
            shouldPauseFirstApply = false
            applyIsPaused = true
            pausedApplyWaiters.forEach { $0.resume() }
            pausedApplyWaiters.removeAll()
            await withCheckedContinuation { continuation in
                applyResumeContinuation = continuation
            }
            applyIsPaused = false
        }
        guard reflectsCommandsInSnapshot,
              case .fixedRPM(let targetRPM) = command.mode,
              let fanIndex = snapshotValue.fans.firstIndex(where: { $0.id == fan.id }) else {
            return
        }
        snapshotValue.fans[fanIndex].currentRPM = targetRPM
        snapshotValue.fans[fanIndex].hardwareMode = .forced
        snapshotValue.fans[fanIndex].targetRPM = targetRPM
    }

    func restoreAuto(fan: Fan) async throws {
        if let restoreError {
            throw restoreError
        }
        restoredFanIDs.append(fan.id)
        guard reflectsCommandsInSnapshot,
              let fanIndex = snapshotValue.fans.firstIndex(where: { $0.id == fan.id }) else {
            return
        }
        snapshotValue.fans[fanIndex].currentRPM = fan.minimumRPM
        snapshotValue.fans[fanIndex].hardwareMode = .automatic
        snapshotValue.fans[fanIndex].targetRPM = fan.minimumRPM
    }
}
