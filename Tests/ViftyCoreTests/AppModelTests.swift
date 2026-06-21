import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelTests: XCTestCase {
    func testSaveProfileWithDuplicateNameOverwrites() {
        let model = AppModel()
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")
        XCTAssertEqual(model.savedProfiles.count, 1)

        // Change sliders to different values.
        model.curveStartTemp = 60
        model.curveStartRPM = 1500

        // Save again with the same name — should overwrite, not append.
        model.saveCurrentProfile(name: "Quiet")
        XCTAssertEqual(model.savedProfiles.count, 1, "Duplicate name should overwrite, not append")
        XCTAssertEqual(model.savedProfiles[0].startTemp, 60, "Should store updated values")
        XCTAssertEqual(model.savedProfiles[0].startRPM, 1500)
    }

    func testSaveProfileWithDifferentNamesAppends() {
        let model = AppModel()
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")
        model.saveCurrentProfile(name: "Loud")
        XCTAssertEqual(model.savedProfiles.count, 2)
    }

    func testEnsureFanOverridesMatchesSavedOverridesByFanIDAndAddsMissingFans() {
        let model = AppModel()
        model.curveStartRPM = 1400
        model.curveMidRPM = 3500
        model.curveMaxRPM = 6000
        model.fanOverrides = [
            FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 5800)
        ]
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
            Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)
        ]

        model.ensureFanOverrides(for: fans)

        XCTAssertEqual(model.fanOverrides.map(\.fanID), [0, 1])
        XCTAssertEqual(model.fanOverride(for: 0)?.startRPM, 1400)
        XCTAssertEqual(model.fanOverride(for: 1)?.startRPM, 2200)
        XCTAssertEqual(model.fanOverride(for: 1)?.midRPM, 4200)
    }

    func testSetFanOverrideUpdatesMatchingFanIDAndClampsToFanRange() {
        let model = AppModel()
        let left = Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 3000, controllable: true)
        let right = Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1400, maximumRPM: 4500, controllable: true)
        model.fanOverrides = [
            FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 4400)
        ]

        model.setOverrideStartRPM(1000, for: left)
        model.setOverrideMaxRPM(9999, for: right)

        XCTAssertEqual(model.fanOverride(for: 0)?.startRPM, 1500)
        XCTAssertEqual(model.fanOverride(for: 1)?.startRPM, 2200)
        XCTAssertEqual(model.fanOverride(for: 1)?.maxRPM, 4500)
    }

    func testDeveloperPresetUsesFanRangeSelectsSensorAndClearsOverrides() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1000, maximumRPM: 5000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1200, maximumRPM: 5200, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.usePerFanOverrides = true
        model.fanOverrides = [
            FanCurveOverride(fanID: 0, startRPM: 4800, midRPM: 4900, maxRPM: 5000)
        ]

        model.loadDeveloperPreset(.build)

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertEqual(model.selectedSensorID, "Tp09")
        XCTAssertEqual(model.curveStartTemp, 52)
        XCTAssertEqual(model.curveMidTemp, 68)
        XCTAssertEqual(model.curveMaxTemp, 84)
        XCTAssertEqual(Int(model.curveStartRPM), 2600)
        XCTAssertEqual(Int(model.curveMidRPM), 3400)
        XCTAssertEqual(Int(model.curveMaxRPM), 4000)
        XCTAssertFalse(model.usePerFanOverrides)
        XCTAssertTrue(model.fanOverrides.isEmpty)
        XCTAssertTrue(model.curveDefaultsSynced)
    }

    func testSelectCurveProfileSwitchesToCurveAndLoadsProfile() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 6200, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 64, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: snapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        let profileID = UUID()
        model.snapshot = snapshot
        model.daemonResponding = true
        model.daemonReachable = true
        model.selectedMode = .auto
        model.savedProfiles = [
            CurveProfile(
                id: profileID,
                name: "Build",
                sensorID: "Tp09",
                startTemp: 54,
                startRPM: 2600,
                midTemp: 70,
                midRPM: 3800,
                maxTemp: 86,
                maxRPM: 5200,
                fanOverrides: [
                    FanCurveOverride(fanID: 1, startRPM: 2800, midRPM: 4100, maxRPM: 5600)
                ]
            )
        ]

        XCTAssertTrue(model.selectCurveProfile(id: profileID))

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertEqual(model.selectedSensorID, "Tp09")
        XCTAssertEqual(model.curveStartTemp, 54)
        XCTAssertEqual(model.curveStartRPM, 2600)
        XCTAssertEqual(model.curveMidTemp, 70)
        XCTAssertEqual(model.curveMidRPM, 3800)
        XCTAssertEqual(model.curveMaxTemp, 86)
        XCTAssertEqual(model.curveMaxRPM, 5200)
        XCTAssertTrue(model.usePerFanOverrides)
        XCTAssertEqual(model.fanOverrides.map(\.fanID), [0, 1])
        XCTAssertEqual(model.fanOverride(for: 1)?.maxRPM, 5600)
    }

    func testSelectCurveProfileIgnoresMissingProfile() {
        let model = AppModel()
        model.savedProfiles = []
        model.selectedMode = .auto
        model.curveStartTemp = 55

        XCTAssertFalse(model.selectCurveProfile(id: UUID()))

        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertEqual(model.curveStartTemp, 55)
    }

    func testDeveloperPresetRPMCapsStayWithinDefaultAgentPolicyCeiling() {
        let policy = AgentControlPolicy()

        for preset in DeveloperFanPreset.allCases {
            XCTAssertLessThanOrEqual(preset.startRPMPercent, policy.maximumAllowedRPMPercent)
            XCTAssertLessThanOrEqual(preset.midRPMPercent, policy.maximumAllowedRPMPercent)
            XCTAssertLessThanOrEqual(preset.maxRPMPercent, policy.maximumAllowedRPMPercent)
        }
    }

    func testSaveProfileReportsProfileStoreFailure() throws {
        let parentFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: parentFile)
        let store = CurveProfileStore(url: parentFile.appendingPathComponent("curve-profiles.json"))
        let model = AppModel(profileStore: store)
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")

        XCTAssertEqual(model.savedProfiles.count, 1)
        XCTAssertTrue(model.lastError?.contains("Failed to save profiles") == true)
    }

    func testCurveDefaultsOnlySyncOnce() {
        let model = AppModel()
        // Initially not synced.
        XCTAssertFalse(model.curveDefaultsSynced)

        // Mark as synced (simulates first poll having run).
        model.curveDefaultsSynced = true

        // Set values to exact defaults — they should NOT be overwritten.
        model.curveStartRPM = 1400
        model.curveMaxRPM = 6000

        // After marking synced, the guard in syncCurveDefaultsIfNeeded
        // returns early, so these values persist.
        XCTAssertEqual(model.curveStartRPM, 1400)
        XCTAssertEqual(model.curveMaxRPM, 6000)
        XCTAssertTrue(model.curveDefaultsSynced)
    }

    func testHelperHealthSummaryReportsCheckingBeforeFirstHardwarePoll() {
        let model = AppModel()

        XCTAssertEqual(model.helperHealthSummary, "Checking fan helper")
        XCTAssertEqual(model.helperHealthState, .checking)
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertNil(model.helperRecoverySuggestion)
    }

    func testHelperHealthSummaryReportsHealthyWhenDaemonAndFansAvailable() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan helper healthy · 1 fan")
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 1))
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertNil(model.helperRecoverySuggestion)
    }

    func testHelperHealthSummaryReportsHelperErrorBeforeHealthyState() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.lastError = "The fan helper rejected the command"

        XCTAssertEqual(model.helperHealthSummary, "Fan helper error · repair needed")
        XCTAssertEqual(model.helperHealthState, .error)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "The helper may be installed, but the current daemon path still needs repair.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck.")
    }

    func testHelperHealthSummaryReportsReachableWithNoFanData() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan helper reachable · waiting for fan data")
        XCTAssertEqual(model.helperHealthState, .noFanData)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperRecoverySuggestion, "Keep Auto selected and collect read-only diagnostics. Fan writes stay blocked until controllable fans appear.")
    }

    func testHelperHealthSummaryPluralizesFanCount() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 2450, minimumRPM: 1400, maximumRPM: 6000, controllable: true)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan helper healthy · 2 fans")
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 2))
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
    }

    func testHelperHealthSummaryWarnsWhenTelemetryFallbackWorksButDaemonDoesNotRespond() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Read-only fan telemetry · repair daemon for writes")
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "macOS helper may be installed, but daemon XPC is not responding; fan reads are read-only and writes stay blocked.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall Helper or approve Login Items if prompted. Fan telemetry is read-only, and manual or agent cooling stays blocked until the daemon responds.")
    }

    func testAutoRestoreActionCopyUsesRequestLanguageWhenWritesCannotBeConfirmed() {
        let healthy = AppModel()
        healthy.daemonResponding = true
        healthy.daemonReachable = true
        healthy.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(healthy.autoRestoreActionTitle, "Auto")
        XCTAssertEqual(healthy.autoRestoreActionHelp, "Restore Auto")
        XCTAssertEqual(healthy.modeSelectionActionTitle, "Auto")
        XCTAssertEqual(healthy.modeSelectionActionHelp, "Restore Auto")
        healthy.selectedMode = .fixed
        XCTAssertEqual(healthy.modeSelectionActionTitle, "Apply")
        XCTAssertEqual(healthy.modeSelectionActionHelp, "Apply selected fan mode")

        let telemetryOnly = AppModel()
        telemetryOnly.daemonResponding = false
        telemetryOnly.daemonReachable = true
        telemetryOnly.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(telemetryOnly.autoRestoreActionTitle, "Request Auto")
        XCTAssertEqual(telemetryOnly.autoRestoreActionHelp, "Request Auto restore; the write cannot be confirmed until the helper responds")
        XCTAssertEqual(telemetryOnly.modeSelectionActionTitle, "Request Auto")
        XCTAssertEqual(telemetryOnly.modeSelectionActionHelp, "Request Auto restore; the write cannot be confirmed until the helper responds")
        telemetryOnly.selectedMode = .fixed
        XCTAssertEqual(telemetryOnly.modeSelectionActionTitle, "Apply")
        XCTAssertEqual(telemetryOnly.modeSelectionActionHelp, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")
    }

    func testHelperMenuCopyUsesCompactRepairHintWhenTelemetryIsReadOnly() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 72, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Read-only fan telemetry · repair daemon for writes")
        XCTAssertEqual(model.helperHealthMenuSummary, "Fan writes blocked")
        XCTAssertEqual(model.helperInstallRuntimeContext, "macOS helper may be installed, but daemon XPC is not responding; fan reads are read-only and writes stay blocked.")
        XCTAssertEqual(model.helperMenuRecoverySuggestion, "Repair/Reinstall Helper; approve Login Items if prompted.")
    }

    func testHelperInstallRuntimeContextIsNilForHealthyAndEvidenceOnlyStates() {
        let model = AppModel()

        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 1))
        XCTAssertNil(model.helperInstallRuntimeContext)

        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        XCTAssertEqual(model.helperHealthState, .noFanData)
        XCTAssertNil(model.helperInstallRuntimeContext)

        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: false),
                Fan(id: 1, name: "Right", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: false)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        XCTAssertEqual(model.helperHealthState, .noControllableFans(fanCount: 2))
        XCTAssertNil(model.helperInstallRuntimeContext)

        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "Mac14,2",
            isAppleSilicon: true,
            isMacBookPro: false
        )
        XCTAssertEqual(model.helperHealthState, .unsupported)
        XCTAssertNil(model.helperInstallRuntimeContext)
    }

    func testHotBlockedFanWritesSuppressRedundantHelperMenuRecovery() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.thermalPressure = .nominal
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.fanWriteBlockedWhileHotSummary, "High temp · fan writes blocked")
        XCTAssertEqual(model.fanWriteBlockedWhileHotRecoverySuggestion, "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds.")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan writes are blocked while hot")
        XCTAssertEqual(model.helperHealthMenuSummary, "Fan writes blocked")
        XCTAssertNil(model.helperMenuRecoverySuggestion)
    }

    func testHotBlockedFanWritesExplainManualRetryInsteadOfAutoOnlyGuidance() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.thermalPressure = .nominal
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.fanWriteBlockedWhileHotSummary, "High temp · fan writes blocked")
        XCTAssertEqual(model.fanWriteBlockedWhileHotRecoverySuggestion, "Reduce heavy work now. Repair/Reinstall Helper; Vifty will retry Curve when the daemon responds. Use Request Auto to stop retries.")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan writes are blocked while hot")
        XCTAssertFalse(model.fanWriteBlockedWhileHotRecoverySuggestion?.contains("Keep Auto selected") == true)
    }

    func testManualPendingHelperOutageShowsRetryCopyInsteadOfBlockedStartCopy() {
        let model = AppModel()
        model.selectedMode = .curve
        model.daemonResponding = false
        model.daemonReachable = true
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 81.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.manualControlAttentionSummary, "Curve request pending · fan writes blocked")
        XCTAssertEqual(
            model.manualControlAttentionRecoverySuggestion,
            "Vifty will retry Curve when the helper responds. Use Request Auto to stop retries; copy support evidence if repair does not clear it."
        )
        XCTAssertEqual(model.modeSelectionActionTitle, "Request Auto")
        XCTAssertEqual(
            model.modeSelectionActionHelp,
            "Request Auto restore; the write cannot be confirmed until the helper responds"
        )
        XCTAssertTrue(model.modeSelectionActionRestoresAuto)
        XCTAssertFalse(model.modeSelectionActionDisabled)
        XCTAssertFalse(model.manualControlAttentionRecoverySuggestion?.contains("before manual fan control") == true)
    }

    func testManualPendingBlockedPrimaryActionRestoresAutoThroughCoordinator() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 81.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )
        model.selectedMode = .curve
        model.daemonResponding = false
        model.daemonReachable = true
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.snapshot = snapshot

        await model.performModeSelectionActionNow()

        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertNil(model.manualSessionExpiresAt)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [0])
    }

    func testHelperSupportEvidenceContextCapturesHotManualOutageState() {
        let model = AppModel()
        model.selectedMode = .curve
        model.manualRunLimit = .indefinitely
        model.daemonResponding = false
        model.daemonReachable = true
        model.thermalPressure = .nominal
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.lastError = "Daemon request timed out."
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 1780,
                    minimumRPM: 1499,
                    maximumRPM: 4296,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                ),
                Fan(
                    id: 1,
                    name: "Right Fan",
                    currentRPM: 1939,
                    minimumRPM: 1499,
                    maximumRPM: 4744,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                )
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let context = model.helperSupportEvidenceContext

        XCTAssertTrue(context.lines.contains("selectedMode=Curve"))
        XCTAssertTrue(context.lines.contains("manualRun=Until changed"))
        XCTAssertTrue(context.lines.contains("daemon=reachable=true responding=false"))
        XCTAssertTrue(context.lines.contains("helper=Read-only fan telemetry · repair daemon for writes"))
        XCTAssertTrue(context.lines.contains("controlOwner=Read-only fan telemetry; repair helper for fan writes · Vifty will retry Curve when the helper responds"))
        XCTAssertTrue(context.lines.contains("hotFanWrites=High temp · fan writes blocked"))
        XCTAssertTrue(context.lines.contains("selectedTemperature=CPU Efficiency Core 1 91.2 C"))
        XCTAssertTrue(context.lines.contains("fans=Left Fan 1780 RPM (10%); Right Fan 1939 RPM (14%)"))
        XCTAssertTrue(context.lines.contains("lastError=Daemon request timed out."))
    }

    func testVisibleLastErrorSuppressesManualHelperBlockedDuplicate() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.lastError = "Manual fan control blocked: Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked."

        XCTAssertNil(model.visibleLastError)
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
    }

    func testVisibleLastErrorKeepsUnrelatedErrorsDuringHelperOutage() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.lastError = "Failed to save profiles: disk full"

        XCTAssertEqual(model.visibleLastError, "Failed to save profiles: disk full")
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
    }

    func testHelperHealthSummaryReportsNoControllableFansWithoutRepairAction() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: false),
                Fan(id: 1, name: "Right", currentRPM: 2450, minimumRPM: 1400, maximumRPM: 6000, controllable: false)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 63, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan telemetry available · no controllable fans")
        XCTAssertEqual(model.helperHealthState, .noControllableFans(fanCount: 2))
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperRecoverySuggestion, "The helper can read 2 fans, but none are marked controllable. Keep fan writes blocked and collect read-only hardware validation evidence before changing support claims.")
        XCTAssertEqual(model.manualFanControlBlockedReason, "No controllable fans are available. Manual fan control stays blocked.")
    }

    func testManualFanControlAvailabilityRequiresDaemonBackedWritePath() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = false

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")

        model.daemonResponding = true

        XCTAssertTrue(model.manualFanControlAvailable)
        XCTAssertNil(model.manualFanControlBlockedReason)
    }

    func testHelperOutageSuppressesAgentStatusNoiseWhenTelemetryIsReadOnly() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        model.daemonReachable = true
        model.daemonResponding = false
        model.controlState = ControlState(mode: .auto)
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertEqual(model.controlOwnershipSummary, "Read-only fan telemetry; repair helper for fan writes")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertNil(model.agentCoolingMenuSummary)
        XCTAssertNil(model.agentCoolingSummary)
        XCTAssertNil(model.agentCoolingRecoverySuggestion)
        XCTAssertFalse(model.agentCoolingNeedsAttention)
        XCTAssertFalse(model.menuTitle.contains("Agent status unavailable"))
        XCTAssertEqual(model.manualFanControlBlockedReason, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")
    }

    func testManualControlOwnershipPrioritizesBlockedHelperRetryOverAgentStatusNoise() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        model.daemonReachable = true
        model.daemonResponding = false
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(
            model.controlOwnershipSummary,
            "Read-only fan telemetry; repair helper for fan writes · Vifty will retry Curve when the helper responds"
        )
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertFalse(model.controlOwnershipSummary.contains("Agent control status unavailable"))
    }

    func testManualFanControlBlocksWhileAgentLeaseOwnsCooling() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1200) })
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Agent Build cooling owns fan control; restore Auto before manual fan control.")
    }

    func testManualFanControlBlocksWhileAgentRestoreIsPending() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1700) })
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Agent cooling restore is pending; restore Auto before manual fan control.")
    }

    func testManualFanControlBlocksWhenAgentStatusIsUnavailable() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Agent control status is unavailable; repair helper before manual fan control.")
    }

    func testHelperHealthSummaryReportsUnreachableDaemon() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonReachable = false
        model.snapshot = HardwareSnapshot(fans: [], temperatureSensors: [], modelIdentifier: "MacBookPro18,3", isAppleSilicon: true, isMacBookPro: true)

        XCTAssertEqual(model.helperHealthSummary, "Fan helper not responding · repair or approve")
        XCTAssertEqual(model.helperHealthState, .unreachable)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "Install status and daemon response are separate; approve or repair before fan writes.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall Helper or approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds.")
    }

    func testHelperHealthSummaryReportsUnsupportedHardwareWithoutRepairAction() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "Macmini9,1",
            isAppleSilicon: true,
            isMacBookPro: false
        )

        XCTAssertEqual(model.helperHealthSummary, "Unsupported hardware · fan writes blocked")
        XCTAssertEqual(model.helperHealthState, .unsupported)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperRecoverySuggestion, "Vifty supports fan control on Apple Silicon MacBook Pro hardware. Keep this machine on read-only diagnostics; do not retry fan writes.")
        XCTAssertEqual(model.manualFanControlBlockedReason, "Unsupported hardware. Manual fan control stays blocked.")
    }

    func testControlOwnershipSummaryReportsMacOSAutoWhenHardwareIsAutomatic() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "macOS Auto owns fan control")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSummaryReportsBlockedWritesWhenAutoHasNoHelperPath() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonResponding = false
        model.daemonReachable = false
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Auto selected · fan writes blocked until helper responds")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSummaryWarnsWhenAutoSelectedButHardwareIsForced() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 3200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware reports Forced mode while Vifty is Auto · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenAgentStatusIsUnavailable() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.controlOwnershipSummary, "Agent control status unavailable; fan ownership uncertain")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSummaryReportsViftyManualModes() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 3200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.selectedSensorID = "Tp09"

        model.controlState = ControlState(mode: .fixedRPM(3200), manualControlActive: true)
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3200 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        model.controlState = ControlState(mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")), manualControlActive: true)
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Curve owns fan targets · CPU Proximity · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        model.manualSessionExpiresAt = Date(timeIntervalSince1970: 1600)
        XCTAssertTrue(model.controlOwnershipSummary.contains("until "))
        XCTAssertTrue(model.controlOwnershipSummary.hasSuffix("; reasserts if macOS drifts"))
    }

    func testControlOwnershipWarnsWhenManualModeTelemetryShowsMacOSReclaimedAuto() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 84, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")),
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware reports Auto while Vifty manual is selected; Vifty will reassert · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenManualTargetDrifts() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 2200)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .fixedRPM(3600),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware fan target drift detected; Vifty will reassert · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSuppressesSingleSampleManualTargetDriftDuringReassertion() async {
        func snapshot(targetRPM: Int) -> HardwareSnapshot {
            HardwareSnapshot(
                fans: [
                    Fan(
                        id: 0,
                        name: "Left",
                        currentRPM: targetRPM,
                        minimumRPM: 1400,
                        maximumRPM: 6000,
                        controllable: true,
                        hardwareMode: .forced,
                        targetRPM: targetRPM
                    )
                ],
                temperatureSensors: [
                    TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
                ],
                modelIdentifier: "MacBookPro18,3",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        }

        let hardware = AppModelFakeHardware(snapshot: snapshot(targetRPM: 2200))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath()),
                initialState: ControlState(
                    mode: .fixedRPM(3600),
                    lastAppliedRPM: [0: 3600],
                    manualControlActive: true
                )
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.daemonReachable = true
        model.daemonResponding = true

        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware fan target drift detected; Vifty will reassert · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)

        await hardware.setSnapshot(snapshot(targetRPM: 3600))
        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenHotManualResponseCannotBeConfirmed() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .fixedRPM(3600),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Manual fan response not confirmed; current RPM is still below requested target · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenElevatedThermalPressureCannotConfirmManualResponse() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.thermalPressure = .serious
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2100, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Manual fan response not confirmed; current RPM is still below requested target · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipDoesNotWarnForMissingManualTargetWhenRPMIsNearExpected() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 3425, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .fixedRPM(3600),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

    func testMenuTitleIncludesPowerSummaryWhenPowerSnapshotAvailable() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.powerSnapshot = PowerSnapshot(
            percent: 76,
            isPluggedIn: true,
            adapter: PowerAdapter(ratedWatts: 96)
        )

        XCTAssertEqual(model.menuTitle, "65 C | 2400 RPM | 96 W adapter")
    }

    func testMenuTitleShowsHelperAttentionWhenFanTelemetryIsReadOnly() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.daemonReachable = true
        model.daemonResponding = false

        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertEqual(model.menuTitle, "65 C | 2400 RPM | Fan writes blocked")
        XCTAssertEqual(model.menuPanelTitle, "65 C | 2400 RPM | Fan writes blocked")
        model.menuBarDisplayMode = .temperature
        XCTAssertEqual(model.menuBarLabelText, "65 C | Fan writes blocked")
    }

    func testMenuTitleShowsHelperAttentionWhenDaemonIsUnreachable() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonReachable = false
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthState, .unreachable)
        XCTAssertEqual(model.menuTitle, "Vifty | Helper not responding")
        XCTAssertEqual(model.menuPanelTitle, "Vifty | Helper not responding")
    }

    func testMenuPanelTitleOmitsPowerSummaryButKeepsWarnings() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.powerSnapshot = PowerSnapshot(
            percent: 76,
            isPluggedIn: true,
            adapter: PowerAdapter(ratedWatts: 96)
        )
        model.daemonReachable = true
        model.daemonResponding = true
        model.thermalPressure = .serious
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.menuTitle, "65 C | 2400 RPM | 96 W adapter | Thermal: Serious | Agent status unavailable")
        XCTAssertEqual(model.menuPanelTitle, "65 C | 2400 RPM | Thermal: Serious | Agent status unavailable")
    }

    func testMenuTitleFlagsHighSelectedTemperatureWhenThermalPressureIsNominal() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.thermalPressure = .nominal
        model.daemonReachable = true
        model.daemonResponding = true

        XCTAssertEqual(model.temperatureAttentionSummary, "High temp")
        XCTAssertEqual(model.menuTitle, "91 C | 1780 RPM | High temp")
        XCTAssertEqual(model.menuPanelTitle, "91 C | 1780 RPM | High temp")
    }

    func testMenuTitleFlagsFanWritesBlockedWhileHot() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.daemonReachable = true
        model.daemonResponding = false
        model.thermalPressure = .nominal
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertEqual(model.temperatureAttentionSummary, "High temp")
        XCTAssertEqual(model.fanWriteBlockedWhileHotSummary, "High temp · fan writes blocked")
        XCTAssertEqual(model.fanWriteBlockedWhileHotRecoverySuggestion, "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds.")
        XCTAssertEqual(model.menuTitle, "91 C | 1780 RPM | High temp | Fan writes blocked")
        XCTAssertEqual(model.menuPanelTitle, "91 C | 1780 RPM | High temp | Fan writes blocked")
        XCTAssertFalse(model.menuTitle.contains("Agent status unavailable"))
        model.menuBarDisplayMode = .temperatureAndRPM
        XCTAssertEqual(model.menuBarLabelText, "91 C | 1780 RPM | Fan writes blocked")
    }

    func testFanWritesBlockedWhileHotRequiresBlockedHelperWritePath() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 92.0, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.daemonReachable = true
        model.daemonResponding = true

        XCTAssertNil(model.fanWriteBlockedWhileHotSummary)
        XCTAssertNil(model.fanWriteBlockedWhileHotRecoverySuggestion)
        XCTAssertEqual(model.menuTitle, "92 C | 2400 RPM | High temp")
    }

    func testMenuTitleDoesNotDuplicateHighTemperatureWhenThermalPressureIsElevated() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 92.0, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.thermalPressure = .serious
        model.daemonReachable = true
        model.daemonResponding = true

        XCTAssertNil(model.temperatureAttentionSummary)
        XCTAssertEqual(model.menuTitle, "92 C | 2400 RPM | Thermal: Serious")
    }

    func testMenuBarTemperatureModeUsesRoundedHighestTemperatureAsLabelText() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        model.menuBarDisplayMode = .temperature

        XCTAssertEqual(model.menuBarLabelText, "69 C")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarTemperatureUsesSelectedCurveSensorBeforeHighestTemperature() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 61.2, source: .smc),
                TemperatureSensor(id: "TB0T", name: "Battery", celsius: 72.9, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.selectedSensorID = "Tp09"

        model.menuBarDisplayMode = .temperature
        XCTAssertEqual(model.menuBarLabelText, "61 C")

        model.menuBarDisplayMode = .temperatureAndRPM
        XCTAssertEqual(model.menuBarLabelText, "61 C | 1528 RPM")

        XCTAssertEqual(model.menuTitle, "61 C | 1528 RPM")
    }

    func testMenuBarTemperatureAndFanModeUsesTemperatureAndFirstFanRPM() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        model.menuBarDisplayMode = .temperatureAndRPM

        XCTAssertEqual(model.menuBarLabelText, "69 C | 1528 RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarOwnerTemperatureAndFanModeShowsMacMeAndAgentOwners() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1200) })
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        XCTAssertEqual(model.menuBarFanOwnerText, "Mac")
        XCTAssertEqual(model.menuBarLabelText, "Mac | 69 C | 1528 RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)

        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(mode: .fixedRPM(3200), manualControlActive: true)

        XCTAssertEqual(model.menuBarFanOwnerText, "Me")
        XCTAssertEqual(model.menuBarLabelText, "Me | 69 C | 3200 RPM")

        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertEqual(model.menuBarFanOwnerText, "Agent")
        XCTAssertEqual(model.menuBarLabelText, "Agent | 69 C | 3200 RPM")
    }

    func testMenuBarOwnerTemperatureAndFanModeMarksUncertainOwnership() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        XCTAssertEqual(model.menuBarFanOwnerText, "Owner?")
        XCTAssertEqual(model.menuBarLabelText, "Owner? | 69 C | 1528 RPM")
    }

    func testMenuBarFanRPMModeUsesFirstFanRPM() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        model.menuBarDisplayMode = .fanRPM

        XCTAssertEqual(model.menuBarLabelText, "1528 RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarAverageFanRPMModeUsesAllFans() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1623, minimumRPM: 1400, maximumRPM: 6000, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        model.menuBarDisplayMode = .averageFanRPM

        XCTAssertEqual(model.menuBarLabelText, "1576 RPM avg")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarAverageFanRPMModeShowsSelectedModeBeforeFansArrive() {
        let model = AppModel()
        model.menuBarDisplayMode = .averageFanRPM

        XCTAssertEqual(model.menuBarLabelText, "-- RPM avg")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarDisplayModesUseSelectedModePlaceholdersWhenTelemetryIsMissing() {
        let model = AppModel()

        let expectations: [(MenuBarDisplayMode, String)] = [
            (.temperature, "-- C"),
            (.fanRPM, "-- RPM"),
            (.averageFanRPM, "-- RPM avg"),
            (.adapterWattage, "-- W"),
            (.temperatureAndRPM, "-- C | -- RPM"),
            (.ownerTemperatureAndRPM, "Mac | -- C | -- RPM")
        ]

        for (mode, label) in expectations {
            model.menuBarDisplayMode = mode
            XCTAssertEqual(model.menuBarLabelText, label, mode.label)
            XCTAssertNil(model.menuBarStatusItemText, mode.label)
            XCTAssertFalse(model.menuBarLabelUsesFanIcon, mode.label)
        }
    }

    func testStatusItemPresentationSuppressesStartupPlaceholders() {
        XCTAssertNil(ViftyStatusItemPresentation.resolvedText(
            statusItemText: "Mac | -- C | -- RPM",
            labelNeedsTelemetryPrime: false
        ))
        XCTAssertNil(ViftyStatusItemPresentation.resolvedText(
            statusItemText: "Mac | 67 C | 3352 RPM",
            labelNeedsTelemetryPrime: true
        ))
        XCTAssertEqual(
            ViftyStatusItemPresentation.resolvedText(
                statusItemText: "Mac | 67 C | 3352 RPM",
                labelNeedsTelemetryPrime: false
            ),
            "Mac | 67 C | 3352 RPM"
        )
    }

    func testMenuBarStatusItemSuppressesPlaceholderUntilTelemetryPrimeResolves() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: snapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        XCTAssertEqual(model.menuBarLabelText, "Mac | -- C | -- RPM")
        XCTAssertNil(model.menuBarStatusItemText)
        XCTAssertTrue(model.menuBarLabelNeedsTelemetryPrime)

        await model.primeMenuBarStatusItemTelemetry()

        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertEqual(model.menuBarStatusItemText, "Mac | 67 C | 3352 RPM")
        XCTAssertFalse(model.menuBarLabelNeedsTelemetryPrime)
    }

    func testPrimeMenuBarStatusItemTelemetryPopulatesSelectedDisplayBeforeMenuOpens() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: snapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        XCTAssertEqual(model.menuBarLabelText, "Mac | -- C | -- RPM")
        XCTAssertNil(model.menuBarStatusItemText)

        await model.primeMenuBarStatusItemTelemetry()

        XCTAssertTrue(model.hasCompletedHardwarePoll)
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertEqual(model.menuBarStatusItemText, "Mac | 67 C | 3352 RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testStartPublishesMenuBarTelemetryBeforeSlowUncleanExitRecovery() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        await hardware.setRestoreAutoDelayNanoseconds(300_000_000)
        let marker = ManualControlMarker(url: temporaryMarkerPath())
        marker.markActive()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: marker
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        model.start()
        for _ in 0..<50 {
            if await hardware.snapshotReadCount() > 0 {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.menuBarStatusItemText, "Mac | 67 C | 3352 RPM")
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertTrue(model.hasCompletedHardwarePoll)
        await model.stopAndRestore()
    }

    func testPrimeMenuBarStatusItemTelemetryRetriesUntilSelectedDisplayHasData() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        await hardware.failNextSnapshot(ViftyError.smcUnavailable)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        await model.primeMenuBarStatusItemTelemetry(maxAttempts: 2, retryDelay: .milliseconds(1))

        let snapshotReads = await hardware.snapshotReadCount()
        XCTAssertTrue(model.hasCompletedHardwarePoll)
        XCTAssertGreaterThanOrEqual(snapshotReads, 2)
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertFalse(model.menuBarLabelNeedsTelemetryPrime)
    }

    func testFirstResolvedMenuBarTelemetryAdvancesStatusItemRevision() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: snapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        XCTAssertEqual(model.menuBarStatusItemRevision, 0)
        XCTAssertEqual(model.menuBarLabelText, "Mac | -- C | -- RPM")

        await model.pollOnce()

        XCTAssertEqual(model.menuBarStatusItemRevision, 1)
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")

        await model.pollOnce()

        XCTAssertEqual(model.menuBarStatusItemRevision, 1)
    }

    func testOverlappingStartupMenuBarPrimesShareOneHardwarePoll() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3352, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 67.2, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        await hardware.setSnapshotDelayNanoseconds(50_000_000)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await model.pollOnce() }
            group.addTask { await model.pollOnce() }
            await group.waitForAll()
        }

        let snapshotReadCount = await hardware.snapshotReadCount()
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertTrue(model.hasCompletedHardwarePoll)
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
    }

    func testMenuBarCombinedModeKeepsRPMPlaceholderWhenOnlyTemperatureIsAvailable() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        model.menuBarDisplayMode = .temperatureAndRPM

        XCTAssertEqual(model.menuBarLabelText, "69 C | -- RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarAdapterModeUsesPowerSummary() {
        let model = AppModel()
        model.powerSnapshot = PowerSnapshot(
            percent: 76,
            isPluggedIn: true,
            adapter: PowerAdapter(ratedWatts: 140)
        )

        model.menuBarDisplayMode = .adapterWattage

        XCTAssertEqual(model.menuBarLabelText, "140 W adapter")
        XCTAssertEqual(model.menuBarStatusItemText, "140 W adapter")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarCompactSummaryIncludesThermalFanAndPower() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.powerSnapshot = PowerSnapshot(
            percent: 76,
            isPluggedIn: true,
            adapter: PowerAdapter(ratedWatts: 140)
        )

        model.menuBarDisplayMode = .compactSummary

        XCTAssertEqual(model.menuBarLabelText, "69 C | 1528 RPM | 140 W adapter")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarFanIconModeKeepsSummaryAsAccessibilityText() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        model.menuBarDisplayMode = .fanIcon

        XCTAssertEqual(model.menuBarLabelText, "65 C | 2400 RPM")
        XCTAssertTrue(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarDisplayModeMigratesLegacyDefaultAndPersistsPrivately() throws {
        let suiteName = "tech.reidar.vifty.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(MenuBarDisplayMode.temperature.rawValue, forKey: AppModel.menuBarDisplayModeDefaultsKey)
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: preferences)

        let model = AppModel(preferencesStore: store)

        XCTAssertEqual(model.menuBarDisplayMode, .temperature)
        XCTAssertEqual(store.load().menuBarDisplayMode, .temperature)
        XCTAssertEqual(try posixPermissions(at: preferencesURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: preferencesURL), 0o600)

        model.menuBarDisplayMode = .averageFanRPM
        XCTAssertEqual(store.load().menuBarDisplayMode, .averageFanRPM)
        XCTAssertEqual(
            preferences.string(forKey: AppModel.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.temperature.rawValue,
            "New preference writes should go to Vifty's private JSON store, not legacy UserDefaults."
        )
    }

    func testStartupModePreferencePersistsPrivately() throws {
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)
        let model = AppModel(preferencesStore: store)

        XCTAssertEqual(model.startupMode, .auto)

        model.startupMode = .curve

        XCTAssertEqual(store.load().startupMode, .curve)
        XCTAssertEqual(try posixPermissions(at: preferencesURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: preferencesURL), 0o600)

        let relaunched = AppModel(preferencesStore: store)
        XCTAssertEqual(relaunched.startupMode, .curve)
    }

    func testLaunchAtLoginStatusComesFromSystemManagerNotPrivatePreferences() throws {
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)
        let launchAtLoginManager = AppModelLaunchAtLoginRecorder(status: .disabled)
        let model = AppModel(
            preferencesStore: store,
            launchAtLoginManager: launchAtLoginManager
        )

        XCTAssertFalse(model.launchAtLoginEnabled)
        XCTAssertEqual(model.launchAtLoginStatus, .disabled)

        model.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(launchAtLoginManager.requestedValues, [true])
        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertNil(model.launchAtLoginStatusMessage)
        let savedPreferences = FileManager.default.fileExists(atPath: preferencesURL.path)
            ? try String(contentsOf: preferencesURL, encoding: .utf8)
            : ""
        XCTAssertFalse(savedPreferences.contains("launchAtLogin"))
    }

    func testLaunchAtLoginApprovalStateKeepsToggleOnAndOpensLoginItems() {
        let launchAtLoginManager = AppModelLaunchAtLoginRecorder(status: .disabled)
        launchAtLoginManager.statusAfterEnable = .requiresApproval
        let model = AppModel(launchAtLoginManager: launchAtLoginManager)

        model.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(model.launchAtLoginStatus, .requiresApproval)
        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertEqual(model.launchAtLoginStatusMessage, "Approve Vifty in Login Items to start at startup.")
        XCTAssertEqual(launchAtLoginManager.openSettingsCount, 1)
    }

    func testLaunchAtLoginFailureRestoresObservedStatusAndSurfacesError() {
        let launchAtLoginManager = AppModelLaunchAtLoginRecorder(status: .disabled)
        launchAtLoginManager.setError = NSError(
            domain: "LaunchAtLogin",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Registration denied"]
        )
        let model = AppModel(launchAtLoginManager: launchAtLoginManager)

        model.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(launchAtLoginManager.requestedValues, [true])
        XCTAssertEqual(model.launchAtLoginStatus, .disabled)
        XCTAssertFalse(model.launchAtLoginEnabled)
        XCTAssertEqual(model.launchAtLoginStatusMessage, "Could not update startup item: Registration denied")
    }

    func testNotificationSettingsMigrateLegacyDefaultsAndPersistPrivately() throws {
        let suiteName = "tech.reidar.vifty.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(true, forKey: AppModel.notificationHelperFailureDefaultsKey)
        preferences.set(true, forKey: AppModel.notificationThermalPressureDefaultsKey)
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: preferences)

        let model = AppModel(preferencesStore: store)

        XCTAssertTrue(model.notificationSettings.helperFailure)
        XCTAssertTrue(model.notificationSettings.elevatedThermalPressure)
        XCTAssertFalse(model.notificationSettings.autoRestoreFailure)
        XCTAssertFalse(model.notificationSettings.pluggedInBatteryDrain)
        XCTAssertFalse(model.notificationSettings.agentCoolingAttention)
        XCTAssertEqual(store.load().notificationSettings, model.notificationSettings)
        XCTAssertEqual(try posixPermissions(at: preferencesURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: preferencesURL), 0o600)

        model.notificationSettings.autoRestoreFailure = true
        model.notificationSettings.pluggedInBatteryDrain = true
        model.notificationSettings.agentCoolingAttention = true

        XCTAssertTrue(store.load().notificationSettings.autoRestoreFailure)
        XCTAssertTrue(store.load().notificationSettings.pluggedInBatteryDrain)
        XCTAssertTrue(store.load().notificationSettings.agentCoolingAttention)
        XCTAssertFalse(preferences.bool(forKey: AppModel.notificationAutoRestoreDefaultsKey))
        XCTAssertFalse(preferences.bool(forKey: AppModel.notificationPluggedInDrainDefaultsKey))
        XCTAssertFalse(preferences.bool(forKey: AppModel.notificationAgentCoolingAttentionDefaultsKey))
    }

    func testPerFanFixedRPMPreferencePersistsPrivately() throws {
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
        ]
        let model = AppModel(preferencesStore: store)

        model.fixedRPM = 3200
        model.usePerFanFixedRPM = true
        model.ensureFixedFanTargets(for: fans)

        let generatedDefaults = store.load()
        XCTAssertTrue(generatedDefaults.usePerFanFixedRPM)
        XCTAssertEqual(generatedDefaults.fixedFanTargets, [
            FixedFanTarget(fanID: 0, rpm: 3200),
            FixedFanTarget(fanID: 1, rpm: 3472)
        ])

        let relaunchedBeforeSliderEdit = AppModel(preferencesStore: store)
        XCTAssertTrue(relaunchedBeforeSliderEdit.usePerFanFixedRPM)
        XCTAssertEqual(relaunchedBeforeSliderEdit.fixedFanTargets, generatedDefaults.fixedFanTargets)

        model.setFixedFanRPM(4400, for: fans[0])
        model.setFixedFanRPM(4700, for: fans[1])

        let saved = store.load()
        XCTAssertTrue(saved.usePerFanFixedRPM)
        XCTAssertEqual(saved.fixedFanTargets, [
            FixedFanTarget(fanID: 0, rpm: 4296),
            FixedFanTarget(fanID: 1, rpm: 4700)
        ])
        XCTAssertEqual(try posixPermissions(at: preferencesURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: preferencesURL), 0o600)

        let relaunched = AppModel(preferencesStore: store)
        XCTAssertTrue(relaunched.usePerFanFixedRPM)
        XCTAssertEqual(relaunched.fixedFanTargets, saved.fixedFanTargets)
    }

    func testOldAppPreferencesDecodeWithoutPerFanFixedFields() throws {
        let preferencesURL = temporaryPreferencesPath()
        try FileManager.default.createDirectory(
            at: preferencesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyPreferences = """
        {
          "menuBarDisplayMode": "temperature",
          "notificationSettings": {
            "helperFailure": true,
            "elevatedThermalPressure": false,
            "autoRestoreFailure": true,
            "pluggedInBatteryDrain": false,
            "agentCoolingAttention": false
          }
        }
        """
        try legacyPreferences.data(using: .utf8)?.write(to: preferencesURL)
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)

        let loaded = store.load()

        XCTAssertEqual(loaded.menuBarDisplayMode, .temperature)
        XCTAssertEqual(loaded.startupMode, .auto)
        XCTAssertTrue(loaded.notificationSettings.helperFailure)
        XCTAssertTrue(loaded.notificationSettings.autoRestoreFailure)
        XCTAssertFalse(loaded.usePerFanFixedRPM)
        XCTAssertTrue(loaded.fixedFanTargets.isEmpty)
    }

    func testStartupFixedModeAppliesOnceThroughManualPreflight() async throws {
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)
        try store.saveThrowing(AppPreferences(
            menuBarDisplayMode: .fanIcon,
            startupMode: .fixed,
            notificationSettings: .disabled
        ))
        let snapshot = agentHardwareSnapshot()
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil) },
            preferencesStore: store
        )
        model.fixedRPM = 3600

        await model.applyStartupModePreferenceIfNeeded()
        await model.applyStartupModePreferenceIfNeeded()

        XCTAssertEqual(model.selectedMode, .fixed)
        XCTAssertEqual(model.controlState.mode, .fixedRPM(3600))
        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [FanCommand(fanID: 0, mode: .fixedRPM(3600))])
    }

    func testHelperFailureNotificationFiresOnAttentionTransitionWhenEnabled() async throws {
        let recorder = AppModelNotificationRecorder()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFailingHardware(error: ViftyError.helperRejected("Snapshot failed")),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: recorder,
            daemonPing: { false },
            agentStatusReader: { nil }
        )
        model.notificationSettings.helperFailure = true

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.helperFailure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(notification.title, "Vifty fan helper needs attention")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan helper needs attention")
        XCTAssertEqual(
            notification.body,
            "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck."
        )
    }

    func testHelperFailureNotificationUsesHotBlockedFanWritesRecoveryWhenAvailable() async throws {
        let recorder = AppModelNotificationRecorder()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: HardwareSnapshot(
                    fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
                    temperatureSensors: [
                        TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
                    ],
                    modelIdentifier: "MacBookPro18,3",
                    isAppleSilicon: true,
                    isMacBookPro: true
                )),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: recorder,
            daemonPing: { false },
            agentStatusReader: { nil }
        )
        model.notificationSettings.helperFailure = true

        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.helperFailure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(notification.title, "Vifty fan writes are blocked while hot")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan writes are blocked while hot")
        XCTAssertEqual(
            notification.body,
            "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds."
        )
    }

    func testSustainedThermalPressureNotificationWaitsBeforeFiring() async throws {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.elevatedThermalPressure = true

        await model.pollOnce()
        XCTAssertTrue(recorder.delivered.isEmpty)

        clock.now = Date(timeIntervalSince1970: 1061)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertTrue(notification.body.contains("sustained serious thermal pressure"))
    }

    func testSustainedThermalPressureNotificationRespectsCooldown() async {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.elevatedThermalPressure = true

        await model.pollOnce()
        clock.now = Date(timeIntervalSince1970: 1061)
        await model.pollOnce()
        clock.now = Date(timeIntervalSince1970: 1065)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure])

        clock.now = Date(timeIntervalSince1970: 1662)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure, .elevatedThermalPressure])
    }

    func testPluggedInBatteryDrainNotificationFiresOnDrainTransition() async throws {
        let recorder = AppModelNotificationRecorder()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: {
                PowerSnapshot(
                    percent: 50,
                    isPluggedIn: true,
                    batteryPowerWatts: -11.25
                )
            },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.pluggedInBatteryDrain = true

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.pluggedInBatteryDrain])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertTrue(notification.body.contains("11.2 W"))
    }

    func testAutoRestoreFailureNotificationFiresWhenAgentLeaseClearFails() async throws {
        let recorder = AppModelNotificationRecorder()
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            },
            agentRestore: { _ in
                throw ViftyError.helperRejected("Daemon connection invalidated.")
            }
        )
        model.notificationSettings.autoRestoreFailure = true
        model.agentControlStatus = AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)

        await model.restoreAutoNow()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.autoRestoreFailure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertTrue(notification.body.contains("Daemon connection invalidated"))
    }

    func testAgentCoolingAttentionNotificationFiresWhenLeaseNeedsRestore() async throws {
        let recorder = AppModelNotificationRecorder()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let lease = agentLease()
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1700) },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            }
        )
        model.notificationSettings.agentCoolingAttention = true

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.agentCoolingAttention])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(notification.title, "Vifty agent cooling needs attention")
        XCTAssertTrue(notification.body.contains("Use Auto to restore daemon control"))
    }

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
        XCTAssertEqual(model.menuTitle, "64 C | 2500 RPM | 16.9 W drain | Fan writes blocked")
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

    func testPollOnceAppendsTelemetryHistorySample() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let now = Date(timeIntervalSince1970: 1234)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -12.5) },
            thermalReader: { .fair },
            now: { now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertEqual(model.telemetryHistory.samples.count, 1)
        XCTAssertEqual(model.telemetryHistory.samples[0].capturedAt, now)
        XCTAssertEqual(model.telemetryHistory.samples[0].selectedTemperatureID, "Tp09")
        XCTAssertEqual(model.telemetryHistory.samples[0].selectedTemperatureName, "CPU Proximity")
        XCTAssertEqual(model.telemetryHistory.samples[0].selectedTemperatureCelsius, 64)
        XCTAssertFalse(model.telemetryHistory.samples[0].temperatureWasUserSelected)
        XCTAssertEqual(model.telemetryHistory.samples[0].highestTemperatureCelsius, 64)
        XCTAssertEqual(model.telemetryHistory.samples[0].firstFanRPM, 2500)
        XCTAssertEqual(model.telemetryHistory.samples[0].averageFanRPM, 2500)
        XCTAssertEqual(model.telemetryHistory.samples[0].batteryPowerWatts, -12.5)
        XCTAssertEqual(model.telemetryHistory.samples[0].thermalPressure, .fair)
    }

    func testProgrammaticDefaultSensorDoesNotMarkTelemetryAsUserSelected() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -12.5) },
            thermalReader: { .fair },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(model.selectedSensorID, "Tp09")
        XCTAssertEqual(model.telemetryHistory.samples.count, 2)
        XCTAssertFalse(model.telemetryHistory.samples[0].temperatureWasUserSelected)
        XCTAssertFalse(model.telemetryHistory.samples[1].temperatureWasUserSelected)
        XCTAssertEqual(TelemetryHistorySummary(history: model.telemetryHistory).latestTemperatureLabel, "CPU temp")
    }

    func testPollOnceAppendsSelectedSensorAndAverageFanTelemetryHistorySample() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2200, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 2800, minimumRPM: 1400, maximumRPM: 6000, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Performance Core 1", celsius: 73, source: .smc),
                TemperatureSensor(id: "Tp01", name: "CPU Efficiency Core 1", celsius: 66, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -8.0) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.selectedSensorID = "Tp01"

        await model.pollOnce()

        let sample = model.telemetryHistory.samples[0]
        XCTAssertEqual(sample.selectedTemperatureID, "Tp01")
        XCTAssertEqual(sample.selectedTemperatureName, "CPU Efficiency Core 1")
        XCTAssertEqual(sample.selectedTemperatureCelsius, 66)
        XCTAssertTrue(sample.temperatureWasUserSelected)
        XCTAssertEqual(sample.highestTemperatureCelsius, 73)
        XCTAssertEqual(sample.firstFanRPM, 2200)
        XCTAssertEqual(sample.averageFanRPM, 2500)
    }

    func testRecentTelemetryTrendSummaryRequiresAtLeastTwoSamples() {
        let model = AppModel()

        XCTAssertNil(model.recentTelemetryTrendSummary)

        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 70.0,
            firstFanRPM: 2_000,
            batteryPowerWatts: -4.0,
            thermalPressure: .nominal
        ))

        XCTAssertNil(model.recentTelemetryTrendSummary)
    }

    func testRecentTelemetryTrendSummaryFormatsCompactDeltasAndPeakThermalPressure() {
        let model = AppModel()
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 70.0,
            firstFanRPM: 2_000,
            averageFanRPM: 2_100,
            batteryPowerWatts: -4.0,
            thermalPressure: .nominal
        ))
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: 74.2,
            firstFanRPM: 2_250,
            averageFanRPM: 2_350,
            batteryPowerWatts: -7.1,
            thermalPressure: .serious
        ))

        XCTAssertEqual(
            model.recentTelemetryTrendSummary,
            "Temp +4.2 C · Avg fan +250 RPM · Power -3.1 W · Peak Serious"
        )
    }

    func testRecentTelemetryTrendSummaryOmitsMissingMetricsAndStableNominalThermalPressure() {
        let model = AppModel()
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: nil,
            firstFanRPM: nil,
            batteryPowerWatts: nil,
            thermalPressure: .nominal
        ))
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: nil,
            firstFanRPM: nil,
            batteryPowerWatts: nil,
            thermalPressure: .nominal
        ))

        XCTAssertNil(model.recentTelemetryTrendSummary)
    }

    func testMenuTitleIncludesElevatedThermalPressure() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 74, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertEqual(model.thermalPressure, .serious)
        XCTAssertTrue(model.menuTitle.contains("Thermal: Serious"))
    }

    func testTimedManualModeRestoresAutoAfterDeadline() async {
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
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0], "Timed expiry must issue a real Auto restore, not only update UI state")
    }

    func testChangingActiveTimedManualRunToUntilChangedClearsOldDeadline() async {
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

    func testChangingActiveUntilChangedManualRunToTimedCreatesFreshDeadline() async {
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

        await model.stopAndRestore()

        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertNil(model.manualSessionExpiresAt)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0], "Stop must wait for a real Auto restore before callers terminate the app.")
    }

    func testStopAndRestoreReportsAgentLeaseClearFailure() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            },
            agentRestore: { _ in
                throw ViftyError.helperRejected("Daemon connection invalidated.")
            }
        )
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)

        await model.stopAndRestore()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertTrue(model.lastError?.contains("Failed to clear agent cooling lease") == true)
        XCTAssertTrue(model.lastError?.contains("Daemon connection invalidated") == true)
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

        XCTAssertEqual(model.selectedMode, .auto)
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

        XCTAssertEqual(model.targetRPMPreview(for: snapshot.fans[0]), 3200)

        await model.applyCurrentModeSelection()

        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [
            FanCommand(fanID: 0, mode: .fixedRPM(3200))
        ])
        XCTAssertEqual(model.controlState.lastAppliedRPM, [0: 3200])
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3200 RPM · until changed; reasserts if macOS drifts")
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

        XCTAssertEqual(model.selectedMode, .auto)
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

        XCTAssertEqual(model.selectedMode, .auto)
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

        XCTAssertEqual(model.selectedMode, .auto)
        XCTAssertNil(model.manualSessionExpiresAt)
        XCTAssertTrue(model.lastError?.contains("Manual fan control blocked") == true)
        XCTAssertTrue(model.lastError?.contains("Agent control status is unavailable") == true)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
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
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: {
                await recorder.status()
            },
            agentRestore: { reason in
                await recorder.restore(reason: reason)
            }
        )

        await model.pollOnce()
        await model.restoreAutoNow()

        let reasons = await recorder.reasons
        XCTAssertEqual(reasons, ["User selected Auto in Vifty"])
        XCTAssertNil(model.agentControlStatus?.activeLease)
    }

    func testRestoreAutoReportsAgentLeaseClearFailure() async {
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            },
            agentRestore: { _ in
                throw ViftyError.helperRejected("Daemon connection invalidated.")
            }
        )

        await model.pollOnce()
        await model.restoreAutoNow()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertEqual(model.agentControlStatus?.activeLease?.id, "lease-1")
        XCTAssertTrue(model.lastError?.contains("Failed to clear agent cooling lease") == true)
        XCTAssertTrue(model.lastError?.contains("Daemon connection invalidated") == true)
    }

    private func agentLease(
        expiresAt: Date = Date(timeIntervalSince1970: 1600),
        targetRPMByFanID: [Int: Int] = [0: 3600]
    ) -> AgentCoolingLease {
        AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(
                workload: .build,
                durationSeconds: 600,
                maxRPMPercent: 75,
                reason: "Build",
                idempotencyKey: "key"
            ),
            createdAt: Date(timeIntervalSince1970: 1000),
            expiresAt: expiresAt,
            targetRPMByFanID: targetRPMByFanID
        )
    }

    private func agentHardwareSnapshot(hardwareMode: FanHardwareMode? = nil) -> HardwareSnapshot {
        HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: hardwareMode)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
    }

    private func temporaryMarkerPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-app-model-tests")
            .appendingPathComponent(UUID().uuidString)
    }

    private func temporaryPreferencesPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-app-preferences-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-preferences.json")
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private final class AppModelTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        self.value = now
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

