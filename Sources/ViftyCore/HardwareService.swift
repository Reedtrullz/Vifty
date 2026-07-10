import Foundation

public protocol HardwareService: Sendable {
    func snapshot() async throws -> HardwareSnapshot
    func apply(_ command: FanCommand, fan: Fan) async throws
    func restoreAuto(fan: Fan) async throws
}

public enum AutoRestoreResult: Sendable, Equatable {
    case restored
    case failed(message: String)
}

public actor FanControlCoordinator {
    private let hardware: HardwareService
    private let uncleanMarker: ManualControlMarker
    private let significantRPMDelta: Int
    private let manualReassertionInterval: TimeInterval
    private var autoRestoreRequested = false
    private var fanOverrides: [FanCurveOverride] = []
    private var fixedFanTargets: [Int: Int] = [:]
    private var lastManualWriteAtByFanID: [Int: Date] = [:]

    public private(set) var state: ControlState
    public private(set) var lastObservedSnapshot: HardwareSnapshot?

    public init(
        hardware: HardwareService,
        uncleanMarker: ManualControlMarker = ManualControlMarker(),
        significantRPMDelta: Int = 75,
        manualReassertionInterval: TimeInterval = 30,
        initialState: ControlState = ControlState()
    ) {
        self.hardware = hardware
        self.uncleanMarker = uncleanMarker
        self.significantRPMDelta = significantRPMDelta
        self.manualReassertionInterval = manualReassertionInterval
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
            autoRestoreRequested = true
            lastManualWriteAtByFanID = [:]
            uncleanMarker.markActive()
        case .fixedRPM, .temperatureCurve:
            autoRestoreRequested = false
            lastManualWriteAtByFanID = [:]
            state.manualControlActive = true
            uncleanMarker.markActive()
        }
    }

    public func setFanOverrides(_ overrides: [FanCurveOverride]) {
        fanOverrides = overrides
    }

    public func setFixedFanTargets(_ targets: [Int: Int]) {
        fixedFanTargets = targets
    }

    public func tick() async throws -> HardwareSnapshot {
        lastObservedSnapshot = nil
        let snapshot = try await hardware.snapshot()
        lastObservedSnapshot = snapshot
        if state.mode != .auto, snapshot.temperatureSensors.isEmpty {
            try await restoreAuto(for: snapshot.fans)
            autoRestoreRequested = false
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            lastManualWriteAtByFanID = [:]
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
            lastManualWriteAtByFanID = [:]
            state.statusMessage = "Auto"
            uncleanMarker.clear()
        case .fixedRPM(let rpm):
            try await applyFixedRPM(rpm, snapshot: snapshot)
            state.manualControlActive = true
            uncleanMarker.markActive()
        case .temperatureCurve(let curve):
            if fanOverrides.isEmpty {
                try await applyCurve(curve, snapshot: snapshot)
            } else {
                try await applyCurveWithOverrides(curve, fanOverrides: fanOverrides, snapshot: snapshot)
            }
            state.manualControlActive = true
            uncleanMarker.markActive()
        }

        return snapshot
    }

    public func forceAuto() async -> AutoRestoreResult {
        do {
            let snapshot = try await hardware.snapshot()
            try await restoreAuto(for: snapshot.fans)
            autoRestoreRequested = false
            state.mode = .auto
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            lastManualWriteAtByFanID = [:]
            state.statusMessage = "Auto"
            uncleanMarker.clear()
            return .restored
        } catch {
            let message = error.localizedDescription
            state.statusMessage = "Auto restore failed: \(message)"
            return .failed(message: message)
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
            let target = FanCurve.clamp(fixedFanTargets[fan.id] ?? rpm, fan.minimumRPM, fan.maximumRPM)
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            state.lastAppliedRPM[fan.id] = target
            lastManualWriteAtByFanID[fan.id] = snapshot.capturedAt
        }
        state.statusMessage = fixedFanTargets.isEmpty ? "Fixed \(rpm) RPM" : "Fixed per-fan RPM"
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
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            state.lastAppliedRPM[fan.id] = target
            lastManualWriteAtByFanID[fan.id] = snapshot.capturedAt
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

    private func shouldApply(_ rpm: Int, to fan: Fan, capturedAt: Date) -> Bool {
        if hardwareNeedsManualReassertion(rpm, fan: fan) {
            return true
        }
        guard let previous = state.lastAppliedRPM[fan.id] else { return true }
        if abs(previous - rpm) >= significantRPMDelta {
            return true
        }
        return manualReassertionDue(for: fan, capturedAt: capturedAt)
    }

    private func hardwareNeedsManualReassertion(_ rpm: Int, fan: Fan) -> Bool {
        if let hardwareMode = fan.hardwareMode, hardwareMode != .forced {
            return true
        }
        if let targetRPM = fan.targetRPM {
            return abs(targetRPM - rpm) >= significantRPMDelta
        }
        return false
    }

    private func manualReassertionDue(for fan: Fan, capturedAt: Date) -> Bool {
        guard manualReassertionInterval > 0 else { return false }
        guard let lastWriteAt = lastManualWriteAtByFanID[fan.id] else { return true }
        return capturedAt.timeIntervalSince(lastWriteAt) >= manualReassertionInterval
    }

    private func restoreAuto(for fans: [Fan]) async throws {
        for fan in fans where fan.controllable {
            try await hardware.restoreAuto(fan: fan)
        }
    }

    public func applyCurveWithOverrides(_ curve: FanCurve, fanOverrides: [FanCurveOverride], snapshot: HardwareSnapshot) async throws {
        let sensor = selectedSensor(for: curve, snapshot: snapshot)
        guard let sensor else {
            try await restoreAuto(for: snapshot.fans)
            throw ViftyError.noTemperatureSensors
        }

        let overridesByID = fanOverridesByID(fanOverrides)

        for fan in snapshot.fans where fan.controllable {
            let target: Int
            if let override = overridesByID[fan.id],
               let fanCurve = curve.applying(override: override) {
                target = fanCurve.targetRPM(
                    for: sensor.celsius,
                    minimumRPM: fan.minimumRPM,
                    maximumRPM: fan.maximumRPM
                )
            } else {
                target = curve.targetRPM(
                    for: sensor.celsius,
                    minimumRPM: fan.minimumRPM,
                    maximumRPM: fan.maximumRPM
                )
            }
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            state.lastAppliedRPM[fan.id] = target
            lastManualWriteAtByFanID[fan.id] = snapshot.capturedAt
        }

        state.selectedSensorID = sensor.id
        state.statusMessage = "\(sensor.name) \(sensor.celsius.rounded()) C"
    }

    private func fanOverridesByID(_ overrides: [FanCurveOverride]) -> [Int: FanCurveOverride] {
        overrides.reduce(into: [:]) { byID, override in
            byID[override.fanID] = override
        }
    }
}

private extension FanCurve {
    func applying(override: FanCurveOverride) -> FanCurve? {
        let sortedPoints = points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        guard let first = sortedPoints.first,
              let last = sortedPoints.last,
              sortedPoints.count >= 3 else {
            return nil
        }
        let middle = sortedPoints[sortedPoints.count / 2]
        return FanCurve(sensorID: sensorID, points: [
            CurvePoint(temperatureCelsius: first.temperatureCelsius, rpm: override.startRPM),
            CurvePoint(temperatureCelsius: middle.temperatureCelsius, rpm: override.midRPM),
            CurvePoint(temperatureCelsius: last.temperatureCelsius, rpm: override.maxRPM)
        ])
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
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
        try? Data("active".utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
