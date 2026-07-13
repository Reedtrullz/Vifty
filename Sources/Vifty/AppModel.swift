import Foundation
import SwiftUI
import ViftyCore

enum HelperHealthState: Equatable {
    case checking
    case healthy(fanCount: Int)
    case error
    case runtimeMismatch
    case telemetryOnly
    case unreachable
    case noFanData
    case noControllableFans(fanCount: Int)
    case unsupported

    var needsAttention: Bool {
        if case .healthy = self {
            return false
        }
        if case .checking = self {
            return false
        }
        return true
    }

    var repairActionAvailable: Bool {
        switch self {
        case .error, .runtimeMismatch, .telemetryOnly, .unreachable:
            return true
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            return false
        }
    }

    var notifiesAsHelperFailure: Bool {
        repairActionAvailable
    }

    var summary: String {
        switch self {
        case .checking:
            return "Checking fan helper"
        case .healthy(let fanCount):
            return "Fan helper healthy · \(fanCount) fan\(fanCount == 1 ? "" : "s")"
        case .error:
            return "Fan helper error · repair needed"
        case .runtimeMismatch:
            return "Fan helper build mismatch · repair needed"
        case .telemetryOnly:
            return "Read-only fan telemetry · repair daemon for writes"
        case .unreachable:
            return "Fan helper not responding · repair or approve"
        case .noFanData:
            return "Fan helper reachable · waiting for fan data"
        case .noControllableFans:
            return "Fan telemetry available · no controllable fans"
        case .unsupported:
            return "Unsupported hardware · fan writes blocked"
        }
    }

    var menuSummary: String {
        switch self {
        case .checking:
            return "Checking helper"
        case .healthy(let fanCount):
            return "Helper healthy · \(fanCount) fan\(fanCount == 1 ? "" : "s")"
        case .error:
            return "Helper needs repair"
        case .runtimeMismatch:
            return "Helper build mismatch"
        case .telemetryOnly:
            return "Fan writes blocked"
        case .unreachable:
            return "Helper not responding"
        case .noFanData:
            return "Waiting for fan data"
        case .noControllableFans:
            return "No controllable fans"
        case .unsupported:
            return "Unsupported hardware"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .checking, .healthy:
            return nil
        case .error:
            return "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck."
        case .runtimeMismatch:
            return "Use Repair/Reinstall Helper from this Vifty app, approve Login Items if prompted, then rerun diagnose. Fan writes stay blocked until the installed daemon matches this build."
        case .telemetryOnly:
            return "Use Repair/Reinstall Helper or approve Login Items if prompted. Fan telemetry is read-only, and manual or agent cooling stays blocked until the daemon responds."
        case .unreachable:
            return "Use Repair/Reinstall Helper or approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds."
        case .noFanData:
            return "Keep Auto selected and collect read-only diagnostics. Fan writes stay blocked until controllable fans appear."
        case .noControllableFans(let fanCount):
            return "The helper can read \(fanCount) fan\(fanCount == 1 ? "" : "s"), but none are marked controllable. Keep fan writes blocked and collect read-only hardware validation evidence before changing support claims."
        case .unsupported:
            return "Vifty supports fan control on Apple Silicon MacBook Pro hardware. Keep this machine on read-only diagnostics; do not retry fan writes."
        }
    }

