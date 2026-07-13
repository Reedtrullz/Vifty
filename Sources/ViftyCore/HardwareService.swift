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
    private var modeGeneration: UInt64 = 0

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
        modeGeneration &+= 1
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
        while true {
            let generation = modeGeneration
            let mode = state.mode
            lastObservedSnapshot = nil
            let snapshot = try await hardware.snapshot()
            guard generation == modeGeneration else { continue }
            lastObservedSnapshot = snapshot
            if mode != .auto, snapshot.temperatureSensors.isEmpty {
                guard try await restoreAuto(for: snapshot.fans, generation: generation) else { continue }
                autoRestoreRequested = false
                state.manualControlActive = false
                state.lastAppliedRPM = [:]
                lastManualWriteAtByFanID = [:]
                state.statusMessage = "Sensor unavailable, restored Auto"
                uncleanMarker.clear()
                throw ViftyError.noTemperatureSensors
            }
            try validate(snapshot, mode: mode)

            let wroteFanState: Bool
            switch mode {
            case .auto:
                wroteFanState = state.manualControlActive || autoRestoreRequested
                if wroteFanState {
                    guard try await restoreAuto(for: snapshot.fans, generation: generation) else { continue }
                }
                guard generation == modeGeneration else { continue }
                autoRestoreRequested = false
                state.manualControlActive = false
                state.lastAppliedRPM = [:]
                lastManualWriteAtByFanID = [:]
                state.statusMessage = "Auto"
                uncleanMarker.clear()
            case .fixedRPM(let rpm):
                guard let applied = try await applyFixedRPM(rpm, snapshot: snapshot, generation: generation) else { continue }
                wroteFanState = applied
                guard generation == modeGeneration else { continue }
                state.manualControlActive = true
                uncleanMarker.markActive()
            case .temperatureCurve(let curve):
                let applied: Bool?
                if fanOverrides.isEmpty {
                    applied = try await applyCurve(curve, snapshot: snapshot, generation: generation)
                } else {
                    applied = try await applyCurveWithOverrides(
                        curve,
                        fanOverrides: fanOverrides,
                        snapshot: snapshot,
                        generation: generation
                    )
                }
                guard let applied else { continue }
                wroteFanState = applied
                guard generation == modeGeneration else { continue }
                state.manualControlActive = true
                uncleanMarker.markActive()
            }

            guard generation == modeGeneration else { continue }
            guard wroteFanState else { return snapshot }

            let confirmedSnapshot = try await hardware.snapshot()
            guard generation == modeGeneration else { continue }
            lastObservedSnapshot = confirmedSnapshot
            if mode != .auto, confirmedSnapshot.temperatureSensors.isEmpty {
                guard try await restoreAuto(for: confirmedSnapshot.fans, generation: generation) else { continue }
                autoRestoreRequested = false
                state.manualControlActive = false
                state.lastAppliedRPM = [:]
                lastManualWriteAtByFanID = [:]
                state.statusMessage = "Sensor unavailable, restored Auto"
                uncleanMarker.clear()
                throw ViftyError.noTemperatureSensors
            }
            try validate(confirmedSnapshot, mode: mode)
            return confirmedSnapshot
        }
    }

    public func forceAuto() async -> AutoRestoreResult {
        let previousState = state
        let previousAutoRestoreRequested = autoRestoreRequested
        modeGeneration &+= 1
        let generation = modeGeneration
        state.mode = .auto
        autoRestoreRequested = true
        uncleanMarker.markActive()
        do {
            let snapshot = try await hardware.snapshot()
            guard generation == modeGeneration,
                  try await restoreAuto(for: snapshot.fans, generation: generation),
                  generation == modeGeneration else {
                return .failed(message: "Auto restore was superseded by a newer fan-control request")
            }
            autoRestoreRequested = false
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            lastManualWriteAtByFanID = [:]
            state.statusMessage = "Auto"
            uncleanMarker.clear()
            return .restored
        } catch {
            let message = error.localizedDescription
            if generation == modeGeneration {
                state = previousState
                state.statusMessage = "Auto restore failed: \(message)"
                autoRestoreRequested = previousAutoRestoreRequested
            }
            return .failed(message: message)
        }
    }

    public func recentManualWriteFanIDs(at date: Date, within interval: TimeInterval) -> Set<Int> {
        guard state.mode != .auto, interval > 0 else { return [] }
        return Set(lastManualWriteAtByFanID.compactMap { fanID, writtenAt in
            let age = date.timeIntervalSince(writtenAt)
            return age >= 0 && age < interval ? fanID : nil
        })
    }

    private func validate(_ snapshot: HardwareSnapshot, mode: FanMode? = nil) throws {
        guard snapshot.isAppleSilicon, snapshot.isMacBookPro else {
            throw ViftyError.unsupportedHardware(snapshot.modelIdentifier)
        }
        guard !snapshot.temperatureSensors.isEmpty else {
            throw ViftyError.noTemperatureSensors
        }
        if (mode ?? state.mode) != .auto, !snapshot.fans.contains(where: \.controllable) {
            throw ViftyError.noControllableFans
        }
    }

    private func applyFixedRPM(_ rpm: Int, snapshot: HardwareSnapshot, generation: UInt64) async throws -> Bool? {
        var appliedFanState = false
        for fan in snapshot.fans where fan.controllable {
            guard generation == modeGeneration else { return nil }
            let target = FanCurve.clamp(fixedFanTargets[fan.id] ?? rpm, fan.minimumRPM, fan.maximumRPM)
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            guard generation == modeGeneration else { return nil }
            appliedFanState = true
            state.lastAppliedRPM[fan.id] = target
            lastManualWriteAtByFanID[fan.id] = snapshot.capturedAt
        }
        state.statusMessage = fixedFanTargets.isEmpty ? "Fixed \(rpm) RPM" : "Fixed per-fan RPM"
        return appliedFanState
    }

    private func applyCurve(_ curve: FanCurve, snapshot: HardwareSnapshot, generation: UInt64) async throws -> Bool? {
        let sensor = selectedSensor(for: curve, snapshot: snapshot)
        guard let sensor else {
            try await restoreAuto(for: snapshot.fans)
            throw ViftyError.noTemperatureSensors
        }

        var appliedFanState = false
        for fan in snapshot.fans where fan.controllable {
            guard generation == modeGeneration else { return nil }
            let target = curve.targetRPM(
                for: sensor.celsius,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
            guard generation == modeGeneration else { return nil }
            appliedFanState = true
            state.lastAppliedRPM[fan.id] = target
            lastManualWriteAtByFanID[fan.id] = snapshot.capturedAt
        }

        state.selectedSensorID = sensor.id
        state.statusMessage = "\(sensor.name) \(sensor.celsius.rounded()) C"
        return appliedFanState
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

    @discardableResult
    private func restoreAuto(for fans: [Fan], generation: UInt64? = nil) async throws -> Bool {
        for fan in fans where fan.controllable {
            if let generation, generation != modeGeneration { return false }
            try await hardware.restoreAuto(fan: fan)
            if let generation, generation != modeGeneration { return false }
        }
        return true
    }

    @discardableResult
    public func applyCurveWithOverrides(_ curve: FanCurve, fanOverrides: [FanCurveOverride], snapshot: HardwareSnapshot) async throws -> Bool {
        try await applyCurveWithOverrides(
            curve,
            fanOverrides: fanOverrides,
            snapshot: snapshot,
            generation: nil
        ) ?? false
    }

    private func applyCurveWithOverrides(
        _ curve: FanCurve,
        fanOverrides: [FanCurveOverride],
        snapshot: HardwareSnapshot,
        generation: UInt64?
    ) async throws -> Bool? {
        let sensor = selectedSensor(for: curve, snapshot: snapshot)
        guard let sensor else {
            try await restoreAuto(for: snapshot.fans)
            throw ViftyError.noTemperatureSensors
        }

        let overridesByID = fanOverridesByID(fanOverrides)

        var appliedFanState = false
        for fan in snapshot.fans where fan.controllable {
            if let generation, generation != modeGeneration { return nil }
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
            if let generation, generation != modeGeneration { return nil }
            appliedFanState = true
            state.lastAppliedRPM[fan.id] = target
            lastManualWriteAtByFanID[fan.id] = snapshot.capturedAt
        }

        state.selectedSensorID = sensor.id
        state.statusMessage = "\(sensor.name) \(sensor.celsius.rounded()) C"
        return appliedFanState
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
