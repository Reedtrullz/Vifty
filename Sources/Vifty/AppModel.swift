import Foundation
import SwiftUI
import ViftyCore

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: HardwareSnapshot?
    @Published var controlState = ControlState()
    @Published var selectedMode = ModeSelection.auto
    @Published var fixedRPM = 2800.0
    @Published var curveStartTemp = 55.0
    @Published var curveMidTemp = 70.0
    @Published var curveMaxTemp = 85.0
    @Published var curveStartRPM = 1400.0
    @Published var curveMidRPM = 3500.0
    @Published var curveMaxRPM = 6000.0
    @Published var usePerFanFixedRPM = false {
        didSet {
            persistAppPreferences()
        }
    }
    @Published var fixedFanTargets: [FixedFanTarget] = []
    @Published var usePerFanOverrides = false
    @Published var fanOverrides: [FanCurveOverride] = []
    @Published var selectedSensorID: String? {
        didSet {
            guard !isSettingSelectedSensorProgrammatically else { return }
            userSelectedSensorID = selectedSensorID
        }
    }
    @Published var lastError: String?
    @Published var curveProfilePersistenceError: String?
    @Published var fanAccessMessage: String?
    @Published var daemonResponding = false
    @Published var daemonReachable = false
    @Published var isRunning = false
    @Published var powerSnapshot: PowerSnapshot?
    @Published var thermalPressure: ThermalPressure = .nominal
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            let wasDisplayingCodexUsage = MenuBarPresentationProvider.displaysCodexUsage(
                oldValue,
                customFields: menuBarCustomFields
            )
            if !wasDisplayingCodexUsage && menuBarDisplaysCodexUsage {
                lastCodexUsageRefreshAt = nil
            }
            if wasDisplayingCodexUsage && !menuBarDisplaysCodexUsage {
                cancelCodexUsageRefresh(clearSnapshot: true)
            }
            persistAppPreferences()
            refreshMenuBarStatusItemIfNeeded()
        }
    }
    @Published var menuBarCustomFields: [MenuBarField] = MenuBarField.defaultCustomFields {
        didSet {
            let normalized = MenuBarField.normalized(menuBarCustomFields)
            if normalized != menuBarCustomFields {
                menuBarCustomFields = normalized
                return
            }
            let wasDisplayingCodexUsage = MenuBarPresentationProvider.displaysCodexUsage(
                menuBarDisplayMode,
                customFields: MenuBarField.normalized(oldValue)
            )
            if !wasDisplayingCodexUsage && menuBarDisplaysCodexUsage {
                lastCodexUsageRefreshAt = nil
            }
            if wasDisplayingCodexUsage && !menuBarDisplaysCodexUsage {
                cancelCodexUsageRefresh(clearSnapshot: true)
            }
            persistAppPreferences()
            refreshMenuBarStatusItemIfNeeded()
        }
    }
    @Published var startupMode: ModeSelection {
        didSet {
            persistAppPreferences()
        }
    }
    @Published var textScale: ViftyTextScale {
        didSet {
            persistAppPreferences()
        }
    }
    @Published var notificationSettings: LocalNotificationSettings {
        didSet {
            persistAppPreferences()
        }
    }
    @Published var notificationAuthorization: LocalNotificationAuthorization = .checking
    @Published var notificationTestMessage: String?
    @Published var codexUsageSnapshot: CodexUsageSnapshot?
    @Published var codexUsageDisplayStyle: CodexUsageDisplayStyle {
        didSet {
            codexUsageDisplayPreferenceDidChange()
        }
    }
    @Published var codexUsageMetricMode: CodexUsageMetricMode {
        didSet {
            codexUsageDisplayPreferenceDidChange()
        }
    }
    @Published var codexUsageResetMode: CodexUsageResetMode {
        didSet {
            codexUsageDisplayPreferenceDidChange()
        }
    }
    @Published var codexUsageRefreshCadence: CodexUsageRefreshCadence {
        didSet {
            lastCodexUsageRefreshAt = nil
            codexUsageDisplayPreferenceDidChange()
        }
    }
    @Published var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    @Published var launchAtLoginError: String?
    var telemetrySession = TelemetrySession()
    var telemetryHistory: TelemetryHistory {
        get { telemetrySession.history }
        set {
            telemetrySession.replaceHistory(newValue)
            publishTelemetrySession()
        }
    }
    @Published var manualRunLimit: ManualRunLimit = .defaultForManualControl
    @Published var manualSessionExpiresAt: Date?
    @Published var fanControlApplyState: FanControlApplyState = .applied
    @Published var agentControlStatus: AgentControlStatus?
    @Published var agentControlStatusError: String?
    @Published var agentCoolingEnabled: Bool?
    @Published var fanControlOwnershipStatus: FanControlOwnershipStatus?
    @Published var fanControlOwnershipStatusError: String?
    @Published var hasCompletedHardwarePoll = false
    @Published var menuBarStatusItemPresentation = MenuBarStatusItemPresentation.placeholder
    @Published var menuBarStatusItemRevision = 0
    @Published var telemetryOverviewSummary = TelemetryHistorySummary(history: TelemetryHistory())
    @Published var compactTelemetryOverviewSummary = TelemetryHistorySummary(
        history: TelemetryHistory(),
        sampleLimit: 90,
        thermalPressureLimit: 24
    )
    @Published var recentTelemetryTrendSummary: String?
    var curveDefaultsSynced = false  // internal, accessible via @testable import
    @Published var savedProfiles: [CurveProfile] = []
    @Published var selectedCurveProfileID: CurveProfile.ID?
    @Published var curveProfileRecoveryMessage: String?
    var isSettingSelectedSensorProgrammatically = false
    var userSelectedSensorID: String?
    var fanControlSessionController: FanControlSessionController

    static let menuBarDisplayModeDefaultsKey = AppPreferencesStore.legacyMenuBarDisplayModeDefaultsKey
    static let highTemperatureAttentionThreshold = 90.0
    static let notificationHelperFailureDefaultsKey = AppPreferencesStore.legacyNotificationHelperFailureDefaultsKey
    static let notificationThermalPressureDefaultsKey = AppPreferencesStore.legacyNotificationThermalPressureDefaultsKey
    static let notificationAutoRestoreDefaultsKey = AppPreferencesStore.legacyNotificationAutoRestoreDefaultsKey
    static let notificationPluggedInDrainDefaultsKey = AppPreferencesStore.legacyNotificationPluggedInDrainDefaultsKey
    static let notificationAgentCoolingAttentionDefaultsKey = AppPreferencesStore.legacyNotificationAgentCoolingAttentionDefaultsKey
    static let manualTargetDriftRPMThreshold = 75
    static let manualTargetDriftAttentionSampleCount = 2
    static let manualTargetWriteSettleInterval: TimeInterval = 5
    static let manualResponseRPMGapThreshold = 250
    static let defaultCodexUsageRefreshInterval: TimeInterval = 5 * 60

    let coordinator: FanControlCoordinator
    let powerReader: @Sendable () -> PowerSnapshot
    let thermalReader: @Sendable () -> ThermalPressure
    let codexUsageReader: @Sendable () -> CodexUsageSnapshot?
    let now: @Sendable () -> Date
    let localNotificationCoordinator: LocalNotificationCoordinator
    let launchAtLoginManager: LaunchAtLoginManaging
    let daemonPing: @Sendable () async -> Bool
    let agentStatusReader: @Sendable () async throws -> AgentControlStatus?
    let agentPolicySetter: @Sendable (Bool) async throws -> AgentControlStatus?
    let agentRestore: @Sendable (String) async throws -> AgentControlStatus?
    let profileStore: CurveProfileStore
    let preferencesStore: AppPreferencesStore
    let pollingController: AppPollingController
    var codexUsageRefreshTask: Task<Void, Never>?
    var codexUsageRefreshGeneration = 0
    var startupModeApplied = false
    var manualTargetDriftSampleCounts: [Int: Int] = [:]
    var manualTargetSettlingFanIDs: Set<Int> = []
    var lastCodexUsageRefreshAt: Date?
    var lastPowerTelemetryRefreshAt: Date?
    var lastDaemonPingAt: Date?
    var lastAgentStatusRefreshAt: Date?
    let powerTelemetryRefreshInterval: TimeInterval = 15
    let daemonPingRefreshInterval: TimeInterval = 30
    let agentStatusRefreshInterval: TimeInterval = 15
    let pollSchedulePolicy = PollSchedulePolicy.standard

    var currentFanControlDraft: FanControlDraft {
        FanControlDraft(
            mode: selectedMode,
            manualRunLimit: manualRunLimit,
            fixedRPM: fixedRPM,
            fixedFanTargets: fixedFanTargets,
            usePerFanFixedRPM: usePerFanFixedRPM,
            curve: FanCurveDraft(
                startTemperature: curveStartTemp,
                startRPM: curveStartRPM,
                rampTemperature: curveMidTemp,
                rampRPM: curveMidRPM,
                highTemperature: curveMaxTemp,
                highRPM: curveMaxRPM
            ),
            selectedSensorID: resolvedCurveSensorID,
            usePerFanOverrides: usePerFanOverrides,
            fanOverrides: fanOverrides
        )
    }

    var hasPendingFanControlChanges: Bool {
        fanControlSessionController.hasPendingChanges(
            currentDraft: currentFanControlDraft,
            selectedMode: selectedMode
        )
    }

    var currentCurveProfileDraft: CurveProfileDraftSnapshot {
        CurveProfileDraftSnapshot(
            sensorID: resolvedCurveSensorID,
            startTemperature: curveStartTemp,
            startRPM: Int(curveStartRPM.rounded()),
            rampTemperature: curveMidTemp,
            rampRPM: Int(curveMidRPM.rounded()),
            highTemperature: curveMaxTemp,
            highRPM: Int(curveMaxRPM.rounded()),
            fanOverrides: usePerFanOverrides ? fanOverrides : []
        )
    }

    var curveProfileEditState: CurveProfileEditState {
        CurveProfileEditState.resolve(
            selectedProfile: selectedCurveProfileID.flatMap { selectedID in
                savedProfiles.first { $0.id == selectedID }
            },
            draft: currentCurveProfileDraft
        )
    }

    var controlSessionPresentation: ControlSessionPresentation {
        ControlSessionPresentation.resolve(ControlSessionInput(
            helperHealth: helperHealthState,
            helperHealthNeedsAttention: helperHealthNeedsAttention,
            helperRepairActionAvailable: helperRepairActionAvailable,
            manualFanControlAvailable: manualFanControlAvailable,
            controlOwnershipNeedsAttention: controlOwnershipNeedsAttention,
            controlOwnershipSummary: controlOwnershipSummary,
            agentCoolingSummary: agentCoolingSummary,
            hasAgentCoolingLease: agentControlStatus?.activeLease != nil,
            agentCoolingNeedsAttention: agentCoolingNeedsAttention,
            manualControlAttentionSummary: manualControlAttentionSummary,
            selectedMode: selectedMode,
            applyState: fanControlPresentationApplyState,
            manualSessionExpiresAt: manualSessionExpiresAt,
            ownershipStatus: fanControlOwnershipStatus
        ))
    }

    var fanControlPresentationApplyState: FanControlApplyState {
        fanControlSessionController.presentationApplyState(
            currentDraft: currentFanControlDraft,
            selectedMode: selectedMode,
            applyState: fanControlApplyState
        )
    }

    var menuBarPanelPresentation: MenuBarPanelPresentation {
        MenuBarPanelPresentation.resolve(input: .init(
            controlSession: controlSessionPresentation,
            ownershipStatus: fanControlOwnershipStatus,
            attentionText: menuBarPanelAttentionText,
            fans: snapshot?.fans ?? []
        ))
    }

    init(
        coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService()),
        powerReader: @escaping @Sendable () -> PowerSnapshot = { PowerInfoReader.read() },
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        codexUsageReader: @escaping @Sendable () -> CodexUsageSnapshot? = { CodexUsageReader.readDefault() },
        codexUsageRefreshInterval: TimeInterval = AppModel.defaultCodexUsageRefreshInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        pollingSleeper: any AppPollingSleeping = ContinuousAppPollingSleeper(),
        notificationDeliverer: LocalNotificationDelivering = UserNotificationDeliverer(),
        notificationHistoryStore: LocalNotificationHistoryStore = LocalNotificationHistoryStore(),
        daemonPing: @escaping @Sendable () async -> Bool = { await ViftyDaemonClient().ping() },
        agentStatusReader: @escaping @Sendable () async throws -> AgentControlStatus? = {
            try await ViftyDaemonClient().agentControlStatus()
        },
        agentPolicySetter: @escaping @Sendable (Bool) async throws -> AgentControlStatus? = { enabled in
            try await ViftyDaemonClient().setAgentControlEnabled(enabled)
        },
        agentRestore: @escaping @Sendable (String) async throws -> AgentControlStatus? = { reason in
            try await ViftyDaemonClient().restoreAgentControl(reason: reason)
        },
        profileStore: CurveProfileStore = CurveProfileStore(),
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        launchAtLoginManager: LaunchAtLoginManaging = SMAppLaunchAtLoginManager()
    ) {
        self.coordinator = coordinator
        self.powerReader = powerReader
        self.thermalReader = thermalReader
        self.codexUsageReader = codexUsageReader
        self.now = now
        fanControlSessionController = FanControlSessionController(now: now)
        pollingController = AppPollingController(sleeper: pollingSleeper)
        localNotificationCoordinator = LocalNotificationCoordinator(
            deliverer: notificationDeliverer,
            historyStore: notificationHistoryStore,
            now: now
        )
        self.launchAtLoginManager = launchAtLoginManager
        self.daemonPing = daemonPing
        self.agentStatusReader = agentStatusReader
        self.agentPolicySetter = agentPolicySetter
        self.agentRestore = agentRestore
        self.profileStore = profileStore
        self.preferencesStore = preferencesStore
        let appPreferences = self.preferencesStore.load()
        menuBarDisplayMode = appPreferences.menuBarDisplayMode
        menuBarCustomFields = MenuBarField.normalized(appPreferences.menuBarCustomFields)
        startupMode = appPreferences.startupMode
        textScale = appPreferences.textScale
        notificationSettings = appPreferences.notificationSettings
        usePerFanFixedRPM = appPreferences.usePerFanFixedRPM
        fixedFanTargets = appPreferences.fixedFanTargets
        codexUsageDisplayStyle = appPreferences.codexUsageDisplayPreferences.displayStyle
        codexUsageMetricMode = appPreferences.codexUsageDisplayPreferences.metricMode
        codexUsageResetMode = appPreferences.codexUsageDisplayPreferences.resetMode
        codexUsageRefreshCadence = if appPreferences.codexUsageDisplayPreferences == .defaults,
                                      let injectedCadence = CodexUsageRefreshCadence(seconds: codexUsageRefreshInterval) {
            injectedCadence
        } else {
            appPreferences.codexUsageDisplayPreferences.refreshCadence
        }
        launchAtLoginStatus = launchAtLoginManager.status
        do {
            let profileLoadResult = try profileStore.loadResult()
            savedProfiles = profileLoadResult.profiles
            curveProfileRecoveryMessage = profileLoadResult.recoveryMessage
        } catch {
            savedProfiles = []
            curveProfileRecoveryMessage = error.localizedDescription
        }
        menuBarStatusItemPresentation = currentMenuBarStatusItemPresentation
    }

    func start() {
        let started = pollingController.start(
            initialOperation: { [weak self] in
                guard let self else { return }
                await coordinator.recoverIfNeeded()
                guard pollingController.isRunning else { return }
                await pollOnce()
                guard pollingController.isRunning else { return }
                await applyStartupModePreferenceIfNeeded()
                guard pollingController.isRunning else { return }
                await refreshNotificationAuthorization()
            },
            interval: { [weak self] in
                self?.backgroundPollInterval() ?? .seconds(10)
            },
            poll: { [weak self] operation in
                await self?.performPollOnce(operation: operation)
            }
        )
        guard started else { return }
        isRunning = true
        ViftyLog.lifecycle.info("Polling started")
    }

    func primeMenuBarStatusItemTelemetry(
        maxAttempts: Int = 1,
        retryDelay: Duration = .milliseconds(250)
    ) async {
        let attempts = max(1, maxAttempts)
        for attempt in 1...attempts {
            guard menuBarLabelNeedsTelemetryPrime else { return }
            await pollOnce()
            guard menuBarLabelNeedsTelemetryPrime else { return }
            if attempt < attempts {
                try? await pollingController.wait(for: retryDelay)
            }
        }
    }

}