    var menuRecoverySuggestion: String? {
        switch self {
        case .checking, .healthy:
            return nil
        case .error, .telemetryOnly, .unreachable:
            return "Repair/Reinstall Helper; approve Login Items if prompted."
        case .runtimeMismatch:
            return "Repair/Reinstall Helper from this app before fan control."
        case .noFanData:
            return "Keep Auto selected and copy diagnose for read-only evidence."
        case .noControllableFans:
            return "Keep Auto selected and collect hardware validation evidence."
        case .unsupported:
            return "Read-only diagnostics only on this Mac."
        }
    }
}

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
    @Published var fanAccessMessage: String?
    @Published var daemonResponding = false
    @Published var daemonReachable = false
    @Published var isRunning = false
    @Published var powerSnapshot: PowerSnapshot?
    @Published var thermalPressure: ThermalPressure = .nominal
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            let wasDisplayingCodexUsage = Self.menuBarModeDisplaysCodexUsage(
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
            let wasDisplayingCodexUsage = Self.menuBarModeDisplaysCodexUsage(
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
    @Published var notificationSettings: LocalNotificationSettings {
        didSet {
            persistAppPreferences()
        }
    }
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
    var telemetryHistory = TelemetryHistory() {
        didSet {
            refreshTelemetrySummaries()
        }
    }
    @Published var manualRunLimit: ManualRunLimit = .defaultForManualControl
    @Published var manualSessionExpiresAt: Date?
    @Published private(set) var fanControlApplyState: FanControlApplyState = .applied
    @Published var agentControlStatus: AgentControlStatus?
    @Published var agentControlStatusError: String?
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
    private var isSettingSelectedSensorProgrammatically = false
    private var userSelectedSensorID: String?
    private var lastAppliedFanControlDraft: FanControlDraft?
    private var appliedManualRunLimit: ManualRunLimit = .defaultForManualControl
    private var fanControlOperationGeneration: UInt64 = 0
    private var manualFanControlApplyAttempt: ManualFanControlApplyAttempt?

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
    private let notificationDeliverer: LocalNotificationDelivering
    private let notificationHistoryStore: LocalNotificationHistoryStore
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let daemonPing: @Sendable () async -> Bool
    private let agentStatusReader: @Sendable () async throws -> AgentControlStatus?
    private let agentRestore: @Sendable (String) async throws -> AgentControlStatus?
    private let profileStore: CurveProfileStore
    private let preferencesStore: AppPreferencesStore
    private var pollingTask: Task<Void, Never>?
    private var activePollTask: Task<Void, Never>?
    private var codexUsageRefreshTask: Task<Void, Never>?
    private var codexUsageRefreshGeneration = 0
    private var startupModeApplied = false
    private var notificationTransitionState = LocalNotificationTransitionState()
    private var manualTargetDriftSampleCounts: [Int: Int] = [:]
    private var manualTargetSettlingFanIDs: Set<Int> = []
    private var elevatedThermalPressureStartedAt: Date?
    private var lastCodexUsageRefreshAt: Date?
    private var lastPowerTelemetryRefreshAt: Date?
    private var lastDaemonPingAt: Date?
    private var lastAgentStatusRefreshAt: Date?
    private let notificationMinimumInterval: TimeInterval = 30 * 60
    private let sustainedThermalPressureInterval: TimeInterval = 60
    private let powerTelemetryRefreshInterval: TimeInterval = 15
    private let daemonPingRefreshInterval: TimeInterval = 30
    private let agentStatusRefreshInterval: TimeInterval = 15
    private let pollSchedulePolicy = PollSchedulePolicy.standard

    private struct ManualFanControlApplyAttempt {
        let generation: UInt64
        let draft: FanControlDraft
        let mode: FanMode
        let previousManualSessionExpiresAt: Date?
        var coordinatorConfigured: Bool
    }

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
            selectedSensorID: selectedSensorID,
            usePerFanOverrides: usePerFanOverrides,
            fanOverrides: fanOverrides
        )
    }

    var hasPendingFanControlChanges: Bool {
        guard let lastAppliedFanControlDraft else { return selectedMode != .auto }
        return currentFanControlDraft.isDirty(comparedTo: lastAppliedFanControlDraft)
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
            manualSessionExpiresAt: manualSessionExpiresAt
        ))
    }

    private var fanControlPresentationApplyState: FanControlApplyState {
        if hasPendingFanControlChanges, fanControlApplyState == .applied {
            return .pending
        }
        if !hasPendingFanControlChanges,
           fanControlApplyState == .pending,
           manualFanControlApplyAttempt == nil {
            return .applied
        }
        return fanControlApplyState
    }

    var menuBarPanelPresentation: MenuBarPanelPresentation {
        MenuBarPanelPresentation.resolve(input: .init(
            controlSession: controlSessionPresentation,
            ownerText: compactControlOwnershipSummary,
            attentionText: menuBarPanelAttentionText,
            fans: snapshot?.fans ?? [],
            isManualControlActive: controlState.manualControlActive
        ))
    }

    init(
        coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService()),
        powerReader: @escaping @Sendable () -> PowerSnapshot = { PowerInfoReader.read() },
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        codexUsageReader: @escaping @Sendable () -> CodexUsageSnapshot? = { CodexUsageReader.readDefault() },
        codexUsageRefreshInterval: TimeInterval = AppModel.defaultCodexUsageRefreshInterval,
        now: @escaping @Sendable () -> Date = { Date() },
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
        self.notificationDeliverer = notificationDeliverer
        self.notificationHistoryStore = notificationHistoryStore
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
        savedProfiles = profileStore.load()
        menuBarStatusItemPresentation = currentMenuBarStatusItemPresentation
    }

    func start() {
        guard pollingTask == nil else { return }
        isRunning = true
        ViftyLog.lifecycle.info("Polling started")

        pollingTask = Task { [self] in
            await pollOnce()
            await coordinator.recoverIfNeeded()
            await applyStartupModePreferenceIfNeeded()

            while !Task.isCancelled {
                try? await Task.sleep(for: backgroundPollInterval())
                guard !Task.isCancelled else { return }
                await pollOnce()
            }
        }
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
                try? await Task.sleep(for: retryDelay)
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
        refreshLaunchAtLoginStatus()
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
        let requiresHardwareRestore = stateBeforeStop.manualControlActive
            || stateBeforeStop.mode != .auto
            || hasAgentLeaseRequiringRestore
        pollingTask?.cancel()
        pollingTask = nil
        codexUsageRefreshGeneration &+= 1
        codexUsageRefreshTask?.cancel()
        codexUsageRefreshTask = nil
        isRunning = false
        selectedMode = .auto
        manualSessionExpiresAt = nil
        let hardwareRestoreResult: AutoRestoreResult = if requiresHardwareRestore {
            await coordinator.forceAuto()
        } else {
            .restored
        }
        let agentRestoreError = await clearAgentLeaseForUserAutoIfNeeded()
        await syncState()

        var failures: [String] = []
        if case .failed(let message) = hardwareRestoreResult {
            failures.append(message)
        }
        if let agentRestoreError {
            failures.append(agentRestoreError)
        }
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
        guard wasRunning, pollingTask == nil else { return }
        isRunning = true
        pollingTask = Task { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: backgroundPollInterval())
                guard !Task.isCancelled else { return }
                await pollOnce()
            }
        }
    }

    func pollOnce() async {
        if let activePollTask {
            await activePollTask.value
            return
        }

        let task = Task { @MainActor in
            await performPollOnce()
        }
        activePollTask = task
        await task.value
        activePollTask = nil
    }

    private func performPollOnce() async {
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
            hasCompletedHardwarePoll = true
            refreshMenuBarStatusItemIfNeeded()
        }
        refreshCodexUsageIfNeeded()
        let expiredAutoOperationGeneration = await restoreAutoIfManualSessionExpired()
        let stateBeforeTick = await coordinator.state
        do {
            let nextSnapshot = try await coordinator.tick()
            recordHardwareSnapshot(nextSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            assignIfChanged(\.lastError, nil)
            await refreshDaemonPingIfNeeded(at: pollStartedAt, force: false)
            assignIfChanged(\.daemonReachable, daemonResponding || !nextSnapshot.fans.isEmpty)
            await refreshAgentControlStatusIfNeeded(at: pollStartedAt)
            assignIfChanged(\.fanAccessMessage, fanAccessMessage(for: nextSnapshot))
            await syncState()
            if let expiredAutoOperationGeneration,
               canCommitAutoRestoration(generation: expiredAutoOperationGeneration) {
                recordAutoRestorationApplied()
            } else {
                reconcileManualApplyAttemptAfterSuccessfulPoll()
            }
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
            ViftyLog.polling.debug("Hardware poll completed")
        } catch {
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
            assignIfChanged(\.daemonReachable, daemonResponding || (preservesManualIntent && snapshot?.fans.isEmpty == false))
            await refreshAgentControlStatusIfNeeded(at: pollStartedAt, force: true)
            if preservesManualIntent, let snapshot {
                assignIfChanged(\.fanAccessMessage, fanAccessMessage(for: snapshot))
            }
            if preservesManualIntent {
                if selectedMode != .auto {
                    let intendedMode: FanMode = stateBeforeTick.mode == .auto ? selectedFanMode() : stateBeforeTick.mode
                    await coordinator.setMode(intendedMode)
                }
                assignIfChanged(\.controlState, await coordinator.state)
            } else {
                let fallbackAutoRestoreResult = await coordinator.forceAuto()
                await syncState()

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

    @discardableResult
    private func refreshMenuBarStatusItemIfNeeded() -> Bool {
        let nextPresentation = currentMenuBarStatusItemPresentation
        guard nextPresentation != menuBarStatusItemPresentation else { return false }
        menuBarStatusItemPresentation = nextPresentation
        menuBarStatusItemRevision &+= 1
        return true
    }

    private var currentMenuBarStatusItemPresentation: MenuBarStatusItemPresentation {
        let statusItemText = ViftyStatusItemPresentation.resolvedText(
            statusItemText: menuBarStatusItemText,
            fallbackStatusItemText: menuBarDisplayMode == .fanIcon ? nil : menuBarLabelText,
            labelNeedsTelemetryPrime: menuBarLabelNeedsTelemetryPrime,
            allowsPlaceholderText: menuBarAllowsPlaceholderStatusItemText
        )
        let content: MenuBarStatusItemPresentation.Content = if let statusItemText {
            .text(statusItemText)
        } else {
            .fanIcon(accessibilityDescription: menuBarLabelText)
        }
        return MenuBarStatusItemPresentation(
            content: content,
            tooltip: menuTitle,
            accessibilityLabel: menuBarLabelText,
            needsTelemetryPrime: menuBarLabelNeedsTelemetryPrime
        )
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
        let selectedTelemetrySensor = telemetryTemperatureSensor(in: nextSnapshot)
        let temperatureWasUserSelected = userSelectedSensorID != nil && selectedTelemetrySensor?.id == userSelectedSensorID
        assignIfChanged(\.snapshot, nextSnapshot)
        telemetryHistory.append(TelemetrySample(
            capturedAt: now(),
            selectedTemperatureID: selectedTelemetrySensor?.id,
            selectedTemperatureName: selectedTelemetrySensor?.name,
            selectedTemperatureCelsius: selectedTelemetrySensor?.celsius,
            temperatureWasUserSelected: temperatureWasUserSelected,
            highestTemperatureCelsius: nextSnapshot.highestTemperature?.celsius,
            firstFanRPM: nextSnapshot.fans.first?.currentRPM,
            averageFanRPM: averageFanRPM(in: nextSnapshot.fans),
            batteryPowerWatts: power.batteryPowerWatts,
            thermalPressure: thermalPressure
        ))
        syncCurveDefaultsIfNeeded(from: nextSnapshot)
        if usePerFanFixedRPM {
            ensureFixedFanTargets(for: nextSnapshot.fans)
        }
    }

    private func telemetryTemperatureSensor(in snapshot: HardwareSnapshot) -> TemperatureSensor? {
        if let selectedSensorID,
           let exact = snapshot.temperatureSensors.first(where: { $0.id == selectedSensorID }) {
            return exact
        }
        return snapshot.temperatureSensors.first { sensor in
            let lower = sensor.name.lowercased()
            return lower.contains("cpu") || lower.contains("package") || lower.contains("die")
        } ?? snapshot.highestTemperature
    }

    private func averageFanRPM(in fans: [Fan]) -> Double? {
        guard !fans.isEmpty else { return nil }
        let totalRPM = fans.reduce(0) { total, fan in
            total + fan.currentRPM
        }
        return Double(totalRPM) / Double(fans.count)
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
        controlSessionPresentation.primaryAction == .restoreAuto
            || controlState.manualControlActive
            || controlState.mode != .auto
            || agentControlStatus?.activeLease != nil
    }

    func markFanControlDraftPending() {
        guard selectedMode != .auto else { return }
        if !hasPendingFanControlChanges,
           manualFanControlApplyAttempt == nil,
           let lastAppliedFanControlDraft,
           controlState.mode == fanMode(for: lastAppliedFanControlDraft) {
            fanControlApplyState = .applied
        } else if fanControlApplyState != .applying {
            fanControlApplyState = .pending
        }
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
        let previousManualSessionExpiresAt = manualFanControlApplyAttempt?.previousManualSessionExpiresAt
            ?? manualSessionExpiresAt
        let generation = beginFanControlOperation()
        let draft = currentFanControlDraft
        let mode = fanMode(for: draft)

        await refreshManualControlPreflight()
        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        if let blockedReason = manualFanControlBlockedReason {
            lastError = "Manual fan control blocked: \(blockedReason)"
            fanControlApplyState = .blocked(reason: blockedReason)
            await syncState()
            guard manualFanControlOperationIsCurrent(generation) else {
                return .superseded
            }
            return .blocked(reason: blockedReason)
        }

        fanControlApplyState = .applying
        lastError = nil
        updateManualDeadline(for: mode, runLimit: draft.manualRunLimit)
        manualFanControlApplyAttempt = ManualFanControlApplyAttempt(
            generation: generation,
            draft: draft,
            mode: mode,
            previousManualSessionExpiresAt: previousManualSessionExpiresAt,
            coordinatorConfigured: false
        )

        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        await coordinator.setFixedFanTargets(fixedFanTargetMap(for: draft))
        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        await coordinator.setFanOverrides(draft.usePerFanOverrides ? draft.fanOverrides : [])
        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        await coordinator.setMode(mode)
        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        if manualFanControlApplyAttempt?.generation == generation {
            manualFanControlApplyAttempt?.coordinatorConfigured = true
        }

        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        await pollOnce()
        guard manualFanControlOperationIsCurrent(generation) else {
            return .superseded
        }
        if let lastError {
            restorePreviousManualDeadline(for: generation)
            fanControlApplyState = .failed(message: lastError)
            return .failed(message: lastError)
        }
        reconcileManualApplyAttemptAfterSuccessfulPoll()
        guard controlState.mode == mode, controlState.manualControlActive else {
            let message = "Manual fan control could not be confirmed after Apply."
            restorePreviousManualDeadline(for: generation)
            lastError = message
            fanControlApplyState = .failed(message: message)
            return .failed(message: message)
        }
        return .applied
    }

    func restoreAutoNow() async {
        let generation = beginAutoRestoreOperation()
        await performAutoRestore(generation: generation)
    }

    private func performAutoRestore(generation: UInt64) async {
        guard fanControlOperationIsCurrent(generation) else { return }
        await coordinator.setMode(.auto)
        guard fanControlOperationIsCurrent(generation) else { return }

        let agentRestoreError = await clearAgentLeaseForUserAutoIfNeeded()
        guard fanControlOperationIsCurrent(generation) else { return }

        guard fanControlOperationIsCurrent(generation) else { return }
        await pollOnce()
        guard fanControlOperationIsCurrent(generation) else { return }
        if let agentRestoreError {
            lastError = agentRestoreError
            await notifyAutoRestoreFailure(agentRestoreError)
            guard fanControlOperationIsCurrent(generation) else { return }
        }
        if let lastError {
            fanControlApplyState = .failed(message: lastError)
        } else if controlState.mode != .auto || controlState.manualControlActive {
            let message = "Auto restore could not be confirmed."
            lastError = message
            fanControlApplyState = .failed(message: message)
        } else {
            recordAutoRestorationApplied()
        }
    }

    func saveCurrentProfile(name: String) {
        let profile = CurveProfile(
            name: name,
            sensorID: selectedSensorID,
            startTemp: curveStartTemp,
            startRPM: Int(curveStartRPM.rounded()),
            midTemp: curveMidTemp,
            midRPM: Int(curveMidRPM.rounded()),
            maxTemp: curveMaxTemp,
            maxRPM: Int(curveMaxRPM.rounded()),
            fanOverrides: usePerFanOverrides ? fanOverrides : []
        )
        if let existingIndex = savedProfiles.firstIndex(where: { $0.name == name }) {
            savedProfiles[existingIndex] = profile
        } else {
            savedProfiles.append(profile)
        }
        selectedCurveProfileID = profile.id
        persistProfiles()
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

    func deleteProfile(_ profile: CurveProfile) {
        savedProfiles.removeAll { $0.id == profile.id }
        if selectedCurveProfileID == profile.id {
            selectedCurveProfileID = nil
        }
        persistProfiles()
    }

    private func persistProfiles() {
        do {
            try profileStore.saveThrowing(savedProfiles)
        } catch {
            lastError = "Failed to save profiles: \(error.localizedDescription)"
        }
    }

    func targetRPMPreview(for fan: Fan) -> Int? {
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
            return currentCurve().targetRPM(
                for: sensor.celsius,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
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

    private func refreshTelemetrySummaries() {
        let overview = TelemetryHistorySummary(
            history: telemetryHistory,
            sampleLimit: 180,
            thermalPressureLimit: 36
        )
        let compact = TelemetryHistorySummary(
            history: telemetryHistory,
            sampleLimit: 90,
            thermalPressureLimit: 24
        )
        assignIfChanged(\.telemetryOverviewSummary, overview)
        assignIfChanged(\.compactTelemetryOverviewSummary, compact)
        assignIfChanged(\.recentTelemetryTrendSummary, trendSummary(from: compact))
    }

    private func trendSummary(from summary: TelemetryHistorySummary) -> String? {
        guard summary.sampleCount >= 2 else { return nil }

        var parts: [String] = []
        if let temperatureChangeText = summary.temperatureChangeText {
            parts.append("Temp \(temperatureChangeText)")
        }
        if let fanRPMChangeText = summary.fanRPMChangeText {
            parts.append("\(summary.fanRPMTrendLabel) \(fanRPMChangeText)")
        }
        if let batteryPowerChangeText = summary.batteryPowerChangeText {
            parts.append("Power \(batteryPowerChangeText)")
        }
        if summary.thermalPressureSamples.count >= 2,
           summary.thermalPressureSummaryText != "Stable Nominal" {
            parts.append(summary.thermalPressureSummaryText)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func ensureFixedFanTargets(for fans: [Fan]) {
        let baseRatio = fixedRPMBaseRangeRatio(for: fixedRPMBaseBounds(for: fans))
        let existingByFanID = fixedFanTargets.reduce(into: [Int: FixedFanTarget]()) { targetsByID, target in
            targetsByID[target.fanID] = target
        }
        let nextTargets = fans.map { fan in
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
        fanOverrides = fans.map { fan in
            existingByFanID[fan.id] ?? defaultFanOverride(for: fan)
        }
    }

    func fanOverride(for fanID: Int) -> FanCurveOverride? {
        fanOverrides.first { $0.fanID == fanID }
    }

    func setOverrideStartRPM(_ rpm: Int, for fan: Fan) {
        updateFanOverride(for: fan) { override in
            override.startRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func setOverrideMidRPM(_ rpm: Int, for fan: Fan) {
        updateFanOverride(for: fan) { override in
            override.midRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func setOverrideMaxRPM(_ rpm: Int, for fan: Fan) {
        updateFanOverride(for: fan) { override in
            override.maxRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    var selectedSensor: TemperatureSensor? {
        guard let sensors = snapshot?.temperatureSensors, !sensors.isEmpty else { return nil }
        if let selectedSensorID, let exact = sensors.first(where: { $0.id == selectedSensorID }) {
            return exact
        }
        return sensors.first { sensor in
            let lower = sensor.name.lowercased()
            return lower.contains("cpu") || lower.contains("package") || lower.contains("die")
        } ?? snapshot?.highestTemperature
    }

    var effectiveSelectedSensorID: String? {
        selectedSensor?.id
    }

    var temperatureAttentionSummary: String? {
        guard thermalPressure.menuSummary == nil else { return nil }
        guard let sensor = selectedSensor ?? snapshot?.highestTemperature else { return nil }
        return sensor.celsius >= Self.highTemperatureAttentionThreshold ? "High temp" : nil
    }

    var fanWriteBlockedWhileHotSummary: String? {
        guard helperWritePathBlockedSummary != nil,
              let sensor = selectedSensor ?? snapshot?.highestTemperature,
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

    private var menuBarPanelAttentionText: String? {
        fanWriteBlockedWhileHotSummary
            ?? thermalPressure.menuSummary
            ?? temperatureAttentionSummary
    }

    var menuTitle: String {
        menuSummary(includePower: true)
    }

    var menuPanelTitle: String {
        menuSummary(includePower: false)
    }

    private func menuSummary(includePower: Bool) -> String {
        var parts: [String]
        if snapshot != nil {
            parts = [menuBarTemperatureText, menuBarFanText].compactMap(\.self)
            if parts.isEmpty {
                parts = ["Vifty"]
            }
            if includePower, let powerSnapshot {
                parts.append(PowerDisplayFormatter.summary(for: powerSnapshot))
            }
        } else {
            parts = if includePower {
                [powerSnapshot.map { PowerDisplayFormatter.summary(for: $0) } ?? "Vifty"]
            } else {
                ["Vifty"]
            }
        }
        if let thermal = thermalPressure.menuSummary {
            parts.append(thermal)
        } else if let temperatureAttentionSummary {
            parts.append(temperatureAttentionSummary)
        }
        let hasHotFanWriteBlock = fanWriteBlockedWhileHotSummary != nil
        if hasHotFanWriteBlock {
            parts.append("Fan writes blocked")
        } else if helperHealthAttentionIsActionable {
            parts.append(helperHealthMenuSummary)
        }
        if let agentCoolingMenuSummary {
            parts.append(agentCoolingMenuSummary)
        }
        return parts.joined(separator: " | ")
    }

    var menuBarLabelText: String {
        switch menuBarDisplayMode {
        case .fanIcon:
            return menuTitle
        case .temperature:
            return menuBarLabelWithAttention(menuBarTemperatureText ?? "-- C")
        case .fanRPM:
            return menuBarLabelWithAttention(menuBarFanText ?? "-- RPM")
        case .averageFanRPM:
            return menuBarLabelWithAttention(menuBarAverageFanText ?? "-- RPM avg")
        case .adapterWattage:
            return menuBarLabelWithAttention(menuBarPowerText ?? "-- W")
        case .codexUsage:
            return CodexUsageFormatter.menuBarText(
                for: codexUsageSnapshot,
                options: codexUsageDisplayPreferences,
                now: now
            )
        case .custom:
            return menuBarLabelWithAttention(menuBarCustomLabelText)
        case .temperatureAndRPM:
            return menuBarLabelWithAttention("\(menuBarTemperatureText ?? "-- C") | \(menuBarFanText ?? "-- RPM")")
        case .ownerTemperatureAndRPM:
            return menuBarLabelWithAttention([
                menuBarFanOwnerText,
                menuBarTemperatureText ?? "-- C",
                menuBarFanText ?? "-- RPM"
            ].joined(separator: " | "))
        case .compactSummary:
            return menuTitle
        }
    }

    var menuBarStatusItemText: String? {
        guard !menuBarLabelUsesFanIcon else { return nil }
        let label = menuBarLabelText
        if menuBarAllowsPlaceholderStatusItemText {
            return label
        }
        guard !label.contains("--") else { return nil }
        return label
    }

    var menuBarLabelNeedsTelemetryPrime: Bool {
        if !hasCompletedHardwarePoll {
            return true
        }
        if menuBarDisplayMode == .codexUsage {
            return false
        }
        if menuBarDisplayMode == .custom {
            return menuBarCustomFields.contains { field in
                field.requiresHardwareTelemetry && (menuBarText(for: field)?.contains("--") ?? false)
            }
        }
        return menuBarLabelText.contains("--")
    }

    var menuBarDisplaysCodexUsage: Bool {
        Self.menuBarModeDisplaysCodexUsage(menuBarDisplayMode, customFields: menuBarCustomFields)
    }

    private static func menuBarModeDisplaysCodexUsage(
        _ mode: MenuBarDisplayMode,
        customFields: [MenuBarField]
    ) -> Bool {
        switch mode {
        case .codexUsage:
            return true
        case .custom:
            return customFields.contains(.codexUsage)
        case .fanIcon, .temperature, .fanRPM, .averageFanRPM, .adapterWattage, .temperatureAndRPM, .ownerTemperatureAndRPM, .compactSummary:
            return false
        }
    }

    var menuBarAllowsPlaceholderStatusItemText: Bool {
        menuBarDisplaysCodexUsage && hasCompletedHardwarePoll
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
        if let lease = agentControlStatus?.activeLease {
            let needsAttention = agentControlStatusError != nil || !lease.isActive(at: now())
            return needsAttention ? "Agent?" : "Agent"
        }

        switch controlState.mode {
        case .fixedRPM, .temperatureCurve:
            return controlOwnershipNeedsAttention ? "Me?" : "Me"
        case .auto:
            if agentControlStatusError != nil {
                return shouldPreferHelperRecoveryOverAgentStatusError ? "Mac?" : "Owner?"
            }
            if !autoForcedModeFans.isEmpty || !autoUnknownModeFans.isEmpty || !autoMissingModeFans.isEmpty {
                return "Owner?"
            }
            if helperWritePathBlockedSummary != nil {
                return "Mac?"
            }
            guard let fans = snapshot?.fans, !fans.isEmpty else {
                return hasCompletedHardwarePoll || daemonReachable ? "Owner?" : "Mac"
            }
            return "Mac"
        }
    }

    private func menuBarLabelWithAttention(_ label: String) -> String {
        guard let attention = menuBarMetricAttentionSummary,
              !label.contains(attention)
        else {
            return label
        }
        return "\(label) | \(attention)"
    }

    private var menuBarCustomLabelText: String {
        let parts = menuBarCustomFields.compactMap { menuBarText(for: $0) }
        return parts.isEmpty ? menuTitle : parts.joined(separator: " | ")
    }

    private func menuBarText(for field: MenuBarField) -> String? {
        switch field {
        case .owner:
            return menuBarFanOwnerText
        case .temperature:
            return menuBarTemperatureText ?? "-- C"
        case .fanStrength:
            return menuBarFanStrengthText ?? "--% fan"
        case .fanRPM:
            return menuBarFanText ?? "-- RPM"
        case .averageFanRPM:
            return menuBarAverageFanText ?? "-- RPM avg"
        case .adapterWattage:
            return menuBarPowerText ?? "-- W"
        case .codexUsage:
            return CodexUsageFormatter.menuBarText(
                for: codexUsageSnapshot,
                options: codexUsageDisplayPreferences,
                now: now
            )
        }
    }

    private var menuBarMetricAttentionSummary: String? {
        if fanWriteBlockedWhileHotSummary != nil {
            return "Fan writes blocked"
        }
        if helperHealthAttentionIsActionable {
            return helperHealthMenuSummary
        }
        return nil
    }

    private var helperHealthAttentionIsActionable: Bool {
        helperHealthNeedsAttention &&
            (hasCompletedHardwarePoll || daemonReachable || daemonResponding || agentControlStatusError != nil || lastError != nil)
    }

    var menuBarLabelUsesFanIcon: Bool {
        menuBarDisplayMode == .fanIcon
    }

    private var menuBarTemperatureText: String? {
        (selectedSensor ?? snapshot?.highestTemperature).map { "\(Int($0.celsius.rounded())) C" }
    }

    private var menuBarFanText: String? {
        snapshot?.fans.first.map { "\($0.currentRPM) RPM" }
    }

    private var menuBarFanStrengthText: String? {
        guard let fans = snapshot?.fans, !fans.isEmpty else { return nil }
        let averagePercentage = Double(fans.reduce(0) { total, fan in
            total + fan.percentage
        }) / Double(fans.count)
        return "\(Int(averagePercentage.rounded()))% fan"
    }

    private var menuBarAverageFanText: String? {
        guard let fans = snapshot?.fans, !fans.isEmpty else { return nil }
        let totalRPM = fans.reduce(0) { total, fan in
            total + fan.currentRPM
        }
        let averageRPM = Double(totalRPM) / Double(fans.count)
        return "\(Int(averageRPM.rounded())) RPM avg"
    }

    private var menuBarPowerText: String? {
        powerSnapshot.map { PowerDisplayFormatter.summary(for: $0) }
    }

    private func persistAppPreferences() {
        preferencesStore.save(AppPreferences(
            menuBarDisplayMode: menuBarDisplayMode,
            menuBarCustomFields: menuBarCustomFields,
            startupMode: startupMode,
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
        switch helperHealthState {
        case .error, .unreachable:
            return "Fan writes blocked until helper responds"
        case .runtimeMismatch:
            return "Fan writes blocked until helper matches this app"
        case .telemetryOnly:
            return "Read-only fan telemetry; repair helper for fan writes"
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            return nil
        }
    }

    private var hasHelperRuntimeMismatchError: Bool {
        guard let lastError else { return false }
        let normalized = lastError.lowercased()
        return normalized.contains("daemonruntimematchesexpected")
            || normalized.contains("daemonruntime")
            || normalized.contains("does not match this vifty build")
            || normalized.contains("daemon differs from the installed app")
            || normalized.contains("helper daemon differs")
            || normalized.contains("installed privileged fan helper does not match")
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
        if let snapshot, !snapshot.isAppleSilicon || !snapshot.isMacBookPro {
            return .unsupported
        }
        if !hasCompletedHardwarePoll, snapshot == nil, !daemonReachable {
            return .checking
        }
        if hasHelperRuntimeMismatchError {
            return .runtimeMismatch
        }
        let fanCount = snapshot?.fans.count ?? 0
        if fanCount > 0 {
            guard daemonReachable else {
                return .unreachable
            }
            guard daemonResponding else {
                return .telemetryOnly
            }
            if let lastError, lastError.localizedCaseInsensitiveContains("fan helper") {
                return .error
            }
            guard snapshot?.fans.contains(where: \.controllable) == true else {
                return .noControllableFans(fanCount: fanCount)
            }
            return .healthy(fanCount: fanCount)
        }
        if let lastError, lastError.localizedCaseInsensitiveContains("fan helper") {
            return .error
        }
        guard daemonReachable else {
            return .unreachable
        }
        return .noFanData
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
        switch helperHealthState {
        case .telemetryOnly:
            return "macOS helper may be installed, but daemon XPC is not responding; fan reads are read-only and writes stay blocked."
        case .unreachable:
            return "Install status and daemon response are separate; approve or repair before fan writes."
        case .error:
            return "The helper may be installed, but the current daemon path still needs repair."
        case .runtimeMismatch:
            return "The installed LaunchDaemon does not match this Vifty app; repair the helper before fan writes."
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            return nil
        }
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
        guard let sensor = selectedSensor ?? snapshot?.highestTemperature else { return false }
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
        FanCurve(sensorID: selectedSensorID, points: [
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
        switch draft.mode {
        case .auto:
            .auto
        case .fixed:
            .fixedRPM(Int(draft.fixedRPM.rounded()))
        case .curve:
            .temperatureCurve(FanCurve(sensorID: draft.selectedSensorID, points: [
                CurvePoint(
                    temperatureCelsius: draft.curve.startTemperature,
                    rpm: Int(draft.curve.startRPM.rounded())
                ),
                CurvePoint(
                    temperatureCelsius: draft.curve.rampTemperature,
                    rpm: Int(draft.curve.rampRPM.rounded())
                ),
                CurvePoint(
                    temperatureCelsius: draft.curve.highTemperature,
                    rpm: Int(draft.curve.highRPM.rounded())
                )
            ]))
        }
    }

    func applyCurveOverrides() {
        markFanControlDraftPending()
    }

    private func commitManualRunLimit(for mode: FanMode, runLimit: ManualRunLimit) {
        appliedManualRunLimit = runLimit
        updateManualDeadline(for: mode, runLimit: appliedManualRunLimit)
    }

    private func updateManualDeadline(for mode: FanMode, runLimit: ManualRunLimit) {
        guard mode != .auto else {
            manualSessionExpiresAt = nil
            return
        }

        switch runLimit {
        case .indefinitely:
            manualSessionExpiresAt = nil
        case .minutes(let minutes):
            manualSessionExpiresAt = now().addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    private func restoreAutoIfManualSessionExpired() async -> UInt64? {
        guard selectedMode != .auto,
              let manualSessionExpiresAt,
              now() >= manualSessionExpiresAt else {
            return nil
        }

        let generation = beginAutoRestoreOperation()
        guard fanControlOperationIsCurrent(generation) else { return nil }
        await coordinator.setMode(.auto)
        guard fanControlOperationIsCurrent(generation) else { return nil }
        return generation
    }

    private func recordAutoRestorationApplied() {
        manualFanControlApplyAttempt = nil
        lastAppliedFanControlDraft = currentFanControlDraft
        fanControlApplyState = .applied
    }

    private func beginFanControlOperation() -> UInt64 {
        fanControlOperationGeneration &+= 1
        manualFanControlApplyAttempt = nil
        return fanControlOperationGeneration
    }

    private func beginAutoRestoreOperation() -> UInt64 {
        let generation = beginFanControlOperation()
        fanControlApplyState = .applying
        lastError = nil
        selectedMode = .auto
        manualSessionExpiresAt = nil
        return generation
    }

    private func fanControlOperationIsCurrent(_ generation: UInt64) -> Bool {
        fanControlOperationGeneration == generation
    }

    private func manualFanControlOperationIsCurrent(_ generation: UInt64) -> Bool {
        fanControlOperationIsCurrent(generation) && selectedMode != .auto
    }

    private func canCommitAutoRestoration(generation: UInt64) -> Bool {
        fanControlOperationIsCurrent(generation)
            && selectedMode == .auto
            && controlState.mode == .auto
            && !controlState.manualControlActive
    }

    private func reconcileManualApplyAttemptAfterSuccessfulPoll() {
        guard let attempt = manualFanControlApplyAttempt,
              attempt.coordinatorConfigured,
              manualFanControlOperationIsCurrent(attempt.generation),
              controlState.mode == attempt.mode,
              controlState.manualControlActive else {
            return
        }

        commitManualRunLimit(for: attempt.mode, runLimit: attempt.draft.manualRunLimit)
        lastAppliedFanControlDraft = attempt.draft
        manualFanControlApplyAttempt = nil
        fanControlApplyState = currentFanControlDraft == attempt.draft ? .applied : .pending
    }

    private func restorePreviousManualDeadline(for generation: UInt64) {
        guard let attempt = manualFanControlApplyAttempt,
              attempt.generation == generation else {
            return
        }
        manualSessionExpiresAt = attempt.previousManualSessionExpiresAt
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

    private func clearAgentLeaseForUserAutoIfNeeded() async -> String? {
        guard agentControlStatus?.activeLease != nil else { return nil }
        do {
            agentControlStatus = try await agentRestore("User selected Auto in Vifty")
            agentControlStatusError = nil
            return nil
        } catch {
            agentControlStatusError = error.localizedDescription
            return "Failed to clear agent cooling lease after Auto restore: \(error.localizedDescription)"
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

    private func refreshManualControlPreflight() async {
        daemonResponding = await daemonPing()
        if let snapshot {
            daemonReachable = daemonResponding || !snapshot.fans.isEmpty
        } else {
            daemonReachable = daemonResponding
        }

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
        guard !curveDefaultsSynced, let fan = snapshot.fans.first else { return }
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
        if let index = fanOverrides.firstIndex(where: { $0.fanID == fan.id }) {
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
        let helperNeedsAttention = helperHealthState.notifiesAsHelperFailure
        if notificationTransitionState.shouldNotify(kind: .helperFailure, isAttention: helperNeedsAttention) {
            await postNotification(
                kind: .helperFailure,
                title: helperFailureNotificationTitle,
                body: helperFailureNotificationBody
            )
        }

        let agentNeedsAttention = agentCoolingNeedsAttention
        if notificationTransitionState.shouldNotify(kind: .agentCoolingAttention, isAttention: agentNeedsAttention) {
            await postNotification(
                kind: .agentCoolingAttention,
                title: "Vifty agent cooling needs attention",
                body: agentCoolingRecoverySuggestion
                    ?? agentCoolingSummary
                    ?? "Check Vifty before starting another developer workload."
            )
        }

        await evaluateThermalPressureNotification(thermalPressure)
        await evaluatePluggedInDrainNotification(power)
    }

    private func evaluateThermalPressureNotification(_ thermalPressure: ThermalPressure) async {
        let isElevated = thermalPressure == .serious || thermalPressure == .critical
        guard isElevated else {
            elevatedThermalPressureStartedAt = nil
            return
        }

        let currentDate = now()
        if elevatedThermalPressureStartedAt == nil {
            elevatedThermalPressureStartedAt = currentDate
        }

        guard let startedAt = elevatedThermalPressureStartedAt,
              currentDate.timeIntervalSince(startedAt) >= sustainedThermalPressureInterval
        else {
            return
        }

        await postNotification(
            kind: .elevatedThermalPressure,
            title: "Vifty thermal pressure is \(thermalPressure.displayName)",
            body: "macOS reports sustained \(thermalPressure.displayName.lowercased()) thermal pressure. Consider reducing workload or restoring Auto."
        )
    }

    private func evaluatePluggedInDrainNotification(_ power: PowerSnapshot) async {
        let isPluggedInDrain = power.isPluggedIn && power.batteryIsActivelyDraining
        if notificationTransitionState.shouldNotify(kind: .pluggedInBatteryDrain, isAttention: isPluggedInDrain) {
            let watts = power.batteryPowerWatts.map { PowerDisplayFormatter.watts(abs($0)) } ?? "battery power"
            await postNotification(
                kind: .pluggedInBatteryDrain,
                title: "Vifty sees battery drain while plugged in",
                body: "Battery is draining at \(watts) even though external power is connected."
            )
        }
    }

    private func notifyAutoRestoreFailure(_ message: String) async {
        await postNotification(
            kind: .autoRestoreFailure,
            title: "Vifty could not confirm Auto restore",
            body: message
        )
    }

    private func postNotification(kind: LocalNotificationKind, title: String, body: String) async {
        guard notificationSettings.isEnabled(kind) else { return }

        let currentDate = now()
        if notificationHistoryStore.isCoolingDown(
            kind,
            at: currentDate,
            minimumInterval: notificationMinimumInterval
        ) {
            return
        }

        let delivered = await notificationDeliverer.deliver(
            LocalNotification(kind: kind, title: title, body: body)
        )
        if delivered {
            do {
                try notificationHistoryStore.recordDelivery(of: kind, at: currentDate)
            } catch {
                ViftyLog.notifications.error(
                    "Notification cooldown persistence failed kind=\(kind.rawValue, privacy: .public)"
                )
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
