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
    @Published private(set) var curveProfilePersistenceError: String?
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
    @Published private(set) var notificationAuthorization: LocalNotificationAuthorization = .checking
    @Published private(set) var notificationTestMessage: String?
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
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    @Published private(set) var launchAtLoginError: String?
    private var telemetrySession = TelemetrySession()
    var telemetryHistory: TelemetryHistory {
        get { telemetrySession.history }
        set {
            telemetrySession.replaceHistory(newValue)
            publishTelemetrySession()
        }
    }
    @Published var manualRunLimit: ManualRunLimit = .defaultForManualControl
    @Published var manualSessionExpiresAt: Date?
    @Published private(set) var fanControlApplyState: FanControlApplyState = .applied
    @Published var agentControlStatus: AgentControlStatus?
    @Published var agentControlStatusError: String?
    @Published private(set) var fanControlOwnershipStatus: FanControlOwnershipStatus?
    @Published private(set) var fanControlOwnershipStatusError: String?
    @Published var hasCompletedHardwarePoll = false
    @Published private(set) var menuBarStatusItemPresentation = MenuBarStatusItemPresentation.placeholder
    @Published private(set) var menuBarStatusItemRevision = 0
    @Published private(set) var telemetryOverviewSummary = TelemetryHistorySummary(history: TelemetryHistory())
    @Published private(set) var compactTelemetryOverviewSummary = TelemetryHistorySummary(
        history: TelemetryHistory(),
        sampleLimit: 90,
        thermalPressureLimit: 24
    )
    @Published private(set) var recentTelemetryTrendSummary: String?
    var curveDefaultsSynced = false  // internal, accessible via @testable import
    @Published var savedProfiles: [CurveProfile] = []
    @Published var selectedCurveProfileID: CurveProfile.ID?
    @Published private(set) var curveProfileRecoveryMessage: String?
    private var isSettingSelectedSensorProgrammatically = false
    private var userSelectedSensorID: String?
    private var fanControlSessionController: FanControlSessionController

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

    private let coordinator: FanControlCoordinator
    private let powerReader: @Sendable () -> PowerSnapshot
    private let thermalReader: @Sendable () -> ThermalPressure
    private let codexUsageReader: @Sendable () -> CodexUsageSnapshot?
    private let now: @Sendable () -> Date
    private let localNotificationCoordinator: LocalNotificationCoordinator
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let daemonPing: @Sendable () async -> Bool
    private let agentStatusReader: @Sendable () async throws -> AgentControlStatus?
    private let agentRestore: @Sendable (String) async throws -> AgentControlStatus?
    private let profileStore: CurveProfileStore
    private let preferencesStore: AppPreferencesStore
    private let pollingController: AppPollingController
    private var codexUsageRefreshTask: Task<Void, Never>?
    private var codexUsageRefreshGeneration = 0
    private var startupModeApplied = false
    private var manualTargetDriftSampleCounts: [Int: Int] = [:]
    private var manualTargetSettlingFanIDs: Set<Int> = []
    private var lastCodexUsageRefreshAt: Date?
    private var lastPowerTelemetryRefreshAt: Date?
    private var lastDaemonPingAt: Date?
    private var lastAgentStatusRefreshAt: Date?
    private let powerTelemetryRefreshInterval: TimeInterval = 15
    private let daemonPingRefreshInterval: TimeInterval = 30
    private let agentStatusRefreshInterval: TimeInterval = 15
    private let pollSchedulePolicy = PollSchedulePolicy.standard

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

    private var fanControlPresentationApplyState: FanControlApplyState {
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

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus.isToggleOn
    }

    var launchAtLoginStatusMessage: String? {
        launchAtLoginError ?? launchAtLoginStatus.message
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginManager.status
        if launchAtLoginStatus == .enabled || launchAtLoginStatus == .disabled {
            launchAtLoginError = nil
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginStatus = launchAtLoginManager.status
            launchAtLoginError = nil
            if launchAtLoginStatus == .requiresApproval {
                launchAtLoginManager.openLoginItemsSettings()
            }
        } catch {
            launchAtLoginStatus = launchAtLoginManager.status
            launchAtLoginError = "Could not update startup item: \(error.localizedDescription)"
        }
    }

    func openLaunchAtLoginSettings() {
        launchAtLoginManager.openLoginItemsSettings()
    }

    func refreshSystemSettingsStateOnActivation() async {
        refreshLaunchAtLoginStatus()
        await refreshNotificationAuthorization()
    }

    func applyStartupModePreferenceIfNeeded() async {
        guard !startupModeApplied else { return }
        startupModeApplied = true
        selectedMode = startupMode
        guard startupMode != .auto else { return }
        if snapshot == nil {
            await pollOnce()
            selectedMode = startupMode
        }
        guard FanControlOwnershipPresentation.resolve(fanControlOwnershipStatus).owner == .macOS else {
            lastError = "Startup manual mode remains a draft until daemon-confirmed macOS fan ownership is available."
            markFanControlDraftPending()
            return
        }
        markFanControlDraftPending()
    }

    func stop() {
        Task { _ = await stopAndRestore() }
    }

    func stopAndRestore() async -> AppTerminationRestoreResult {
        ViftyLog.fanControl.notice("Termination restore started")
        let wasRunning = isRunning
        let stateBeforeStop = await coordinator.state
        let hasAgentLeaseRequiringRestore = agentControlStatus?.activeLease != nil
        pollingController.stop()
        codexUsageRefreshGeneration &+= 1
        codexUsageRefreshTask?.cancel()
        codexUsageRefreshTask = nil
        isRunning = false
        selectedMode = .auto
        manualSessionExpiresAt = nil

        var failures: [String] = []
        let ownershipBeforeRestore: FanControlOwnershipStatus?
        do {
            let status = try await coordinator.fanControlOwnershipStatus()
            fanControlOwnershipStatus = status
            fanControlOwnershipStatusError = nil
            ownershipBeforeRestore = status
        } catch {
            let message = "Could not confirm daemon fan-control ownership before termination: \(error.localizedDescription)"
            fanControlOwnershipStatus = nil
            fanControlOwnershipStatusError = error.localizedDescription
            ownershipBeforeRestore = nil
            failures.append(message)
        }

        let requiresHardwareRestore = stateBeforeStop.manualControlActive
            || stateBeforeStop.mode != .auto
            || hasAgentLeaseRequiringRestore
            || ownershipBeforeRestore.map {
                !FanControlCoordinator.confirmsCleanOSOwnership($0)
            } == true

        // A failed ownership read must not suppress a restore already required
        // by local manual state or an agent lease. We still fail termination
        // closed on that unreadable precondition, but make the best available
        // safety move back to Auto and then re-read authoritative ownership.
        if requiresHardwareRestore {
            let hardwareRestoreResult = await coordinator.forceAuto()
            if case .failed(let message) = hardwareRestoreResult {
                failures.append(message)
            }

            do {
                let status = try await coordinator.fanControlOwnershipStatus()
                fanControlOwnershipStatus = status
                fanControlOwnershipStatusError = nil
                if !FanControlCoordinator.confirmsCleanOSOwnership(status) {
                    failures.append(
                        "Auto restore did not reach clean daemon-confirmed macOS fan ownership."
                    )
                }
            } catch {
                fanControlOwnershipStatus = nil
                fanControlOwnershipStatusError = error.localizedDescription
                failures.append(
                    "Could not confirm daemon fan-control ownership after Auto restore: \(error.localizedDescription)"
                )
            }
        }
        await refreshAgentControlStatus()
        await syncState()

        guard !failures.isEmpty else {
            recordAutoRestorationApplied()
            ViftyLog.fanControl.notice("Termination restore confirmed")
            return .restored
        }

        let message = failures.joined(separator: "\n")
        lastError = message
        await notifyAutoRestoreFailure(message)
        selectedMode = modeSelection(for: controlState.mode)
        resumePollingAfterTerminationFailure(wasRunning: wasRunning)
        ViftyLog.fanControl.error("Termination restore failed")
        return .failed(message: message)
    }

    private func modeSelection(for mode: FanMode) -> ModeSelection {
        switch mode {
        case .auto:
            .auto
        case .fixedRPM:
            .fixed
        case .temperatureCurve:
            .curve
        }
    }

    private func resumePollingAfterTerminationFailure(wasRunning: Bool) {
        guard wasRunning, !pollingController.isRunning else { return }
        let started = pollingController.start(
            interval: { [weak self] in
                self?.backgroundPollInterval() ?? .seconds(10)
            },
            poll: { [weak self] operation in
                await self?.performPollOnce(operation: operation)
            }
        )
        isRunning = started
    }

    func pollOnce() async {
        await pollingController.pollOnce { [weak self] operation in
            await self?.performPollOnce(operation: operation)
        }
    }

    private func performPollOnce(
        operation: AppPollingOperation,
        reconcileManualApply: Bool = true
    ) async {
        guard pollingController.isCurrent(operation) else { return }
        let pollingIntervalState = ViftyLog.pollingSignposter.beginInterval("Hardware poll")
        defer {
            ViftyLog.pollingSignposter.endInterval("Hardware poll", pollingIntervalState)
        }
        let pollStartedAt = now()
        let shouldRefreshPowerTelemetry = shouldRefresh(
            lastRefreshAt: lastPowerTelemetryRefreshAt,
            interval: powerTelemetryRefreshInterval,
            at: pollStartedAt
        )
        let currentPower: PowerSnapshot
        let currentThermalPressure: ThermalPressure
        if shouldRefreshPowerTelemetry {
            currentPower = powerReader()
            currentThermalPressure = thermalReader()
            lastPowerTelemetryRefreshAt = pollStartedAt
            assignIfChanged(\.powerSnapshot, currentPower)
            assignIfChanged(\.thermalPressure, currentThermalPressure)
        } else {
            currentPower = powerSnapshot ?? PowerSnapshot()
            currentThermalPressure = thermalPressure
        }

        defer {
            if pollingController.isCurrent(operation) {
                hasCompletedHardwarePoll = true
                refreshMenuBarStatusItemIfNeeded()
            }
        }
        refreshCodexUsageIfNeeded()
        let expiredAutoOperationGeneration = await restoreAutoIfManualSessionExpired()
        guard pollingController.isCurrent(operation) else { return }
        let stateBeforeTick = await coordinator.state
        guard pollingController.isCurrent(operation) else { return }
        do {
            let nextSnapshot = try await coordinator.tick()
            guard pollingController.isCurrent(operation) else { return }
            recordHardwareSnapshot(nextSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            assignIfChanged(\.lastError, nil)
            await refreshDaemonPingIfNeeded(at: pollStartedAt, force: false)
            guard pollingController.isCurrent(operation) else { return }
            assignIfChanged(\.daemonReachable, daemonResponding || !nextSnapshot.fans.isEmpty)
            await refreshAgentControlStatusIfNeeded(at: pollStartedAt)
            guard pollingController.isCurrent(operation) else { return }
            await refreshFanControlOwnershipStatus()
            guard pollingController.isCurrent(operation) else { return }
            assignIfChanged(\.fanAccessMessage, fanAccessMessage(for: nextSnapshot))
            await syncState()
            guard pollingController.isCurrent(operation) else { return }
            if let expiredAutoOperationGeneration,
               canCommitAutoRestoration(generation: expiredAutoOperationGeneration) {
                recordAutoRestorationApplied()
            } else if reconcileManualApply {
                reconcileManualApplyAttemptAfterSuccessfulPoll()
            }
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
            ViftyLog.polling.debug("Hardware poll completed")
        } catch {
            guard pollingController.isCurrent(operation) else { return }
            ViftyLog.polling.warning("Hardware poll failed")
            let preservesManualIntent = shouldPreserveManualIntent(
                afterTickFailure: error,
                attemptedMode: stateBeforeTick.mode
            )
            if preservesManualIntent, let observedSnapshot = await coordinator.lastObservedSnapshot {
                recordHardwareSnapshot(observedSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            }
            assignIfChanged(\.lastError, error.localizedDescription)
            await refreshDaemonPingIfNeeded(at: pollStartedAt, force: true)
            guard pollingController.isCurrent(operation) else { return }
            assignIfChanged(\.daemonReachable, daemonResponding || (preservesManualIntent && snapshot?.fans.isEmpty == false))
            await refreshAgentControlStatusIfNeeded(at: pollStartedAt, force: true)
            guard pollingController.isCurrent(operation) else { return }
            await refreshFanControlOwnershipStatus()
            guard pollingController.isCurrent(operation) else { return }
            if preservesManualIntent, let snapshot {
                assignIfChanged(\.fanAccessMessage, fanAccessMessage(for: snapshot))
            }
            if preservesManualIntent {
                if selectedMode != .auto {
                    let intendedMode: FanMode = stateBeforeTick.mode == .auto ? selectedFanMode() : stateBeforeTick.mode
                    await coordinator.setMode(intendedMode)
                    guard pollingController.isCurrent(operation) else { return }
                }
                assignIfChanged(\.controlState, await coordinator.state)
            } else if selectedMode == .auto,
                      expiredAutoOperationGeneration == nil {
                // The coordinator tick already attempted the current Auto
                // transaction. Do not double the retry rate with a second
                // forceAuto request in the same poll; later polls may make one
                // authority-free safety retry.
                await syncState()
            } else {
                let fallbackAutoRestoreResult = await coordinator.forceAuto()
                guard pollingController.isCurrent(operation) else { return }
                await syncState()
                guard pollingController.isCurrent(operation) else { return }

                if let expiredAutoOperationGeneration,
                   fanControlOperationIsCurrent(expiredAutoOperationGeneration) {
                    switch fallbackAutoRestoreResult {
                    case .restored:
                        if canCommitAutoRestoration(generation: expiredAutoOperationGeneration) {
                            recordAutoRestorationApplied()
                        } else {
                            let message = "\(error.localizedDescription)\nFallback Auto restore could not be confirmed."
                            assignIfChanged(\.lastError, message)
                            fanControlApplyState = .failed(message: message)
                        }
                    case .failed(let fallbackMessage):
                        let message = "\(error.localizedDescription)\nFallback Auto restore failed: \(fallbackMessage)"
                        assignIfChanged(\.lastError, message)
                        fanControlApplyState = .failed(message: message)
                    }
                }
            }
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
        }
    }

    private func refreshCodexUsageIfNeeded() {
        guard menuBarDisplaysCodexUsage else {
            if codexUsageRefreshTask != nil || codexUsageSnapshot != nil {
                cancelCodexUsageRefresh(clearSnapshot: true)
            }
            return
        }
        guard codexUsageRefreshTask == nil else { return }

        let currentTime = now()
        if let lastCodexUsageRefreshAt,
           currentTime.timeIntervalSince(lastCodexUsageRefreshAt) < codexUsageRefreshCadence.seconds {
            return
        }

        lastCodexUsageRefreshAt = currentTime
        let reader = codexUsageReader
        codexUsageRefreshGeneration &+= 1
        let generation = codexUsageRefreshGeneration
        codexUsageRefreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                reader()
            }.value
            let wasCancelled = Task.isCancelled

            guard let self else { return }
            guard self.codexUsageRefreshGeneration == generation else { return }
            self.codexUsageRefreshTask = nil
            guard !wasCancelled else { return }
            guard self.menuBarDisplaysCodexUsage else {
                self.cancelCodexUsageRefresh(clearSnapshot: true)
                return
            }

            self.assignIfChanged(\.codexUsageSnapshot, snapshot)
            self.refreshMenuBarStatusItemIfNeeded()
        }
    }

    private func cancelCodexUsageRefresh(clearSnapshot: Bool) {
        codexUsageRefreshGeneration &+= 1
        codexUsageRefreshTask?.cancel()
        codexUsageRefreshTask = nil
        lastCodexUsageRefreshAt = nil
        if clearSnapshot {
            assignIfChanged(\.codexUsageSnapshot, nil)
        }
        refreshMenuBarStatusItemIfNeeded()
    }

    func waitForCodexUsageRefresh() async {
        await codexUsageRefreshTask?.value
    }

    @discardableResult
    private func refreshMenuBarStatusItemIfNeeded() -> Bool {
        let nextPresentation = currentMenuBarStatusItemPresentation
        guard nextPresentation != menuBarStatusItemPresentation else { return false }
        menuBarStatusItemPresentation = nextPresentation
        menuBarStatusItemRevision &+= 1
        return true
    }

    private var currentMenuBarStatusItemPresentation: MenuBarStatusItemPresentation {
        resolvedMenuBarPresentation.statusItemPresentation
    }

    private func shouldRefresh(lastRefreshAt: Date?, interval: TimeInterval, at date: Date) -> Bool {
        guard let lastRefreshAt else { return true }
        return date.timeIntervalSince(lastRefreshAt) >= interval
    }

    private func backgroundPollInterval() -> Duration {
        pollSchedulePolicy.interval(
            selectedMode: selectedMode,
            controlMode: controlState.mode,
            hasAgentLease: agentControlStatus?.activeLease?.isActive(at: now()) == true
        )
    }

    private func refreshDaemonPingIfNeeded(at date: Date, force: Bool) async {
        guard force || !daemonResponding || shouldRefresh(
            lastRefreshAt: lastDaemonPingAt,
            interval: daemonPingRefreshInterval,
            at: date
        ) else {
            return
        }
        let responding = await daemonPing()
        lastDaemonPingAt = date
        assignIfChanged(\.daemonResponding, responding)
    }

    private func refreshAgentControlStatusIfNeeded(at date: Date, force: Bool = false) async {
        let activeLease = agentControlStatus?.activeLease
        let activeAgentWork = activeLease?.isActive(at: date) == true || agentControlStatusError != nil
        guard force || activeAgentWork || shouldRefresh(
            lastRefreshAt: lastAgentStatusRefreshAt,
            interval: agentStatusRefreshInterval,
            at: date
        ) else {
            return
        }
        await refreshAgentControlStatus()
        lastAgentStatusRefreshAt = date
    }

    @discardableResult
    private func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppModel, Value>,
        _ value: Value
    ) -> Bool {
        guard self[keyPath: keyPath] != value else { return false }
        self[keyPath: keyPath] = value
        return true
    }

    private func recordHardwareSnapshot(
        _ nextSnapshot: HardwareSnapshot,
        power: PowerSnapshot,
        thermalPressure: ThermalPressure
    ) {
        assignIfChanged(\.snapshot, nextSnapshot)
        telemetrySession.record(
            snapshot: nextSnapshot,
            power: power,
            thermalPressure: thermalPressure,
            userSelectedSensorID: userSelectedSensorID,
            capturedAt: now(),
        )
        publishTelemetrySession()
        syncCurveDefaultsIfNeeded(from: nextSnapshot)
        if usePerFanFixedRPM {
            ensureFixedFanTargets(for: nextSnapshot.fans)
        }
    }

    private func fanAccessMessage(for snapshot: HardwareSnapshot) -> String? {
        snapshot.fans.isEmpty
            ? (daemonResponding ? "The fan helper is running but did not return fan data." : "Install and approve the fan helper to enable fan reads and control.")
            : nil
    }

    func applyModeSelection() {
        if selectedMode == .auto {
            restoreAuto()
        } else {
            markFanControlDraftPending()
        }
    }

    func performModeSelectionAction() {
        Task { await performModeSelectionActionNow() }
    }

    func performModeSelectionActionNow() async {
        switch controlSessionPresentation.primaryAction {
        case .restoreAuto:
            await restoreAutoNow()
        case .apply:
            _ = await applyCurrentModeSelection()
        case .none, .repairHelper, .copyDiagnostics:
            break
        }
    }

    func restoreAuto() {
        let generation = beginAutoRestoreOperation()
        Task { await performAutoRestore(generation: generation) }
    }

    var canRequestRestoreAuto: Bool {
        FanControlOwnershipPresentation
            .resolve(fanControlOwnershipStatus)
            .canRequestRestoreAuto
    }

    func markFanControlDraftPending() {
        fanControlApplyState = fanControlSessionController.draftPendingApplyState(
            currentDraft: currentFanControlDraft,
            selectedMode: selectedMode,
            controlMode: controlState.mode,
            applyState: fanControlApplyState
        )
    }

    func applyPendingFanControl() {
        Task { _ = await applyCurrentModeSelection() }
    }

    @discardableResult
    func applyCurrentModeSelection() async -> FanControlApplyResult {
        if selectedMode == .auto {
            await restoreAutoNow()
            if case .failed(let message) = fanControlApplyState {
                return .failed(message: message)
            }
            return selectedMode == .auto && controlState.mode == .auto ? .applied : .superseded
        }

        if usePerFanFixedRPM, let fans = snapshot?.fans {
            ensureFixedFanTargets(for: fans)
        }
        let manualOperation = fanControlSessionController.beginManualOperation(
            currentSessionExpiresAt: manualSessionExpiresAt
        )
        let operation = manualOperation.operation
        let draft = currentFanControlDraft
        let mode = fanMode(for: draft)

        await refreshManualControlPreflight()
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        if let blockedReason = manualFanControlBlockedReason {
            lastError = "Manual fan control blocked: \(blockedReason)"
            fanControlApplyState = .blocked(reason: blockedReason)
            await syncState()
            guard manualFanControlOperationIsCurrent(operation) else {
                return .superseded
            }
            return .blocked(reason: blockedReason)
        }

        fanControlApplyState = .applying
        lastError = nil
        let provisionalSessionExpiresAt = fanControlSessionController.registerManualApply(
            manualOperation,
            draft: draft,
            mode: mode
        )
        manualSessionExpiresAt = provisionalSessionExpiresAt

        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        await coordinator.setFixedFanTargets(fixedFanTargetMap(for: draft))
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        await coordinator.setFanOverrides(draft.usePerFanOverrides ? draft.fanOverrides : [])
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        await coordinator.setMode(mode)
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        fanControlSessionController.markCoordinatorConfigured(operation)

        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        // A successful hardware poll is necessary but not sufficient to commit
        // the draft or its run limit. The fresh daemon ownership read below is
        // the final Apply boundary.
        await pollingController.freshPollOnce { [weak self] pollingOperation in
            await self?.performPollOnce(
                operation: pollingOperation,
                reconcileManualApply: false
            )
        }
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        if let lastError {
            restorePreviousManualDeadline(for: manualOperation)
            fanControlApplyState = .failed(message: lastError)
            return .failed(message: lastError)
        }
        do {
            let confirmedOwnership = try await coordinator.confirmCurrentManualOwnership()
            guard manualFanControlOperationIsCurrent(operation) else {
                return .superseded
            }
            fanControlOwnershipStatus = confirmedOwnership
            fanControlOwnershipStatusError = nil
        } catch {
            guard manualFanControlOperationIsCurrent(operation) else {
                return .superseded
            }
            let message = "Manual fan control could not be confirmed after Apply: \(error.localizedDescription)"
            rejectUnconfirmedManualApply(
                manualOperation,
                provisionalSessionExpiresAt: provisionalSessionExpiresAt
            )
            lastError = message
            fanControlOwnershipStatus = nil
            fanControlOwnershipStatusError = error.localizedDescription
            fanControlApplyState = .failed(message: message)
            return .failed(message: message)
        }
        guard controlState.mode == mode, controlState.manualControlActive else {
            let message = "Manual fan control could not be confirmed after Apply."
            rejectUnconfirmedManualApply(
                manualOperation,
                provisionalSessionExpiresAt: provisionalSessionExpiresAt
            )
            lastError = message
            fanControlApplyState = .failed(message: message)
            return .failed(message: message)
        }
        reconcileManualApplyAttemptAfterSuccessfulPoll()
        return .applied
    }

    func restoreAutoNow() async {
        let generation = beginAutoRestoreOperation()
        await performAutoRestore(generation: generation)
    }

    private func performAutoRestore(generation: FanControlSessionOperation) async {
        guard fanControlOperationIsCurrent(generation) else { return }
        await coordinator.setMode(
            .auto,
            unreadableJournalRecoveryAuthority: .explicitOperator
        )
        guard fanControlOperationIsCurrent(generation) else { return }

        // Auto is a safety-priority operation. Do not coalesce it behind an
        // in-flight manual poll: invalidate that poll's publication token and
        // start a concurrent Auto tick so the daemon can preempt at the next
        // physical fan boundary.
        pollingController.supersedeActivePoll()
        await pollOnce()
        guard fanControlOperationIsCurrent(generation) else { return }
        // The coordinator's protocol-v2 full-Auto transaction routes through
        // AgentControlService in the daemon and clears the lease atomically.
        // Refresh visibility only; never issue a second lease-clear restore.
        await refreshAgentControlStatus()
        guard fanControlOperationIsCurrent(generation) else { return }
        if let lastError {
            fanControlApplyState = .failed(message: lastError)
            await notifyAutoRestoreFailure(lastError)
        } else if controlState.mode != .auto || controlState.manualControlActive {
            let message = "Auto restore could not be confirmed."
            lastError = message
            fanControlApplyState = .failed(message: message)
            await notifyAutoRestoreFailure(message)
        } else {
            recordAutoRestorationApplied()
        }
    }

    func saveCurrentProfile(name: String) {
        guard let result = saveCurrentProfileAs(name: name, confirmOverwrite: false) else { return }
        if case .overwriteConfirmationRequired(let existing, _) = result {
            lastError = "Confirm before replacing the saved profile \(existing.name)."
        }
    }

    @discardableResult
    func saveCurrentProfileAs(
        name: String,
        confirmOverwrite: Bool
    ) -> CurveProfileSaveResult? {
        guard let result = CurveProfileSavePolicy.saveAs(
            name: name,
            draft: currentCurveProfileDraft,
            existingProfiles: savedProfiles,
            confirmOverwrite: confirmOverwrite
        ) else { return nil }

        switch result {
        case .created(let profile):
            let proposedProfiles = savedProfiles + [profile]
            guard persistProfiles(proposedProfiles) else {
                return .persistenceFailed(message: profilePersistenceErrorMessage)
            }
            savedProfiles = proposedProfiles
            selectedCurveProfileID = profile.id
        case .updated(let profile):
            guard let index = savedProfiles.firstIndex(where: { $0.id == profile.id }) else {
                return nil
            }
            var proposedProfiles = savedProfiles
            proposedProfiles[index] = profile
            guard persistProfiles(proposedProfiles) else {
                return .persistenceFailed(message: profilePersistenceErrorMessage)
            }
            savedProfiles = proposedProfiles
            selectedCurveProfileID = profile.id
        case .overwriteConfirmationRequired:
            break
        case .persistenceFailed:
            preconditionFailure("CurveProfileSavePolicy never emits persistence results.")
        }
        return result
    }

    @discardableResult
    func updateSelectedCurveProfile() -> Bool {
        let selected = selectedCurveProfileID.flatMap { selectedID in
            savedProfiles.first { $0.id == selectedID }
        }
        guard case .updated(let profile)? = CurveProfileSavePolicy.update(
            selectedProfile: selected,
            draft: currentCurveProfileDraft
        ), let index = savedProfiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }

        var proposedProfiles = savedProfiles
        proposedProfiles[index] = profile
        guard persistProfiles(proposedProfiles) else { return false }
        savedProfiles = proposedProfiles
        selectedCurveProfileID = profile.id
        return true
    }

    func loadProfile(_ profile: CurveProfile) {
        curveStartTemp = profile.startTemp
        curveStartRPM = Double(profile.startRPM)
        curveMidTemp = profile.midTemp
        curveMidRPM = Double(profile.midRPM)
        curveMaxTemp = profile.maxTemp
        curveMaxRPM = Double(profile.maxRPM)
        selectedSensorID = profile.sensorID
        fanOverrides = profile.fanOverrides
        usePerFanOverrides = !profile.fanOverrides.isEmpty
        if let fans = snapshot?.fans, usePerFanOverrides {
            ensureFanOverrides(for: fans)
        }
        markFanControlDraftPending()
    }

    @discardableResult
    func selectCurveProfile(id profileID: CurveProfile.ID?) -> Bool {
        guard let profileID else {
            selectedCurveProfileID = nil
            return true
        }
        guard let profile = savedProfiles.first(where: { $0.id == profileID }) else {
            return false
        }
        selectedCurveProfileID = profileID
        selectedMode = .curve
        loadProfile(profile)
        return true
    }

    func loadDeveloperPreset(_ preset: DeveloperFanPreset) {
        selectedCurveProfileID = nil
        selectedMode = .curve
        curveStartTemp = preset.startTemperatureCelsius
        curveMidTemp = preset.midTemperatureCelsius
        curveMaxTemp = preset.maxTemperatureCelsius
        curveStartRPM = Double(rpm(forPercent: preset.startRPMPercent))
        curveMidRPM = Double(rpm(forPercent: preset.midRPMPercent))
        curveMaxRPM = Double(rpm(forPercent: preset.maxRPMPercent))
        if selectedSensorID == nil {
            selectedSensorID = selectedSensor?.id
        }
        usePerFanOverrides = false
        fanOverrides = []
        curveDefaultsSynced = true
        markFanControlDraftPending()
    }

    @discardableResult
    func deleteProfile(_ profile: CurveProfile) -> Bool {
        let proposedProfiles = savedProfiles.filter { $0.id != profile.id }
        guard persistProfiles(proposedProfiles) else { return false }
        savedProfiles = proposedProfiles
        if selectedCurveProfileID == profile.id {
            selectedCurveProfileID = nil
        }
        return true
    }

    private var profilePersistenceErrorMessage: String {
        curveProfilePersistenceError ?? "Failed to save profiles."
    }

    @discardableResult
    private func persistProfiles(_ profiles: [CurveProfile]) -> Bool {
        do {
            try profileStore.saveThrowing(profiles)
            curveProfileRecoveryMessage = nil
            if lastError == curveProfilePersistenceError {
                lastError = nil
            }
            curveProfilePersistenceError = nil
            return true
        } catch {
            let message = "Failed to save profiles: \(error.localizedDescription)"
            curveProfilePersistenceError = message
            lastError = message
            return false
        }
    }

    func targetRPMPreview(for fan: Fan) -> Int? {
        guard fan.controllable else { return nil }
        switch selectedMode {
        case .auto:
            return nil
        case .fixed:
            if perFanFixedRPMApplies {
                return fixedFanTargetRPM(for: fan)
            }
            return FanCurve.clamp(Int(fixedRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
        case .curve:
            guard let sensor = selectedSensor else { return nil }
            return FanCurveTargetResolver.targetRPM(
                baseCurve: currentCurve(),
                fan: fan,
                temperature: sensor.celsius,
                overrides: usePerFanOverrides ? fanOverrides : []
            )
        }
    }

    func appliedTargetRPM(for fan: Fan) -> Int? {
        let targetRPM = fan.targetRPM ?? (controlState.manualControlActive ? controlState.lastAppliedRPM[fan.id] : nil)
        return targetRPM.map { FanCurve.clamp($0, fan.minimumRPM, fan.maximumRPM) }
    }

    func draftTargetRPMPreview(for fan: Fan) -> Int? {
        guard selectedMode != .auto, hasPendingFanControlChanges else { return nil }
        let draftTargetRPM = targetRPMPreview(for: fan)
        return draftTargetRPM == appliedTargetRPM(for: fan) ? nil : draftTargetRPM
    }

    private func publishTelemetrySession() {
        assignIfChanged(\.telemetryOverviewSummary, telemetrySession.overviewSummary)
        assignIfChanged(\.compactTelemetryOverviewSummary, telemetrySession.compactSummary)
        assignIfChanged(\.recentTelemetryTrendSummary, telemetrySession.recentTrendSummary)
    }

    func ensureFixedFanTargets(for fans: [Fan]) {
        let controllableFans = fans.filter(\.controllable)
        let baseRatio = fixedRPMBaseRangeRatio(for: fixedRPMBaseBounds(for: controllableFans))
        let existingByFanID = fixedFanTargets.reduce(into: [Int: FixedFanTarget]()) { targetsByID, target in
            targetsByID[target.fanID] = target
        }
        let nextTargets = controllableFans.map { fan in
            if let existing = existingByFanID[fan.id] {
                return FixedFanTarget(
                    fanID: fan.id,
                    rpm: FanCurve.clamp(existing.rpm, fan.minimumRPM, fan.maximumRPM)
                )
            }
            return defaultFixedFanTarget(for: fan, baseRatio: baseRatio)
        }
        guard nextTargets != fixedFanTargets else { return }
        fixedFanTargets = nextTargets
        persistAppPreferences()
    }

    func fixedFanTarget(for fanID: Int) -> FixedFanTarget? {
        fixedFanTargets.first { $0.fanID == fanID }
    }

    func fixedFanTargetRPM(for fan: Fan) -> Int {
        fixedFanTarget(for: fan.id)?.rpm ?? defaultFixedFanTargetRPM(for: fan)
    }

    func fixedFanSliderRPM(for fan: Fan) -> Int {
        fixedFanTargetRPM(for: fan)
    }

    func fixedFanTargetPercent(for fan: Fan) -> Int {
        rpmPercent(fixedFanTargetRPM(for: fan), for: fan)
    }

    func setFixedFanRPM(_ rpm: Int, for fan: Fan, persist: Bool = true) {
        updateFixedFanTarget(for: fan) { target in
            target.rpm = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
        if persist {
            persistAppPreferences()
        }
    }

    func commitFixedFanTargetsAndApply() {
        persistAppPreferences()
        markFanControlDraftPending()
    }

    func commitFixedFanTargetsAndApplyNow() async {
        persistAppPreferences()
        markFanControlDraftPending()
    }

    func ensureFanOverrides(for fans: [Fan]) {
        let existingByFanID = fanOverrides.reduce(into: [Int: FanCurveOverride]()) { overridesByID, override in
            overridesByID[override.fanID] = override
        }
        fanOverrides = fans.filter(\.controllable).map { fan in
            existingByFanID[fan.id] ?? defaultFanOverride(for: fan)
        }
    }

    func fanOverride(for fanID: Int) -> FanCurveOverride? {
        fanOverrides.last { $0.fanID == fanID }
    }

    func setOverrideStartRPM(_ rpm: Int, for fan: Fan) {
        guard fan.controllable else { return }
        updateFanOverride(for: fan) { override in
            override.startRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func setOverrideMidRPM(_ rpm: Int, for fan: Fan) {
        guard fan.controllable else { return }
        updateFanOverride(for: fan) { override in
            override.midRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func setOverrideMaxRPM(_ rpm: Int, for fan: Fan) {
        guard fan.controllable else { return }
        updateFanOverride(for: fan) { override in
            override.maxRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    var selectedSensor: TemperatureSensor? {
        curveTemperatureSelection.curveMetric
    }

    var effectiveSelectedSensorID: String? {
        selectedSensor?.id
    }

    var curveTemperatureSelection: TemperatureSensorSelection {
        TemperatureSensorSelection.resolve(
            sensors: snapshot?.temperatureSensors ?? [],
            selectedSensorID: userSelectedSensorID
        )
    }

    private var resolvedCurveSensorID: String? {
        guard snapshot?.temperatureSensors.isEmpty == false else { return selectedSensorID }
        return effectiveSelectedSensorID
    }

    var temperatureAttentionSummary: String? {
        guard thermalPressure.menuSummary == nil else { return nil }
        guard let sensor = snapshot?.highestTemperature else { return nil }
        return sensor.celsius >= Self.highTemperatureAttentionThreshold ? "High temp" : nil
    }

    var fanWriteBlockedWhileHotSummary: String? {
        guard helperWritePathBlockedSummary != nil,
              let sensor = snapshot?.highestTemperature,
              sensor.celsius >= Self.highTemperatureAttentionThreshold else {
            return nil
        }
        return "High temp · fan writes blocked"
    }

    var fanWriteBlockedWhileHotRecoverySuggestion: String? {
        guard fanWriteBlockedWhileHotSummary != nil else { return nil }
        switch controlState.mode {
        case .auto:
            return "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds."
        case .fixedRPM, .temperatureCurve:
            return "Reduce heavy work now. Repair/Reinstall Helper; Vifty will retry \(manualModeName) when the daemon responds. Use \(autoRestoreActionTitle) to stop retries."
        }
    }

    var visibleLastError: String? {
        guard let lastError else { return nil }
        guard !lastErrorIsCoveredByHelperRecovery(lastError) else { return nil }
        return lastError
    }

    private var resolvedMenuBarPresentation: MenuBarPresentation {
        let currentDate = now()
        let lease = agentControlStatus?.activeLease
        return MenuBarPresentationProvider.resolve(MenuBarPresentationInput(
            displayMode: menuBarDisplayMode,
            customFields: menuBarCustomFields,
            snapshotIsAvailable: snapshot != nil,
            selectedTemperature: selectedSensor ?? snapshot?.highestTemperature,
            selectedTemperatureLabel: curveTemperatureSelection.curveMetricLabel,
            fans: snapshot?.fans ?? [],
            power: powerSnapshot,
            thermalPressure: thermalPressure,
            temperatureAttentionSummary: temperatureAttentionSummary,
            fanWriteBlockedWhileHotSummary: fanWriteBlockedWhileHotSummary,
            helperState: helperHealthState,
            hasCompletedHardwarePoll: hasCompletedHardwarePoll,
            daemonReachable: daemonReachable,
            daemonResponding: daemonResponding,
            lastErrorIsPresent: lastError != nil,
            agentCoolingMenuSummary: agentCoolingMenuSummary,
            agentStatusIsUnavailable: agentControlStatusError != nil,
            shouldPreferHelperRecoveryOverAgentStatusError: shouldPreferHelperRecoveryOverAgentStatusError,
            hasAgentLease: lease != nil,
            agentLeaseNeedsAttention: agentControlStatusError != nil
                || lease.map { !$0.isActive(at: currentDate) } == true,
            fanControlOwnershipStatus: fanControlOwnershipStatus,
            controlMode: controlState.mode,
            controlOwnershipNeedsAttention: controlOwnershipNeedsAttention,
            autoHardwareModeIsUncertain: !autoForcedModeFans.isEmpty
                || !autoUnknownModeFans.isEmpty
                || !autoMissingModeFans.isEmpty,
            codexUsageSnapshot: codexUsageSnapshot,
            codexUsageDisplayPreferences: codexUsageDisplayPreferences,
            currentDate: currentDate
        ))
    }

    private var menuBarPanelAttentionText: String? {
        resolvedMenuBarPresentation.panelAttentionText
    }

    var menuTitle: String {
        resolvedMenuBarPresentation.title
    }

    var menuPanelTitle: String {
        resolvedMenuBarPresentation.panelTitle
    }

    var menuBarLabelText: String {
        resolvedMenuBarPresentation.labelText
    }

    var menuBarStatusItemText: String? {
        resolvedMenuBarPresentation.statusItemText
    }

    var menuBarLabelNeedsTelemetryPrime: Bool {
        resolvedMenuBarPresentation.labelNeedsTelemetryPrime
    }

    var menuBarDisplaysCodexUsage: Bool {
        MenuBarPresentationProvider.displaysCodexUsage(
            menuBarDisplayMode,
            customFields: menuBarCustomFields
        )
    }

    var menuBarAllowsPlaceholderStatusItemText: Bool {
        resolvedMenuBarPresentation.allowsPlaceholderStatusItemText
    }

    func isMenuBarCustomFieldEnabled(_ field: MenuBarField) -> Bool {
        menuBarCustomFields.contains(field)
    }

    func setMenuBarCustomField(_ field: MenuBarField, enabled: Bool) {
        var fields = menuBarCustomFields
        if enabled {
            guard !fields.contains(field) else { return }
            fields.append(field)
        } else {
            fields.removeAll { $0 == field }
            guard !fields.isEmpty else { return }
        }
        menuBarCustomFields = MenuBarField.normalized(fields)
    }

    var codexUsageSummary: String {
        CodexUsageFormatter.summaryText(
            for: codexUsageSnapshot,
            options: codexUsageDisplayPreferences,
            now: now
        )
    }

    var codexUsageDetailSummary: String? {
        CodexUsageFormatter.detailText(
            for: codexUsageSnapshot,
            options: codexUsageDisplayPreferences
        )
    }

    var codexUsageDetailLines: [String] {
        CodexUsageFormatter.detailLines(
            for: codexUsageSnapshot,
            options: codexUsageDisplayPreferences,
            now: now
        )
    }

    var menuBarFanOwnerText: String {
        resolvedMenuBarPresentation.fanOwnerText
    }

    var menuBarLabelUsesFanIcon: Bool {
        resolvedMenuBarPresentation.labelUsesFanIcon
    }

    private func persistAppPreferences() {
        preferencesStore.save(AppPreferences(
            menuBarDisplayMode: menuBarDisplayMode,
            menuBarCustomFields: menuBarCustomFields,
            startupMode: startupMode,
            textScale: textScale,
            notificationSettings: notificationSettings,
            usePerFanFixedRPM: usePerFanFixedRPM,
            fixedFanTargets: fixedFanTargets,
            codexUsageDisplayPreferences: codexUsageDisplayPreferences
        ))
    }

    private var codexUsageDisplayPreferences: CodexUsageDisplayPreferences {
        CodexUsageDisplayPreferences(
            displayStyle: codexUsageDisplayStyle,
            metricMode: codexUsageMetricMode,
            resetMode: codexUsageResetMode,
            refreshCadence: codexUsageRefreshCadence
        )
    }

    private func codexUsageDisplayPreferenceDidChange() {
        persistAppPreferences()
        if menuBarDisplaysCodexUsage {
            refreshMenuBarStatusItemIfNeeded()
        }
    }

    private var helperWritePathBlockedSummary: String? {
        helperHealthState.writePathBlockedSummary
    }

    private func lastErrorIsCoveredByHelperRecovery(_ error: String) -> Bool {
        guard helperWritePathBlockedSummary != nil else { return false }
        return error.lowercased().hasPrefix("manual fan control blocked:")
    }

    private var shouldPreferHelperRecoveryOverAgentStatusError: Bool {
        agentControlStatus?.activeLease == nil
            && agentControlStatusError != nil
            && helperWritePathBlockedSummary != nil
    }

    var agentCoolingMenuSummary: String? {
        guard let lease = agentControlStatus?.activeLease else {
            if shouldPreferHelperRecoveryOverAgentStatusError { return nil }
            return agentControlStatusError == nil ? nil : "Agent status unavailable"
        }
        if agentControlStatusError != nil {
            return "Agent status warning"
        }
        return lease.isActive(at: now()) ? "Agent cooling" : "Agent restore pending"
    }

    var agentCoolingPanelTitle: String {
        if agentControlStatusError != nil {
            if shouldPreferHelperRecoveryOverAgentStatusError { return "Agent cooling unavailable" }
            return agentControlStatus?.activeLease == nil ? "Agent status unavailable" : "Agent status warning"
        }
        return agentCoolingNeedsAttention ? "Agent restore pending" : "Agent cooling active"
    }

    var agentCoolingSummary: String? {
        guard let lease = agentControlStatus?.activeLease else {
            if shouldPreferHelperRecoveryOverAgentStatusError { return nil }
            guard agentControlStatusError != nil else { return nil }
            return "Agent cooling status unavailable; repair helper before requesting cooling."
        }

        let state = if lease.isActive(at: now()) {
            "Agent \(lease.request.workload.displayName) cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))"
        } else {
            "Agent \(lease.request.workload.displayName) cooling expired; waiting for Auto restore"
        }

        let targets = lease.targetRPMByFanID
            .sorted { $0.key < $1.key }
            .map { "F\($0.key) \($0.value) RPM" }
            .joined(separator: ", ")

        let baseSummary = targets.isEmpty ? state : "\(state) · \(targets)"
        if agentControlStatusError != nil {
            return "\(baseSummary) · status refresh failed; do not start another workload"
        }
        return baseSummary
    }

    var agentCoolingRecoverySuggestion: String? {
        if agentControlStatusError != nil {
            if shouldPreferHelperRecoveryOverAgentStatusError { return nil }
            guard agentControlStatus?.activeLease != nil else {
                return "Repair Helper before requesting agent cooling."
            }
            return "Do not start another workload; use Auto to restore cooling, then check viftyctl status/audit after helper repair."
        }
        guard let lease = agentControlStatus?.activeLease, !lease.isActive(at: now()) else {
            return nil
        }
        return "Use Auto to restore daemon control before starting another workload."
    }

    var agentCoolingRestoreActionAvailable: Bool {
        agentControlStatus?.activeLease != nil
    }

    var autoRestoreActionTitle: String {
        helperWritePathBlockedSummary == nil ? "Auto" : "Request Auto"
    }

    var autoRestoreActionHelp: String {
        if helperWritePathBlockedSummary == nil {
            return "Restore Auto"
        }
        return "Request Auto restore; the write cannot be confirmed until the helper responds"
    }

    var modeSelectionActionTitle: String {
        modeSelectionActionRestoresAuto ? autoRestoreActionTitle : "Apply"
    }

    var modeSelectionActionHelp: String {
        modeSelectionActionRestoresAuto
            ? autoRestoreActionHelp
            : (manualFanControlBlockedReason ?? "Apply selected fan mode")
    }

    var modeSelectionActionRestoresAuto: Bool {
        selectedMode == .auto || manualControlAttentionSummary != nil
    }

    var modeSelectionActionDisabled: Bool {
        !modeSelectionActionRestoresAuto && !manualFanControlAvailable
    }

    var agentCoolingRestoreActionTitle: String {
        autoRestoreActionTitle
    }

    var agentCoolingRestoreActionHelp: String {
        if helperWritePathBlockedSummary == nil {
            return "Restore Auto before starting another agent workload"
        }
        return autoRestoreActionHelp
    }

    var agentCoolingNeedsAttention: Bool {
        if agentControlStatusError != nil {
            if shouldPreferHelperRecoveryOverAgentStatusError { return false }
            return true
        }
        guard let lease = agentControlStatus?.activeLease else { return false }
        return !lease.isActive(at: now())
    }

    var controlOwnershipSummary: String {
        if let lease = agentControlStatus?.activeLease {
            let statusWarning = agentControlStatusError == nil ? "" : " · status refresh failed"
            if lease.isActive(at: now()) {
                return "Agent \(lease.request.workload.displayName) owns cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))\(statusWarning)"
            }
            return "Agent \(lease.request.workload.displayName) lease expired; restore Auto to clear daemon control\(statusWarning)"
        }

        if let manualHelperWriteBlockedSummary {
            return manualHelperWriteBlockedSummary
        }

        if controlState.mode == .auto, helperWritePathBlockedSummary != nil {
            return autoControlOwnershipSummary
        }

        if agentControlStatusError != nil {
            return "Agent control status unavailable; fan ownership uncertain"
        }

        switch controlState.mode {
        case .auto:
            return autoControlOwnershipSummary
        case .fixedRPM(let rpm):
            if let manualControlDriftSummary {
                return manualControlDriftSummary
            }
            return "Vifty Fixed owns fan targets · \(fixedModeTargetSummary(fallbackRPM: rpm)) · \(manualRunOwnershipSummary)"
        case .temperatureCurve:
            if let manualControlDriftSummary {
                return manualControlDriftSummary
            }
            if let sensor = selectedSensor {
                return "Vifty Curve owns fan targets · \(sensor.name) · \(manualRunOwnershipSummary)"
            }
            return "Vifty Curve owns fan targets · \(manualRunOwnershipSummary)"
        }
    }

    var compactControlOwnershipSummary: String {
        if let lease = agentControlStatus?.activeLease {
            if lease.isActive(at: now()) {
                return "Owner: Agent until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Owner: Agent restore pending"
        }

        if let manualHelperWriteBlockedSummary {
            return manualHelperWriteBlockedSummary
        }

        if controlState.mode == .auto, helperWritePathBlockedSummary != nil {
            return "Owner: Mac?"
        }

        if agentControlStatusError != nil {
            return "Owner: uncertain"
        }

        switch controlState.mode {
        case .auto:
            return "Owner: \(menuBarFanOwnerText)"
        case .fixedRPM:
            return "Owner: Vifty Fixed"
        case .temperatureCurve:
            return "Owner: Vifty Curve"
        }
    }

    var controlOwnershipNeedsAttention: Bool {
        if let lease = agentControlStatus?.activeLease {
            return agentControlStatusError != nil || !lease.isActive(at: now())
        }
        if agentControlStatusError != nil {
            return true
        }

        guard controlState.mode == .auto else {
            return manualHelperWriteBlockedSummary != nil || manualControlDriftSummary != nil
        }
        guard let fans = snapshot?.fans, !fans.isEmpty else {
            return hasCompletedHardwarePoll || daemonReachable
        }
        return !autoSystemModeFans.isEmpty
            || !autoForcedModeFans.isEmpty
            || !autoUnknownModeFans.isEmpty
            || !autoMissingModeFans.isEmpty
            || helperWritePathBlockedSummary != nil
    }

    var helperHealthState: HelperHealthState {
        HelperHealthPresentation.resolve(HelperHealthPresentationInput(
            hardwareIsSupported: snapshot.map { $0.isAppleSilicon && $0.isMacBookPro },
            hasCompletedHardwarePoll: hasCompletedHardwarePoll,
            daemonReachable: daemonReachable,
            daemonResponding: daemonResponding,
            fanCount: snapshot?.fans.count ?? 0,
            hasControllableFan: snapshot?.fans.contains(where: \.controllable) == true,
            lastError: lastError
        ))
    }

    var helperHealthSummary: String {
        helperHealthState.summary
    }

    var helperHealthMenuSummary: String {
        helperHealthState.menuSummary
    }

    var helperHealthNeedsAttention: Bool {
        helperHealthState.needsAttention
    }

    var helperRepairActionAvailable: Bool {
        helperHealthState.repairActionAvailable
    }

    var helperRecoverySuggestion: String? {
        helperHealthState.recoverySuggestion
    }

    var helperInstallRuntimeContext: String? {
        helperHealthState.installRuntimeContext
    }

    var helperFailureNotificationBody: String {
        fanWriteBlockedWhileHotRecoverySuggestion
            ?? helperRecoverySuggestion
            ?? "Repair or approve the fan helper before requesting fan control."
    }

    var helperFailureNotificationTitle: String {
        fanWriteBlockedWhileHotSummary == nil
            ? "Vifty fan helper needs attention"
            : "Vifty fan writes are blocked while hot"
    }

    var helperSupportEvidenceContext: HelperSupportEvidenceContext {
        var lines: [String] = [
            "selectedMode=\(selectedMode.rawValue)",
            "manualRun=\(manualRunLimit.label)",
            "daemon=reachable=\(daemonReachable) responding=\(daemonResponding)",
            "helper=\(helperHealthSummary)",
            "controlOwner=\(controlOwnershipSummary)"
        ]

        if let helperInstallRuntimeContext {
            lines.append("helperRuntime=\(helperInstallRuntimeContext)")
        }
        if let helperRecoverySuggestion {
            lines.append("helperRecovery=\(helperRecoverySuggestion)")
        }
        if let fanWriteBlockedWhileHotSummary {
            lines.append("hotFanWrites=\(fanWriteBlockedWhileHotSummary)")
        }
        if let fanWriteBlockedWhileHotRecoverySuggestion {
            lines.append("hotRecovery=\(fanWriteBlockedWhileHotRecoverySuggestion)")
        }
        if let sensor = selectedSensor ?? snapshot?.highestTemperature {
            lines.append("selectedTemperature=\(sensor.name) \(String(format: "%.1f", sensor.celsius)) C")
        }
        if let fans = snapshot?.fans, !fans.isEmpty {
            let fanSummary = fans
                .map { "\($0.name) \($0.currentRPM) RPM (\($0.percentage)%)" }
                .joined(separator: "; ")
            lines.append("fans=\(fanSummary)")
        }
        if let agentCoolingSummary {
            lines.append("agentCooling=\(agentCoolingSummary)")
        }
        if let lastError {
            lines.append("lastError=\(lastError)")
        }

        return HelperSupportEvidenceContext(lines: lines)
    }

    var helperMenuRecoverySuggestion: String? {
        if fanWriteBlockedWhileHotSummary != nil {
            return nil
        }
        return helperHealthState.menuRecoverySuggestion
    }

    var manualFanControlAvailable: Bool {
        manualFanControlBlockedReason == nil
    }

    var manualFanControlBlockedReason: String? {
        guard let snapshot else {
            return daemonResponding
                ? "Waiting for fan telemetry before manual fan control."
                : "Install or repair the fan helper before manual fan control."
        }
        guard snapshot.isAppleSilicon, snapshot.isMacBookPro else {
            return "Unsupported hardware. Manual fan control stays blocked."
        }
        if helperHealthState == .runtimeMismatch {
            return "Repair/Reinstall Helper before manual fan control; the installed helper does not match this Vifty app."
        }
        guard daemonResponding else {
            return daemonReachable
                ? "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked."
                : "Install or repair the fan helper before manual fan control."
        }
        if let lease = agentControlStatus?.activeLease {
            if lease.isActive(at: now()) {
                return "Agent \(lease.request.workload.displayName) cooling owns fan control; restore Auto before manual fan control."
            }
            return "Agent cooling restore is pending; restore Auto before manual fan control."
        }
        if agentControlStatusError != nil {
            return "Agent control status is unavailable; repair helper before manual fan control."
        }
        guard !snapshot.fans.isEmpty else {
            return "Fan data is unavailable. Manual fan control stays blocked."
        }
        guard snapshot.fans.contains(where: \.controllable) else {
            return "No controllable fans are available. Manual fan control stays blocked."
        }
        guard !snapshot.temperatureSensors.isEmpty else {
            return "Temperature sensors are unavailable. Manual fan control stays blocked."
        }
        let confirmedOwnership = FanControlOwnershipPresentation.resolve(fanControlOwnershipStatus)
        switch confirmedOwnership.owner {
        case .macOS, .viftyManual:
            break
        case .agent:
            return "Agent cooling owns fan control; restore Auto before manual fan control."
        case .recovery:
            return "Fan recovery is pending; restore Auto before manual fan control."
        case .mixedOrUnknown:
            return "Fan ownership is unconfirmed; manual fan control stays blocked."
        }
        return nil
    }

    var manualControlAttentionSummary: String? {
        guard controlState.mode != .auto,
              helperWritePathBlockedSummary != nil else {
            return nil
        }
        return "\(manualModeName) request pending · fan writes blocked"
    }

    var manualControlAttentionRecoverySuggestion: String? {
        guard manualControlAttentionSummary != nil else { return nil }
        return "Vifty will retry \(manualModeName) when the helper responds. Use \(autoRestoreActionTitle) to stop retries; copy support evidence if repair does not clear it."
    }

    private var manualHelperWriteBlockedSummary: String? {
        guard controlState.mode != .auto,
              let helperWritePathBlockedSummary else {
            return nil
        }
        return "\(helperWritePathBlockedSummary) · Vifty will retry \(manualModeName) when the helper responds"
    }

    private var manualModeName: String {
        switch controlState.mode {
        case .auto:
            return "manual control"
        case .fixedRPM:
            return "Fixed"
        case .temperatureCurve:
            return "Curve"
        }
    }

    private var manualRunOwnershipSummary: String {
        let runLimitSummary = manualSessionExpiresAt.map {
            "until \($0.formatted(date: .omitted, time: .shortened))"
        } ?? "until changed"
        return "\(runLimitSummary); reasserts if macOS drifts"
    }

    private var autoControlOwnershipSummary: String {
        guard let fans = snapshot?.fans, !fans.isEmpty else {
            return daemonReachable
                ? "Auto selected · fan hardware state unavailable"
                : "Auto selected · fan writes blocked until helper responds"
        }

        if let helperWritePathBlockedSummary {
            return helperWritePathBlockedSummary
        }
        if !autoSystemModeFans.isEmpty {
            return "macOS System/protected owns fan control · \(fanIDList(autoSystemModeFans))"
        }
        if !autoForcedModeFans.isEmpty {
            return "Hardware reports Forced mode while Vifty is Auto · \(fanIDList(autoForcedModeFans))"
        }
        if !autoUnknownModeFans.isEmpty {
            return "Auto selected · unknown hardware mode on \(fanIDList(autoUnknownModeFans))"
        }
        if !autoMissingModeFans.isEmpty {
            return "Auto selected · hardware mode unavailable on \(fanIDList(autoMissingModeFans))"
        }
        return "macOS Auto owns fan control"
    }

    private var manualControlDriftSummary: String? {
        guard controlState.mode != .auto,
              let fans = snapshot?.fans.filter(\.controllable),
              !fans.isEmpty else {
            return nil
        }

        let reclaimed = fans.filter { fan in
            guard let mode = fan.hardwareMode else { return false }
            return mode != .forced
        }
        if !reclaimed.isEmpty {
            let modes = reclaimed.reduce(into: [String]()) { names, fan in
                guard let name = fan.hardwareMode?.displayName, !names.contains(name) else { return }
                names.append(name)
            }.joined(separator: "/")
            let modeLabel = modes.isEmpty ? "non-forced mode" : modes
            return "Hardware reports \(modeLabel) while Vifty manual is selected; Vifty will reassert · \(fanIDList(reclaimed))"
        }

        let drifted = manualTargetDriftAttentionFans
        if !drifted.isEmpty {
            return "Hardware fan target drift detected; Vifty will reassert · \(fanIDList(drifted))"
        }

        let unconfirmedResponse = fans.filter { fan in
            guard fan.targetRPM == nil,
                  manualResponseAttentionIsWarranted,
                  let expectedRPM = expectedManualTargetRPM(for: fan) else {
                return false
            }
            return expectedRPM - fan.currentRPM >= Self.manualResponseRPMGapThreshold
        }
        guard !unconfirmedResponse.isEmpty else { return nil }
        return "Manual fan response not confirmed; current RPM is still below requested target · \(fanIDList(unconfirmedResponse))"
    }

    private var currentManualTargetDriftFans: [Fan] {
        guard controlState.mode != .auto,
              let fans = snapshot?.fans.filter(\.controllable),
              !fans.isEmpty else {
            return []
        }

        return fans.filter { fan in
            guard !manualTargetSettlingFanIDs.contains(fan.id),
                  fan.hardwareMode == .forced,
                  let targetRPM = fan.targetRPM,
                  let expectedRPM = expectedManualTargetRPM(for: fan) else {
                return false
            }
            return abs(targetRPM - expectedRPM) >= Self.manualTargetDriftRPMThreshold
        }
    }

    private var manualTargetDriftAttentionFans: [Fan] {
        let drifted = currentManualTargetDriftFans
        if !hasCompletedHardwarePoll {
            return drifted
        }
        return drifted.filter { fan in
            (manualTargetDriftSampleCounts[fan.id] ?? 0) >= Self.manualTargetDriftAttentionSampleCount
        }
    }

    private func updateManualTargetDriftStability() {
        let driftedIDs = Set(currentManualTargetDriftFans.map(\.id))
        guard !driftedIDs.isEmpty else {
            manualTargetDriftSampleCounts = [:]
            return
        }

        manualTargetDriftSampleCounts = driftedIDs.reduce(into: [:]) { countsByFanID, fanID in
            let count = (manualTargetDriftSampleCounts[fanID] ?? 0) + 1
            countsByFanID[fanID] = min(count, Self.manualTargetDriftAttentionSampleCount)
        }
    }

    private var manualResponseAttentionIsWarranted: Bool {
        if thermalPressure == .serious || thermalPressure == .critical {
            return true
        }
        guard let sensor = snapshot?.highestTemperature else { return false }
        return sensor.celsius >= Self.highTemperatureAttentionThreshold
    }

    private func fixedModeTargetSummary(fallbackRPM: Int) -> String {
        guard perFanFixedRPMApplies else { return "\(fallbackRPM) RPM" }

        let controllableFans = snapshot?.fans.filter(\.controllable) ?? []
        if !controllableFans.isEmpty {
            return controllableFans.map { fan in
                let rpm = expectedManualTargetRPM(for: fan)
                    ?? FanCurve.clamp(fallbackRPM, fan.minimumRPM, fan.maximumRPM)
                return "\(fan.name) \(rpm) RPM"
            }
            .joined(separator: ", ")
        }

        let targets = fixedFanTargets.sorted { $0.fanID < $1.fanID }
        guard !targets.isEmpty else { return "per-fan RPM" }
        return targets
            .map { target in "F\(target.fanID) \(target.rpm) RPM" }
            .joined(separator: ", ")
    }

    private func expectedManualTargetRPM(for fan: Fan) -> Int? {
        if let lastAppliedRPM = controlState.lastAppliedRPM[fan.id] {
            return lastAppliedRPM
        }

        switch controlState.mode {
        case .auto:
            return nil
        case .fixedRPM(let rpm):
            if perFanFixedRPMApplies, let target = fixedFanTarget(for: fan.id)?.rpm {
                return FanCurve.clamp(target, fan.minimumRPM, fan.maximumRPM)
            }
            return FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        case .temperatureCurve(let curve):
            guard let snapshot,
                  let sensor = snapshot.temperatureSensors.first(where: { $0.id == (curve.sensorID ?? controlState.selectedSensorID) })
                    ?? selectedSensor else {
                return nil
            }
            return curve.targetRPM(
                for: sensor.celsius,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
        }
    }

    private var autoSystemModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { $0.hardwareMode == .system } ?? []
    }

    private var autoForcedModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { $0.hardwareMode == .forced } ?? []
    }

    private var autoUnknownModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { fan in
            if case .unknown = fan.hardwareMode {
                return true
            }
            return false
        } ?? []
    }

    private var autoMissingModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { $0.hardwareMode == nil } ?? []
    }

    private func fanIDList(_ fans: [Fan]) -> String {
        fans.map { "F\($0.id)" }.joined(separator: ", ")
    }

    var fanRange: ClosedRange<Double> {
        let bounds = fixedRPMBaseBounds
        return Double(bounds.minimumRPM)...Double(bounds.maximumRPM)
    }

    private func rpm(forPercent percent: Int) -> Int {
        let bounds = fixedRPMBaseBounds
        let span = bounds.maximumRPM - bounds.minimumRPM
        let rpm = bounds.minimumRPM + Int((Double(span) * Double(percent) / 100.0).rounded())
        return FanCurve.clamp(rpm, bounds.minimumRPM, bounds.maximumRPM)
    }

    private func currentCurve() -> FanCurve {
        FanCurve(sensorID: resolvedCurveSensorID, points: [
            CurvePoint(temperatureCelsius: curveStartTemp, rpm: Int(curveStartRPM.rounded())),
            CurvePoint(temperatureCelsius: curveMidTemp, rpm: Int(curveMidRPM.rounded())),
            CurvePoint(temperatureCelsius: curveMaxTemp, rpm: Int(curveMaxRPM.rounded()))
        ])
    }

    private func fixedFanTargetMap(for draft: FanControlDraft) -> [Int: Int] {
        guard draft.mode == .fixed, draft.usePerFanFixedRPM else { return [:] }
        if let fans = snapshot?.fans {
            guard fans.filter(\.controllable).count > 1 else { return [:] }
        } else {
            guard draft.fixedFanTargets.count > 1 else { return [:] }
        }
        return draft.fixedFanTargets.reduce(into: [Int: Int]()) { targetsByID, target in
            targetsByID[target.fanID] = target.rpm
        }
    }

    private var perFanFixedRPMApplies: Bool {
        guard usePerFanFixedRPM else { return false }
        if let fans = snapshot?.fans {
            return fans.filter(\.controllable).count > 1
        }
        return fixedFanTargets.count > 1
    }

    private func selectedFanMode() -> FanMode {
        fanMode(for: currentFanControlDraft)
    }

    private func fanMode(for draft: FanControlDraft) -> FanMode {
        fanControlSessionController.fanMode(for: draft)
    }

    func applyCurveOverrides() {
        markFanControlDraftPending()
    }

    private func restoreAutoIfManualSessionExpired() async -> FanControlSessionOperation? {
        guard fanControlSessionController.shouldRestoreExpiredManualSession(
            selectedMode: selectedMode,
            manualSessionExpiresAt: manualSessionExpiresAt
        ) else {
            return nil
        }

        let generation = beginAutoRestoreOperation()
        guard fanControlOperationIsCurrent(generation) else { return nil }
        await coordinator.setMode(.auto)
        guard fanControlOperationIsCurrent(generation) else { return nil }
        return generation
    }

    private func recordAutoRestorationApplied() {
        fanControlSessionController.recordAutoRestorationApplied(currentDraft: currentFanControlDraft)
        fanControlApplyState = .applied
    }

#if DEBUG
    func configureReviewFixtureAppliedFanControlDraft() {
        fanControlSessionController.recordAutoRestorationApplied(currentDraft: currentFanControlDraft)
        fanControlApplyState = .applied
    }
#endif

    private func beginAutoRestoreOperation() -> FanControlSessionOperation {
        let operation = fanControlSessionController.beginAutoOperation()
        fanControlApplyState = .applying
        lastError = nil
        selectedMode = .auto
        manualSessionExpiresAt = nil
        return operation
    }

    private func fanControlOperationIsCurrent(_ operation: FanControlSessionOperation) -> Bool {
        fanControlSessionController.isCurrent(operation)
    }

    private func manualFanControlOperationIsCurrent(_ operation: FanControlSessionOperation) -> Bool {
        fanControlSessionController.isCurrentManual(operation, selectedMode: selectedMode)
    }

    private func canCommitAutoRestoration(generation: FanControlSessionOperation) -> Bool {
        fanControlSessionController.canCommitAutoRestoration(
            operation: generation,
            selectedMode: selectedMode,
            controlState: controlState
        )
    }

    private func reconcileManualApplyAttemptAfterSuccessfulPoll() {
        guard let reconciliation = fanControlSessionController.reconcileManualApplyAfterSuccessfulPoll(
            operationSelectedMode: selectedMode,
            controlState: controlState,
            currentDraft: currentFanControlDraft
        ) else { return }
        manualSessionExpiresAt = reconciliation.manualSessionExpiresAt
        fanControlApplyState = reconciliation.applyState
    }

    private func restorePreviousManualDeadline(for operation: FanControlManualOperation) {
        // Use the operation's immutable capture: the polling path may have
        // advanced controller reconciliation state before a later check fails.
        manualSessionExpiresAt = operation.previousSessionExpiresAt
    }

    private func rejectUnconfirmedManualApply(
        _ operation: FanControlManualOperation,
        provisionalSessionExpiresAt: Date?
    ) {
        fanControlSessionController.rejectManualApply(operation.operation)
        // If this was the first finite Apply there is no previous deadline to
        // restore. Keep the provisional bound because the hardware transaction
        // completed before its final ownership read failed; never turn that
        // bounded user request into an indefinite manual session.
        manualSessionExpiresAt = operation.previousSessionExpiresAt
            ?? provisionalSessionExpiresAt
    }

    private func shouldPreserveManualIntent(afterTickFailure error: Error, attemptedMode: FanMode) -> Bool {
        guard attemptedMode != .auto else { return false }
        guard let viftyError = error as? ViftyError else { return true }

        switch viftyError {
        case .helperRejected, .smcUnavailable, .smcOpenFailed, .smcCallFailed, .smcKeyUnavailable, .smcWriteRejected:
            return true
        case .unsupportedHardware:
            return false
        case .noTemperatureSensors:
            return true
        case .noControllableFans:
            return true
        }
    }

    private func refreshAgentControlStatus() async {
        do {
            agentControlStatus = try await agentStatusReader()
            agentControlStatusError = nil
        } catch {
            agentControlStatusError = error.localizedDescription
        }
    }

    private func refreshFanControlOwnershipStatus() async {
        do {
            fanControlOwnershipStatus = try await coordinator.fanControlOwnershipStatus()
            fanControlOwnershipStatusError = nil
        } catch {
            fanControlOwnershipStatus = nil
            fanControlOwnershipStatusError = error.localizedDescription
        }
    }

    private func refreshManualControlPreflight() async {
        daemonResponding = await daemonPing()
        if let snapshot {
            daemonReachable = daemonResponding || !snapshot.fans.isEmpty
        } else {
            daemonReachable = daemonResponding
        }

        // A draft must never infer ownership from its selected mode or from
        // stale fan telemetry. Refresh the daemon's transaction status as part
        // of the same preflight that authorizes every manual Apply attempt.
        await refreshFanControlOwnershipStatus()

        guard agentControlStatus?.activeLease == nil || agentControlStatusError != nil else {
            return
        }

        do {
            guard let status = try await agentStatusReader() else { return }
            agentControlStatus = status
            agentControlStatusError = nil
        } catch {
            agentControlStatusError = error.localizedDescription
        }
    }

    private func syncCurveDefaultsIfNeeded(from snapshot: HardwareSnapshot) {
        guard !curveDefaultsSynced,
              let fan = snapshot.fans.first(where: \.controllable) else { return }
        curveStartRPM = Double(fan.minimumRPM)
        curveMaxRPM = Double(fan.maximumRPM)
        if selectedSensorID == nil {
            setProgrammaticSelectedSensorID(selectedSensor?.id)
        }
        curveDefaultsSynced = true
    }

    private func setProgrammaticSelectedSensorID(_ sensorID: String?) {
        isSettingSelectedSensorProgrammatically = true
        selectedSensorID = sensorID
        isSettingSelectedSensorProgrammatically = false
    }

    private func defaultFanOverride(for fan: Fan) -> FanCurveOverride {
        FanCurveOverride(
            fanID: fan.id,
            startRPM: FanCurve.clamp(Int(curveStartRPM.rounded()), fan.minimumRPM, fan.maximumRPM),
            midRPM: FanCurve.clamp(Int(curveMidRPM.rounded()), fan.minimumRPM, fan.maximumRPM),
            maxRPM: FanCurve.clamp(Int(curveMaxRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
        )
    }

    private func defaultFixedFanTarget(for fan: Fan) -> FixedFanTarget {
        FixedFanTarget(
            fanID: fan.id,
            rpm: defaultFixedFanTargetRPM(for: fan)
        )
    }

    private var fixedRPMBaseBounds: (minimumRPM: Int, maximumRPM: Int) {
        fixedRPMBaseBounds(for: snapshot?.fans ?? [])
    }

    private func fixedRPMBaseBounds(for fans: [Fan]) -> (minimumRPM: Int, maximumRPM: Int) {
        let fan = fans.first(where: \.controllable) ?? fans.first
        return (
            minimumRPM: fan?.minimumRPM ?? 1200,
            maximumRPM: fan?.maximumRPM ?? 6500
        )
    }

    private var fixedRPMBaseRangeRatio: Double {
        fixedRPMBaseRangeRatio(for: fixedRPMBaseBounds)
    }

    private func fixedRPMBaseRangeRatio(for bounds: (minimumRPM: Int, maximumRPM: Int)) -> Double {
        guard bounds.maximumRPM > bounds.minimumRPM else { return 0 }
        let clamped = FanCurve.clamp(Int(fixedRPM.rounded()), bounds.minimumRPM, bounds.maximumRPM)
        return Double(clamped - bounds.minimumRPM) / Double(bounds.maximumRPM - bounds.minimumRPM)
    }

    private func defaultFixedFanTargetRPM(for fan: Fan) -> Int {
        defaultFixedFanTarget(for: fan, baseRatio: fixedRPMBaseRangeRatio).rpm
    }

    private func defaultFixedFanTarget(for fan: Fan, baseRatio: Double) -> FixedFanTarget {
        guard fan.maximumRPM > fan.minimumRPM else {
            return FixedFanTarget(
                fanID: fan.id,
                rpm: FanCurve.clamp(Int(fixedRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
            )
        }
        let rpm = Double(fan.minimumRPM) + Double(fan.maximumRPM - fan.minimumRPM) * baseRatio
        return FixedFanTarget(
            fanID: fan.id,
            rpm: FanCurve.clamp(Int(rpm.rounded()), fan.minimumRPM, fan.maximumRPM)
        )
    }

    private func rpmPercent(_ rpm: Int, for fan: Fan) -> Int {
        guard fan.maximumRPM > fan.minimumRPM else { return 0 }
        let clamped = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        let ratio = Double(clamped - fan.minimumRPM) / Double(fan.maximumRPM - fan.minimumRPM)
        return min(100, max(0, Int((ratio * 100).rounded())))
    }

    private func updateFixedFanTarget(for fan: Fan, mutate: (inout FixedFanTarget) -> Void) {
        if let index = fixedFanTargets.firstIndex(where: { $0.fanID == fan.id }) {
            mutate(&fixedFanTargets[index])
        } else {
            var target = defaultFixedFanTarget(for: fan)
            mutate(&target)
            fixedFanTargets.append(target)
        }
        fixedFanTargets = fixedFanTargets.reduce(into: [Int: FixedFanTarget]()) { targetsByID, target in
            targetsByID[target.fanID] = target
        }
        .sorted { $0.key < $1.key }
        .map(\.value)
    }

    private func updateFanOverride(for fan: Fan, mutate: (inout FanCurveOverride) -> Void) {
        // Fan-curve resolution and presentation are deliberately last-wins for
        // duplicate persisted records. Mutate that same effective record before
        // canonicalizing, otherwise the untouched final duplicate would erase
        // the user's edit during the reduction below.
        if let index = fanOverrides.lastIndex(where: { $0.fanID == fan.id }) {
            mutate(&fanOverrides[index])
        } else {
            var override = defaultFanOverride(for: fan)
            mutate(&override)
            fanOverrides.append(override)
        }
        fanOverrides = fanOverrides.reduce(into: [Int: FanCurveOverride]()) { overridesByID, override in
            overridesByID[override.fanID] = override
        }
        .sorted { $0.key < $1.key }
        .map(\.value)
    }

    private func syncState() async {
        assignIfChanged(\.controlState, await coordinator.state)
        manualTargetSettlingFanIDs = await coordinator.recentManualWriteFanIDs(
            at: now(),
            within: Self.manualTargetWriteSettleInterval
        )
        updateManualTargetDriftStability()
    }

    private func evaluateLocalNotifications(power: PowerSnapshot, thermalPressure: ThermalPressure) async {
        if let authorization = await localNotificationCoordinator.evaluate(
            settings: notificationSettings,
            input: LocalNotificationEvaluationInput(
                helperNeedsAttention: helperHealthState.notifiesAsHelperFailure,
                helperTitle: helperFailureNotificationTitle,
                helperBody: helperFailureNotificationBody,
                agentNeedsAttention: agentCoolingNeedsAttention,
                agentBody: agentCoolingRecoverySuggestion
                    ?? agentCoolingSummary
                    ?? "Check Vifty before starting another developer workload.",
                power: power,
                thermalPressure: thermalPressure
            )
        ) {
            notificationAuthorization = authorization
        }
    }

    private func notifyAutoRestoreFailure(_ message: String) async {
        if let authorization = await localNotificationCoordinator.notifyAutoRestoreFailure(
            message,
            settings: notificationSettings
        ) {
            notificationAuthorization = authorization
        }
    }

    func setNotificationEnabled(_ kind: LocalNotificationKind, isEnabled: Bool) {
        notificationSettings.set(kind, enabled: isEnabled)
        guard isEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let status = await localNotificationCoordinator.requestAuthorization()
            notificationAuthorization = status
        }
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await localNotificationCoordinator.authorizationStatus()
    }

    func sendTestNotification() async {
        let result = await localNotificationCoordinator.sendTestNotification()
        notificationAuthorization = result.authorization
        notificationTestMessage = result.delivered
            ? "Test notification sent."
            : "Test notification was not delivered."
    }

    func openNotificationSettings() async {
        notificationAuthorization = await localNotificationCoordinator.openSettings()
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
