import Foundation
import ViftyCore
import ViftyFanControlSafety

final class DaemonTransactionalHardwareService: HardwareService, @unchecked Sendable {
    private let snapshotProvider: @Sendable () throws -> HardwareSnapshot
    private let arbiter: FanControlArbiter

    init(
        snapshotProvider: @escaping @Sendable () throws -> HardwareSnapshot,
        arbiter: FanControlArbiter
    ) {
        self.snapshotProvider = snapshotProvider
        self.arbiter = arbiter
    }

    func snapshot() async throws -> HardwareSnapshot { try snapshotProvider() }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        throw ViftyError.helperRejected(
            "Legacy per-fan writes are disabled; daemon writes require one protocol-v2 transaction."
        )
    }

    func restoreAuto(fan: Fan) async throws {
        throw ViftyError.helperRejected(
            "Legacy per-fan Auto is disabled; daemon restoration requires one authoritative full-set transaction."
        )
    }

    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus { await arbiter.status() }

    func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        try await arbiter.applyManual(request)
    }

    func applyAgentFanControl(
        _ request: AgentFanControlRequest
    ) async throws -> FanControlTransactionResult {
        try await arbiter.applyAgent(request)
    }

    func restoreFanControlIfOwned(
        transactionID: String,
        owner: FanControlOwner,
        reason: String,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult? {
        try await arbiter.restoreAutoIfOwned(
            transactionID: transactionID,
            owner: owner,
            reason: reason,
            beforeJournalClear: beforeOwnershipClear
        )
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        arbiter.requestRestorePriority()
        return try await arbiter.restoreAuto(request, beforeJournalClear: beforeOwnershipClear)
    }
}

public final class DaemonService: NSObject, ViftyDaemonProtocol, @unchecked Sendable {
    // Retaining this descriptor for the service lifetime is the process-wide
    // writer exclusion boundary. It is acquired before the arbiter or listener.
    private let exclusiveLock: FanControlExclusiveLock
    private let snapshotProvider: @Sendable () throws -> HardwareSnapshot
    private let arbiter: FanControlArbiter
    private let agentControl: AgentControlService
    private let writeGate: DaemonWriteGate
    private let maintenanceCoordinator: DaemonLifecycleCoordinator?
    private let snapshotCacheTTL: TimeInterval
    private let snapshotCacheLock = NSLock()
    private var cachedSnapshot: (capturedAt: Date, snapshot: HardwareSnapshot)?

    init(
        exclusiveLock: FanControlExclusiveLock,
        snapshotProvider: @escaping @Sendable () throws -> HardwareSnapshot,
        arbiter: FanControlArbiter,
        agentControl: AgentControlService,
        writeGate: DaemonWriteGate,
        maintenanceCoordinator: DaemonLifecycleCoordinator? = nil,
        snapshotCacheTTL: TimeInterval = 1
    ) {
        self.exclusiveLock = exclusiveLock
        self.snapshotProvider = snapshotProvider
        self.arbiter = arbiter
        self.agentControl = agentControl
        self.writeGate = writeGate
        self.maintenanceCoordinator = maintenanceCoordinator
        self.snapshotCacheTTL = snapshotCacheTTL
        super.init()
    }

