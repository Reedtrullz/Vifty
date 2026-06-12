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
    @Published var usePerFanOverrides = false
    @Published var fanOverrides: [FanCurveOverride] = []
    @Published var selectedSensorID: String?
    @Published var lastError: String?
    @Published var fanAccessMessage: String?
    @Published var daemonReachable = false
    @Published var isRunning = false
    @Published var powerSnapshot: PowerSnapshot?
    @Published var thermalPressure: ThermalPressure = .nominal
    @Published var telemetryHistory = TelemetryHistory()
    @Published var manualRunLimit: ManualRunLimit = .indefinitely
    @Published var manualSessionExpiresAt: Date?
    @Published var agentControlStatus: AgentControlStatus?
    var curveDefaultsSynced = false  // internal, accessible via @testable import
    @Published var savedProfiles: [CurveProfile] = []

    private let coordinator: FanControlCoordinator
    private let powerReader: @Sendable () -> PowerSnapshot
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let daemonPing: @Sendable () async -> Bool
    private let agentStatusReader: @Sendable () async -> AgentControlStatus?
    private let agentRestore: @Sendable (String) async throws -> AgentControlStatus?
    private let profileStore: CurveProfileStore
    private var pollingTask: Task<Void, Never>?

    init(
        coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService()),
        powerReader: @escaping @Sendable () -> PowerSnapshot = { PowerInfoReader.read() },
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        daemonPing: @escaping @Sendable () async -> Bool = { await ViftyDaemonClient().ping() },
        agentStatusReader: @escaping @Sendable () async -> AgentControlStatus? = {
            try? await ViftyDaemonClient().agentControlStatus()
        },
        agentRestore: @escaping @Sendable (String) async throws -> AgentControlStatus? = { reason in
            try await ViftyDaemonClient().restoreAgentControl(reason: reason)
        },
        profileStore: CurveProfileStore = CurveProfileStore()
    ) {
        self.coordinator = coordinator
        self.powerReader = powerReader
        self.thermalReader = thermalReader
        self.now = now
        self.daemonPing = daemonPing
        self.agentStatusReader = agentStatusReader
        self.agentRestore = agentRestore
        self.profileStore = profileStore
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
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        Task {
            await coordinator.forceAuto()
            await syncState()
        }
    }

    func pollOnce() async {
        let currentPower = powerReader()
        let currentThermalPressure = thermalReader()
        powerSnapshot = currentPower
        thermalPressure = currentThermalPressure
        _ = await restoreAutoIfManualSessionExpired()
        do {
            let nextSnapshot = try await coordinator.tick()
            snapshot = nextSnapshot
            telemetryHistory.append(TelemetrySample(
                capturedAt: now(),
                highestTemperatureCelsius: nextSnapshot.highestTemperature?.celsius,
                firstFanRPM: nextSnapshot.fans.first?.currentRPM,
                batteryPowerWatts: currentPower.batteryPowerWatts,
                thermalPressure: currentThermalPressure
            ))
            lastError = nil
            daemonReachable = await daemonPing() || !nextSnapshot.fans.isEmpty
            agentControlStatus = await agentStatusReader()
            fanAccessMessage = nextSnapshot.fans.isEmpty
                ? (daemonReachable ? "The fan helper is running but did not return fan data." : "Install and approve the fan helper to enable fan reads and control.")
                : nil
            syncCurveDefaultsIfNeeded(from: nextSnapshot)
            await syncState()
        } catch {
            lastError = error.localizedDescription
            daemonReachable = await daemonPing()
            agentControlStatus = await agentStatusReader()
            await coordinator.forceAuto()
            await syncState()
        }
    }

    func applyModeSelection() {
        Task { await applyCurrentModeSelection() }
    }

    func restoreAuto() {
        Task { await restoreAutoNow() }
    }

    func applyCurrentModeSelection() async {
        let mode = selectedFanMode()
        updateManualDeadline(for: mode)
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
        guard selectedMode == .curve else { return nil }
        guard let sensor = selectedSensor else { return nil }
        return currentCurve().targetRPM(
            for: sensor.celsius,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM
        )
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

    var menuTitle: String {
        var parts: [String]
        if let snapshot {
            let temp = snapshot.highestTemperature.map { "\(Int($0.celsius.rounded())) C" } ?? "-- C"
            let fan = snapshot.fans.first.map { "\($0.currentRPM) RPM" } ?? "No fan"
            parts = [temp, fan]
            if let powerSnapshot {
                parts.append(PowerDisplayFormatter.summary(for: powerSnapshot))
            }
        } else {
            parts = [powerSnapshot.map { PowerDisplayFormatter.summary(for: $0) } ?? "Vifty"]
        }
        if let thermal = thermalPressure.menuSummary {
            parts.append(thermal)
        }
        if let agentCoolingMenuSummary {
            parts.append(agentCoolingMenuSummary)
        }
        return parts.joined(separator: " | ")
    }

    var agentCoolingMenuSummary: String? {
        guard let lease = agentControlStatus?.activeLease else { return nil }
        return lease.isActive(at: now()) ? "Agent cooling" : "Agent restore pending"
    }

    var agentCoolingSummary: String? {
        guard let lease = agentControlStatus?.activeLease else { return nil }

        let state = if lease.isActive(at: now()) {
            "Agent \(lease.request.workload.displayName) cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))"
        } else {
            "Agent \(lease.request.workload.displayName) cooling expired; waiting for Auto restore"
        }

        let targets = lease.targetRPMByFanID
            .sorted { $0.key < $1.key }
            .map { "F\($0.key) \($0.value) RPM" }
            .joined(separator: ", ")

        return targets.isEmpty ? state : "\(state) · \(targets)"
    }

    var agentCoolingNeedsAttention: Bool {
        guard let lease = agentControlStatus?.activeLease else { return false }
        return !lease.isActive(at: now())
    }

    var controlOwnershipSummary: String {
        if let lease = agentControlStatus?.activeLease {
            if lease.isActive(at: now()) {
                return "Agent \(lease.request.workload.displayName) owns cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Agent \(lease.request.workload.displayName) lease expired; restore Auto to clear daemon control"
        }

        switch controlState.mode {
        case .auto:
            return autoControlOwnershipSummary
        case .fixedRPM(let rpm):
            return "Vifty Fixed owns fan targets · \(rpm) RPM"
        case .temperatureCurve:
            if let sensor = selectedSensor {
                return "Vifty Curve owns fan targets · \(sensor.name)"
            }
            return "Vifty Curve owns fan targets"
        }
    }

    var controlOwnershipNeedsAttention: Bool {
        if let lease = agentControlStatus?.activeLease {
            return !lease.isActive(at: now())
        }

        guard controlState.mode == .auto else { return false }
        return !autoSystemModeFans.isEmpty
            || !autoForcedModeFans.isEmpty
            || !autoUnknownModeFans.isEmpty
            || !autoMissingModeFans.isEmpty
    }

    var helperHealthSummary: String {
        if let lastError, lastError.localizedCaseInsensitiveContains("fan helper") {
            return "Fan helper error"
        }
        guard daemonReachable else {
            return "Fan helper unreachable"
        }
        let fanCount = snapshot?.fans.count ?? 0
        guard fanCount > 0 else {
            return "Fan helper reachable · no fan data"
        }
        return "Fan helper healthy · \(fanCount) fan\(fanCount == 1 ? "" : "s")"
    }

    var helperRecoverySuggestion: String? {
        if let lastError, lastError.localizedCaseInsensitiveContains("fan helper") {
            return "Use Repair to reinstall or approve the helper. Restore Auto first if fans appear stuck."
        }
        guard daemonReachable else {
            return "Use Repair/Reinstall to copy the daemon, strip quarantine, and restart launchd; fan writes stay blocked until it responds."
        }
        let fanCount = snapshot?.fans.count ?? 0
        guard fanCount > 0 else {
            return "Fan data is unavailable. Do not start manual or agent cooling until fans appear."
        }
        return nil
    }

    private var autoControlOwnershipSummary: String {
        guard let fans = snapshot?.fans, !fans.isEmpty else {
            return daemonReachable
                ? "Auto selected · fan hardware state unavailable"
                : "Auto selected · fan helper unreachable"
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

    private func clearAgentLeaseForUserAutoIfNeeded() async -> String? {
        guard agentControlStatus?.activeLease != nil else { return nil }
        do {
            agentControlStatus = try await agentRestore("User selected Auto in Vifty")
            return nil
        } catch {
            return "Failed to clear agent cooling lease after Auto restore: \(error.localizedDescription)"
        }
    }

    private func syncCurveDefaultsIfNeeded(from snapshot: HardwareSnapshot) {
        guard !curveDefaultsSynced, let fan = snapshot.fans.first else { return }
        curveStartRPM = Double(fan.minimumRPM)
        curveMaxRPM = Double(fan.maximumRPM)
        if selectedSensorID == nil {
            selectedSensorID = selectedSensor?.id
        }
        curveDefaultsSynced = true
    }

    private func defaultFanOverride(for fan: Fan) -> FanCurveOverride {
        FanCurveOverride(
            fanID: fan.id,
            startRPM: FanCurve.clamp(Int(curveStartRPM.rounded()), fan.minimumRPM, fan.maximumRPM),
            midRPM: FanCurve.clamp(Int(curveMidRPM.rounded()), fan.minimumRPM, fan.maximumRPM),
            maxRPM: FanCurve.clamp(Int(curveMaxRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
        )
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
}

enum ModeSelection: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case curve = "Curve"
    case fixed = "Fixed"

    var id: String { rawValue }
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
