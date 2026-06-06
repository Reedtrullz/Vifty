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
    var curveDefaultsSynced = false  // internal, accessible via @testable import
    @Published var savedProfiles: [CurveProfile] = []

    private let coordinator: FanControlCoordinator
    private let powerReader: @Sendable () -> PowerSnapshot
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let daemonPing: @Sendable () async -> Bool
    private let profileStore = CurveProfileStore()
    private var pollingTask: Task<Void, Never>?

    init(
        coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService()),
        powerReader: @escaping @Sendable () -> PowerSnapshot = { PowerInfoReader.read() },
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        daemonPing: @escaping @Sendable () async -> Bool = { await ViftyDaemonClient().ping() }
    ) {
        self.coordinator = coordinator
        self.powerReader = powerReader
        self.thermalReader = thermalReader
        self.now = now
        self.daemonPing = daemonPing
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
            daemonReachable = await daemonPing()
            fanAccessMessage = nextSnapshot.fans.isEmpty
                ? (daemonReachable ? "The fan helper is running but did not return fan data." : "Install and approve the fan helper to enable fan reads and control.")
                : nil
            syncCurveDefaultsIfNeeded(from: nextSnapshot)
            await syncState()
        } catch {
            lastError = error.localizedDescription
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
        await pollOnce()
    }

    func restoreAutoNow() async {
        selectedMode = .auto
        manualSessionExpiresAt = nil
        await coordinator.setMode(.auto)
        await pollOnce()
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
            maxRPM: Int(curveMaxRPM.rounded())
        )
        if let existingIndex = savedProfiles.firstIndex(where: { $0.name == name }) {
            savedProfiles[existingIndex] = profile
        } else {
            savedProfiles.append(profile)
        }
        profileStore.save(savedProfiles)
    }

    func loadProfile(_ profile: CurveProfile) {
        curveStartTemp = profile.startTemp
        curveStartRPM = Double(profile.startRPM)
        curveMidTemp = profile.midTemp
        curveMidRPM = Double(profile.midRPM)
        curveMaxTemp = profile.maxTemp
        curveMaxRPM = Double(profile.maxRPM)
        selectedSensorID = profile.sensorID
        applyModeSelection()
    }

    func deleteProfile(_ profile: CurveProfile) {
        savedProfiles.removeAll { $0.id == profile.id }
        profileStore.save(savedProfiles)
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
        guard let snapshot else { return powerSnapshot.map { PowerDisplayFormatter.summary(for: $0) } ?? "Vifty" }
        let temp = snapshot.highestTemperature.map { "\(Int($0.celsius.rounded())) C" } ?? "-- C"
        let fan = snapshot.fans.first.map { "\($0.currentRPM) RPM" } ?? "No fan"
        var parts = [temp, fan]
        if let powerSnapshot {
            parts.append(PowerDisplayFormatter.summary(for: powerSnapshot))
        }
        if let thermal = thermalPressure.menuSummary {
            parts.append(thermal)
        }
        return parts.joined(separator: " | ")
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

    var fanRange: ClosedRange<Double> {
        guard let fan = snapshot?.fans.first else { return 1200...6500 }
        return Double(fan.minimumRPM)...Double(fan.maximumRPM)
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

    private func syncCurveDefaultsIfNeeded(from snapshot: HardwareSnapshot) {
        guard !curveDefaultsSynced, let fan = snapshot.fans.first else { return }
        curveStartRPM = Double(fan.minimumRPM)
        curveMaxRPM = Double(fan.maximumRPM)
        if selectedSensorID == nil {
            selectedSensorID = selectedSensor?.id
        }
        curveDefaultsSynced = true
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