    public static func bootstrap() async throws -> DaemonService {
        // A receipt authorizes teardown only for the daemon session that
        // minted it. Revoke any prior-session receipt synchronously before
        // constructing the writer boundary or returning a service that can be
        // exposed through the XPC listener. Failure is a startup failure.
        let maintenanceAuthorityStore = HelperMaintenanceAuthorityStore()
        try revokeMaintenanceAuthorityBeforeBootstrap {
            try maintenanceAuthorityStore.clear()
        }
        let exclusiveLock = try FanControlExclusiveLock()
        let readHardware = RealMacHardwareService(preferDaemon: false)
        let snapshotProvider: @Sendable () throws -> HardwareSnapshot = {
            try readHardware.localSnapshot()
        }
        let privilegedHardware = LocalPrivilegedFanControlHardware(
            snapshotProvider: snapshotProvider
        )
        let restoreSignal = FanControlRestoreSignal()
        let arbiter = FanControlArbiter(
            hardware: privilegedHardware,
            journalStore: FanControlJournalStore(),
            exclusiveLock: exclusiveLock,
            restoreSignal: restoreSignal
        )
        let hardware = DaemonTransactionalHardwareService(
            snapshotProvider: snapshotProvider,
            arbiter: arbiter
        )
        let agentControl = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            automaticallySchedulePersistedLeaseMonitor: false
        )
        // Startup performs exactly one recovery attempt and never schedules an
        // automatic retry. If it cannot prove OS ownership, the listener stays
        // reachable but write-gated. A human-triggered full Auto request is the
        // only bounded retry and its attempt/error state is exposed over XPC.
        let startupRecoveryError: String?
        do {
            _ = try await agentControl.recoverOnStartup()
            startupRecoveryError = nil
        } catch {
            startupRecoveryError = error.localizedDescription
        }
        let writeGate = DaemonWriteGate(
            startupRecoveryError: startupRecoveryError,
            ownershipStatus: await arbiter.status()
        )
        let maintenanceCoordinator = DaemonLifecycleCoordinator(
            restoreSignal: restoreSignal,
            restoreAllAuto: { request in
                do {
                    let result = try await agentControl.restoreAllAuto(request)
                    await writeGate.recordRecoveryResult(ownershipStatus: await arbiter.status())
                    return result
                } catch {
                    await writeGate.recordRecoveryResult(
                        error: error.localizedDescription,
                        ownershipStatus: await arbiter.status()
                    )
                    throw error
                }
            },
            ownershipStatus: {
                await writeGate.statusOverlay(await arbiter.status())
            },
            freshSnapshot: snapshotProvider,
            journalGeneration: { await arbiter.currentJournalGeneration() },
            persistAuthority: { try maintenanceAuthorityStore.save($0) },
            clearAuthority: { try maintenanceAuthorityStore.clear() }
        )
        return DaemonService(
            exclusiveLock: exclusiveLock,
            snapshotProvider: snapshotProvider,
            arbiter: arbiter,
            agentControl: agentControl,
            writeGate: writeGate,
            maintenanceCoordinator: maintenanceCoordinator
        )
    }

    static func revokeMaintenanceAuthorityBeforeBootstrap(
        _ clearAuthority: () throws -> Void
    ) throws {
        try clearAuthority()
    }

    public func ping(reply: @escaping (Bool) -> Void) { reply(true) }

    public func snapshot(reply: @escaping (NSDictionary?, String?) -> Void) {
        do {
            reply(XPCSnapshotCoding.encode(try awaitSnapshot()), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    public func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        Task { reply(XPCAgentControlCoding.encode(await agentControl.status()), nil) }
    }

    public func agentControlAudit(
        _ limit: Int,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        Task {
            do {
                reply(XPCAgentControlCoding.encodeAuditEvents(try await agentControl.auditEvents(limit: limit)), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func prepareAgentControl(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        reply(nil, "Legacy agent-control mutation selector is disabled; protocol-v2 client required.")
    }

    public func prepareAgentControlV2(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        guard let decoded = XPCAgentControlCoding.decodeRequest(request) else {
            reply(nil, AgentControlErrorCode.invalidArguments.rawValue)
            return
        }
        let maintenancePermit: FanControlMutationPermit?
        do {
            maintenancePermit = try maintenanceCoordinator?.beginExternalMutation()
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        Task {
            defer {
                maintenancePermit?.release()
                clearSnapshotCache()
            }
            do {
                try maintenanceCoordinator?.requireControlAllowed()
                try await writeGate.requireWriteAllowed()
                reply(XPCAgentControlCoding.encode(try await agentControl.prepare(decoded)), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func restoreAgentControl(
        _ reason: String,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        reply(nil, "Legacy agent-control restore selector is disabled; protocol-v2 client required.")
    }

    public func restoreAgentControlV2(
        _ reason: String,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        let maintenancePermit: FanControlMutationPermit?
        do {
            maintenancePermit = try maintenanceCoordinator?.beginExternalMutation()
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        arbiter.requestRestorePriority()
        Task {
            defer {
                maintenancePermit?.release()
                clearSnapshotCache()
            }
            do {
                let status = try await agentControl.restoreAuto(reason: reason)
                await recordRecoveryResult()
                reply(XPCAgentControlCoding.encode(status), nil)
            } catch {
                await recordRecoveryFailure(error)
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func fanControlOwnershipStatus(
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        Task {
            let status = await writeGate.statusOverlay(await arbiter.status())
            reply(XPCFanControlCoding.encode(status), nil)
        }
    }

    public func applyManualFanControl(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        guard let decoded = XPCFanControlCoding.decodeManualRequest(request) else {
            reply(nil, "Invalid protocol-v2 manual fan-control request.")
            return
        }
        let maintenancePermit: FanControlMutationPermit?
        do {
            maintenancePermit = try maintenanceCoordinator?.beginExternalMutation()
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        Task {
            defer {
                maintenancePermit?.release()
                clearSnapshotCache()
            }
            do {
                try maintenanceCoordinator?.requireControlAllowed()
                try await writeGate.requireWriteAllowed()
                reply(XPCFanControlCoding.encode(try await arbiter.applyManual(decoded)), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func restoreAllAuto(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        guard let decoded = XPCFanControlCoding.decodeAutoRestoreRequest(request) else {
            reply(nil, "Invalid protocol-v2 full-set Auto request.")
            return
        }
        let maintenancePermit: FanControlMutationPermit?
        do {
            maintenancePermit = try maintenanceCoordinator?.beginExternalMutation()
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        arbiter.requestRestorePriority()
        Task {
            defer {
                maintenancePermit?.release()
                clearSnapshotCache()
            }
            do {
                let result = try await agentControl.restoreAllAuto(decoded)
                await recordRecoveryResult()
                reply(XPCFanControlCoding.encode(result), nil)
            } catch {
                await recordRecoveryFailure(error)
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func prepareHelperMaintenance(
        _ operation: String,
        helperSHA256: String,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        guard let operation = HelperMaintenanceOperation(rawValue: operation),
              operation == .repair || operation == .uninstall else {
            reply(nil, "Invalid helper-maintenance operation.")
            return
        }
        guard let maintenanceCoordinator else {
            reply(nil, "Helper-maintenance authority is unavailable; refusing teardown.")
            return
        }
        Task {
            defer { clearSnapshotCache() }
            do {
                reply(
                    XPCHelperMaintenanceCoding.encode(
                        try await maintenanceCoordinator.prepare(
                            operation: operation,
                            helperSHA256: helperSHA256
                        )
                    ),
                    nil
                )
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func consumeHelperMaintenanceToken(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        guard let decoded = XPCHelperMaintenanceCoding.decodeAuthorizationRequest(request) else {
            reply(nil, "Invalid helper-maintenance authorization request.")
            return
        }
        guard let maintenanceCoordinator else {
            reply(nil, "Helper-maintenance authority is unavailable; refusing teardown.")
            return
        }
        Task {
            do {
                reply(
                    XPCHelperMaintenanceCoding.encode(
                        try await maintenanceCoordinator.consume(decoded)
                    ),
                    nil
                )
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func cancelHelperMaintenance(
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        guard let maintenanceCoordinator else {
            reply(false, "Helper-maintenance authority is unavailable.")
            return
        }
        Task {
            do {
                try await maintenanceCoordinator.cancel()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    public func prepareVoluntaryTermination() async throws -> HelperMaintenanceReport {
        guard let maintenanceCoordinator else {
            throw ViftyError.helperRejected(
                "Helper-maintenance authority is unavailable; voluntary termination remains blocked."
            )
        }
        return try await maintenanceCoordinator.prepareVoluntaryTermination()
    }

    public func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        reply(
            false,
            "Legacy per-fan write rejected for fan \(fanID) at \(rpm) RPM (range \(minimumRPM)-\(maximumRPM)); reinstall/update Vifty and use protocol v2."
        )
    }

    public func restoreAuto(
        _ fanID: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        let maintenancePermit: FanControlMutationPermit?
        do {
            maintenancePermit = try maintenanceCoordinator?.beginExternalMutation()
        } catch {
            reply(false, error.localizedDescription)
            return
        }
        arbiter.requestRestorePriority()
        Task {
            defer {
                maintenancePermit?.release()
                clearSnapshotCache()
            }
            do {
                _ = try await agentControl.restoreAllAuto(AutoRestoreRequest(
                    transactionID: "legacy-auto-\(UUID().uuidString)",
                    expectedFanIDs: [],
                    reason: "Legacy per-fan Auto for fan \(fanID) mapped to global restore (range \(minimumRPM)-\(maximumRPM))",
                    allowRestoreAllTrustedFans: true
                ))
                await recordRecoveryResult()
                reply(true, nil)
            } catch {
                await recordRecoveryFailure(error)
                reply(false, error.localizedDescription)
            }
        }
    }

    private func recordRecoveryResult() async {
        await writeGate.recordRecoveryResult(ownershipStatus: await arbiter.status())
    }

    private func recordRecoveryFailure(_ error: any Error) async {
        await writeGate.recordRecoveryResult(
            error: error.localizedDescription,
            ownershipStatus: await arbiter.status()
        )
    }

    private func awaitSnapshot() throws -> HardwareSnapshot {
        let now = Date()
        if let cached = cachedSnapshotIfFresh(now: now) { return cached }
        let snapshot = try snapshotProvider()
        snapshotCacheLock.withLock { cachedSnapshot = (now, snapshot) }
        return snapshot
    }

    private func cachedSnapshotIfFresh(now: Date) -> HardwareSnapshot? {
        snapshotCacheLock.withLock {
            guard let cachedSnapshot,
                  now.timeIntervalSince(cachedSnapshot.capturedAt) < snapshotCacheTTL else {
                return nil
            }
            return cachedSnapshot.snapshot
        }
    }

    private func clearSnapshotCache() {
        snapshotCacheLock.withLock { cachedSnapshot = nil }
    }
}