private final class AppModelPingSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool]

    init(values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return false }
        return values.removeFirst()
    }
}

@MainActor
private final class AppModelLaunchAtLoginRecorder: LaunchAtLoginManaging {
    private(set) var requestedValues: [Bool] = []
    private(set) var openSettingsCount = 0
    var status: LaunchAtLoginStatus
    var statusAfterEnable: LaunchAtLoginStatus = .enabled
    var statusAfterDisable: LaunchAtLoginStatus = .disabled
    var setError: Error?

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let setError {
            throw setError
        }
        status = enabled ? statusAfterEnable : statusAfterDisable
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

private actor AppModelFakeHardware: HardwareService {
    var snapshotValue: HardwareSnapshot
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []
    private var snapshotFailures: [Error] = []
    private var applyFailures: [Error] = []
    private var snapshotDelayNanoseconds: UInt64?
    private var restoreAutoDelayNanoseconds: UInt64?
    private var snapshotReads = 0

    init(snapshot: HardwareSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotReads += 1
        if !snapshotFailures.isEmpty {
            throw snapshotFailures.removeFirst()
        }
        if let snapshotDelayNanoseconds {
            try? await Task.sleep(nanoseconds: snapshotDelayNanoseconds)
        }
        return snapshotValue
    }

    func setSnapshot(_ snapshot: HardwareSnapshot) {
        snapshotValue = snapshot
    }

    func setSnapshotDelayNanoseconds(_ nanoseconds: UInt64?) {
        snapshotDelayNanoseconds = nanoseconds
    }

    func setRestoreAutoDelayNanoseconds(_ nanoseconds: UInt64?) {
        restoreAutoDelayNanoseconds = nanoseconds
    }

    func snapshotReadCount() -> Int {
        snapshotReads
    }

    func failNextSnapshot(_ error: Error) {
        snapshotFailures.append(error)
    }

    func failNextApply(_ error: Error) {
        applyFailures.append(error)
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        if !applyFailures.isEmpty {
            throw applyFailures.removeFirst()
        }
        appliedCommands.append(command)
    }

    func restoreAuto(fan: Fan) async throws {
        if let restoreAutoDelayNanoseconds {
            try? await Task.sleep(nanoseconds: restoreAutoDelayNanoseconds)
        }
        restoredFanIDs.append(fan.id)
    }
}

private actor AppModelFailingHardware: HardwareService {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func snapshot() async throws -> HardwareSnapshot {
        throw error
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        throw error
    }

    func restoreAuto(fan: Fan) async throws {
        throw error
    }
}

private actor AgentRestoreRecorder {
    var reasons: [String] = []
    private var currentStatus: AgentControlStatus

    init(activeLease: AgentCoolingLease? = nil) {
        self.currentStatus = AgentControlStatus(enabled: true, activeLease: activeLease, lastDecision: nil, lastErrorCode: nil)
    }

    func status() -> AgentControlStatus? {
        currentStatus
    }

    func restore(reason: String) -> AgentControlStatus? {
        reasons.append(reason)
        currentStatus = AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)
        return currentStatus
    }
}

private actor AgentStatusSequence {
    private var results: [Result<AgentControlStatus?, Error>]

    init(results: [Result<AgentControlStatus?, Error>]) {
        self.results = results
    }

    func next() throws -> AgentControlStatus? {
        guard !results.isEmpty else { return nil }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class AppModelNotificationRecorder: LocalNotificationDelivering {
    private(set) var delivered: [LocalNotification] = []

    func deliver(_ notification: LocalNotification) async {
        delivered.append(notification)
    }
}
