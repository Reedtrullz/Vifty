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

    func testHelperHealthSummaryReportsCheckingBeforeFirstHardwarePoll() {
        let model = AppModel()

        XCTAssertEqual(model.helperHealthSummary, "Checking fan helper")
        XCTAssertEqual(model.helperHealthState, .checking)
        XCTAssertFalse(model.helperHealthNeedsAttention)
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
        XCTAssertEqual(model.helperHealthState, .error)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck.")
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
        XCTAssertEqual(model.helperHealthState, .noFanData)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Fan data is unavailable. Fan writes stay blocked until controllable fans appear.")
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
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Repair/Reinstall Helper, approve Login Items if prompted, then retry manual or agent cooling only after the daemon responds; fallback telemetry is read-only.")
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

        XCTAssertEqual(model.helperHealthSummary, "Fan helper unreachable")
        XCTAssertEqual(model.helperHealthState, .unreachable)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Repair/Reinstall Helper copies the daemon, strips quarantine, restarts launchd, and may require Login Items approval. Fan writes stay blocked until the daemon responds.")
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
        model.thermalPressure = .serious
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.menuTitle, "65 C | 2400 RPM | 96 W adapter | Thermal: Serious | Agent status unavailable")
        XCTAssertEqual(model.menuPanelTitle, "65 C | 2400 RPM | Thermal: Serious | Agent status unavailable")
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

    func testMenuBarDisplayModeLoadsAndPersistsPreference() {
        let suiteName = "tech.reidar.vifty.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(MenuBarDisplayMode.temperature.rawValue, forKey: AppModel.menuBarDisplayModeDefaultsKey)

        let model = AppModel(preferences: preferences)

        XCTAssertEqual(model.menuBarDisplayMode, .temperature)
        model.menuBarDisplayMode = .temperatureAndRPM
        XCTAssertEqual(preferences.string(forKey: AppModel.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.temperatureAndRPM.rawValue)
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
            daemonPing: { false },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertTrue(model.daemonReachable)
        XCTAssertFalse(model.daemonResponding)
        XCTAssertEqual(model.helperHealthSummary, "Fan telemetry available · daemon not responding")
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Repair/Reinstall Helper, approve Login Items if prompted, then retry manual or agent cooling only after the daemon responds; fallback telemetry is read-only.")
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
        XCTAssertEqual(model.helperHealthSummary, "Fan helper error")
        XCTAssertEqual(model.helperHealthState, .error)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertEqual(model.helperRecoverySuggestion, "Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck.")
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
        XCTAssertTrue(model.menuTitle.contains("Agent status unavailable"))
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
