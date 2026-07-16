import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelFanControlTests: XCTestCase {
    func testRevertingManualDraftToAppliedValuesClearsPendingPresentation() async {
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
        model.curveDefaultsSynced = true
        model.selectedMode = .fixed
        model.fixedRPM = 3_000
        model.manualRunLimit = .indefinitely
        let initialResult = await model.applyCurrentModeSelection()
        XCTAssertEqual(initialResult, .applied)

        model.fixedRPM = 4_000
        model.markFanControlDraftPending()
        XCTAssertTrue(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .pending)

        model.fixedRPM = 3_000
        model.markFanControlDraftPending()

        XCTAssertFalse(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.fanControlApplyState, .applied)
        XCTAssertEqual(model.controlSessionPresentation.state, .manual)
        XCTAssertNotEqual(model.controlSessionPresentation.primaryActionTitle, "Apply Changes")
    }

    func testMarkFanControlDraftPendingUpdatesPresentationWithoutApplyingHardware() {
        let model = AppModel()
        model.selectedMode = .curve

        model.markFanControlDraftPending()

        XCTAssertEqual(model.fanControlApplyState, .pending)
        XCTAssertTrue(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.controlSessionPresentation.primaryAction, .none)
        XCTAssertEqual(model.controlSessionPresentation.state, .checking)
    }

    func testManualModeSelectionFailsClosedWhenDaemonDoesNotRespond() async {
        let snapshot = agentHardwareSnapshot()
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = false
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)

        await model.applyCurrentModeSelection()

        XCTAssertEqual(model.selectedMode, .fixed)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("Manual fan control blocked") == true)
        XCTAssertTrue(model.lastError?.contains("daemon writes are blocked") == true)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
    }

    func testFixedPerFanTargetsSyncWithLiveFansAndClampToEachFanRange() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: AppModelFakeHardware(snapshot: snapshot), uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.fixedRPM = 4600
        model.ensureFixedFanTargets(for: snapshot.fans)

        XCTAssertEqual(model.fixedFanTargets, [
            FixedFanTarget(fanID: 0, rpm: 4296),
            FixedFanTarget(fanID: 1, rpm: 4744)
        ])
        XCTAssertEqual(model.fixedFanTargetPercent(for: snapshot.fans[0]), 100)
        XCTAssertEqual(model.fixedFanTargetPercent(for: snapshot.fans[1]), 100)

        model.setFixedFanRPM(4900, for: snapshot.fans[1])
        model.setFixedFanRPM(1200, for: snapshot.fans[0])

        XCTAssertEqual(model.fixedFanTargets, [
            FixedFanTarget(fanID: 0, rpm: 1499),
            FixedFanTarget(fanID: 1, rpm: 4744)
        ])

        let replacementFans = [
            snapshot.fans[1],
            Fan(id: 2, name: "Center", currentRPM: 1500, minimumRPM: 1600, maximumRPM: 5000, controllable: true)
        ]
        model.ensureFixedFanTargets(for: replacementFans)

        XCTAssertEqual(model.fixedFanTargets, [
            FixedFanTarget(fanID: 1, rpm: 4744),
            FixedFanTarget(fanID: 2, rpm: 4849)
        ])
    }

    func testCurveDraftPreviewMatchesAppliedPerFanOverrideTargets() async {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1_500, minimumRPM: 1_500, maximumRPM: 6_000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1_500, minimumRPM: 1_500, maximumRPM: 4_500, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 60, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
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
        model.selectedMode = .curve
        model.selectedSensorID = "Tp09"
        model.curveStartTemp = 40
        model.curveStartRPM = 2_000
        model.curveMidTemp = 60
        model.curveMidRPM = 4_000
        model.curveMaxTemp = 85
        model.curveMaxRPM = 5_500
        model.usePerFanOverrides = true
        model.fanOverrides = [
            FanCurveOverride(fanID: 1, startRPM: 2_200, midRPM: 4_200, maxRPM: 4_500)
        ]
        model.markFanControlDraftPending()

        let previewTargets: [Int: Int] = Dictionary(uniqueKeysWithValues: snapshot.fans.compactMap { fan in
            model.draftTargetRPMPreview(for: fan).map { (fan.id, $0) }
        })

        XCTAssertEqual(previewTargets, [0: 4_000, 1: 4_200])

        _ = await model.applyCurrentModeSelection()

        let appliedCommands = await hardware.appliedCommands
        let appliedTargets: [Int: Int] = Dictionary(uniqueKeysWithValues: appliedCommands.compactMap { command in
            guard case .fixedRPM(let rpm) = command.mode else { return nil }
            return (command.fanID, rpm)
        })
        XCTAssertEqual(appliedTargets, previewTargets)
    }

    func testFixedPerFanDefaultsUseEachFanRangeBeforeTargetsAreStored() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: AppModelFakeHardware(snapshot: snapshot), uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.selectedMode = .fixed
        model.fixedRPM = 3200
        model.usePerFanFixedRPM = true

        XCTAssertTrue(model.fixedFanTargets.isEmpty)
        XCTAssertEqual(model.fixedFanSliderRPM(for: snapshot.fans[0]), 3200)
        XCTAssertEqual(model.fixedFanSliderRPM(for: snapshot.fans[1]), 3472)
        XCTAssertEqual(model.fixedFanTargetPercent(for: snapshot.fans[0]), 61)
        XCTAssertEqual(model.fixedFanTargetPercent(for: snapshot.fans[1]), 61)
        XCTAssertEqual(model.targetRPMPreview(for: snapshot.fans[0]), 3200)
        XCTAssertEqual(model.targetRPMPreview(for: snapshot.fans[1]), 3472)
    }

    func testFixedPerFanDraftRequiresExplicitApplyAfterCommit() async {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil },
            preferencesStore: AppPreferencesStore(url: temporaryPreferencesPath())
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .fixed
        model.fixedRPM = 3200
        model.usePerFanFixedRPM = true
        model.ensureFixedFanTargets(for: snapshot.fans)

        model.setFixedFanRPM(3600, for: snapshot.fans[0], persist: false)
        model.setFixedFanRPM(3900, for: snapshot.fans[0], persist: false)
        model.setFixedFanRPM(4700, for: snapshot.fans[1], persist: false)

        let appliedBeforeCommit = await hardware.appliedCommands
        XCTAssertTrue(appliedBeforeCommit.isEmpty)

        await model.commitFixedFanTargetsAndApplyNow()

        let pendingCommands = await hardware.appliedCommands
        XCTAssertTrue(pendingCommands.isEmpty)
        XCTAssertEqual(model.fanControlApplyState, .pending)

        await model.applyCurrentModeSelection()

        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [
            FanCommand(fanID: 0, mode: .fixedRPM(3900)),
            FanCommand(fanID: 1, mode: .fixedRPM(4700))
        ])
    }

    func testFixedPerFanModeAppliesDistinctTargetsThroughCoordinator() async {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
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
        model.fixedRPM = 3200
        model.usePerFanFixedRPM = true
        model.ensureFixedFanTargets(for: snapshot.fans)
        model.setFixedFanRPM(4400, for: snapshot.fans[0])
        model.setFixedFanRPM(4700, for: snapshot.fans[1])
        model.manualRunLimit = .minutes(10)

        await model.applyCurrentModeSelection()

        XCTAssertNotNil(model.manualSessionExpiresAt)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [
            FanCommand(fanID: 0, mode: .fixedRPM(4296)),
            FanCommand(fanID: 1, mode: .fixedRPM(4700))
        ])
        XCTAssertEqual(model.controlState.lastAppliedRPM, [0: 4296, 1: 4700])
        XCTAssertEqual(
            model.controlOwnershipSummary,
            "Vifty Fixed owns fan targets · Left 4296 RPM, Right 4700 RPM · until \(model.manualSessionExpiresAt!.formatted(date: .omitted, time: .shortened)); reasserts if macOS drifts"
        )
    }

    func testFixedPerFanModeFallsBackToGlobalRPMWhenOnlyOneFanIsControllable() async {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: false)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
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
        model.fixedRPM = 3200
        model.usePerFanFixedRPM = true
        model.ensureFixedFanTargets(for: snapshot.fans)
        model.setFixedFanRPM(4200, for: snapshot.fans[0])
        model.manualRunLimit = .indefinitely

        XCTAssertEqual(model.targetRPMPreview(for: snapshot.fans[0]), 3200)

        await model.applyCurrentModeSelection()

        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [
            FanCommand(fanID: 0, mode: .fixedRPM(3200))
        ])
        XCTAssertEqual(model.controlState.lastAppliedRPM, [0: 3200])
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3200 RPM · until changed; reasserts if macOS drifts")
    }

    func testManualModeSelectionFailsClosedWhenAgentLeaseIsActive() async {
        let snapshot = agentHardwareSnapshot()
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )
        model.selectedMode = .fixed
        model.fixedRPM = 5000
        model.manualRunLimit = .minutes(10)

        await model.applyCurrentModeSelection()

        XCTAssertEqual(model.selectedMode, .fixed)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("Manual fan control blocked") == true)
        XCTAssertTrue(model.lastError?.contains("Agent Build cooling owns fan control") == true)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
    }

    func testManualModeSelectionRefreshesAgentStatusBeforeWritingFans() async {
        let snapshot = agentHardwareSnapshot()
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let lease = agentLease()
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(
                    enabled: true,
                    activeLease: lease,
                    lastDecision: nil,
                    lastErrorCode: nil
                )
            }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = true
        model.selectedMode = .curve
        model.manualRunLimit = .indefinitely

        await model.applyCurrentModeSelection()

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertEqual(model.agentControlStatus?.activeLease?.id, "lease-1")
        XCTAssertTrue(model.lastError?.contains("Manual fan control blocked") == true)
        XCTAssertTrue(model.lastError?.contains("Agent Build cooling owns fan control") == true)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
    }

    func testManualModeSelectionFailsClosedWhenAgentStatusIsUnavailable() async {
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
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription
        model.selectedMode = .curve
        model.manualRunLimit = .minutes(10)

        await model.applyCurrentModeSelection()

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("Manual fan control blocked") == true)
        XCTAssertTrue(model.lastError?.contains("Agent control status is unavailable") == true)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
    }

    func testAgentCoolingSummaryKeepsKnownLeaseVisibleWhenStatusRefreshFails() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1200) })
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent status warning")
        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent status warning")
        XCTAssertTrue(model.agentCoolingNeedsAttention)
        XCTAssertTrue(model.agentCoolingSummary?.contains("Agent Build cooling until") == true)
        XCTAssertTrue(model.agentCoolingSummary?.contains("status refresh failed; do not start another workload") == true)
        XCTAssertTrue(model.controlOwnershipSummary.contains("Agent Build owns cooling until"))
        XCTAssertTrue(model.controlOwnershipSummary.contains("status refresh failed"))
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertEqual(
            model.agentCoolingRecoverySuggestion,
            "Do not start another workload; use Auto to restore cooling, then check viftyctl status/audit after helper repair."
        )
        XCTAssertTrue(model.agentCoolingRestoreActionAvailable)
        XCTAssertEqual(model.agentCoolingRestoreActionTitle, "Auto")
        XCTAssertEqual(model.agentCoolingRestoreActionHelp, "Restore Auto before starting another agent workload")
    }

    func testAgentCoolingSummaryIncludesWorkloadAndSortedTargets() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1200) })
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(targetRPMByFanID: [1: 3700, 0: 3600]),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent cooling")
        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent cooling active")
        XCTAssertFalse(model.agentCoolingNeedsAttention)
        XCTAssertTrue(model.agentCoolingSummary?.contains("Agent Build cooling until") == true)
        XCTAssertTrue(model.agentCoolingSummary?.contains("F0 3600 RPM, F1 3700 RPM") == true)
        XCTAssertTrue(model.controlOwnershipSummary.contains("Agent Build owns cooling until"))
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
        XCTAssertNil(model.agentCoolingRecoverySuggestion)
    }

    func testAgentCoolingSummaryWarnsWhenLeaseExpiredButUnrestored() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1700) })
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = agentHardwareSnapshot()
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent restore pending")
        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent restore pending")
        XCTAssertTrue(model.agentCoolingNeedsAttention)
        XCTAssertTrue(model.agentCoolingSummary?.contains("expired; waiting for Auto restore") == true)
        XCTAssertTrue(model.menuTitle.contains("Agent restore pending"))
        XCTAssertEqual(model.controlOwnershipSummary, "Agent Build lease expired; restore Auto to clear daemon control")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertEqual(
            model.agentCoolingRecoverySuggestion,
            "Use Auto to restore daemon control before starting another workload."
        )
        XCTAssertTrue(model.agentCoolingRestoreActionAvailable)
        XCTAssertEqual(model.agentCoolingRestoreActionTitle, "Auto")
        XCTAssertEqual(model.agentCoolingRestoreActionHelp, "Restore Auto before starting another agent workload")
    }

    func testAgentCoolingRestoreActionUsesRequestCopyWhenHelperCannotConfirmWrites() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1700) })
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = agentHardwareSnapshot()
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertEqual(model.agentCoolingPanelTitle, "Agent restore pending")
        XCTAssertTrue(model.agentCoolingNeedsAttention)
        XCTAssertTrue(model.agentCoolingRestoreActionAvailable)
        XCTAssertEqual(model.agentCoolingRestoreActionTitle, "Request Auto")
        XCTAssertEqual(model.agentCoolingRestoreActionHelp, "Request Auto restore; the write cannot be confirmed until the helper responds")
    }

    func testAgentCoolingRecoverySuggestionRepairsStatusUnavailableBeforeCooling() {
        let model = AppModel()
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(
            model.agentCoolingRecoverySuggestion,
            "Repair Helper before requesting agent cooling."
        )
    }

    func testRestoreAutoClearsDaemonOwnedAgentLease() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let recorder = AgentRestoreRecorder(activeLease: lease)
        let statusSequence = AgentStatusSequence(results: [
            .success(AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)),
            .success(AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil))
        ])
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: {
                try await statusSequence.next()
            },
            agentRestore: { reason in
                await recorder.restore(reason: reason)
            }
        )

        await model.pollOnce()
        await model.restoreAutoNow()

        let reasons = await recorder.reasons
        XCTAssertEqual(reasons, [], "User Auto must not issue a second independent agent restore")
        let restoreAttemptCount = await hardware.restoreAttemptCount()
        XCTAssertEqual(restoreAttemptCount, 1)
        XCTAssertNil(model.agentControlStatus?.activeLease)
    }

    func testRestoreAutoReportsAuthoritativeTransactionFailureWithoutAgentClearFallback() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        await hardware.failNextRestore(ViftyError.helperRejected("Daemon connection invalidated."))
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

        await model.pollOnce()
        await model.restoreAutoNow()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [])
        XCTAssertEqual(model.agentControlStatus?.activeLease?.id, "lease-1")
        XCTAssertTrue(model.lastError?.contains("Daemon connection invalidated") == true)
        let reasons = await recorder.reasons
        XCTAssertEqual(reasons, [])
    }

}
