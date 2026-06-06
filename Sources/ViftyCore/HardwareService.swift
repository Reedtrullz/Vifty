import Foundation

public protocol HardwareService: Sendable {
    func snapshot() async throws -> HardwareSnapshot
    func apply(_ command: FanCommand, fan: Fan) async throws
    func restoreAuto(fan: Fan) async throws
}

public actor FanControlCoordinator {
    private let hardware: HardwareService
    private let uncleanMarker: ManualControlMarker
    private let significantRPMDelta: Int
    private var autoRestoreRequested = false

    public private(set) var state: ControlState

    public init(
        hardware: HardwareService,
        uncleanMarker: ManualControlMarker = ManualControlMarker(),
        significantRPMDelta: Int = 75,
        initialState: ControlState = ControlState()
    ) {
        self.hardware = hardware
        self.uncleanMarker = uncleanMarker
        self.significantRPMDelta = significantRPMDelta
        self.state = initialState
    }

    public func recoverIfNeeded() async {
        guard uncleanMarker.wasManualControlActive else { return }
        do {
            let snapshot = try await hardware.snapshot()
            try await restoreAuto(for: snapshot.fans)
            autoRestoreRequested = false
            uncleanMarker.clear()
            state.statusMessage = "Restored Auto after previous unclean exit"
        } catch {
            state.statusMessage = "Could not restore Auto after previous unclean exit: \(error.localizedDescription)"
        }
    }

    public func setMode(_ mode: FanMode) {
        state.mode = mode
        switch mode {
        case .auto:
            // An explicit Auto selection is an SMC command, not just UI state:
            // the hardware may still be in forced/manual mode even if our
            // previous state was already cleared.
            autoRestoreRequested = true
            uncleanMarker.markActive()
        case .fixedRPM, .temperatureCurve:
            autoRestoreRequested = false
            state.manualControlActive = true
            uncleanMarker.markActive()
        }
    }

    public func tick() async throws -> HardwareSnapshot {
        let snapshot = try await hardware.snapshot()
        if state.mode != .auto, snapshot.temperatureSensors.isEmpty {
            try await restoreAuto(for: snapshot.fans)
            autoRestoreRequested = false
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            state.statusMessage = "Sensor unavailable, restored Auto"
            uncleanMarker.clear()
            throw ViftyError.noTemperatureSensors
        }
        try validate(snapshot)

        switch state.mode {
        case .auto:
            if state.manualControlActive || autoRestoreRequested {
                try await restoreAuto(for: snapshot.fans)
            }
            autoRestoreRequested = false
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            state.statusMessage = "Auto"
            uncleanMarker.clear()
        case .fixedRPM(let rpm):
            try await applyFixedRPM(rpm, snapshot: snapshot)
            state.manualControlActive = true
            uncleanMarker.markActive()
        case .temperatureCurve(let curve):
            try await applyCurve(curve, snapshot: snapshot)
            state.manualControlActive = true
            uncleanMarker.markActive()
        }

        return snapshot
    }

    public func forceAuto() async {
        do {
            let snapshot = try await hardware.snapshot()
            try await restoreAuto(for: snapshot.fans)
            autoRestoreRequested = false
            state.mode = .auto
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            state.statusMessage = "Auto"
            uncleanMarker.clear()
        } catch {
            state.statusMessage = "Auto restore failed: \(error.localizedDescription)"
        }
    }

    private func validate(_ snapshot: HardwareSnapshot) throws {
        guard snapshot.isAppleSilicon, snapshot.isMacBookPro else {
            throw ViftyError.unsupportedHardware(snapshot.modelIdentifier)
        }
        guard !snapshot.temperatureSensors.isEmpty else {
            throw ViftyError.noTemperatureSensors
        }
        if state.mode != .auto, !snapshot.fans.contains(where: \.controllable) {
            throw ViftyError.noControllableFans
        }
    }

    private func applyFixedRPM(_ rpm: Int, snapshot: HardwareSnapshot) async throws {
        for fan in snapshot.fans where fan.controllable {
            let target = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
            guard shouldApply(target, to: fan.id) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            state.lastAppliedRPM[fan.id] = target
        }
        state.statusMessage = "Fixed \(rpm) RPM"
    }

    private func applyCurve(_ curve: FanCurve, snapshot: HardwareSnapshot) async throws {
        let sensor = selectedSensor(for: curve, snapshot: snapshot)
        guard let sensor else {
            try await restoreAuto(for: snapshot.fans)
            throw ViftyError.noTemperatureSensors
        }

        for fan in snapshot.fans where fan.controllable {
            let target = curve.targetRPM(
                for: sensor.celsius,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
            guard shouldApply(target, to: fan.id) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            state.lastAppliedRPM[fan.id] = target
        }

        state.selectedSensorID = sensor.id
        state.statusMessage = "\(sensor.name) \(sensor.celsius.rounded()) C"
    }

    private func selectedSensor(for curve: FanCurve, snapshot: HardwareSnapshot) -> TemperatureSensor? {
        if let sensorID = curve.sensorID ?? state.selectedSensorID,
           let exact = snapshot.temperatureSensors.first(where: { $0.id == sensorID }) {
            return exact
        }

        return snapshot.temperatureSensors.first { sensor in
            let lower = sensor.name.lowercased()
            return lower.contains("cpu") || lower.contains("package") || lower.contains("die")
        } ?? snapshot.highestTemperature
    }

    private func shouldApply(_ rpm: Int, to fanID: Int) -> Bool {
        guard let previous = state.lastAppliedRPM[fanID] else { return true }
        return abs(previous - rpm) >= significantRPMDelta
    }

    private func restoreAuto(for fans: [Fan]) async throws {
        for fan in fans where fan.controllable {
            try await hardware.restoreAuto(fan: fan)
        }
    }
}

public struct ManualControlMarker: Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/manual-control-active", isDirectory: false)
    }

    public var wasManualControlActive: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func markActive() {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("active".utf8).write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
