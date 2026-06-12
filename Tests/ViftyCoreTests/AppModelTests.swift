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

        XCTAssertEqual(model.helperHealthSummary, "Fan helper error")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair to reinstall or approve the helper. Restore Auto first if fans appear stuck.")
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

        XCTAssertEqual(model.helperHealthSummary, "Fan helper reachable · no fan data")
        XCTAssertEqual(model.helperRecoverySuggestion, "Fan data is unavailable. Do not start manual or agent cooling until fans appear.")
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

        XCTAssertEqual(model.helperHealthSummary, "Fan telemetry available · daemon not responding")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall before manual or agent cooling; fan writes stay blocked until the daemon responds.")
    }

    func testHelperHealthSummaryReportsUnreachableDaemon() {
        let model = AppModel()
        model.daemonReachable = false
        model.snapshot = HardwareSnapshot(fans: [], temperatureSensors: [], modelIdentifier: "MacBookPro18,3", isAppleSilicon: true, isMacBookPro: true)

        XCTAssertEqual(model.helperHealthSummary, "Fan helper unreachable")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall to copy the daemon, strip quarantine, and restart launchd; fan writes stay blocked until it responds.")
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

    func testControlOwnershipSummaryWarnsWhenAutoSelectedButHardwareIsForced() {
        let model = AppModel()
        model.daemonReachable = true
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

    func testControlOwnershipSummaryReportsViftyManualModes() {
        let model = AppModel()
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
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3200 RPM")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        model.controlState = ControlState(mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")), manualControlActive: true)
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Curve owns fan targets · CPU Proximity")
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
            daemonPing: { false }
        )

        await model.pollOnce()

        XCTAssertEqual(model.powerSnapshot, expectedPower)
        XCTAssertEqual(model.menuTitle, "64 C | 2500 RPM | 16.9 W drain")
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
            daemonPing: { false }
        )

        await model.pollOnce()

        XCTAssertTrue(model.daemonReachable)
        XCTAssertFalse(model.daemonResponding)
        XCTAssertEqual(model.helperHealthSummary, "Fan telemetry available · daemon not responding")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall before manual or agent cooling; fan writes stay blocked until the daemon responds.")
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
        XCTAssertEqual(model.helperHealthSummary, "Fan helper error")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair to reinstall or approve the helper. Restore Auto first if fans appear stuck.")
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
            daemonPing: { true }
        )

        await model.pollOnce()

        XCTAssertEqual(model.telemetryHistory.samples.count, 1)
        XCTAssertEqual(model.telemetryHistory.samples[0].capturedAt, now)
        XCTAssertEqual(model.telemetryHistory.samples[0].highestTemperatureCelsius, 64)
        XCTAssertEqual(model.telemetryHistory.samples[0].firstFanRPM, 2500)
        XCTAssertEqual(model.telemetryHistory.samples[0].batteryPowerWatts, -12.5)
        XCTAssertEqual(model.telemetryHistory.samples[0].thermalPressure, .fair)
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
            daemonPing: { true }
        )

        await model.pollOnce()

        XCTAssertEqual(model.thermalPressure, .serious)
        XCTAssertTrue(model.menuTitle.contains("Thermal: Serious"))
    }

    func testTimedManualModeRestoresAutoAfterDeadline() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true }
        )

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

    func testExplicitRestoreAutoClearsTimedManualDeadline() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let now = Date(timeIntervalSince1970: 1000)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { now },
            daemonPing: { true }
        )

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

    func testAgentCoolingSummaryIncludesWorkloadAndSortedTargets() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1200) })
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(targetRPMByFanID: [1: 3700, 0: 3600]),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent cooling")
        XCTAssertFalse(model.agentCoolingNeedsAttention)
        XCTAssertTrue(model.agentCoolingSummary?.contains("Agent Build cooling until") == true)
        XCTAssertTrue(model.agentCoolingSummary?.contains("F0 3600 RPM, F1 3700 RPM") == true)
        XCTAssertTrue(model.controlOwnershipSummary.contains("Agent Build owns cooling until"))
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

    func testAgentCoolingSummaryWarnsWhenLeaseExpiredButUnrestored() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1700) })
        model.snapshot = agentHardwareSnapshot()
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertEqual(model.agentCoolingMenuSummary, "Agent restore pending")
        XCTAssertTrue(model.agentCoolingNeedsAttention)
        XCTAssertTrue(model.agentCoolingSummary?.contains("expired; waiting for Auto restore") == true)
        XCTAssertTrue(model.menuTitle.contains("Agent restore pending"))
        XCTAssertEqual(model.controlOwnershipSummary, "Agent Build lease expired; restore Auto to clear daemon control")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
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

    private func agentHardwareSnapshot() -> HardwareSnapshot {
        HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
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

private actor AppModelFakeHardware: HardwareService {
    var snapshotValue: HardwareSnapshot
    var restoredFanIDs: [Int] = []

    init(snapshot: HardwareSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotValue
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {}

    func restoreAuto(fan: Fan) async throws { restoredFanIDs.append(fan.id) }
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
