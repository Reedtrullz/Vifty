import Foundation

public struct AgentControlScheduledExpiry: Sendable {
    private let cancelHandler: @Sendable () -> Void

    public init(_ cancelHandler: @escaping @Sendable () -> Void) {
        self.cancelHandler = cancelHandler
    }

    public func cancel() {
        cancelHandler()
    }
}

public typealias AgentControlExpiryScheduler = @Sendable (_ delay: TimeInterval, _ operation: @escaping @Sendable () async -> Void) -> AgentControlScheduledExpiry

public enum AgentControlDefaultScheduler {
    public static func schedule(after delay: TimeInterval, operation: @escaping @Sendable () async -> Void) -> AgentControlScheduledExpiry {
        let task = Task {
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await operation()
        }
        return AgentControlScheduledExpiry {
            task.cancel()
        }
    }
}

public actor AgentControlService {
    private let hardware: HardwareService
    private let policy: AgentControlPolicy
    private let store: AgentControlStore
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let leaseID: @Sendable () -> String
    private let expiryScheduler: AgentControlExpiryScheduler

    private var activeLease: AgentCoolingLease?
    private var lastDecision: AgentControlDecision?
    private var lastErrorCode: AgentControlErrorCode?
    private var operationInProgress = false
    private var scheduledExpiry: AgentControlScheduledExpiry?
    private var lastPrepareCompletedAt: Date?
    private let monitorIntervalSeconds: TimeInterval = 5

    public init(
        hardware: HardwareService,
        policy: AgentControlPolicy,
        store: AgentControlStore = AgentControlStore(),
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        leaseID: @escaping @Sendable () -> String = { UUID().uuidString },
        expiryScheduler: @escaping AgentControlExpiryScheduler = AgentControlDefaultScheduler.schedule(after:operation:)
    ) {
        self.hardware = hardware
        self.policy = policy
        self.store = store
        self.thermalReader = thermalReader
        self.now = now
        self.leaseID = leaseID
        self.expiryScheduler = expiryScheduler
        self.activeLease = try? store.loadActiveLease()
        self.scheduledExpiry = nil
        if let activeLease {
            Task { [weak self] in
                await self?.scheduleMonitor(for: activeLease)
            }
        }
    }

    public func status() -> AgentControlStatus {
        let currentTime = now()
        let lease = activeLease?.isActive(at: currentTime) == true ? activeLease : nil
        return AgentControlStatus(
            enabled: policy.enabled,
            activeLease: lease,
            lastDecision: lastDecision,
            lastErrorCode: lastErrorCode
        )
    }

    public func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        try beginOperation()
        defer { endOperation() }

        if let lease = activeLease,
           lease.request.idempotencyKey == request.idempotencyKey,
           lease.isActive(at: now()) {
            return status()
        }

        if let lease = activeLease,
           lease.isActive(at: now()) {
            let decision = AgentControlDecision.denied(
                .policyDenied,
                message: "Agent cooling lease already active. Restore Auto before starting a new lease."
            )
            lastDecision = decision
            lastErrorCode = decision.errorCode
            appendAudit(action: "prepare-denied", leaseID: lease.id, message: decision.message)
            return status()
        }

        if let lastPrepare = lastPrepareCompletedAt,
           now().timeIntervalSince(lastPrepare) < Double(policy.prepareCooldownSeconds) {
            let remaining = policy.prepareCooldownSeconds - Int(now().timeIntervalSince(lastPrepare))
            let decision = AgentControlDecision.denied(
                .prepareRateLimited,
                message: "Prepare rate-limited. Wait \(remaining)s between prepare calls."
            )
            lastDecision = decision
            lastErrorCode = decision.errorCode
            appendAudit(action: "prepare-rate-limited", leaseID: nil, message: decision.message)
            return status()
        }

        let snapshot = try await hardware.snapshot()
        let decision = policy.evaluate(request, snapshot: snapshot, thermalPressure: thermalReader())
        lastDecision = decision
        lastErrorCode = decision.errorCode

        guard decision.allowed else {
            appendAudit(action: "prepare-denied", leaseID: nil, message: decision.message)
            return status()
        }

        var appliedFans: [Fan] = []
        var rollbackLeaseID: String?

        do {
            for fan in snapshot.fans where fan.controllable {
                guard let target = decision.targetRPMByFanID[fan.id] else { continue }
                let command = FanCommand(fanID: fan.id, mode: .fixedRPM(target))
                try await hardware.apply(command, fan: fan)
                appliedFans.append(fan)
            }

            let createdAt = now()
            let lease = AgentCoolingLease(
                id: leaseID(),
                request: request,
                createdAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(TimeInterval(request.durationSeconds)),
                targetRPMByFanID: decision.targetRPMByFanID
            )
            rollbackLeaseID = lease.id
            activeLease = lease
            try store.saveActiveLease(lease)
            scheduleMonitor(for: lease)
            lastPrepareCompletedAt = now()
            appendAudit(action: "prepare", leaseID: lease.id, message: request.reason)
            return status()
        } catch {
            for fan in appliedFans {
                do {
                    try await hardware.restoreAuto(fan: fan)
                } catch {
                    appendAudit(action: "prepare-rollback-failure", leaseID: rollbackLeaseID,
                                 message: "Failed to restore fan \(fan.id) during rollback: \(error.localizedDescription)")
                }
            }
            activeLease = nil
            try? store.saveActiveLease(nil)
            appendAudit(action: "prepare-rollback", leaseID: rollbackLeaseID, message: "Prepare rolled back: \(error.localizedDescription)")
            throw error
        }
    }

    public func restoreAuto(reason: String) async throws -> AgentControlStatus {
        try beginOperation()
        defer { endOperation() }

        let snapshot = try await hardware.snapshot()
        return try await restoreAuto(reason: reason, snapshot: snapshot)
    }

    private func restoreAuto(reason: String, snapshot: HardwareSnapshot) async throws -> AgentControlStatus {
        let lease = activeLease

        for fan in snapshot.fans where fan.controllable {
            try await hardware.restoreAuto(fan: fan)
        }

        if let lease {
            appendAudit(action: "restore-auto", leaseID: lease.id, message: reason)
        }
        cancelScheduledExpiry()
        activeLease = nil
        try store.saveActiveLease(nil)
        lastErrorCode = nil
        return status()
    }

    public func clearActiveLease(reason: String) throws -> AgentControlStatus {
        try beginOperation()
        defer { endOperation() }

        cancelScheduledExpiry()
        if let lease = activeLease {
            appendAudit(action: "clear-lease", leaseID: lease.id, message: reason)
        }
        activeLease = nil
        try store.saveActiveLease(nil)
        return status()
    }

    private func scheduleMonitor(for lease: AgentCoolingLease) {
        guard activeLease?.id == lease.id else { return }
        cancelScheduledExpiry()
        let delay = max(0, min(lease.expiresAt.timeIntervalSince(now()), monitorIntervalSeconds))
        let leaseID = lease.id
        scheduledExpiry = expiryScheduler(delay) { [weak self] in
            await self?.monitorLease(id: leaseID)
        }
    }

    private func scheduleMonitorRetry(for lease: AgentCoolingLease) {
        guard activeLease?.id == lease.id else { return }
        cancelScheduledExpiry()
        let delay = max(0.001, min(1, monitorIntervalSeconds))
        let leaseID = lease.id
        scheduledExpiry = expiryScheduler(delay) { [weak self] in
            await self?.monitorLease(id: leaseID)
        }
    }

    private func monitorLease(id: String) async {
        guard let lease = activeLease, lease.id == id else { return }

        guard lease.isActive(at: now()) else {
            await restoreFromMonitor(reason: "Agent cooling lease expired", leaseID: id, snapshot: nil)
            return
        }

        do {
            let snapshot = try await hardware.snapshot()
            guard let currentLease = activeLease, currentLease.id == id else { return }

            if snapshot.temperatureSensors.isEmpty || thermalReader() == .critical {
                await restoreFromMonitor(reason: "Agent cooling safety monitor restored Auto", leaseID: id, snapshot: snapshot)
            } else {
                scheduleMonitor(for: currentLease)
            }
        } catch {
            await restoreFromMonitor(reason: "Agent cooling safety monitor restored Auto after monitor failure: \(error.localizedDescription)", leaseID: id, snapshot: nil)
        }
    }

    private func restoreFromMonitor(reason: String, leaseID: String, snapshot: HardwareSnapshot?) async {
        guard let lease = activeLease, lease.id == leaseID else { return }

        do {
            try beginOperation()
        } catch {
            appendAudit(action: "restore-retry-scheduled", leaseID: leaseID, message: "Agent cooling safety monitor restore deferred; retry scheduled: \(error.localizedDescription)")
            scheduleMonitorRetry(for: lease)
            return
        }
        defer { endOperation() }

        do {
            let restoreSnapshot: HardwareSnapshot
            if let snapshot {
                restoreSnapshot = snapshot
            } else {
                restoreSnapshot = try await hardware.snapshot()
            }
            _ = try await restoreAuto(reason: reason, snapshot: restoreSnapshot)
        } catch {
            appendAudit(action: "restore-retry-scheduled", leaseID: leaseID, message: "Agent cooling safety monitor restore failed; retry scheduled: \(error.localizedDescription)")
            if let currentLease = activeLease, currentLease.id == leaseID {
                scheduleMonitorRetry(for: currentLease)
            }
        }
    }

    private func cancelScheduledExpiry() {
        scheduledExpiry?.cancel()
        scheduledExpiry = nil
    }

    private func beginOperation() throws {
        guard !operationInProgress else {
            throw ViftyError.helperRejected("Agent control operation already in progress.")
        }
        operationInProgress = true
    }

    private func endOperation() {
        operationInProgress = false
    }

    private func appendAudit(action: String, leaseID: String?, message: String) {
        try? store.appendAuditEvent(AgentControlAuditEvent(
            timestamp: now(),
            action: action,
            leaseID: leaseID,
            message: message
        ))
    }
}
