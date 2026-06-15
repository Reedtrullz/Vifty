import Foundation
import SwiftUI
import ViftyCore

enum HelperHealthState: Equatable {
    case checking
    case healthy(fanCount: Int)
    case error
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
        case .error, .telemetryOnly, .unreachable:
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
        case .noFanData:
            return "Keep Auto selected and copy diagnose for read-only evidence."
        case .noControllableFans:
            return "Keep Auto selected and collect hardware validation evidence."
        case .unsupported:
            return "Read-only diagnostics only on this Mac."
        }
    }
}

enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable {
    case fanIcon
    case temperature
    case fanRPM
    case averageFanRPM
    case adapterWattage
    case temperatureAndRPM
    case compactSummary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fanIcon:
            return "Icon only"
        case .temperature:
            return "Temperature"
        case .fanRPM:
            return "Fan RPM"
        case .averageFanRPM:
            return "Average fan RPM"
        case .adapterWattage:
            return "Adapter wattage"
        case .temperatureAndRPM:
            return "Temperature + RPM"
        case .compactSummary:
            return "Compact summary"
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
    @Published var usePerFanFixedRPM = false
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
            persistAppPreferences()
        }
    }
    @Published var notificationSettings: LocalNotificationSettings {
        didSet {
            persistAppPreferences()
        }
    }
    @Published var telemetryHistory = TelemetryHistory()
    @Published var manualRunLimit: ManualRunLimit = .indefinitely {
        didSet {
            updateManualDeadlineForActiveManualMode()
        }
    }
    @Published var manualSessionExpiresAt: Date?
    @Published var agentControlStatus: AgentControlStatus?
    @Published var agentControlStatusError: String?
    @Published var hasCompletedHardwarePoll = false
    var curveDefaultsSynced = false  // internal, accessible via @testable import
    @Published var savedProfiles: [CurveProfile] = []
    private var isSettingSelectedSensorProgrammatically = false
    private var userSelectedSensorID: String?

    static let menuBarDisplayModeDefaultsKey = AppPreferencesStore.legacyMenuBarDisplayModeDefaultsKey
    static let highTemperatureAttentionThreshold = 90.0
    static let notificationHelperFailureDefaultsKey = AppPreferencesStore.legacyNotificationHelperFailureDefaultsKey
    static let notificationThermalPressureDefaultsKey = AppPreferencesStore.legacyNotificationThermalPressureDefaultsKey
    static let notificationAutoRestoreDefaultsKey = AppPreferencesStore.legacyNotificationAutoRestoreDefaultsKey
    static let notificationPluggedInDrainDefaultsKey = AppPreferencesStore.legacyNotificationPluggedInDrainDefaultsKey
    static let notificationAgentCoolingAttentionDefaultsKey = AppPreferencesStore.legacyNotificationAgentCoolingAttentionDefaultsKey
    static let manualTargetDriftRPMThreshold = 75

    private let coordinator: FanControlCoordinator
    private let powerReader: @Sendable () -> PowerSnapshot
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let notificationDeliverer: LocalNotificationDelivering
    private let daemonPing: @Sendable () async -> Bool
    private let agentStatusReader: @Sendable () async throws -> AgentControlStatus?
    private let agentRestore: @Sendable (String) async throws -> AgentControlStatus?
    private let profileStore: CurveProfileStore
    private let preferencesStore: AppPreferencesStore
    private var pollingTask: Task<Void, Never>?
    private var lastNotificationAt: [LocalNotificationKind: Date] = [:]
    private var previousHelperNeedsAttention = false
    private var previousPluggedInDrain = false
    private var previousAgentCoolingNeedsAttention = false
    private var elevatedThermalPressureStartedAt: Date?
    private let notificationMinimumInterval: TimeInterval = 10 * 60
    private let sustainedThermalPressureInterval: TimeInterval = 60

    init(
        coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService()),
        powerReader: @escaping @Sendable () -> PowerSnapshot = { PowerInfoReader.read() },
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        notificationDeliverer: LocalNotificationDelivering = UserNotificationDeliverer(),
        daemonPing: @escaping @Sendable () async -> Bool = { await ViftyDaemonClient().ping() },
        agentStatusReader: @escaping @Sendable () async throws -> AgentControlStatus? = {
            try await ViftyDaemonClient().agentControlStatus()
        },
        agentRestore: @escaping @Sendable (String) async throws -> AgentControlStatus? = { reason in
            try await ViftyDaemonClient().restoreAgentControl(reason: reason)
        },
        profileStore: CurveProfileStore = CurveProfileStore(),
        preferencesStore: AppPreferencesStore = AppPreferencesStore()
    ) {
        self.coordinator = coordinator
        self.powerReader = powerReader
        self.thermalReader = thermalReader
        self.now = now
        self.notificationDeliverer = notificationDeliverer
        self.daemonPing = daemonPing
        self.agentStatusReader = agentStatusReader
        self.agentRestore = agentRestore
        self.profileStore = profileStore
        self.preferencesStore = preferencesStore
        let appPreferences = self.preferencesStore.load()
        menuBarDisplayMode = appPreferences.menuBarDisplayMode
        notificationSettings = appPreferences.notificationSettings
        savedProfiles = profileStore.load()
    }

    func start() {
        guard pollingTask == nil else { return }
        isRunning = true

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await coordinator.recoverIfNeeded()

            while !Task.isCancelled {
                await pollOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        Task { await stopAndRestore() }
    }

    func stopAndRestore() async {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        selectedMode = .auto
        manualSessionExpiresAt = nil
        await coordinator.forceAuto()
        let agentRestoreError = await clearAgentLeaseForUserAutoIfNeeded()
        await syncState()
        if let agentRestoreError {
            lastError = agentRestoreError
            await notifyAutoRestoreFailure(agentRestoreError)
        }
    }

    func pollOnce() async {
        defer { hasCompletedHardwarePoll = true }
        let currentPower = powerReader()
        let currentThermalPressure = thermalReader()
        powerSnapshot = currentPower
        thermalPressure = currentThermalPressure
        _ = await restoreAutoIfManualSessionExpired()
        let stateBeforeTick = await coordinator.state
        do {
            let nextSnapshot = try await coordinator.tick()
            recordHardwareSnapshot(nextSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            lastError = nil
            daemonResponding = await daemonPing()
            daemonReachable = daemonResponding || !nextSnapshot.fans.isEmpty
            await refreshAgentControlStatus()
            fanAccessMessage = fanAccessMessage(for: nextSnapshot)
            await syncState()
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
        } catch {
            let preservesManualIntent = shouldPreserveManualIntent(
                afterTickFailure: error,
                attemptedMode: stateBeforeTick.mode
            )
            if preservesManualIntent, let observedSnapshot = await coordinator.lastObservedSnapshot {
                recordHardwareSnapshot(observedSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            }
            lastError = error.localizedDescription
            daemonResponding = await daemonPing()
            daemonReachable = daemonResponding || (preservesManualIntent && snapshot?.fans.isEmpty == false)
            await refreshAgentControlStatus()
            if preservesManualIntent, let snapshot {
                fanAccessMessage = fanAccessMessage(for: snapshot)
            }
            if preservesManualIntent {
                controlState = await coordinator.state
            } else {
                await coordinator.forceAuto()
                await syncState()
            }
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
        }
    }

    private func recordHardwareSnapshot(
        _ nextSnapshot: HardwareSnapshot,
        power: PowerSnapshot,
        thermalPressure: ThermalPressure
    ) {
        let selectedTelemetrySensor = telemetryTemperatureSensor(in: nextSnapshot)
        let temperatureWasUserSelected = userSelectedSensorID != nil && selectedTelemetrySensor?.id == userSelectedSensorID
        snapshot = nextSnapshot
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
        Task { await applyCurrentModeSelection() }
    }

    func restoreAuto() {
        Task { await restoreAutoNow() }
    }

    func applyCurrentModeSelection() async {
        let mode = selectedFanMode()
        if mode != .auto {
            await refreshManualControlPreflight()
        }
        if mode != .auto, let blockedReason = manualFanControlBlockedReason {
            selectedMode = .auto
            manualSessionExpiresAt = nil
            lastError = "Manual fan control blocked: \(blockedReason)"
            await syncState()
            return
        }

        updateManualDeadline(for: mode)
        await coordinator.setFixedFanTargets(fixedFanTargetMapForCurrentMode())
        await coordinator.setMode(mode)
        let agentRestoreError: String?
        if mode == .auto {
            agentRestoreError = await clearAgentLeaseForUserAutoIfNeeded()
        } else {
            agentRestoreError = nil
        }
        await pollOnce()
        if let agentRestoreError {
            lastError = agentRestoreError
            await notifyAutoRestoreFailure(agentRestoreError)
        }
    }

    func restoreAutoNow() async {
        selectedMode = .auto
        manualSessionExpiresAt = nil
        await coordinator.setMode(.auto)
        let agentRestoreError = await clearAgentLeaseForUserAutoIfNeeded()
        await pollOnce()
        if let agentRestoreError {
            lastError = agentRestoreError
            await notifyAutoRestoreFailure(agentRestoreError)
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
        applyModeSelection()
    }

    func loadDeveloperPreset(_ preset: DeveloperFanPreset) {
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
    }

    func deleteProfile(_ profile: CurveProfile) {
        savedProfiles.removeAll { $0.id == profile.id }
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
            if usePerFanFixedRPM, let target = fixedFanTarget(for: fan.id)?.rpm {
                return FanCurve.clamp(target, fan.minimumRPM, fan.maximumRPM)
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

    func ensureFixedFanTargets(for fans: [Fan]) {
        let existingByFanID = fixedFanTargets.reduce(into: [Int: FixedFanTarget]()) { targetsByID, target in
            targetsByID[target.fanID] = target
        }
        fixedFanTargets = fans.map { fan in
            if let existing = existingByFanID[fan.id] {
                return FixedFanTarget(
                    fanID: fan.id,
                    rpm: FanCurve.clamp(existing.rpm, fan.minimumRPM, fan.maximumRPM)
                )
            }
            return defaultFixedFanTarget(for: fan)
        }
    }

    func fixedFanTarget(for fanID: Int) -> FixedFanTarget? {
        fixedFanTargets.first { $0.fanID == fanID }
    }

    func setFixedFanRPM(_ rpm: Int, for fan: Fan) {
        updateFixedFanTarget(for: fan) { target in
            target.rpm = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
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
            return "Reduce heavy work now. Repair/Reinstall Helper; Vifty will retry \(manualModeName) when the daemon responds. Use Auto to stop retries."
        }
    }

    var visibleLastError: String? {
        guard let lastError else { return nil }
        guard !lastErrorIsCoveredByHelperRecovery(lastError) else { return nil }
        return lastError
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
        if fanWriteBlockedWhileHotSummary != nil {
            parts.append("Fan writes blocked")
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
            return menuBarTemperatureText ?? menuTitle
        case .fanRPM:
            return menuBarFanText ?? menuTitle
        case .averageFanRPM:
            return menuBarAverageFanText ?? menuTitle
        case .adapterWattage:
            return menuBarPowerText ?? menuTitle
        case .temperatureAndRPM:
            if let temperature = menuBarTemperatureText,
               let fan = menuBarFanText {
                return "\(temperature) | \(fan)"
            }
            return menuTitle
        case .compactSummary:
            return menuTitle
        }
    }

    var menuBarLabelUsesFanIcon: Bool {
        menuBarDisplayMode == .fanIcon || menuBarLabelText == "Vifty"
    }

    private var menuBarTemperatureText: String? {
        (selectedSensor ?? snapshot?.highestTemperature).map { "\(Int($0.celsius.rounded())) C" }
    }

    private var menuBarFanText: String? {
        snapshot?.fans.first.map { "\($0.currentRPM) RPM" }
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
            notificationSettings: notificationSettings
        ))
    }

    private var helperWritePathBlockedSummary: String? {
        switch helperHealthState {
        case .error, .unreachable:
            return "Fan writes blocked until helper responds"
        case .telemetryOnly:
            return "Read-only fan telemetry; repair helper for fan writes"
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            return nil
        }
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
            if usePerFanFixedRPM {
                return "Vifty Fixed owns fan targets · per-fan RPM · \(manualRunOwnershipSummary)"
            }
            return "Vifty Fixed owns fan targets · \(rpm) RPM · \(manualRunOwnershipSummary)"
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
        if let helperWritePathBlockedSummary {
            return helperWritePathBlockedSummary
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

        let drifted = fans.filter { fan in
            guard let targetRPM = fan.targetRPM,
                  let expectedRPM = expectedManualTargetRPM(for: fan) else {
                return false
            }
            return abs(targetRPM - expectedRPM) >= Self.manualTargetDriftRPMThreshold
        }
        guard !drifted.isEmpty else { return nil }
        return "Hardware fan target drift detected; Vifty will reassert · \(fanIDList(drifted))"
    }

    private func expectedManualTargetRPM(for fan: Fan) -> Int? {
        if let lastAppliedRPM = controlState.lastAppliedRPM[fan.id] {
            return lastAppliedRPM
        }

        switch controlState.mode {
        case .auto:
            return nil
        case .fixedRPM(let rpm):
            if usePerFanFixedRPM, let target = fixedFanTarget(for: fan.id)?.rpm {
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
        guard let fan = snapshot?.fans.first else { return 1200...6500 }
        return Double(fan.minimumRPM)...Double(fan.maximumRPM)
    }

    private func rpm(forPercent percent: Int) -> Int {
        guard let fan = snapshot?.fans.first else {
            let lower = Int(fanRange.lowerBound.rounded())
            let upper = Int(fanRange.upperBound.rounded())
            let span = upper - lower
            return FanCurve.clamp(lower + Int((Double(span) * Double(percent) / 100.0).rounded()), lower, upper)
        }

        let span = fan.maximumRPM - fan.minimumRPM
        let rpm = fan.minimumRPM + Int((Double(span) * Double(percent) / 100.0).rounded())
        return FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
    }

    private func currentCurve() -> FanCurve {
        FanCurve(sensorID: selectedSensorID, points: [
            CurvePoint(temperatureCelsius: curveStartTemp, rpm: Int(curveStartRPM.rounded())),
            CurvePoint(temperatureCelsius: curveMidTemp, rpm: Int(curveMidRPM.rounded())),
            CurvePoint(temperatureCelsius: curveMaxTemp, rpm: Int(curveMaxRPM.rounded()))
        ])
    }

    private func fixedFanTargetMapForCurrentMode() -> [Int: Int] {
        guard selectedMode == .fixed, usePerFanFixedRPM else { return [:] }
        if let fans = snapshot?.fans {
            ensureFixedFanTargets(for: fans)
        }
        return fixedFanTargets.reduce(into: [Int: Int]()) { targetsByID, target in
            targetsByID[target.fanID] = target.rpm
        }
    }

    private func selectedFanMode() -> FanMode {
        switch selectedMode {
        case .auto:
            .auto
        case .fixed:
            .fixedRPM(Int(fixedRPM.rounded()))
        case .curve:
            .temperatureCurve(currentCurve())
        }
    }

    func applyCurveOverrides() {
        Task {
            await coordinator.setFanOverrides(usePerFanOverrides ? fanOverrides : [])
            await applyCurrentModeSelection()
        }
    }

    private func updateManualDeadline(for mode: FanMode) {
        guard mode != .auto else {
            manualSessionExpiresAt = nil
            return
        }

        switch manualRunLimit {
        case .indefinitely:
            manualSessionExpiresAt = nil
        case .minutes(let minutes):
            manualSessionExpiresAt = now().addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    private func updateManualDeadlineForActiveManualMode() {
        guard controlState.mode != .auto else { return }
        updateManualDeadline(for: controlState.mode)
    }

    private func restoreAutoIfManualSessionExpired() async -> Bool {
        guard selectedMode != .auto,
              let manualSessionExpiresAt,
              now() >= manualSessionExpiresAt else {
            return false
        }

        selectedMode = .auto
        self.manualSessionExpiresAt = nil
        await coordinator.setMode(.auto)
        return true
    }

    private func shouldPreserveManualIntent(afterTickFailure error: Error, attemptedMode: FanMode) -> Bool {
        guard attemptedMode != .auto else { return false }
        guard let viftyError = error as? ViftyError else { return false }

        switch viftyError {
        case .helperRejected, .smcUnavailable, .smcOpenFailed, .smcCallFailed, .smcKeyUnavailable, .smcWriteRejected:
            return true
        case .unsupportedHardware, .noTemperatureSensors, .noControllableFans:
            return false
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
            rpm: FanCurve.clamp(Int(fixedRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
        )
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
        controlState = await coordinator.state
    }

    private func evaluateLocalNotifications(power: PowerSnapshot, thermalPressure: ThermalPressure) async {
        let helperNeedsAttention = helperHealthState.notifiesAsHelperFailure
        if helperNeedsAttention, !previousHelperNeedsAttention {
            await postNotification(
                kind: .helperFailure,
                title: helperFailureNotificationTitle,
                body: helperFailureNotificationBody
            )
        }
        previousHelperNeedsAttention = helperNeedsAttention

        let agentNeedsAttention = agentCoolingNeedsAttention
        if agentNeedsAttention, !previousAgentCoolingNeedsAttention {
            await postNotification(
                kind: .agentCoolingAttention,
                title: "Vifty agent cooling needs attention",
                body: agentCoolingRecoverySuggestion
                    ?? agentCoolingSummary
                    ?? "Check Vifty before starting another developer workload."
            )
        }
        previousAgentCoolingNeedsAttention = agentNeedsAttention

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
        if isPluggedInDrain, !previousPluggedInDrain {
            let watts = power.batteryPowerWatts.map { PowerDisplayFormatter.watts(abs($0)) } ?? "battery power"
            await postNotification(
                kind: .pluggedInBatteryDrain,
                title: "Vifty sees battery drain while plugged in",
                body: "Battery is draining at \(watts) even though external power is connected."
            )
        }
        previousPluggedInDrain = isPluggedInDrain
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
        if let previous = lastNotificationAt[kind],
           currentDate.timeIntervalSince(previous) < notificationMinimumInterval {
            return
        }

        lastNotificationAt[kind] = currentDate
        await notificationDeliverer.deliver(LocalNotification(kind: kind, title: title, body: body))
    }
}

enum ModeSelection: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case curve = "Curve"
    case fixed = "Fixed"

    var id: String { rawValue }
}

struct FixedFanTarget: Equatable, Identifiable, Sendable {
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
