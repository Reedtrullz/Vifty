import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelPollingTests: XCTestCase {
    func testPollOnceRefreshesPowerSnapshotFromInjectedReader() async {
        let expectedPower = PowerSnapshot(
            percent: 54,
            isPluggedIn: false,
            batteryVoltageVolts: 11.9,
            batteryCurrentAmps: -1.42,
            batteryPowerWatts: -16.898
        )
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { expectedPower },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertEqual(model.powerSnapshot, expectedPower)
        XCTAssertEqual(
            model.menuTitle,
            "Automatic CPU · CPU Proximity 64 C | 2500 RPM | 16.9 W drain | Fan writes blocked"
        )
    }

    func testPollOnceTreatsFanSnapshotAsReachableWhenPingFails() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            daemonPing: { false },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertTrue(model.daemonReachable)
        XCTAssertFalse(model.daemonResponding)
        XCTAssertEqual(model.helperHealthSummary, "Read-only fan telemetry · repair daemon for writes")
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall Helper or approve Login Items if prompted. Fan telemetry is read-only, and manual or agent cooling stays blocked until the daemon responds.")
    }

    func testPollOnceClearsStaleHelperUnreachableAfterDaemonRepair() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.hasCompletedHardwarePoll = true
        model.daemonReachable = false
        model.daemonResponding = false
        model.snapshot = HardwareSnapshot(fans: [], temperatureSensors: [], modelIdentifier: "MacBookPro18,3", isAppleSilicon: true, isMacBookPro: true)
        model.lastError = "Fan helper unreachable"

        XCTAssertEqual(model.helperHealthState, .error)
        XCTAssertTrue(model.helperHealthNeedsAttention)

        await model.pollOnce()

        XCTAssertNil(model.lastError)
        XCTAssertTrue(model.daemonReachable)
        XCTAssertTrue(model.daemonResponding)
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 1))
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertNil(model.helperRecoverySuggestion)
        XCTAssertNil(model.manualFanControlBlockedReason)
    }

    func testPollOnceUsesSlowerCadencesForPowerDaemonPingAndAgentStatus() async {
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let powerReads = AppModelReadCounter()
        let thermalReads = AppModelReadCounter()
        let daemonPings = AppModelReadCounter()
        let agentReads = AppModelReadCounter()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: {
                powerReads.increment()
                return PowerSnapshot(percent: 50)
            },
            thermalReader: {
                thermalReads.increment()
                return .nominal
            },
            now: { clock.now },
            daemonPing: {
                daemonPings.increment()
                return true
            },
            agentStatusReader: {
                agentReads.increment()
                return nil
            }
        )

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(powerReads.value, 1)
        XCTAssertEqual(thermalReads.value, 1)
        XCTAssertEqual(daemonPings.value, 1)
        XCTAssertEqual(agentReads.value, 1)

        clock.now = Date(timeIntervalSince1970: 1_016)
        await model.pollOnce()

        XCTAssertEqual(powerReads.value, 2)
        XCTAssertEqual(thermalReads.value, 2)
        XCTAssertEqual(daemonPings.value, 1)
        XCTAssertEqual(agentReads.value, 2)

        clock.now = Date(timeIntervalSince1970: 1_031)
        await model.pollOnce()

        XCTAssertEqual(powerReads.value, 3)
        XCTAssertEqual(thermalReads.value, 3)
        XCTAssertEqual(daemonPings.value, 2)
        XCTAssertEqual(agentReads.value, 3)
    }

    func testPollOnceRefreshesHelperStatusAfterSnapshotFailure() async {
        let hardware = AppModelFailingHardware(error: ViftyError.helperRejected("Snapshot failed"))
        let expectedStatus = AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            daemonPing: { true },
            agentStatusReader: { expectedStatus }
        )

        await model.pollOnce()

        XCTAssertTrue(model.daemonReachable)
        XCTAssertTrue(model.daemonResponding)
        XCTAssertEqual(model.agentControlStatus?.enabled, true)
        XCTAssertEqual(model.helperHealthSummary, "Fan helper error · repair needed")
        XCTAssertEqual(model.helperHealthState, .error)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck.")
        XCTAssertTrue(model.lastError?.contains("Snapshot failed") == true)
    }

    func testPollOncePreservesUntilChangedManualModeAfterTransientWriteFailure() async {
        let initialSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3600,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 3600
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1000)
        )
        let reclaimedSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 1800,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1010)
        )
        let hardware = AppModelFakeHardware(snapshot: initialSnapshot)
        let pingSequence = AppModelPingSequence(values: [true, false, false])
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { pingSequence.next() },
            agentStatusReader: { nil }
        )
        model.snapshot = initialSnapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .curve
        model.curveStartTemp = 50
        model.curveStartRPM = 3000
        model.curveMidTemp = 70
        model.curveMidRPM = 5000
        model.curveMaxTemp = 85
        model.curveMaxRPM = 6000
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()
        await hardware.setSnapshot(reclaimedSnapshot)
        await hardware.failNextApply(ViftyError.helperRejected("Daemon request timed out."))

        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("Daemon request timed out") == true)
        XCTAssertFalse(model.daemonResponding)
        XCTAssertTrue(model.daemonReachable)
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        switch model.controlState.mode {
        case .temperatureCurve:
            break
        default:
            XCTFail("Until-changed curve intent should survive a transient manual reassert failure.")
        }
        let restoredAfterFailure = await hardware.restoredFanIDs
        XCTAssertTrue(restoredAfterFailure.isEmpty, "A transient reassert failure should not force Auto and abandon the selected curve.")

        await model.pollOnce()

        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.selectedMode, .curve)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [
            FanCommand(fanID: 0, mode: .fixedRPM(4400)),
            FanCommand(fanID: 0, mode: .fixedRPM(4400))
        ])
    }

    func testPollOncePreservesUntilChangedManualModeAfterTransientNoTemperatureFailure() async {
        let initialSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3600,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 3600
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1000)
        )
        let noTemperatureSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3200,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 3200
                )
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1010)
        )
        let restoredSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3800,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 91.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1015)
        )
        let hardware = AppModelFakeHardware(snapshot: initialSnapshot)
        let pingSequence = AppModelPingSequence(values: [true, false, true])
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { pingSequence.next() },
            agentStatusReader: { nil }
        )
        model.snapshot = initialSnapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .curve
        model.curveStartTemp = 50
        model.curveStartRPM = 3000
        model.curveMidTemp = 70
        model.curveMidRPM = 5000
        model.curveMaxTemp = 85
        model.curveMaxRPM = 6000
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()
        await hardware.setSnapshot(noTemperatureSnapshot)
        await hardware.failNextSnapshot(ViftyError.noTemperatureSensors)

        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("No temperature sensors are available.") == true)
        XCTAssertEqual(model.daemonReachable, true)
        switch model.controlState.mode {
        case .temperatureCurve:
            break
        default:
            XCTFail("Until-changed curve intent should survive a transient no-temperature snapshot failure.")
        }

        await hardware.setSnapshot(restoredSnapshot)
        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .curve)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [
            FanCommand(fanID: 0, mode: .fixedRPM(4400)),
            FanCommand(fanID: 0, mode: .fixedRPM(6000))
        ])
    }

    func testPollOnceKeepsUntilChangedManualModeAfterTransientNoControllableFailure() async {
        let initialSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3600,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 3600
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1000)
        )
        let nonControllableSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3400,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: false,
                    hardwareMode: .forced,
                    targetRPM: 3400
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1010)
        )
        let hardware = AppModelFakeHardware(snapshot: initialSnapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = initialSnapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 4200
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()
        await hardware.failNextSnapshot(ViftyError.noControllableFans)

        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .fixed)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("No controllable fans are available.") == true)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [])
        switch model.controlState.mode {
        case .fixedRPM(4200):
            break
        default:
            XCTFail("Until-changed fixed intent should survive a transient no-controllable snapshot failure.")
        }

        await hardware.setSnapshot(nonControllableSnapshot)
        await model.pollOnce()

        XCTAssertEqual(model.selectedMode, .fixed)
        XCTAssertEqual(model.controlState.mode, .fixedRPM(4200))
    }

    func testPollOnceKeepsLatestTelemetryVisibleAfterManualReassertFailure() async {
        let initialSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 3600,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 3600
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1000)
        )
        let hotReclaimedSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 1780,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                )
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 91.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1010)
        )
        let hardware = AppModelFakeHardware(snapshot: initialSnapshot)
        let now = Date(timeIntervalSince1970: 1100)
        let pingSequence = AppModelPingSequence(values: [true, false])
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: 0) },
            thermalReader: { .nominal },
            now: { now },
            daemonPing: { pingSequence.next() },
            agentStatusReader: { nil }
        )
        model.snapshot = initialSnapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .curve
        model.curveStartTemp = 50
        model.curveStartRPM = 3000
        model.curveMidTemp = 70
        model.curveMidRPM = 5000
        model.curveMaxTemp = 85
        model.curveMaxRPM = 6000
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()
        await hardware.setSnapshot(hotReclaimedSnapshot)
        await hardware.failNextApply(ViftyError.helperRejected("Daemon request timed out."))

        await model.pollOnce()

        XCTAssertEqual(model.snapshot, hotReclaimedSnapshot)
        XCTAssertEqual(model.telemetryHistory.samples.last?.capturedAt, now)
        XCTAssertEqual(model.telemetryHistory.samples.last?.highestTemperatureCelsius, 91.2)
        XCTAssertEqual(model.telemetryHistory.samples.last?.firstFanRPM, 1780)
        XCTAssertEqual(model.controlOwnershipSummary, "Read-only fan telemetry; repair helper for fan writes · Vifty will retry Curve when the helper responds")
    }

    func testPollOncePeriodicallyReassertsUntilChangedCurveWhenHardwareTelemetryCannotConfirmOwnership() async {
        let startedAt = Date(timeIntervalSince1970: 2000)
        func snapshot(capturedAt: Date) -> HardwareSnapshot {
            HardwareSnapshot(
                fans: [
                    Fan(
                        id: 0,
                        name: "Left",
                        currentRPM: 4400,
                        minimumRPM: 1400,
                        maximumRPM: 6000,
                        controllable: true,
                        hardwareMode: nil,
                        targetRPM: nil
                    )
                ],
                temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
                modelIdentifier: "MacBookPro18,3",
                isAppleSilicon: true,
                isMacBookPro: true,
                capturedAt: capturedAt
            )
        }
        let expectedCommand = FanCommand(fanID: 0, mode: .fixedRPM(4400))
        let hardware = AppModelFakeHardware(snapshot: snapshot(capturedAt: startedAt))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot(capturedAt: startedAt)
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .curve
        model.curveStartTemp = 50
        model.curveStartRPM = 3000
        model.curveMidTemp = 70
        model.curveMidRPM = 5000
        model.curveMaxTemp = 85
        model.curveMaxRPM = 6000
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()
        var appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [expectedCommand])

        await hardware.setSnapshot(snapshot(capturedAt: startedAt.addingTimeInterval(20)))
        await model.pollOnce()
        appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [expectedCommand])

        await hardware.setSnapshot(snapshot(capturedAt: startedAt.addingTimeInterval(31)))
        await model.pollOnce()
        appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [expectedCommand, expectedCommand])
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Curve owns fan targets · CPU Proximity · until changed; reasserts if macOS drifts")
    }

    func testPollOnceRefreshesAgentControlStatus() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            },
            agentRestore: { _ in
                AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)
            }
        )

        await model.pollOnce()

        XCTAssertEqual(model.agentControlStatus?.activeLease?.id, "lease-1")
        XCTAssertTrue(model.menuTitle.contains("Agent cooling"))
    }

    func testPollOnceSurfacesAgentControlStatusFailure() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { true },
            agentStatusReader: {
                throw ViftyError.helperRejected("Daemon request timed out.")
            }
        )

        await model.pollOnce()

        XCTAssertNil(model.agentControlStatus)
        XCTAssertTrue(model.agentControlStatusError?.contains("Daemon request timed out") == true)
        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent status unavailable")
        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent status unavailable")
        XCTAssertEqual(model.agentCoolingSummary, "Agent cooling status unavailable; repair helper before requesting cooling.")
        XCTAssertTrue(model.agentCoolingNeedsAttention)
        XCTAssertFalse(model.agentCoolingRestoreActionAvailable)
        XCTAssertTrue(model.menuTitle.contains("Agent status unavailable"))
    }

    func testPollOncePrioritizesHelperRepairWhenAgentStatusFailsThroughReadOnlyTelemetry() async {
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot(hardwareMode: .automatic))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { false },
            agentStatusReader: {
                throw ViftyError.helperRejected("Daemon request timed out.")
            }
        )

        await model.pollOnce()

        XCTAssertTrue(model.agentControlStatusError?.contains("Daemon request timed out") == true)
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertEqual(model.controlOwnershipSummary, "Read-only fan telemetry; repair helper for fan writes")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertNil(model.agentCoolingMenuSummary)
        XCTAssertNil(model.agentCoolingSummary)
        XCTAssertNil(model.agentCoolingRecoverySuggestion)
        XCTAssertFalse(model.agentCoolingNeedsAttention)
        XCTAssertFalse(model.menuTitle.contains("Agent status unavailable"))
        XCTAssertTrue(model.menuTitle.contains("Fan writes blocked"))
        model.menuBarDisplayMode = .temperature
        XCTAssertFalse(model.menuBarLabelText.contains("Agent status unavailable"))
        XCTAssertTrue(model.menuBarLabelText.contains("Fan writes blocked"))
        XCTAssertEqual(model.manualFanControlBlockedReason, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")
    }

    func testPollOnceClearsAgentControlStatusFailureAfterSuccessfulRefresh() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let statusSequence = AgentStatusSequence(
            results: [
                .failure(ViftyError.helperRejected("Daemon request timed out.")),
                .success(AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil))
            ]
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { true },
            agentStatusReader: {
                try await statusSequence.next()
            }
        )

        await model.pollOnce()
        XCTAssertTrue(model.agentControlStatusError?.contains("Daemon request timed out") == true)
        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent status unavailable")

        await model.pollOnce()
        XCTAssertNil(model.agentControlStatusError)
        XCTAssertEqual(model.agentControlStatus?.activeLease?.id, "lease-1")
        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent cooling active")
        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent cooling")
    }

}
