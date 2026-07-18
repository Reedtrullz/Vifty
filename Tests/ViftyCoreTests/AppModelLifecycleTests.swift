import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelLifecycleTests: XCTestCase {
    func testManualApplyWaitsForFreshPostConfigurationPollInsteadOfCompletingOlderAutoPoll() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let pingGate = AppModelPreflightGate()
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
        )
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { await pingGate.ping() },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = false
        model.curveDefaultsSynced = true

        let olderAutoPoll = Task { await model.pollOnce() }
        await pingGate.waitUntilFirstCallStarts()
        let readsBeforeApply = await hardware.snapshotReadCount()
        XCTAssertEqual(readsBeforeApply, 1)

        model.selectedMode = .fixed
        model.fixedRPM = 4_200
        model.manualRunLimit = .minutes(10)
        let apply = Task { await model.applyCurrentModeSelection() }

        for _ in 0..<100 {
            if await coordinator.state.mode == .fixedRPM(4_200) {
                break
            }
            await Task.yield()
        }
        let configuredState = await coordinator.state
        let commandsBeforeRelease = await hardware.appliedCommands
        let readsWhileOlderPollPaused = await hardware.snapshotReadCount()
        XCTAssertEqual(configuredState.mode, .fixedRPM(4_200))
        XCTAssertTrue(commandsBeforeRelease.isEmpty)
        XCTAssertEqual(readsWhileOlderPollPaused, 1)

        await pingGate.releaseFirstCall()
        await olderAutoPoll.value
        let result = await apply.value
        let appliedCommands = await hardware.appliedCommands
        let finalSnapshotReads = await hardware.snapshotReadCount()

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(appliedCommands.count, 1)
        XCTAssertEqual(finalSnapshotReads, 3)
        XCTAssertEqual(model.controlState.mode, .fixedRPM(4_200))
        XCTAssertTrue(model.controlState.manualControlActive)
        XCTAssertEqual(
            FanControlOwnershipPresentation.resolve(model.fanControlOwnershipStatus).owner,
            .viftyManual
        )
    }

    func testSelectingAutoSupersedesPausedManualPollAndRestoresBeforeBatchCanContinue() async {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1_500, minimumRPM: 1_400, maximumRPM: 6_000, controllable: true, hardwareMode: .automatic, hardwareModeKey: "F0Md", targetRPM: 1_500),
                Fan(id: 1, name: "Right", currentRPM: 1_600, minimumRPM: 1_500, maximumRPM: 6_200, controllable: true, hardwareMode: .automatic, hardwareModeKey: "F1Md", targetRPM: 1_600)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 60, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        await hardware.pauseFirstApply()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.curveDefaultsSynced = true
        model.selectedMode = .fixed
        model.fixedRPM = 4_200
        model.manualRunLimit = .minutes(10)

        let applyTask = Task { await model.applyCurrentModeSelection() }
        await hardware.waitForPausedApply()

        model.selectedMode = .auto
        await model.restoreAutoNow()
        let restoredBeforeManualResumed = await hardware.restoredFanIDs
        await hardware.resumePausedApply()
        let applyResult = await applyTask.value
        let appliedCommands = await hardware.appliedCommands

        XCTAssertEqual(restoredBeforeManualResumed, [0, 1])
        XCTAssertEqual(appliedCommands.count, 1)
        XCTAssertEqual(applyResult, .superseded)
        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertEqual(model.controlState.mode, .auto)
        XCTAssertFalse(model.controlState.manualControlActive)
    }

    func testSelectingAutoWhileManualApplyWaitsForPreflightKeepsAutoAuthoritative() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let preflightGate = AppModelPreflightGate()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { await preflightGate.ping() },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.curveDefaultsSynced = true
        model.selectedMode = .fixed
        model.fixedRPM = 4_200
        model.manualRunLimit = .minutes(10)

        let applyTask = Task { await model.applyCurrentModeSelection() }
        await preflightGate.waitUntilFirstCallStarts()

        model.selectedMode = .auto
        await model.restoreAutoNow()
        await preflightGate.releaseFirstCall()
        let applyResult = await applyTask.value

        XCTAssertEqual(applyResult, .superseded)
        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertEqual(model.controlState.mode, .auto)
        XCTAssertFalse(model.controlState.manualControlActive)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        XCTAssertEqual(model.controlSessionPresentation.state, .ready)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
    }

    func testSuccessfulPollReconcilesFailedManualApplyWhenAttemptedDraftMatches() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .forced)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 3_000
        model.manualRunLimit = .indefinitely
        let initialResult = await model.applyCurrentModeSelection()
        XCTAssertEqual(initialResult, .applied)

        model.fixedRPM = 4_000
        model.markFanControlDraftPending()
        await hardware.failNextApply(ViftyError.helperRejected("transient apply failure"))
        let failedResult = await model.applyCurrentModeSelection()

        guard case .failed = failedResult else {
            return XCTFail("Expected the manual apply to fail before retry reconciliation")
        }
        guard case .failed = model.fanControlApplyState else {
            return XCTFail("Expected failed apply state before the successful retry poll")
        }
        XCTAssertTrue(model.hasPendingFanControlChanges)

        await model.pollOnce()

        XCTAssertNil(model.lastError)
        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        XCTAssertEqual(model.controlState.mode, .fixedRPM(4_000))
        XCTAssertEqual(model.controlSessionPresentation.state, .manual)
        XCTAssertNotEqual(model.controlSessionPresentation.primaryActionTitle, "Apply Changes")
    }

    func testExplicitApplyAtOldDeadlineRenewsManualSessionWithoutRestoringAuto() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .forced)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
        )
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 3_000
        model.manualRunLimit = .minutes(10)
        let initialResult = await model.applyCurrentModeSelection()
        XCTAssertEqual(initialResult, .applied)
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))

        clock.now = Date(timeIntervalSince1970: 1_600)
        model.fixedRPM = 4_500
        model.markFanControlDraftPending()
        let renewedResult = await model.applyCurrentModeSelection()

        XCTAssertEqual(renewedResult, .applied)
        XCTAssertEqual(model.selectedMode, .fixed)
        let coordinatorState = await coordinator.state
        XCTAssertEqual(coordinatorState.mode, .fixedRPM(4_500))
        XCTAssertTrue(coordinatorState.manualControlActive)
        XCTAssertEqual(model.controlState.mode, .fixedRPM(4_500))
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 2_200))
        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        XCTAssertEqual(model.controlSessionPresentation.state, .manual)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(restoredFanIDs.isEmpty)
    }

    func testFailedUntilChangedApplyPreservesPreviouslyCommittedTimedDeadline() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .forced)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 3_000
        model.manualRunLimit = .minutes(10)
        let initialResult = await model.applyCurrentModeSelection()
        XCTAssertEqual(initialResult, .applied)
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))

        model.fixedRPM = 4_000
        model.manualRunLimit = .indefinitely
        model.markFanControlDraftPending()
        await hardware.failNextApply(ViftyError.helperRejected("transient apply failure"))

        guard case .failed = await model.applyCurrentModeSelection() else {
            return XCTFail("Expected the Until changed apply to fail")
        }

        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))
        XCTAssertTrue(model.hasPendingFanControlChanges)
    }

    func testUnconfirmedUntilChangedApplyPreservesPreviouslyCommittedTimedDeadline() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .forced)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 3_000
        model.manualRunLimit = .minutes(10)

        let initialResult = await model.applyCurrentModeSelection()
        XCTAssertEqual(initialResult, .applied)
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))

        let ownershipReadsBeforeApply = await hardware.ownershipStatusReadCount()
        let commandsBeforeApply = await hardware.appliedCommands.count
        await hardware.failOwnershipStatus(
            onRead: ownershipReadsBeforeApply + 3,
            with: ViftyError.helperRejected("final ownership unavailable")
        )
        model.fixedRPM = 4_000
        model.manualRunLimit = .indefinitely
        model.markFanControlDraftPending()

        let result = await model.applyCurrentModeSelection()

        guard case .failed(let message) = result else {
            return XCTFail("Expected final ownership confirmation to fail")
        }
        let commandsAfterApply = await hardware.appliedCommands.count
        XCTAssertTrue(message.contains("final ownership unavailable"))
        XCTAssertEqual(commandsAfterApply, commandsBeforeApply + 1)
        XCTAssertEqual(model.controlState.mode, .fixedRPM(4_000))
        XCTAssertTrue(model.controlState.manualControlActive)
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))
        XCTAssertTrue(model.hasPendingFanControlChanges)
    }

    func testUnconfirmedFirstTimedApplyKeepsDeadlineAndCannotReconcileOnBackgroundPoll() async {
        let snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 3_000
        model.manualRunLimit = .minutes(10)

        let ownershipReadsBeforeApply = await hardware.ownershipStatusReadCount()
        await hardware.failOwnershipStatus(
            onRead: ownershipReadsBeforeApply + 3,
            with: ViftyError.helperRejected("final ownership unavailable")
        )

        let result = await model.applyCurrentModeSelection()

        guard case .failed(let message) = result else {
            return XCTFail("Expected final ownership confirmation to fail")
        }
        XCTAssertTrue(message.contains("final ownership unavailable"))
        XCTAssertEqual(model.controlState.mode, .fixedRPM(3_000))
        XCTAssertTrue(model.controlState.manualControlActive)
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))
        XCTAssertTrue(model.hasPendingFanControlChanges)

        await model.pollOnce()

        guard case .failed = model.fanControlApplyState else {
            return XCTFail("A later poll must not promote an Apply whose final ownership confirmation failed")
        }
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1_600))
        XCTAssertTrue(model.hasPendingFanControlChanges)
    }

    func testCurrentManualOwnershipConfirmationRejectsMismatchedTransactionID() async throws {
        let hardware = AppModelFakeHardware(
            snapshot: agentHardwareSnapshot(hardwareMode: .automatic)
        )
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
        )
        await coordinator.setMode(.fixedRPM(3_000))
        _ = try await coordinator.tick()

        let appliedStatus = try await hardware.fanControlOwnershipStatus()
        guard let owner = appliedStatus.owner,
              case .manual(let sessionID) = owner else {
            return XCTFail("Expected the fake daemon to expose the current manual session")
        }
        XCTAssertEqual(appliedStatus.transactionID, sessionID)
        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .manual(sessionID: sessionID),
            phase: .active,
            transactionID: "mismatched-transaction",
            expectedFanIDs: appliedStatus.expectedFanIDs,
            recoveryPending: false
        ))

        do {
            _ = try await coordinator.confirmCurrentManualOwnership()
            XCTFail("A different transaction must not confirm the current manual session")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains(
                "did not confirm the current Vifty manual fan-control transaction"
            ))
        }
    }

    func testStartPublishesMenuBarTelemetryBeforeFirstScheduledSleep() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let pollingSleeper = AppModelManualPollingSleeper()
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: marker
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: pollingSleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        model.start()
        await hardware.waitForSnapshotReadCount(1)
        let requestedDuration = await pollingSleeper.nextRequestedDuration()

        XCTAssertEqual(model.menuBarStatusItemText, "Mac | 67 C | 3352 RPM")
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertTrue(model.hasCompletedHardwarePoll)
        XCTAssertEqual(requestedDuration, .seconds(10))
        _ = await model.stopAndRestore()
        await pollingSleeper.cancelAll()
    }

    func testStartDoesNotImmediatelyPollTwice() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .automatic))
        let pollingSleeper = AppModelManualPollingSleeper()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: pollingSleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.start()
        await hardware.waitForSnapshotReadCount(1)
        let requestedDuration = await pollingSleeper.nextRequestedDuration()

        let snapshotReads = await hardware.snapshotReadCount()
        XCTAssertEqual(snapshotReads, 1)
        XCTAssertEqual(requestedDuration, .seconds(10))
        _ = await model.stopAndRestore()
        await pollingSleeper.cancelAll()
    }

    func testStartRecoversUncleanMarkerBeforeFirstRegularPoll() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .automatic))
        let pollingSleeper = AppModelManualPollingSleeper()
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        marker.markActive()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: marker
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: pollingSleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.start()
        let requestedDuration = await pollingSleeper.nextRequestedDuration()
        let snapshotReadCount = await hardware.snapshotReadCount()
        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let events = await hardware.recordedEvents()

        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertEqual(events, [.snapshot, .restoreAuto(fanID: 0), .snapshot])
        XCTAssertFalse(marker.wasManualControlActive)
        XCTAssertEqual(requestedDuration, .seconds(10))
        _ = await model.stopAndRestore()
        await pollingSleeper.cancelAll()
    }

    func testStartRestoresMarkerAbsentDaemonManualOwnershipBeforeFirstRegularPoll() async throws {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .manual(sessionID: "orphaned-manual-session"),
            phase: .active,
            transactionID: "orphaned-manual-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        ))
        let pollingSleeper = AppModelManualPollingSleeper()
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        XCTAssertFalse(marker.wasManualControlActive)
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: marker)
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: pollingSleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.start()
        let requestedDuration = await pollingSleeper.nextRequestedDuration()

        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let events = await hardware.recordedEvents()
        let ownershipStatus = try await hardware.fanControlOwnershipStatus()
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertEqual(events, [.snapshot, .restoreAuto(fanID: 0), .snapshot])
        XCTAssertTrue(FanControlCoordinator.confirmsCleanOSOwnership(ownershipStatus))
        XCTAssertFalse(marker.wasManualControlActive)
        let state = await coordinator.state
        XCTAssertEqual(state.mode, .auto)
        XCTAssertFalse(state.manualControlActive)
        XCTAssertEqual(requestedDuration, .seconds(10))

        _ = await model.stopAndRestore()
        await pollingSleeper.cancelAll()
    }

    func testStartRestoresMarkerAbsentDaemonRestorePendingOwnershipBeforeFirstRegularPoll() async throws {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .recovery,
            phase: .restorePending,
            transactionID: "pending-recovery-transaction",
            expectedFanIDs: [0],
            confirmedOSManagedFanIDs: [],
            recoveryPending: true,
            errorCode: "STARTUP_RECOVERY_BLOCKED"
        ))
        let pollingSleeper = AppModelManualPollingSleeper()
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        XCTAssertFalse(marker.wasManualControlActive)
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: marker)
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: pollingSleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.start()
        let requestedDuration = await pollingSleeper.nextRequestedDuration()

        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let ownershipStatus = try await hardware.fanControlOwnershipStatus()
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertTrue(FanControlCoordinator.confirmsCleanOSOwnership(ownershipStatus))
        XCTAssertFalse(marker.wasManualControlActive)
        let state = await coordinator.state
        XCTAssertEqual(state.mode, .auto)
        XCTAssertFalse(state.manualControlActive)
        XCTAssertEqual(requestedDuration, .seconds(10))

        _ = await model.stopAndRestore()
        await pollingSleeper.cancelAll()
    }

    func testStartKeepsUncleanMarkerAndRecoveryPendingWhenInitialAndRetryRestoreFail() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        await hardware.failNextRestore(ViftyError.helperRejected("initial recovery failed"))
        await hardware.failNextRestore(ViftyError.helperRejected("first poll retry failed"))
        let pollingSleeper = AppModelManualPollingSleeper()
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        marker.markActive()
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: marker)
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: pollingSleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.start()
        let requestedDuration = await pollingSleeper.nextRequestedDuration()
        let events = await hardware.recordedEvents()
        let state = await coordinator.state

        XCTAssertEqual(
            events,
            [.snapshot, .restoreAuto(fanID: 0), .snapshot, .restoreAuto(fanID: 0)]
        )
        XCTAssertTrue(marker.wasManualControlActive)
        XCTAssertEqual(state.mode, .auto)
        XCTAssertTrue(state.manualControlActive)
        XCTAssertEqual(requestedDuration, .seconds(10))

        _ = await model.stopAndRestore()
        await pollingSleeper.cancelAll()
    }

    func testUncleanRecoveryCannotRestoreOrClearAfterNewManualModeSupersedesSnapshot() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        let snapshotGate = AppModelAsyncGate()
        await hardware.setSnapshotGate(snapshotGate)
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        marker.markActive()
        let coordinator = FanControlCoordinator(hardware: hardware, uncleanMarker: marker)

        let recovery = Task { await coordinator.recoverIfNeeded() }
        await snapshotGate.waitUntilEntered()
        await coordinator.setMode(.fixedRPM(3_600))
        await snapshotGate.open()
        await recovery.value

        let state = await coordinator.state
        let events = await hardware.recordedEvents()
        XCTAssertEqual(events, [.snapshot])
        XCTAssertEqual(state.mode, .fixedRPM(3_600))
        XCTAssertTrue(state.manualControlActive)
        XCTAssertTrue(marker.wasManualControlActive)
    }

    func testTimedManualModeRestoresAutoAndClearsDraftBookkeeping() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true

        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)
        await model.applyCurrentModeSelection()

        clock.now = Date(timeIntervalSince1970: 1000 + 601)
        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        XCTAssertNotEqual(model.controlSessionPresentation.state, .manual)
        XCTAssertNotEqual(model.controlSessionPresentation.primaryAction, .apply)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0], "Timed expiry must issue a real Auto restore, not only update UI state")
    }

    func testTimedExpiryFallbackAutoCommitsDraftAfterInitialRestoreFailure() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)
        await model.applyCurrentModeSelection()
        await hardware.failNextRestore(ViftyError.helperRejected("initial expiry restore refused"))

        clock.now = Date(timeIntervalSince1970: 1601)
        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertTrue(model.lastError?.contains("initial expiry restore refused") == true)
        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
    }

    func testTimedExpiryRestoreFailureMarksApplyStateFailedWhenFallbackAlsoFails() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)
        await model.applyCurrentModeSelection()
        await hardware.failNextRestore(ViftyError.helperRejected("initial expiry restore refused"))
        await hardware.failNextRestore(ViftyError.helperRejected("fallback Auto restore refused"))

        clock.now = Date(timeIntervalSince1970: 1601)
        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .auto)
        guard case .failed(let message) = model.fanControlApplyState else {
            return XCTFail("Expected failed apply state after two Auto restore failures")
        }
        XCTAssertTrue(message.contains("initial expiry restore refused"))
        XCTAssertTrue(message.contains("fallback Auto restore refused"))
        XCTAssertTrue(model.hasPendingFanControlChanges)
    }

    func testPendingManualRunChangeKeepsCommittedTimedDeadlineUntilApply() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)

        await model.applyCurrentModeSelection()
        XCTAssertNotNil(model.manualSessionExpiresAt)

        model.manualRunLimit = .indefinitely
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 1000 + 600))
        XCTAssertTrue(model.hasPendingFanControlChanges)

        await model.applyCurrentModeSelection()
        XCTAssertNil(model.manualSessionExpiresAt)

        clock.now = Date(timeIntervalSince1970: 1000 + 601)
        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .fixed)
        switch model.controlState.mode {
        case .fixedRPM(5000):
            break
        default:
            XCTFail("Until-changed manual mode should survive past the stale timed deadline.")
        }
        let restored = await hardware.restoredFanIDs
        XCTAssertTrue(restored.isEmpty)
    }

    func testPendingTimedManualRunDoesNotCreateDeadlineUntilApply() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 2000))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()
        XCTAssertNil(model.manualSessionExpiresAt)

        model.manualRunLimit = .minutes(30)

        XCTAssertNil(model.manualSessionExpiresAt)

        await model.applyCurrentModeSelection()
        XCTAssertEqual(model.manualSessionExpiresAt, Date(timeIntervalSince1970: 2000 + 1800))
    }

    func testExplicitRestoreAutoClearsTimedManualDeadline() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let now = Date(timeIntervalSince1970: 1000)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true

        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)
        await model.applyCurrentModeSelection()
        XCTAssertNotNil(model.manualSessionExpiresAt)

        await model.restoreAutoNow()

        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertNil(model.manualSessionExpiresAt)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0], "Explicit Auto must also issue a hardware restore")
    }

    func testStopAndRestoreWaitsForHardwareAutoRestore() async {
        let snapshot = agentHardwareSnapshot()
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)

        await model.applyCurrentModeSelection()
        XCTAssertNotNil(model.manualSessionExpiresAt)
        model.fixedRPM = 5200
        model.markFanControlDraftPending()
        XCTAssertEqual(model.fanControlApplyState, .pending)

        let result = await model.stopAndRestore()

        XCTAssertEqual(result, .restored)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0], "Stop must wait for a real Auto restore before callers terminate the app.")
    }

    func testStopAndRestoreUsesOneAuthoritativeTransactionWithoutAgentClearFallback() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let recorder = AgentRestoreRecorder(activeLease: lease)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            },
            agentRestore: { reason in
                await recorder.restore(reason: reason)
            }
        )
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)

        let result = await model.stopAndRestore()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertEqual(result, .restored)
        let reasons = await recorder.reasons
        XCTAssertEqual(reasons, [])
        let restoreAttempts = await hardware.restoreAttemptCount()
        XCTAssertEqual(restoreAttempts, 1)
    }

    func testStopAndRestoreRestoresMarkerAbsentDaemonManualOwnershipAndConfirmsCleanStatus() async throws {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .manual(sessionID: "orphaned-manual-session"),
            phase: .active,
            transactionID: "orphaned-manual-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        let result = await model.stopAndRestore()

        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let ownershipStatusReadCount = await hardware.ownershipStatusReadCount()
        let ownershipStatus = try await hardware.fanControlOwnershipStatus()
        XCTAssertEqual(result, .restored)
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertEqual(ownershipStatusReadCount, 2)
        XCTAssertTrue(FanControlCoordinator.confirmsCleanOSOwnership(ownershipStatus))
    }

    func testStopAndRestoreFailsClosedWhenFreshOwnershipStatusIsUnreadable() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .automatic))
        await hardware.failOwnershipStatus(
            onRead: 1,
            with: ViftyError.helperRejected("ownership unavailable")
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )

        let result = await model.stopAndRestore()

        guard case .failed(let message) = result else {
            return XCTFail("Unreadable authoritative ownership must cancel termination")
        }
        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let ownershipStatusReadCount = await hardware.ownershipStatusReadCount()
        XCTAssertTrue(message.contains("before termination"))
        XCTAssertTrue(message.contains("ownership unavailable"))
        XCTAssertEqual(restoreAttemptCount, 0)
        XCTAssertEqual(ownershipStatusReadCount, 1)
    }

    func testStopAndRestoreStillAttemptsAutoWhenLocalManualStateExistsAndOwnershipReadFails() async throws {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        await hardware.failOwnershipStatus(
            onRead: 1,
            with: ViftyError.helperRejected("ownership unavailable")
        )
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
        )
        await coordinator.setMode(.fixedRPM(3_200))
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )

        let result = await model.stopAndRestore()

        guard case .failed(let message) = result else {
            return XCTFail("The unreadable pre-restore owner must still fail termination closed")
        }
        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let ownershipStatusReadCount = await hardware.ownershipStatusReadCount()
        let finalOwnershipStatus = try await hardware.fanControlOwnershipStatus()
        XCTAssertTrue(message.contains("before termination"))
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertEqual(ownershipStatusReadCount, 2)
        XCTAssertTrue(FanControlCoordinator.confirmsCleanOSOwnership(finalOwnershipStatus))
    }

    func testStopAndRestoreFailsClosedWhenPostRestoreOwnershipConfirmationIsUnreadable() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .forced))
        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-session"),
            phase: .active,
            transactionID: "manual-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        ))
        await hardware.failOwnershipStatus(
            onRead: 2,
            with: ViftyError.helperRejected("confirmation unavailable")
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        let result = await model.stopAndRestore()

        guard case .failed(let message) = result else {
            return XCTFail("Missing post-restore ownership confirmation must cancel termination")
        }
        let restoreAttemptCount = await hardware.restoreAttemptCount()
        let ownershipStatusReadCount = await hardware.ownershipStatusReadCount()
        XCTAssertTrue(message.contains("after Auto restore"))
        XCTAssertTrue(message.contains("confirmation unavailable"))
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertEqual(ownershipStatusReadCount, 2)
    }

    func testStopAndRestoreReturnsFailureWhenHardwareAutoCannotBeConfirmed() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        await hardware.failNextRestore(ViftyError.helperRejected("restore refused"))
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
        )
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = agentHardwareSnapshot()
        model.selectedMode = .fixed
        await coordinator.setMode(.fixedRPM(3200))

        let result = await model.stopAndRestore()

        XCTAssertEqual(result, .failed(message: "The fan helper rejected the command: restore refused"))
        XCTAssertTrue(model.lastError?.contains("restore refused") == true)
    }

    func testStopAndRestoreDoesNotRequireHardwareWriteWhenAlreadyAuto() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .automatic))
        await hardware.failNextRestore(ViftyError.helperRejected("daemon unavailable"))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )

        let result = await model.stopAndRestore()

        XCTAssertEqual(result, .restored)
        let restoreAttempts = await hardware.restoreAttemptCount()
        let ownershipStatusReadCount = await hardware.ownershipStatusReadCount()
        XCTAssertEqual(restoreAttempts, 0)
        XCTAssertEqual(ownershipStatusReadCount, 1)
    }

    func testFailedTerminationRestoreResumesPreviouslyRunningModel() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
        )
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.start()
        await model.pollOnce()
        model.selectedMode = .fixed
        await coordinator.setMode(.fixedRPM(3200))
        await hardware.failNextRestore(ViftyError.helperRejected("restore refused"))

        let result = await model.stopAndRestore()

        XCTAssertEqual(result, .failed(message: "The fan helper rejected the command: restore refused"))
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.selectedMode, .fixed)
        _ = await model.stopAndRestore()
    }

}
