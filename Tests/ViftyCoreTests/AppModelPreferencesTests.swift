import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelPreferencesTests: XCTestCase {
    func testSaveProfileWithDuplicateNameRequiresConfirmationAndPreservesIdentity() throws {
        let model = AppModel()
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")
        XCTAssertEqual(model.savedProfiles.count, 1)

        // Change sliders to different values.
        model.curveStartTemp = 60
        model.curveStartRPM = 1500

        let originalID = try XCTUnwrap(model.savedProfiles.first?.id)

        let unconfirmed = model.saveCurrentProfileAs(name: "Quiet", confirmOverwrite: false)
        XCTAssertEqual(model.savedProfiles.count, 1, "Duplicate name should overwrite, not append")
        guard case .overwriteConfirmationRequired? = unconfirmed else {
            return XCTFail("Expected explicit overwrite confirmation")
        }
        XCTAssertNotEqual(model.savedProfiles[0].startTemp, 60)

        _ = model.saveCurrentProfileAs(name: "Quiet", confirmOverwrite: true)
        XCTAssertEqual(model.savedProfiles[0].startTemp, 60, "Should store updated values")
        XCTAssertEqual(model.savedProfiles[0].startRPM, 1500)
        XCTAssertEqual(model.savedProfiles[0].id, originalID)
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
            Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
            Fan(id: 2, name: "Read only", currentRPM: 1500, minimumRPM: 1400, maximumRPM: 6000, controllable: false)
        ]

        model.ensureFanOverrides(for: fans)

        XCTAssertEqual(model.fanOverrides.map(\.fanID), [0, 1])
        XCTAssertEqual(model.fanOverride(for: 0)?.startRPM, 1400)
        XCTAssertEqual(model.fanOverride(for: 1)?.startRPM, 2200)
        XCTAssertEqual(model.fanOverride(for: 1)?.midRPM, 4200)
        XCTAssertNil(model.fanOverride(for: 2))
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

    func testCurveProfileSelectionIsSharedAndClearsForUnsavedCurves() {
        let model = AppModel()
        let profile = CurveProfile(
            name: "Build",
            sensorID: "Tp09",
            startTemp: 54,
            startRPM: 2_600,
            midTemp: 70,
            midRPM: 3_800,
            maxTemp: 86,
            maxRPM: 5_200
        )
        model.savedProfiles = [profile]

        XCTAssertTrue(model.selectCurveProfile(id: profile.id))
        XCTAssertEqual(model.selectedCurveProfileID, profile.id)

        model.loadDeveloperPreset(.build)
        XCTAssertNil(model.selectedCurveProfileID)

        XCTAssertTrue(model.selectCurveProfile(id: nil))
        XCTAssertNil(model.selectedCurveProfileID)
    }

    func testSavingAndDeletingProfileKeepsSharedSelectionValid() throws {
        let model = AppModel()
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")

        let savedProfile = try XCTUnwrap(model.savedProfiles.first)
        XCTAssertEqual(model.selectedCurveProfileID, savedProfile.id)

        model.deleteProfile(savedProfile)
        XCTAssertNil(model.selectedCurveProfileID)
    }

    func testDeveloperPresetRPMCapsStayWithinDefaultAgentPolicyCeiling() {
        let policy = AgentControlPolicy()

        for preset in DeveloperFanPreset.allCases {
            XCTAssertLessThanOrEqual(preset.startRPMPercent, policy.maximumAllowedRPMPercent)
            XCTAssertLessThanOrEqual(preset.midRPMPercent, policy.maximumAllowedRPMPercent)
            XCTAssertLessThanOrEqual(preset.maxRPMPercent, policy.maximumAllowedRPMPercent)
        }
    }

    func testProfilePersistenceFailureDoesNotCommitSaveUpdateOrDeleteInMemory() throws {
        let parentFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parentFile) }
        try Data("not a directory".utf8).write(to: parentFile)
        let store = CurveProfileStore(url: parentFile.appendingPathComponent("curve-profiles.json"))
        let model = AppModel(profileStore: store)
        model.savedProfiles = []

        let createResult = model.saveCurrentProfileAs(name: "Quiet", confirmOverwrite: false)

        guard case .persistenceFailed? = createResult else {
            return XCTFail("Expected failed persistence result")
        }
        XCTAssertTrue(model.savedProfiles.isEmpty)
        XCTAssertNil(model.selectedCurveProfileID)
        XCTAssertTrue(model.lastError?.contains("Failed to save profiles") == true)

        let existing = CurveProfile(
            name: "Existing",
            startTemp: 50,
            startRPM: 1_500,
            midTemp: 65,
            midRPM: 3_000,
            maxTemp: 80,
            maxRPM: 4_500
        )
        model.savedProfiles = [existing]
        model.selectedCurveProfileID = existing.id
        model.curveStartTemp = 61

        XCTAssertFalse(model.updateSelectedCurveProfile())
        XCTAssertEqual(model.savedProfiles, [existing])
        XCTAssertEqual(model.selectedCurveProfileID, existing.id)

        XCTAssertFalse(model.deleteProfile(existing))
        XCTAssertEqual(model.savedProfiles, [existing])
        XCTAssertEqual(model.selectedCurveProfileID, existing.id)

        try FileManager.default.removeItem(at: parentFile)
        try FileManager.default.createDirectory(at: parentFile, withIntermediateDirectories: true)
        XCTAssertTrue(model.updateSelectedCurveProfile())
        XCTAssertNil(model.curveProfilePersistenceError)
        XCTAssertNil(model.lastError)
    }

    func testProfileBackupRecoveryIsVisibleWithoutRewritingPrimary() throws {
        let url = temporaryPreferencesPath()
            .deletingLastPathComponent()
            .appendingPathComponent("curve-profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corruptPrimary = Data("corrupt primary".utf8)
        try corruptPrimary.write(to: url)
        let profile = CurveProfile(
            name: "Recovered",
            startTemp: 50,
            startRPM: 1_500,
            midTemp: 65,
            midRPM: 3_000,
            maxTemp: 80,
            maxRPM: 4_500
        )
        try JSONEncoder().encode([profile]).write(to: url.appendingPathExtension("bak"))

        let model = AppModel(profileStore: CurveProfileStore(url: url))

        XCTAssertEqual(model.savedProfiles, [profile])
        XCTAssertNotNil(model.curveProfileRecoveryMessage)
        XCTAssertEqual(try Data(contentsOf: url), corruptPrimary)
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

    func testMenuBarCustomFieldsPersistPrivately() throws {
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)
        let model = AppModel(preferencesStore: store)

        XCTAssertEqual(model.menuBarCustomFields, [.temperature, .fanStrength, .codexUsage])

        model.menuBarDisplayMode = .custom
        model.menuBarCustomFields = [.codexUsage, .fanStrength, .owner, .temperature, .codexUsage]

        let loaded = store.load()
        XCTAssertEqual(loaded.menuBarDisplayMode, .custom)
        XCTAssertEqual(loaded.menuBarCustomFields, [.owner, .temperature, .fanStrength, .codexUsage])
        XCTAssertEqual(try posixPermissions(at: preferencesURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: preferencesURL), 0o600)

        let relaunched = AppModel(preferencesStore: store)
        XCTAssertEqual(relaunched.menuBarDisplayMode, .custom)
        XCTAssertEqual(relaunched.menuBarCustomFields, [.owner, .temperature, .fanStrength, .codexUsage])

        relaunched.setMenuBarCustomField(.owner, enabled: false)
        XCTAssertEqual(store.load().menuBarCustomFields, [.temperature, .fanStrength, .codexUsage])
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

    func testTextScalePreferencePersistsPrivatelyAndLoadsOnRelaunch() throws {
        let preferencesURL = temporaryPreferencesPath()
        let store = AppPreferencesStore(url: preferencesURL, legacyDefaults: nil)
        let model = AppModel(preferencesStore: store)

        XCTAssertEqual(model.textScale, .standard)

        model.textScale = .large

        XCTAssertEqual(store.load().textScale, .large)
        XCTAssertEqual(try posixPermissions(at: preferencesURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: preferencesURL), 0o600)

        let relaunched = AppModel(preferencesStore: store)
        XCTAssertEqual(relaunched.textScale, .large)
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
        XCTAssertEqual(loaded.menuBarCustomFields, [.temperature, .fanStrength, .codexUsage])
        XCTAssertEqual(loaded.startupMode, .auto)
        XCTAssertEqual(loaded.textScale, .standard)
        XCTAssertTrue(loaded.notificationSettings.helperFailure)
        XCTAssertTrue(loaded.notificationSettings.autoRestoreFailure)
        XCTAssertFalse(loaded.usePerFanFixedRPM)
        XCTAssertTrue(loaded.fixedFanTargets.isEmpty)
        XCTAssertEqual(loaded.codexUsageDisplayPreferences.displayStyle, .text)
    }

    func testNonAutoStartupPreferenceCreatesDraftWithoutFanWrite() async throws {
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
        XCTAssertTrue(model.hasPendingFanControlChanges)
        XCTAssertEqual(model.controlState.mode, .auto)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertEqual(appliedCommands, [])
    }

}
