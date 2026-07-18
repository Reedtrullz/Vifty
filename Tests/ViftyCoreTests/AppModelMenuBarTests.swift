import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelMenuBarTests: XCTestCase {
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

        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Proximity 65 C | 2400 RPM | 96 W adapter")
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
        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Proximity 65 C | 2400 RPM | Fan writes blocked")
        XCTAssertEqual(model.menuPanelTitle, "Automatic CPU · CPU Proximity 65 C | 2400 RPM | Fan writes blocked")
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

        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Proximity 65 C | 2400 RPM | 96 W adapter | Thermal: Serious | Agent status unavailable")
        XCTAssertEqual(model.menuPanelTitle, "Automatic CPU · CPU Proximity 65 C | 2400 RPM | Thermal: Serious | Agent status unavailable")
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
        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Efficiency Core 1 91 C | 1780 RPM | High temp")
        XCTAssertEqual(model.menuPanelTitle, "Automatic CPU · CPU Efficiency Core 1 91 C | 1780 RPM | High temp")
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
        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Efficiency Core 1 91 C | 1780 RPM | High temp | Fan writes blocked")
        XCTAssertEqual(model.menuPanelTitle, "Automatic CPU · CPU Efficiency Core 1 91 C | 1780 RPM | High temp | Fan writes blocked")
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
        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Proximity 92 C | 2400 RPM | High temp")
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
        XCTAssertEqual(model.menuTitle, "Automatic CPU · CPU Proximity 92 C | 2400 RPM | Thermal: Serious")
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

        XCTAssertEqual(model.menuTitle, "Curve sensor · CPU Efficiency Core 1 61 C | 1528 RPM")
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

    func testMenuBarOwnerTemperatureAndFanModeUsesAuthoritativeDaemonOwnership() async {
        let initialSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: initialSnapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1200) },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.daemonReachable = true
        model.daemonResponding = true
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        XCTAssertEqual(model.menuBarFanOwnerText, "Owner?")
        await model.pollOnce()
        XCTAssertEqual(model.menuBarFanOwnerText, "Mac")
        XCTAssertEqual(model.menuBarLabelText, "Mac | 69 C | 1528 RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)

        await hardware.setSnapshot(HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 3200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-session"),
            phase: .active,
            transactionID: "manual-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        ))
        await model.pollOnce()

        XCTAssertEqual(model.menuBarFanOwnerText, "Me")
        XCTAssertEqual(model.menuBarLabelText, "Me | 69 C | 3200 RPM")

        await hardware.setFanControlOwnershipStatus(FanControlOwnershipStatus(
            owner: .agent(leaseID: "lease-1"),
            phase: .active,
            transactionID: "agent-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        ))
        await model.pollOnce()

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

    func testMenuBarCodexUsageModeUsesLocalCodexUsageSnapshot() async {
        let usageSnapshot = CodexUsageSnapshot(
            usedPercent: 42.4,
            resetDate: Date(timeIntervalSince1970: 1_800_003_600),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            planType: "pro",
            creditsSummary: "Credits: 10.00",
            sourceFileName: "session.jsonl"
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: { usageSnapshot },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.menuBarDisplayMode = .codexUsage
        await model.pollOnce()
        await waitForCodexUsageSnapshot(model)

        XCTAssertEqual(model.menuBarLabelText, "Ai 58% left · 1h")
        XCTAssertEqual(model.menuBarStatusItemText, "Ai 58% left · 1h")
        XCTAssertEqual(model.codexUsageSummary, "Codex: 58% left, 42% used · resets in 1:00:00")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testMenuBarCustomModeCombinesSelectedTemperatureFanStrengthAndCodexUsage() async {
        let usageSnapshot = CodexUsageSnapshot(
            usedPercent: 22.6,
            resetDate: Date(timeIntervalSince1970: 1_800_016_980),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            planType: "pro"
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 68.6, source: .smc),
                TemperatureSensor(id: "TB0T", name: "Battery", celsius: 73.1, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: { usageSnapshot },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.selectedSensorID = "Tp09"
        model.menuBarDisplayMode = .custom

        await model.pollOnce()
        await waitForCodexUsageSnapshot(model)

        XCTAssertEqual(model.menuBarCustomFields, [.temperature, .fanStrength, .codexUsage])
        XCTAssertTrue(model.menuBarDisplaysCodexUsage)
        XCTAssertEqual(model.menuBarLabelText, "69 C | 3% fan | Ai 77% left · 4h 43m")
        XCTAssertEqual(model.menuBarStatusItemText, "69 C | 3% fan | Ai 77% left · 4h 43m")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
    }

    func testCodexUsageDisplayPreferencesAffectMenuBarAndPersist() async throws {
        let resetDate = Date(timeIntervalSince1970: 1_800_003_600)
        let usageSnapshot = CodexUsageSnapshot(
            usedPercent: 42.4,
            resetDate: resetDate,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            planType: "pro",
            creditsSummary: "Credits: 10.00",
            sourceFileName: "session.jsonl"
        )
        let store = AppPreferencesStore(url: temporaryPreferencesPath(), legacyDefaults: nil)
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: { usageSnapshot },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            daemonPing: { true },
            agentStatusReader: { nil },
            preferencesStore: store
        )

        model.menuBarDisplayMode = .codexUsage
        model.codexUsageDisplayStyle = .battery
        model.codexUsageMetricMode = .percentUsed
        model.codexUsageResetMode = .resetTime
        model.codexUsageRefreshCadence = .thirtySeconds
        await model.pollOnce()
        await waitForCodexUsageSnapshot(model)

        let resetTime = DateFormatter.localizedString(from: resetDate, dateStyle: .none, timeStyle: .short)
        XCTAssertEqual(model.menuBarLabelText, "Ai [##---] 42% used · \(resetTime)")
        XCTAssertEqual(model.codexUsageSummary, "Codex: 42% used, 58% left · resets at \(resetTime)")

        let relaunched = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            codexUsageReader: { usageSnapshot },
            preferencesStore: store
        )
        XCTAssertEqual(relaunched.menuBarDisplayMode, .codexUsage)
        XCTAssertEqual(relaunched.codexUsageDisplayStyle, .battery)
        XCTAssertEqual(relaunched.codexUsageMetricMode, .percentUsed)
        XCTAssertEqual(relaunched.codexUsageResetMode, .resetTime)
        XCTAssertEqual(relaunched.codexUsageRefreshCadence, .thirtySeconds)
    }

    func testCodexUsageReaderOnlyRunsForSelectedMenuModeAndIsThrottled() async {
        let recorder = CodexUsageReadRecorder(now: Date(timeIntervalSince1970: 1_800_000_000))
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            codexUsageRefreshInterval: 300,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.menuBarDisplayMode = .temperature
        await model.pollOnce()
        XCTAssertEqual(recorder.readCount, 0)

        model.menuBarDisplayMode = .custom
        model.menuBarCustomFields = [.temperature, .fanRPM]
        await model.pollOnce()
        XCTAssertEqual(recorder.readCount, 0)

        model.setMenuBarCustomField(.codexUsage, enabled: true)
        await model.pollOnce()
        await waitForCodexUsageReadCount(1, recorder: recorder)
        XCTAssertEqual(model.menuBarLabelText, "69 C | 1528 RPM | Ai 75% left")

        model.menuBarDisplayMode = .codexUsage
        await model.pollOnce()
        XCTAssertEqual(recorder.readCount, 1)
        XCTAssertEqual(model.menuBarLabelText, "Ai 75% left")

        recorder.advance(by: 120)
        await model.pollOnce()
        XCTAssertEqual(recorder.readCount, 1)

        recorder.advance(by: 181)
        await model.pollOnce()
        await waitForCodexUsageReadCount(2, recorder: recorder)
        XCTAssertEqual(recorder.readCount, 2)
    }

    func testCodexUsageClearsWhenMenuBarNoLongerDisplaysCodex() async {
        let recorder = CodexUsageReadRecorder(now: Date(timeIntervalSince1970: 1_800_000_000))
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .codexUsage

        await model.pollOnce()
        await waitForCodexUsageSnapshot(model)
        XCTAssertEqual(model.menuBarLabelText, "Ai 75% left")

        model.menuBarDisplayMode = .temperature

        XCTAssertNil(model.codexUsageSnapshot)
        XCTAssertFalse(model.menuBarDisplaysCodexUsage)
        XCTAssertEqual(model.menuBarLabelText, "69 C")
    }

    func testInFlightCodexUsageRefreshIsIgnoredAfterDisplayIsDisabled() async {
        let readGate = CodexUsageReadGate()
        let recorder = CodexUsageReadRecorder(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            gate: readGate
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .codexUsage

        await model.pollOnce()
        await readGate.waitUntilEntered()
        model.menuBarDisplayMode = .temperature
        readGate.open()
        await waitForCodexUsageReadCount(1, recorder: recorder)
        await Task.yield()

        XCTAssertNil(model.codexUsageSnapshot)
        XCTAssertEqual(model.menuBarLabelText, "69 C")
    }

    func testMenuBarCustomCodexPlaceholderCanShowAfterHardwarePrime() async {
        let readGate = CodexUsageReadGate()
        let recorder = CodexUsageReadRecorder(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            gate: readGate
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            codexUsageRefreshInterval: 300,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.menuBarDisplayMode = .custom
        await model.pollOnce()

        XCTAssertNil(model.codexUsageSnapshot)
        XCTAssertEqual(model.menuBarLabelText, "69 C | 3% fan | Ai --")
        XCTAssertEqual(model.menuBarStatusItemText, "69 C | 3% fan | Ai --")
        XCTAssertFalse(model.menuBarLabelNeedsTelemetryPrime)

        await readGate.waitUntilEntered()
        readGate.open()
        await waitForCodexUsageSnapshot(model)

        XCTAssertEqual(model.menuBarLabelText, "69 C | 3% fan | Ai 75% left")
        XCTAssertEqual(model.menuBarStatusItemText, "69 C | 3% fan | Ai 75% left")
    }

    func testCodexUsageRefreshCadenceCanBeReducedForLiveTopBarTracking() async {
        let recorder = CodexUsageReadRecorder(now: Date(timeIntervalSince1970: 1_800_000_000))
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .codexUsage
        model.codexUsageRefreshCadence = .thirtySeconds

        await model.pollOnce()
        await waitForCodexUsageReadCount(1, recorder: recorder)

        recorder.advance(by: 29)
        await model.pollOnce()
        XCTAssertEqual(recorder.readCount, 1)

        recorder.advance(by: 2)
        await model.pollOnce()
        await waitForCodexUsageReadCount(2, recorder: recorder)
    }

    func testCodexUsageRefreshDoesNotBlockHardwarePoll() async {
        let readGate = CodexUsageReadGate()
        let recorder = CodexUsageReadRecorder(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            gate: readGate
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            codexUsageRefreshInterval: 300,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.menuBarDisplayMode = .codexUsage
        await model.pollOnce()

        XCTAssertNil(model.codexUsageSnapshot)
        XCTAssertEqual(model.menuBarLabelText, "Ai --")

        await readGate.waitUntilEntered()
        readGate.open()
        await waitForCodexUsageSnapshot(model)

        XCTAssertEqual(recorder.readCount, 1)
        XCTAssertEqual(model.menuBarLabelText, "Ai 75% left")
        XCTAssertEqual(model.menuBarStatusItemText, "Ai 75% left")
        XCTAssertEqual(model.menuBarStatusItemPresentation.content, .text("Ai 75% left"))
    }

    func testCodexUsageModeShowsStatusItemPlaceholderAfterPrimeWhileRefreshIsPending() async {
        let readGate = CodexUsageReadGate()
        let recorder = CodexUsageReadRecorder(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            gate: readGate
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.menuBarDisplayMode = .codexUsage
        await model.primeMenuBarStatusItemTelemetry(maxAttempts: 1)

        XCTAssertNil(model.codexUsageSnapshot)
        XCTAssertEqual(model.menuBarLabelText, "Ai --")
        XCTAssertEqual(model.menuBarStatusItemText, "Ai --")
        XCTAssertFalse(model.menuBarLabelNeedsTelemetryPrime)
        await readGate.waitUntilEntered()
        readGate.open()
        await model.waitForCodexUsageRefresh()
    }

    func testCancelledCodexUsageRefreshDoesNotPublishStaleSnapshot() async {
        let readGate = CodexUsageReadGate()
        let recorder = CodexUsageReadRecorder(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            gate: readGate
        )
        let hardwareSnapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1528, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68.6, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: hardwareSnapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            codexUsageReader: recorder.read,
            codexUsageRefreshInterval: 300,
            now: recorder.currentTime,
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        model.menuBarDisplayMode = .codexUsage
        await model.pollOnce()
        XCTAssertNil(model.codexUsageSnapshot)

        await readGate.waitUntilEntered()
        _ = await model.stopAndRestore()
        readGate.open()
        await waitForCodexUsageReadCount(1, recorder: recorder)
        await Task.yield()

        XCTAssertNil(model.codexUsageSnapshot)
        XCTAssertEqual(model.menuBarLabelText, "Ai --")
    }

    func testMenuBarDisplayModesUseSelectedModePlaceholdersWhenTelemetryIsMissing() {
        let model = AppModel()

        let expectations: [(MenuBarDisplayMode, String)] = [
            (.temperature, "-- C"),
            (.fanRPM, "-- RPM"),
            (.averageFanRPM, "-- RPM avg"),
            (.adapterWattage, "-- W"),
            (.codexUsage, "Ai --"),
            (.custom, "-- C | --% fan | Ai --"),
            (.temperatureAndRPM, "-- C | -- RPM"),
            (.ownerTemperatureAndRPM, "Owner? | -- C | -- RPM")
        ]

        for (mode, label) in expectations {
            model.menuBarDisplayMode = mode
            XCTAssertEqual(model.menuBarLabelText, label, mode.label)
            XCTAssertNil(model.menuBarStatusItemText, mode.label)
            XCTAssertFalse(model.menuBarLabelUsesFanIcon, mode.label)
        }
    }

    func testExtractedMenuBarPresentationTypesPreserveDefaults() {
        XCTAssertEqual(MenuBarField.defaultCustomFields, [.temperature, .fanStrength, .codexUsage])
        XCTAssertEqual(MenuBarStatusItemPresentation.placeholder.tooltip, "Vifty")
        XCTAssertTrue(MenuBarStatusItemPresentation.placeholder.needsTelemetryPrime)
    }

    func testStatusItemPresentationSuppressesStartupPlaceholders() {
        XCTAssertNil(ViftyStatusItemPresentation.resolvedText(
            statusItemText: "Mac | -- C | -- RPM",
            fallbackStatusItemText: nil,
            labelNeedsTelemetryPrime: false,
            allowsPlaceholderText: false
        ))
        XCTAssertNil(ViftyStatusItemPresentation.resolvedText(
            statusItemText: "Mac | 67 C | 3352 RPM",
            fallbackStatusItemText: nil,
            labelNeedsTelemetryPrime: true,
            allowsPlaceholderText: false
        ))
        XCTAssertEqual(
            ViftyStatusItemPresentation.resolvedText(
                statusItemText: "Mac | 67 C | 3352 RPM",
                fallbackStatusItemText: nil,
                labelNeedsTelemetryPrime: false,
                allowsPlaceholderText: false
            ),
            "Mac | 67 C | 3352 RPM"
        )
        XCTAssertEqual(
            ViftyStatusItemPresentation.resolvedText(
                statusItemText: "Ai --",
                fallbackStatusItemText: nil,
                labelNeedsTelemetryPrime: false,
                allowsPlaceholderText: true
            ),
            "Ai --"
        )
    }

    func testStatusItemPresentationUsesFallbackWhenPlaceholderIsHidden() {
        XCTAssertEqual(
            ViftyStatusItemPresentation.resolvedText(
                statusItemText: "Mac | -- C | -- RPM",
                fallbackStatusItemText: "Mac | -- C | -- RPM",
                labelNeedsTelemetryPrime: false,
                allowsPlaceholderText: false
            ),
            "Mac | -- C | -- RPM"
        )
        XCTAssertEqual(
            ViftyStatusItemPresentation.resolvedText(
                statusItemText: "Mac | 67 C | 3352 RPM",
                fallbackStatusItemText: "Mac | -- C | -- RPM",
                labelNeedsTelemetryPrime: false,
                allowsPlaceholderText: false
            ),
            "Mac | 67 C | 3352 RPM"
        )
        XCTAssertEqual(
            ViftyStatusItemPresentation.resolvedText(
                statusItemText: "Mac | 67 C | 3352 RPM",
                fallbackStatusItemText: "Mac | -- C | -- RPM",
                labelNeedsTelemetryPrime: true,
                allowsPlaceholderText: false
            ),
            "Mac | -- C | -- RPM"
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

        XCTAssertEqual(model.menuBarLabelText, "Owner? | -- C | -- RPM")
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

        XCTAssertEqual(model.menuBarLabelText, "Owner? | -- C | -- RPM")
        XCTAssertNil(model.menuBarStatusItemText)

        await model.primeMenuBarStatusItemTelemetry()

        XCTAssertTrue(model.hasCompletedHardwarePoll)
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertEqual(model.menuBarStatusItemText, "Mac | 67 C | 3352 RPM")
        XCTAssertFalse(model.menuBarLabelUsesFanIcon)
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
        let sleeper = AppModelManualPollingSleeper()
        await hardware.failNextSnapshot(ViftyError.smcUnavailable)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            pollingSleeper: sleeper,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.menuBarDisplayMode = .ownerTemperatureAndRPM

        let primeTask = Task {
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 2, retryDelay: .milliseconds(1))
        }
        let requestedDuration = await sleeper.nextRequestedDuration()
        XCTAssertEqual(requestedDuration, .milliseconds(1))
        await sleeper.resumeNext()
        await primeTask.value

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

        XCTAssertEqual(model.menuBarStatusItemRevision, 1)
        XCTAssertEqual(model.menuBarLabelText, "Owner? | -- C | -- RPM")
        XCTAssertEqual(model.menuBarStatusItemPresentation.content, .text("Owner? | -- C | -- RPM"))

        await model.pollOnce()

        XCTAssertEqual(model.menuBarStatusItemRevision, 2)
        XCTAssertEqual(model.menuBarLabelText, "Mac | 67 C | 3352 RPM")
        XCTAssertEqual(model.menuBarStatusItemPresentation.content, .text("Mac | 67 C | 3352 RPM"))

        await model.pollOnce()

        XCTAssertEqual(model.menuBarStatusItemRevision, 2)
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
        let snapshotGate = AppModelAsyncGate()
        await hardware.setSnapshotGate(snapshotGate)
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

        let firstPoll = Task { @MainActor in await model.pollOnce() }
        await snapshotGate.waitUntilEntered()
        let secondPoll = Task { @MainActor in await model.pollOnce() }
        await snapshotGate.open()
        await firstPoll.value
        await secondPoll.value

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

        XCTAssertEqual(model.menuBarLabelText, "Automatic CPU · CPU Proximity 65 C | 2400 RPM")
        XCTAssertTrue(model.menuBarLabelUsesFanIcon)
    }

}
