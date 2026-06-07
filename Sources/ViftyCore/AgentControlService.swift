import Foundation

public actor AgentControlService {
    private let hardware: HardwareService
    private let policy: AgentControlPolicy
    private let store: AgentControlStore
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let leaseID: @Sendable () -> String

    private var activeLease: AgentCoolingLease?
    private var lastDecision: AgentControlDecision?
    private var lastErrorCode: AgentControlErrorCode?

    public init(
        hardware: HardwareService,
        policy: AgentControlPolicy,
        store: AgentControlStore = AgentControlStore(),
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        leaseID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.hardware = hardware
        self.policy = policy
        self.store = store
        self.thermalReader = thermalReader
        self.now = now
        self.leaseID = leaseID
        self.activeLease = try? store.loadActiveLease()
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
            appendAudit(action: "prepare", leaseID: lease.id, message: request.reason)
            return status()
        } catch {
            for fan in appliedFans {
                try? await hardware.restoreAuto(fan: fan)
            }
            activeLease = nil
            try? store.saveActiveLease(nil)
            appendAudit(action: "prepare-rollback", leaseID: rollbackLeaseID, message: "Prepare rolled back: \(error.localizedDescription)")
            throw error
        }
    }

    public func restoreAuto(reason: String) async throws -> AgentControlStatus {
        let snapshot = try await hardware.snapshot()
        let lease = activeLease

        for fan in snapshot.fans where fan.controllable {
            try await hardware.restoreAuto(fan: fan)
        }

        if let lease {
            appendAudit(action: "restore-auto", leaseID: lease.id, message: reason)
        }
        activeLease = nil
        try store.saveActiveLease(nil)
        lastErrorCode = nil
        return status()
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