enum ModeSelection: String, Codable, CaseIterable, Identifiable {
    case auto = "Auto"
    case curve = "Curve"
    case fixed = "Fixed"

    var id: String { rawValue }
}

struct FixedFanTarget: Codable, Equatable, Identifiable, Sendable {
    var fanID: Int
    var rpm: Int

    var id: Int { fanID }
}

enum ManualRunLimit: Equatable, Hashable, Identifiable {
    case indefinitely
    case minutes(Int)

    var id: String {
        switch self {
        case .indefinitely:
            "indefinitely"
        case .minutes(let minutes):
            "\(minutes)m"
        }
    }

    var label: String {
        switch self {
        case .indefinitely:
            "Until changed"
        case .minutes(let minutes):
            "\(minutes) min"
        }
    }

    static let defaultForManualControl: ManualRunLimit = .minutes(30)
    static let presets: [ManualRunLimit] = [.indefinitely, .minutes(10), .minutes(30), .minutes(60)]
}

enum DeveloperFanPreset: String, CaseIterable, Identifiable {
    case tests
    case build
    case localModel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tests:
            "Tests"
        case .build:
            "Build"
        case .localModel:
            "Local Model"
        }
    }

    var systemImage: String {
        switch self {
        case .tests:
            "checkmark.seal"
        case .build:
            "hammer"
        case .localModel:
            "cpu"
        }
    }

    var startTemperatureCelsius: Double {
        switch self {
        case .tests:
            55
        case .build:
            52
        case .localModel:
            50
        }
    }

    var midTemperatureCelsius: Double {
        switch self {
        case .tests:
            70
        case .build:
            68
        case .localModel:
            66
        }
    }

    var maxTemperatureCelsius: Double {
        switch self {
        case .tests:
            85
        case .build:
            84
        case .localModel:
            82
        }
    }

    var startRPMPercent: Int {
        switch self {
        case .tests:
            35
        case .build:
            40
        case .localModel:
            45
        }
    }

    var midRPMPercent: Int {
        switch self {
        case .tests:
            55
        case .build:
            60
        case .localModel:
            65
        }
    }

    var maxRPMPercent: Int {
        switch self {
        case .tests:
            70
        case .build:
            75
        case .localModel:
            78
        }
    }
}
