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
            fans: [Self.fan(currentRPM: 4000, hardwareMode: .forced, targetRPM: 4000)],
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
            fans: [Self.fan(currentRPM: 4000, hardwareMode: .forced, targetRPM: 4000)],
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

    func testAutoSelectionPreemptsInFlightBatchAtFanBoundaryThenRestoresWholeFanSet() async throws {
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

        let tickTask = Task { () -> Error? in
            do {
                _ = try await coordinator.tick()
                return nil
            } catch {
                return error
            }
        }
        await hardware.waitForPausedApply()
        await coordinator.setMode(.auto)
        let snapshot = try await coordinator.tick()
        await hardware.resumePausedApply()
        let preemptedError = await tickTask.value
        let appliedCommandCount = await hardware.appliedCommands.count
        let restoredFanIDs = await hardware.restoredFanIDs

        XCTAssertEqual(
            appliedCommandCount,
            1,
            "Once Auto reaches the daemon, the in-flight batch may finish its current fan mutation but must not start the next Fixed write."
        )
        XCTAssertTrue(preemptedError?.localizedDescription.contains("preempted") == true)
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

    func testFixedRPMUsesFakeOnlyCompatibilityBatch() async throws {
        // HardwareService's per-fan compatibility implementation exists for
        // deterministic fakes. RealMacHardwareService overrides the batch and
        // fails closed when its daemon transaction is unavailable.
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

    func testCoordinatorUsesOneBatchForManualApplyAndOneFullSetBatchForAuto() async throws {
        let snapshot = HardwareSnapshot(
            fans: [Self.fan()],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = BatchRecordingHardware(snapshot: snapshot)
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: Self.marker())

        await coordinator.setMode(.fixedRPM(3_200))
        _ = try await coordinator.tick()

        let manualRequests = await hardware.manualRequests
        XCTAssertEqual(manualRequests.count, 1)
        XCTAssertEqual(manualRequests[0].expectedFanIDs, [0])
        XCTAssertEqual(manualRequests[0].targetRPMByFanID, [0: 3_200])
        let legacyApplyCallCount = await hardware.legacyApplyCallCount
        XCTAssertEqual(legacyApplyCallCount, 0)

        await coordinator.setMode(.auto)
        _ = try await coordinator.tick()

        let restoreRequests = await hardware.restoreRequests
        XCTAssertEqual(restoreRequests.count, 1)
        XCTAssertEqual(restoreRequests[0].expectedFanIDs, [])
        XCTAssertTrue(restoreRequests[0].allowRestoreAllTrustedFans)
        XCTAssertNil(restoreRequests[0].unreadableJournalRecoveryAuthority)
        let legacyRestoreCallCount = await hardware.legacyRestoreCallCount
        XCTAssertEqual(legacyRestoreCallCount, 0)
    }

    func testExplicitAutoPropagatesUnreadableJournalOperatorAuthorityOnce() async throws {
        let snapshot = HardwareSnapshot(
            fans: [Self.fan()],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = BatchRecordingHardware(snapshot: snapshot)
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: Self.marker(),
            initialState: ControlState(mode: .auto, manualControlActive: true)
        )

        await coordinator.setMode(
            .auto,
            unreadableJournalRecoveryAuthority: .explicitOperator
        )
        _ = try await coordinator.tick()

        let requests = await hardware.restoreRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].unreadableJournalRecoveryAuthority, .explicitOperator)
    }

    func testFailedExplicitAutoDoesNotReuseOperatorAuthorityOnBackgroundRetry() async throws {
        let snapshot = HardwareSnapshot(
            fans: [Self.fan()],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = BatchRecordingHardware(snapshot: snapshot, restoreFailuresRemaining: 1)
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: Self.marker(),
            initialState: ControlState(mode: .auto, manualControlActive: true)
        )

        await coordinator.setMode(
            .auto,
            unreadableJournalRecoveryAuthority: .explicitOperator
        )
        do {
            _ = try await coordinator.tick()
            XCTFail("Expected injected explicit restore failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("injected restore failure"))
        }
        _ = try await coordinator.tick()

        let requests = await hardware.restoreRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].unreadableJournalRecoveryAuthority, .explicitOperator)
        XCTAssertNil(requests[1].unreadableJournalRecoveryAuthority)
    }

    func testExplicitAutoUsesDaemonAuthoritativeRestoreWhenClientSnapshotHasNoFans() async throws {
        let snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = BatchRecordingHardware(snapshot: snapshot)
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: Self.marker(),
            initialState: ControlState(mode: .auto, manualControlActive: true)
        )

        await coordinator.setMode(
            .auto,
            unreadableJournalRecoveryAuthority: .explicitOperator
        )
        _ = try await coordinator.tick()

        let requests = await hardware.restoreRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].allowRestoreAllTrustedFans)
        XCTAssertEqual(requests[0].unreadableJournalRecoveryAuthority, .explicitOperator)
    }

    func testPartialNoJournalAutoFailsAndRetainsManualMarker() async throws {
        let marker = Self.marker()
        marker.markActive()
        let partialFan = Fan(
            id: 1,
            name: "Partial Fan",
            currentRPM: 1_500,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: nil,
            controlEligibility: FanControlEligibility(
                canApplyFixedRPM: false,
                canRestoreOSManagedMode: false,
                reasons: [.missingModeKey]
            )
        )
        let hardware = FakeHardware(snapshot: HardwareSnapshot(
            fans: [Self.fan(), partialFan],
            temperatureSensors: [Self.sensor(60)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: marker,
            initialState: ControlState(mode: .auto, manualControlActive: true)
        )

        do {
            _ = try await coordinator.tick()
            XCTFail("Expected partial global Auto refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("complete trusted fan inventory"))
        }

        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(restoredFanIDs.isEmpty)
        XCTAssertTrue(marker.wasManualControlActive)
        let state = await coordinator.state
        XCTAssertTrue(state.manualControlActive)
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
        hardwareMode: FanHardwareMode? = .automatic,
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
            hardwareModeKey: "F0Md",
            targetRPM: targetRPM ?? minimumRPM,
            controlEligibility: .trusted
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
    private var restoreGeneration: UInt64 = 0

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
        if reflectsCommandsInSnapshot,
           case .fixedRPM(let targetRPM) = command.mode,
           let fanIndex = snapshotValue.fans.firstIndex(where: { $0.id == fan.id }) {
            snapshotValue.fans[fanIndex].currentRPM = targetRPM
            snapshotValue.fans[fanIndex].hardwareMode = .forced
            snapshotValue.fans[fanIndex].targetRPM = targetRPM
        }
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
    }

    func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        let startingRestoreGeneration = restoreGeneration
        let fansByID = Dictionary(uniqueKeysWithValues: snapshotValue.fans.map { ($0.id, $0) })
        for fanID in request.targetRPMByFanID.keys.sorted() {
            guard let fan = fansByID[fanID], let rpm = request.targetRPMByFanID[fanID] else {
                throw ViftyError.helperRejected("Fan \(fanID) is missing from fake batch telemetry.")
            }
            guard restoreGeneration == startingRestoreGeneration else {
                throw ViftyError.helperRejected("Auto restoration preempted fan application.")
            }
            try await apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
            guard restoreGeneration == startingRestoreGeneration else {
                throw ViftyError.helperRejected("Auto restoration preempted fan application.")
            }
        }
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            phase: .active,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
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

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        restoreGeneration &+= 1
        let expectedFanIDs: [Int]
        if request.expectedFanIDs.isEmpty && request.allowRestoreAllTrustedFans {
            guard !snapshotValue.fans.isEmpty,
                  snapshotValue.fans.map(\.id).count == Set(snapshotValue.fans.map(\.id)).count,
                  snapshotValue.fans.allSatisfy({
                      SMCFanControlKeys.isValidFanID($0.id)
                          && $0.controlEligibility.canRestoreOSManagedMode
                  }) else {
                throw ViftyError.helperRejected(
                    "Global Auto restore requires one complete trusted fan inventory."
                )
            }
            expectedFanIDs = snapshotValue.fans.map(\.id).sorted()
        } else {
            expectedFanIDs = request.expectedFanIDs
        }
        let fansByID = Dictionary(uniqueKeysWithValues: snapshotValue.fans.map { ($0.id, $0) })
        for fanID in expectedFanIDs {
            guard let fan = fansByID[fanID] else {
                throw ViftyError.helperRejected("Expected fan \(fanID) is missing from fake restore telemetry.")
            }
            try await restoreAuto(fan: fan)
        }
        try beforeOwnershipClear()
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: nil,
            phase: nil,
            expectedFanIDs: expectedFanIDs,
            confirmedFanIDs: expectedFanIDs
        )
    }
}

private actor BatchRecordingHardware: HardwareService {
    let snapshotValue: HardwareSnapshot
    var manualRequests: [ManualFanControlRequest] = []
    var restoreRequests: [AutoRestoreRequest] = []
    var legacyApplyCallCount = 0
    var legacyRestoreCallCount = 0
    var restoreFailuresRemaining: Int

    init(snapshot: HardwareSnapshot, restoreFailuresRemaining: Int = 0) {
        self.snapshotValue = snapshot
        self.restoreFailuresRemaining = restoreFailuresRemaining
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotValue
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        legacyApplyCallCount += 1
    }

    func restoreAuto(fan: Fan) async throws {
        legacyRestoreCallCount += 1
    }

    func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        manualRequests.append(request)
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            phase: .active,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        restoreRequests.append(request)
        if restoreFailuresRemaining > 0 {
            restoreFailuresRemaining -= 1
            throw ViftyError.helperRejected("injected restore failure")
        }
        try beforeOwnershipClear()
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: nil,
            phase: nil,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
    }
}
