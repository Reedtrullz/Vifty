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
    @Published var savedProfiles: [CurveProfile] = []

    private let coordinator: FanControlCoordinator
    private let profileStore = CurveProfileStore()
    private var pollingTask: Task<Void, Never>?

    init(coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService())) {
        self.coordinator = coordinator
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
        do {
            let nextSnapshot = try await coordinator.tick()
            snapshot = nextSnapshot
            lastError = nil
            daemonReachable = await ViftyDaemonClient().ping()
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
        let mode: FanMode
        switch selectedMode {
        case .auto:
            mode = .auto
        case .fixed:
            mode = .fixedRPM(Int(fixedRPM.rounded()))
        case .curve:
            mode = .temperatureCurve(currentCurve())
        }

        Task {
            await coordinator.setMode(mode)
            await pollOnce()
        }
    }

    func restoreAuto() {
        selectedMode = .auto
        Task {
            await coordinator.setMode(.auto)
            await pollOnce()
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
        guard let snapshot else { return "Vifty" }
        let temp = snapshot.highestTemperature.map { "\(Int($0.celsius.rounded())) C" } ?? "-- C"
        let fan = snapshot.fans.first.map { "\($0.currentRPM) RPM" } ?? "No fan"
        return "\(temp) | \(fan)"
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

    private func syncCurveDefaultsIfNeeded(from snapshot: HardwareSnapshot) {
        guard let fan = snapshot.fans.first else { return }
        if curveStartRPM == 1400 {
            curveStartRPM = Double(fan.minimumRPM)
        }
        if curveMaxRPM == 6000 {
            curveMaxRPM = Double(fan.maximumRPM)
        }
        if selectedSensorID == nil {
            selectedSensorID = selectedSensor?.id
        }
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
