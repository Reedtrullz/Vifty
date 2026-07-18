import Foundation

public protocol HardwareService: Sendable {
    func snapshot() async throws -> HardwareSnapshot
    func apply(_ command: FanCommand, fan: Fan) async throws
    func restoreAuto(fan: Fan) async throws
    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus
    func applyManualFanControl(_ request: ManualFanControlRequest) async throws -> FanControlTransactionResult
    func applyAgentFanControl(_ request: AgentFanControlRequest) async throws -> FanControlTransactionResult
    func restoreFanControlIfOwned(
        transactionID: String,
        owner: FanControlOwner,
        reason: String,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult?
    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult
}

public extension HardwareService {
    /// Compatibility behavior for deterministic fake hardware only. Production
    /// hardware services must override these methods with one daemon transaction.
    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        .osManaged
    }

    func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        try await applyCompatibilityBatch(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            expectedFanIDs: request.expectedFanIDs,
            targetRPMByFanID: request.targetRPMByFanID
        )
    }

    func applyAgentFanControl(
        _ request: AgentFanControlRequest
    ) async throws -> FanControlTransactionResult {
        try await applyCompatibilityBatch(
            transactionID: request.transactionID,
            owner: .agent(leaseID: request.leaseID),
            expectedFanIDs: request.expectedFanIDs,
            targetRPMByFanID: request.targetRPMByFanID
        )
    }

    /// This operation must compare ownership and begin restoration inside the
    /// same daemon arbiter isolation domain. A read-then-restore fallback would
    /// reintroduce a TOCTOU window and is therefore deliberately unavailable.
    func restoreFanControlIfOwned(
        transactionID: String,
        owner: FanControlOwner,
        reason: String,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult? {
        throw ViftyError.helperRejected(
            "Atomic owner-conditional Auto restoration is unavailable for this hardware service."
        )
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        let currentSnapshot = try await snapshot()
        let expectedFanIDs: [Int]
        if request.expectedFanIDs.isEmpty && request.allowRestoreAllTrustedFans {
            guard !currentSnapshot.fans.isEmpty,
                  currentSnapshot.fans.map(\.id).count == Set(currentSnapshot.fans.map(\.id)).count,
                  currentSnapshot.fans.allSatisfy({
                      SMCFanControlKeys.isValidFanID($0.id)
                          && $0.controlEligibility.canRestoreOSManagedMode
                  }) else {
                throw ViftyError.helperRejected(
                    "Global Auto restore requires one complete trusted fan inventory."
                )
            }
            expectedFanIDs = currentSnapshot.fans.map(\.id).sorted()
        } else {
            expectedFanIDs = request.expectedFanIDs
        }
        let fansByID = Dictionary(uniqueKeysWithValues: currentSnapshot.fans.map { ($0.id, $0) })
        for fanID in expectedFanIDs {
            guard let fan = fansByID[fanID] else {
                throw ViftyError.helperRejected("Expected fan \(fanID) is missing from fake restore telemetry.")
            }
            try await restoreAuto(fan: fan)
        }
        try beforeOwnershipClear()
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: nil,
            phase: nil,
            expectedFanIDs: expectedFanIDs,
            confirmedFanIDs: expectedFanIDs
        )
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest
    ) async throws -> FanControlTransactionResult {
        try await restoreAllAuto(request, beforeOwnershipClear: {})
    }

    private func applyCompatibilityBatch(
        transactionID: String,
        owner: FanControlOwner,
        expectedFanIDs: [Int],
        targetRPMByFanID: [Int: Int]
    ) async throws -> FanControlTransactionResult {
        let currentSnapshot = try await snapshot()
        let fansByID = Dictionary(uniqueKeysWithValues: currentSnapshot.fans.map { ($0.id, $0) })
        for fanID in targetRPMByFanID.keys.sorted() {
            guard let fan = fansByID[fanID], let rpm = targetRPMByFanID[fanID] else {
                throw ViftyError.helperRejected("Fan \(fanID) is missing from fake batch telemetry.")
            }
            try await apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
        }
        return FanControlTransactionResult(
            transactionID: transactionID,
            owner: owner,
            phase: .active,
            expectedFanIDs: expectedFanIDs,
            confirmedFanIDs: expectedFanIDs
        )
    }
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
    private var manualSessionID: String?
    private var pendingAutoUnreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority?

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
        let markerWasActive = uncleanMarker.wasManualControlActive
        let ownershipWasClean: Bool
        do {
            ownershipWasClean = Self.confirmsCleanOSOwnership(
                try await hardware.fanControlOwnershipStatus()
            )
        } catch {
            // An unreadable daemon ownership state is not equivalent to Auto.
            // Keep recovery fail-closed and make one full-Auto attempt below.
            ownershipWasClean = false
        }
        guard markerWasActive || !ownershipWasClean else { return }

        modeGeneration &+= 1
        let generation = modeGeneration
        state.mode = .auto
        state.manualControlActive = true
        autoRestoreRequested = true
        lastManualWriteAtByFanID = [:]
        manualSessionID = nil
        pendingAutoUnreadableJournalRecoveryAuthority = nil
        uncleanMarker.markActive()
        do {
            let snapshot = try await hardware.snapshot()
            guard try await restoreAuto(for: snapshot.fans, generation: generation),
                  generation == modeGeneration else { return }
            let confirmedOwnership = try await hardware.fanControlOwnershipStatus()
            guard Self.confirmsCleanOSOwnership(confirmedOwnership) else {
                throw ViftyError.helperRejected(
                    "Full Auto completed without clean daemon ownership confirmation."
                )
            }
            autoRestoreRequested = false
            state.manualControlActive = false
            state.lastAppliedRPM = [:]
            uncleanMarker.clear()
            state.statusMessage = markerWasActive
                ? "Restored Auto after previous unclean exit"
                : "Restored Auto after daemon ownership recovery"
        } catch {
            guard generation == modeGeneration else { return }
            state.statusMessage = "Could not confirm Auto during startup recovery: \(error.localizedDescription)"
        }
    }

    public nonisolated static func confirmsCleanOSOwnership(
        _ status: FanControlOwnershipStatus
    ) -> Bool {
        status.protocolVersion == FanControlProtocolVersion.current
            && status.owner == nil
            && status.phase == nil
            && status.transactionID == nil
            && status.expectedFanIDs.isEmpty
            && status.confirmedOSManagedFanIDs.isEmpty
            && !status.recoveryPending
            && status.errorCode == nil
            && status.errorMessage == nil
    }

    public func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        try await hardware.fanControlOwnershipStatus()
    }

    /// Returns only after a fresh daemon read proves the active manual owner is
    /// the exact coordinator session that issued the current Apply request.
    /// Local mode state alone is never sufficient confirmation.
    public func confirmCurrentManualOwnership() async throws -> FanControlOwnershipStatus {
        guard state.mode != .auto,
              state.manualControlActive,
              let manualSessionID else {
            throw ViftyError.helperRejected(
                "No current manual fan-control session is available for confirmation."
            )
        }

        let status = try await hardware.fanControlOwnershipStatus()
        guard status.protocolVersion == FanControlProtocolVersion.current,
              status.owner == .manual(sessionID: manualSessionID),
              status.phase == .active,
              status.transactionID == manualSessionID,
              !status.expectedFanIDs.isEmpty,
              status.confirmedOSManagedFanIDs.isEmpty,
              !status.recoveryPending,
              status.errorCode == nil,
              status.errorMessage == nil else {
            throw ViftyError.helperRejected(
                "Daemon did not confirm the current Vifty manual fan-control transaction."
            )
        }
        return status
    }

    public func setMode(
        _ mode: FanMode,
        unreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority? = nil
    ) {
        let previousMode = state.mode
        modeGeneration &+= 1
        state.mode = mode
        switch mode {
        case .auto:
            autoRestoreRequested = true
            pendingAutoUnreadableJournalRecoveryAuthority = unreadableJournalRecoveryAuthority
            lastManualWriteAtByFanID = [:]
            uncleanMarker.markActive()
        case .fixedRPM, .temperatureCurve:
            pendingAutoUnreadableJournalRecoveryAuthority = nil
            if previousMode == .auto || manualSessionID == nil {
                manualSessionID = UUID().uuidString
            }
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
            let autoUnreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority?
            if mode == .auto {
                // Operator authority is a one-attempt capability. Consume it
                // before even reading telemetry so a failed poll or daemon call
                // cannot silently reuse the click on a later background tick.
                autoUnreadableJournalRecoveryAuthority = pendingAutoUnreadableJournalRecoveryAuthority
                pendingAutoUnreadableJournalRecoveryAuthority = nil
            } else {
                autoUnreadableJournalRecoveryAuthority = nil
            }
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
                manualSessionID = nil
                state.statusMessage = "Sensor unavailable, restored Auto"
                uncleanMarker.clear()
                throw ViftyError.noTemperatureSensors
            }
            try validate(snapshot, mode: mode)

            let wroteFanState: Bool
            switch mode {
            case .auto:
                // A persisted marker is authoritative recovery evidence even
                // when in-memory state was lost in a previous process. Never
                // let an ordinary Auto telemetry poll erase it without first
                // completing a daemon-confirmed Auto transaction.
                wroteFanState = state.manualControlActive
                    || autoRestoreRequested
                    || uncleanMarker.wasManualControlActive
                if wroteFanState {
                    guard try await restoreAuto(
                        for: snapshot.fans,
                        generation: generation,
                        unreadableJournalRecoveryAuthority: autoUnreadableJournalRecoveryAuthority
                    ) else { continue }
                }
                guard generation == modeGeneration else { continue }
                autoRestoreRequested = false
                state.manualControlActive = false
                state.lastAppliedRPM = [:]
                lastManualWriteAtByFanID = [:]
                state.statusMessage = "Auto"
                manualSessionID = nil
                pendingAutoUnreadableJournalRecoveryAuthority = nil
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
                manualSessionID = nil
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
        pendingAutoUnreadableJournalRecoveryAuthority = nil
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
            manualSessionID = nil
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
        if (mode ?? state.mode) != .auto {
            guard !snapshot.temperatureSensors.isEmpty else {
                throw ViftyError.noTemperatureSensors
            }
            guard snapshot.fans.contains(where: \.controllable) else {
                throw ViftyError.noControllableFans
            }
        }
    }

    private func applyFixedRPM(_ rpm: Int, snapshot: HardwareSnapshot, generation: UInt64) async throws -> Bool? {
        var targets: [Int: Int] = [:]
        for fan in snapshot.fans where fan.controllable {
            guard generation == modeGeneration else { return nil }
            let target = FanCurve.clamp(fixedFanTargets[fan.id] ?? rpm, fan.minimumRPM, fan.maximumRPM)
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            targets[fan.id] = target
        }
        guard let appliedFanState = try await applyManualBatch(
            targets,
            snapshot: snapshot,
            generation: generation,
            reason: "User applied Fixed"
        ) else { return nil }
        state.statusMessage = fixedFanTargets.isEmpty ? "Fixed \(rpm) RPM" : "Fixed per-fan RPM"
        return appliedFanState
    }

    private func applyCurve(_ curve: FanCurve, snapshot: HardwareSnapshot, generation: UInt64) async throws -> Bool? {
        let sensor = selectedSensor(for: curve, snapshot: snapshot)
        guard let sensor else {
            try await restoreAuto(for: snapshot.fans)
            throw ViftyError.noTemperatureSensors
        }

        var targets: [Int: Int] = [:]
        for fan in snapshot.fans where fan.controllable {
            guard generation == modeGeneration else { return nil }
            let target = curve.targetRPM(
                for: sensor.celsius,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            targets[fan.id] = target
        }

        guard let appliedFanState = try await applyManualBatch(
            targets,
            snapshot: snapshot,
            generation: generation,
            reason: "User applied Temperature Curve"
        ) else { return nil }

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
        try await restoreAuto(
            for: fans,
            generation: generation,
            unreadableJournalRecoveryAuthority: nil
        )
    }

    @discardableResult
    private func restoreAuto(
        for _: [Fan],
        generation: UInt64? = nil,
        unreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority?
    ) async throws -> Bool {
        if let generation, generation != modeGeneration { return false }
        _ = try await hardware.restoreAllAuto(
            AutoRestoreRequest(
                transactionID: "restore-\(UUID().uuidString)",
                expectedFanIDs: [],
                reason: "User/app requested Auto",
                allowRestoreAllTrustedFans: true,
                unreadableJournalRecoveryAuthority: unreadableJournalRecoveryAuthority
            )
        )
        if let generation, generation != modeGeneration { return false }
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

        var targets: [Int: Int] = [:]
        for fan in snapshot.fans where fan.controllable {
            if let generation, generation != modeGeneration { return nil }
            let target = FanCurveTargetResolver.targetRPM(
                baseCurve: curve,
                fan: fan,
                temperature: sensor.celsius,
                overrides: fanOverrides
            )
            guard shouldApply(target, to: fan, capturedAt: snapshot.capturedAt) else { continue }
            targets[fan.id] = target
        }

        let appliedFanState: Bool
        if let generation {
            guard let result = try await applyManualBatch(
                targets,
                snapshot: snapshot,
                generation: generation,
                reason: "User applied Temperature Curve overrides"
            ) else { return nil }
            appliedFanState = result
        } else {
            let currentGeneration = modeGeneration
            guard let result = try await applyManualBatch(
                targets,
                snapshot: snapshot,
                generation: currentGeneration,
                reason: "User applied Temperature Curve overrides"
            ) else { return nil }
            appliedFanState = result
        }

        state.selectedSensorID = sensor.id
        state.statusMessage = "\(sensor.name) \(sensor.celsius.rounded()) C"
        return appliedFanState
    }

    private func applyManualBatch(
        _ targetRPMByFanID: [Int: Int],
        snapshot: HardwareSnapshot,
        generation: UInt64,
        reason: String
    ) async throws -> Bool? {
        guard generation == modeGeneration else { return nil }
        guard !targetRPMByFanID.isEmpty else { return false }
        let expectedFanIDs = snapshot.fans
            .filter { $0.controllable && $0.controlEligibility.canApplyFixedRPM }
            .map(\.id)
            .sorted()
        guard !expectedFanIDs.isEmpty else { throw ViftyError.noControllableFans }
        let sessionID = manualSessionID ?? UUID().uuidString
        manualSessionID = sessionID
        _ = try await hardware.applyManualFanControl(
            ManualFanControlRequest(
                transactionID: sessionID,
                sessionID: sessionID,
                expectedFanIDs: expectedFanIDs,
                targetRPMByFanID: targetRPMByFanID,
                reason: reason
            )
        )
        guard generation == modeGeneration else { return nil }
        for (fanID, target) in targetRPMByFanID {
            state.lastAppliedRPM[fanID] = target
            lastManualWriteAtByFanID[fanID] = snapshot.capturedAt
        }
        return true
    }
}

public struct ManualControlMarker: Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.resolvedDefaultURLForCurrentProcess
    }

    static var resolvedDefaultURLForCurrentProcess: URL {
        if isRunningUnderXCTest {
            return xctestDefaultURL
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/manual-control-active", isDirectory: false)
    }

    private static let xctestDefaultURL = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("vifty-manual-control-marker-xctest", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("manual-control-active", isDirectory: false)

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
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
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: url.path
            )
            return
        }
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
