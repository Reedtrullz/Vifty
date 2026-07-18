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
    private let store: any AgentControlPersisting
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let leaseID: @Sendable () -> String
    private let expiryScheduler: AgentControlExpiryScheduler

    private var activeLease: AgentCoolingLease?
    private var persistenceLoadErrorMessage: String?
    private var lastDecision: AgentControlDecision?
    private var lastErrorCode: AgentControlErrorCode?
    private var operationInProgress = false
    private var restoreOperationCount = 0
    private var restoreRequestGeneration = 0
    private var scheduledExpiry: AgentControlScheduledExpiry?
    private var lastPrepareCompletedAt: Date?
    private let monitorIntervalSeconds: TimeInterval = 5

    public init(
        hardware: HardwareService,
        policy: AgentControlPolicy,
        store: any AgentControlPersisting = AgentControlStore(),
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        leaseID: @escaping @Sendable () -> String = { UUID().uuidString },
        expiryScheduler: @escaping AgentControlExpiryScheduler = AgentControlDefaultScheduler.schedule(after:operation:),
        automaticallySchedulePersistedLeaseMonitor: Bool = true
    ) {
        self.hardware = hardware
        self.policy = policy
        self.store = store
        self.thermalReader = thermalReader
        self.now = now
        self.leaseID = leaseID
        self.expiryScheduler = expiryScheduler
        do {
            self.activeLease = try store.loadActiveLease()
            self.persistenceLoadErrorMessage = nil
        } catch {
            self.activeLease = nil
            self.persistenceLoadErrorMessage = error.localizedDescription
        }
        self.scheduledExpiry = nil
        if automaticallySchedulePersistedLeaseMonitor, let activeLease {
            Task { [weak self] in
                await self?.scheduleMonitor(for: activeLease)
            }
        }
    }

    public func status() -> AgentControlStatus {
        let lease = activeLease?.restoredAt == nil ? activeLease : nil
        return AgentControlStatus(
            enabled: policy.enabled,
            activeLease: lease,
            lastDecision: lastDecision,
            lastErrorCode: lastErrorCode,
            policy: policy.snapshot
        )
    }

    public func auditEvents(limit: Int = AgentControlStore.defaultMaximumAuditEvents) throws -> [AgentControlAuditEvent] {
        try store.loadRecentAuditEvents(limit: limit)
    }

    /// Daemon startup barrier. Any durable lease, unresolved fan journal, or
    /// unreadable lease state is reconciled through one full-set Auto
    /// transaction before the XPC listener exposes write operations.
    public func recoverOnStartup() async throws -> AgentControlStatus {
        let ownership = try await hardware.fanControlOwnershipStatus()
        let needsRecovery = activeLease != nil
            || persistenceLoadErrorMessage != nil
            || ownership.owner != nil
            || ownership.recoveryPending
        guard needsRecovery else { return status() }

        let durableExpectedFanIDs = Array(
            Set(ownership.expectedFanIDs)
                .union(activeLease?.targetRPMByFanID.keys ?? Dictionary<Int, Int>().keys)
        ).sorted()
        guard !durableExpectedFanIDs.isEmpty else {
            throw ViftyError.helperRejected(
                "STARTUP_RECOVERY_REQUIRES_OPERATOR: durable lease state is unreadable and no trusted journal fan set exists; daemon writes remain read-only until one explicit operator-approved restore-all."
            )
        }

        markRestoreRequested()
        restoreOperationCount += 1
        defer { restoreOperationCount -= 1 }
        _ = try await performFullAutoRestore(AutoRestoreRequest(
            transactionID: ownership.transactionID
                ?? activeLease?.id
                ?? "startup-recovery-\(UUID().uuidString)",
            expectedFanIDs: durableExpectedFanIDs,
            reason: "Daemon startup recovery",
            allowRestoreAllTrustedFans: false,
            unreadableJournalRecoveryAuthority: .durableState
        ))
        return status()
    }

    public func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        try beginOperation()
        defer { endOperation() }
        if let persistenceLoadErrorMessage {
            throw ViftyError.helperRejected(
                "Agent-control ownership state is unreadable; startup Auto recovery is required before prepare: \(persistenceLoadErrorMessage)"
            )
        }
        let prepareRestoreGeneration = restoreRequestGeneration
        guard let request = request.normalizedMetadata else {
            let decision = AgentControlDecision.denied(
                .invalidArguments,
                message: request.metadataValidationFailureMessage ?? "Agent cooling request metadata is invalid."
            )
            lastDecision = decision
            lastErrorCode = decision.errorCode
            appendAudit(action: "prepare-denied", leaseID: nil, message: decision.message)
            return status()
        }

        if let lease = activeLease,
           lease.request.idempotencyKey == request.idempotencyKey,
           lease.isActive(at: now()) {
            return status()
        }

        if let lease = activeLease,
           lease.restoredAt == nil {
            let message = lease.isActive(at: now())
                ? "Agent cooling lease already active. Restore Auto before starting a new lease."
                : "Agent cooling lease expired but Auto restore has not completed. Restore Auto before starting a new lease."
            let decision = AgentControlDecision.denied(
                .policyDenied,
                message: message
            )
            lastDecision = decision
            lastErrorCode = decision.errorCode
            appendAudit(action: "prepare-denied", leaseID: lease.id, message: decision.message)
            return status()
        }

        if let lastPrepare = lastPrepareCompletedAt,
           now().timeIntervalSince(lastPrepare) < Double(policy.prepareCooldownSeconds) {
            let elapsed = now().timeIntervalSince(lastPrepare)
            let remaining = max(1, Int(ceil(Double(policy.prepareCooldownSeconds) - elapsed)))
            let decision = AgentControlDecision.denied(
                .prepareRateLimited,
                message: "Prepare rate-limited. Wait \(remaining)s between prepare calls.",
                retryAfterSeconds: remaining
            )
            lastDecision = decision
            lastErrorCode = decision.errorCode
            appendAudit(action: "prepare-rate-limited", leaseID: nil, message: decision.message)
            return status()
        }

        let snapshot = try await hardware.snapshot()
        if restoreWasRequested(since: prepareRestoreGeneration) {
            try cancelPrepareBecauseRestoreWasRequested(leaseID: nil)
            return status()
        }
        let expectedFanIDs = snapshot.fans
            .filter { $0.controlEligibility.canApplyFixedRPM }
            .map(\.id)
            .sorted()
        if let blocker = prepareHardwareBlocker(snapshot, expectedFanIDs: expectedFanIDs) {
            let hardwareDecision = AgentControlDecision.denied(.policyDenied, message: blocker)
            lastDecision = hardwareDecision
            lastErrorCode = hardwareDecision.errorCode
            appendAudit(action: "prepare-denied", leaseID: nil, message: hardwareDecision.message)
            return status()
        }

        let decision = policy.evaluate(request, snapshot: snapshot, thermalPressure: thermalReader())
        lastDecision = decision
        lastErrorCode = decision.errorCode

        guard decision.allowed else {
            appendAudit(action: "prepare-denied", leaseID: nil, message: decision.message)
            return status()
        }

        let ownership = try await hardware.fanControlOwnershipStatus()
        if ownership.owner != nil || ownership.recoveryPending {
            let ownershipDecision = AgentControlDecision.denied(
                .policyDenied,
                message: "Fan control is already owned by another transaction or requires Auto recovery."
            )
            lastDecision = ownershipDecision
            lastErrorCode = ownershipDecision.errorCode
            appendAudit(action: "prepare-denied", leaseID: nil, message: ownershipDecision.message)
            return status()
        }

        guard !expectedFanIDs.isEmpty,
              Set(decision.targetRPMByFanID.keys) == Set(expectedFanIDs) else {
            throw ViftyError.noControllableFans
        }
        let createdAt = now()
        let lease = AgentCoolingLease(
            id: leaseID(),
            request: request,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(TimeInterval(request.durationSeconds)),
            targetRPMByFanID: decision.targetRPMByFanID
        )
        activeLease = lease

        do {
            _ = try await hardware.applyAgentFanControl(
                AgentFanControlRequest(
                    transactionID: lease.id,
                    leaseID: lease.id,
                    expectedFanIDs: expectedFanIDs,
                    targetRPMByFanID: decision.targetRPMByFanID
                )
            )
        } catch {
            activeLease = nil
            try? store.saveActiveLease(nil)
            appendAudit(
                action: "prepare-apply-failed",
                leaseID: lease.id,
                message: "Transactional fan apply failed; the arbiter owns rollback: \(error.localizedDescription)"
            )
            throw error
        }

        if restoreWasRequested(since: prepareRestoreGeneration) {
            _ = try await restoreAuto(
                reason: "Prepare cancelled because Auto restore was requested",
                snapshot: snapshot
            )
            let restoreDecision = AgentControlDecision.denied(
                .restoreRequested,
                message: "Prepare cancelled because Auto restore was requested."
            )
            lastDecision = restoreDecision
            lastErrorCode = restoreDecision.errorCode
            appendAudit(action: "prepare-cancelled", leaseID: lease.id, message: restoreDecision.message)
            return status()
        }

        do {
            try store.saveActiveLease(lease)
        } catch {
            let persistenceError = error
            let durableLeaseCleared = AgentControlSendableFlag()
            let rollbackResult: FanControlTransactionResult?
            do {
                rollbackResult = try await hardware.restoreFanControlIfOwned(
                    transactionID: lease.id,
                    owner: .agent(leaseID: lease.id),
                    reason: "Prepare persistence rollback",
                    beforeOwnershipClear: { [store] in
                        try store.saveActiveLease(nil)
                        durableLeaseCleared.mark()
                    }
                )
            } catch {
                if durableLeaseCleared.value {
                    activeLease = nil
                    persistenceLoadErrorMessage = nil
                } else {
                    scheduleMonitor(for: lease)
                }
                appendAudit(
                    action: "prepare-rollback-failure",
                    leaseID: lease.id,
                    message: "Atomic owner-conditional Auto rollback failed: \(error.localizedDescription)"
                )
                throw ViftyError.helperRejected(
                    "Lease persistence failed (\(persistenceError.localizedDescription)); atomic full-set Auto rollback remains pending (\(error.localizedDescription))."
                )
            }

            guard rollbackResult != nil else {
                activeLease = nil
                try? store.saveActiveLease(nil)
                appendAudit(
                    action: "prepare-persistence-foreign-owner",
                    leaseID: lease.id,
                    message: "Lease persistence failed but the atomic arbiter check found different ownership; no foreign ownership was cleared."
                )
                throw persistenceError
            }

            activeLease = nil
            persistenceLoadErrorMessage = nil
            appendAudit(
                action: "prepare-rollback",
                leaseID: lease.id,
                message: "Lease persistence failed and the atomic arbiter restored its exact owned fan transaction: \(persistenceError.localizedDescription)"
            )
            throw persistenceError
        }

        scheduleMonitor(for: lease)
        lastPrepareCompletedAt = now()
        appendAudit(action: "prepare", leaseID: lease.id, message: request.reason)
        return status()
    }

    private func prepareHardwareBlocker(
        _ snapshot: HardwareSnapshot,
        expectedFanIDs: [Int]
    ) -> String? {
        guard snapshot.fanControlProtocolVersion >= FanControlProtocolVersion.current else {
            return "Agent prepare requires fan-control protocol v2."
        }
        let physicalFans = snapshot.fans
        guard !physicalFans.isEmpty,
              physicalFans.map(\.id).count == Set(physicalFans.map(\.id)).count,
              physicalFans.allSatisfy({
                  SMCFanControlKeys.isValidFanID($0.id)
                      && $0.controlEligibility.canRestoreOSManagedMode
              }) else {
            return "Agent prepare requires one complete, unique physical fan inventory with trusted restore telemetry."
        }
        let fixedEligibleFanIDs = physicalFans
            .filter { $0.controlEligibility.canApplyFixedRPM }
            .map(\.id)
            .sorted()
        guard !expectedFanIDs.isEmpty, expectedFanIDs == fixedEligibleFanIDs else {
            return "Agent prepare requires an exact target for every Fixed-eligible physical fan."
        }
        guard physicalFans.allSatisfy({
            $0.hardwareMode == .automatic || $0.hardwareMode == .system
        }) else {
            return "Agent prepare is blocked because a physical fan is Forced/Unknown without an active owner; restore Auto explicitly first."
        }
        return nil
    }

    public func restoreAuto(reason: String) async throws -> AgentControlStatus {
        markRestoreRequested()
        restoreOperationCount += 1
        defer { restoreOperationCount -= 1 }

        let normalizedReason = Self.normalizedAuditReason(reason, fallback: "manual restore")
        let snapshot = try await hardware.snapshot()
        return try await restoreAuto(reason: normalizedReason, snapshot: snapshot)
    }

    public func restoreAllAuto(
        _ request: AutoRestoreRequest
    ) async throws -> FanControlTransactionResult {
        markRestoreRequested()
        restoreOperationCount += 1
        defer { restoreOperationCount -= 1 }
        let leaseFanIDs = activeLease?.targetRPMByFanID.keys.sorted()
        let explicitOperatorRecovery = request.unreadableJournalRecoveryAuthority == .explicitOperator
        let authoritativeRequest = AutoRestoreRequest(
            transactionID: request.transactionID,
            expectedFanIDs: explicitOperatorRecovery ? [] : (leaseFanIDs ?? []),
            reason: request.reason,
            allowRestoreAllTrustedFans: explicitOperatorRecovery || leaseFanIDs == nil,
            unreadableJournalRecoveryAuthority: explicitOperatorRecovery
                ? .explicitOperator
                : (leaseFanIDs == nil ? nil : .durableState)
        )
        return try await performFullAutoRestore(authoritativeRequest)
    }

    private func restoreAuto(reason: String, snapshot: HardwareSnapshot) async throws -> AgentControlStatus {
        let lease = activeLease
        _ = snapshot
        let expectedFanIDs = lease?.targetRPMByFanID.keys.sorted() ?? []
        _ = try await performFullAutoRestore(
            AutoRestoreRequest(
                transactionID: lease?.id ?? "restore-\(UUID().uuidString)",
                expectedFanIDs: expectedFanIDs,
                reason: reason,
                allowRestoreAllTrustedFans: lease == nil,
                unreadableJournalRecoveryAuthority: lease == nil ? nil : .durableState
            )
        )
        return status()
    }

    private func performFullAutoRestore(
        _ request: AutoRestoreRequest
    ) async throws -> FanControlTransactionResult {
        let lease = activeLease
        let durableLeaseCleared = AgentControlSendableFlag()
        let result: FanControlTransactionResult
        do {
            result = try await hardware.restoreAllAuto(
                request,
                beforeOwnershipClear: { [store] in
                    try store.saveActiveLease(nil)
                    durableLeaseCleared.mark()
                }
            )
        } catch {
            if durableLeaseCleared.value {
                cancelScheduledExpiry()
                activeLease = nil
                persistenceLoadErrorMessage = nil
            }
            throw error
        }

        if let lease {
            appendAudit(action: "restore-auto", leaseID: lease.id, message: request.reason)
        }
        cancelScheduledExpiry()
        activeLease = nil
        persistenceLoadErrorMessage = nil
        lastDecision = nil
        lastErrorCode = nil
        return result
    }

    /// Compatibility entry point for callers that previously cleared lease
    /// metadata after a per-fan Auto write. It now performs authoritative
    /// full-set Auto restoration and cannot clear ownership independently.
    public func clearActiveLease(reason: String) async throws -> AgentControlStatus {
        let lease = activeLease
        let normalizedReason = Self.normalizedAuditReason(reason, fallback: "lease cleared")
        let restored = try await restoreAuto(reason: normalizedReason)
        if let lease {
            appendAudit(action: "clear-lease", leaseID: lease.id, message: normalizedReason)
        }
        return restored
    }

    private func cancelPrepareBecauseRestoreWasRequested(leaseID: String?) throws {
        let decision = AgentControlDecision.denied(
            .restoreRequested,
            message: "Prepare cancelled because Auto restore was requested."
        )
        activeLease = nil
        try store.saveActiveLease(nil)
        persistenceLoadErrorMessage = nil
        lastDecision = decision
        lastErrorCode = decision.errorCode
        appendAudit(action: "prepare-cancelled", leaseID: leaseID, message: decision.message)
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
        guard !operationInProgress, restoreOperationCount == 0 else {
            throw ViftyError.helperRejected("Agent control operation already in progress.")
        }
        operationInProgress = true
    }

    private func endOperation() {
        operationInProgress = false
    }

    private func markRestoreRequested() {
        restoreRequestGeneration += 1
    }

    private func restoreWasRequested(since generation: Int) -> Bool {
        restoreRequestGeneration != generation
    }

    private func appendAudit(action: String, leaseID: String?, message: String) {
        try? store.appendAuditEvent(AgentControlAuditEvent(
            timestamp: now(),
            action: action,
            leaseID: leaseID,
            message: message
        ))
    }

    private static func normalizedAuditReason(_ reason: String, fallback: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? fallback : trimmed
        return String(normalized.prefix(AgentControlRequest.maximumReasonLength))
    }
}

private final class AgentControlSendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func mark() {
        lock.withLock { storage = true }
    }
}
