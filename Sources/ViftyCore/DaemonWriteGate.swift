import Foundation

public enum DaemonWriteGateError: Error, Equatable, LocalizedError, Sendable {
    case recoveryPending(String)

    public var errorDescription: String? {
        switch self {
        case .recoveryPending(let reason):
            "Daemon fan writes remain read-only until full Auto recovery is confirmed: \(reason)"
        }
    }
}

/// Keeps the daemon available for read-only status and recovery when startup
/// Auto restoration cannot be confirmed. Manual and agent applies stay blocked
/// until a later authoritative restore reaches a clean OS-owned state.
public actor DaemonWriteGate {
    private var recoveryBlockReason: String?
    private var recoveryAttemptCount: Int

    public init(
        startupRecoveryError: String? = nil,
        ownershipStatus: FanControlOwnershipStatus
    ) {
        recoveryBlockReason = Self.blockReason(
            recoveryError: startupRecoveryError,
            ownershipStatus: ownershipStatus
        )
        recoveryAttemptCount = recoveryBlockReason == nil ? 0 : 1
    }

    public var writesAllowed: Bool {
        recoveryBlockReason == nil
    }

    public var blockReason: String? {
        recoveryBlockReason
    }

    public func requireWriteAllowed() throws {
        if let recoveryBlockReason {
            throw DaemonWriteGateError.recoveryPending(recoveryBlockReason)
        }
    }

    public func recordRecoveryResult(
        error: String? = nil,
        ownershipStatus: FanControlOwnershipStatus
    ) {
        recoveryAttemptCount += 1
        recoveryBlockReason = Self.blockReason(
            recoveryError: error,
            ownershipStatus: ownershipStatus
        )
    }

    public func statusOverlay(_ status: FanControlOwnershipStatus) -> FanControlOwnershipStatus {
        guard let recoveryBlockReason else { return status }
        guard status.owner == nil, !status.recoveryPending else {
            var status = status
            if status.errorCode == nil {
                status.errorCode = "STARTUP_RECOVERY_BLOCKED"
            }
            status.errorMessage = recoveryBlockReason
            status.recoveryAttemptCount = recoveryAttemptCount
            return status
        }
        return FanControlOwnershipStatus(
            protocolVersion: status.protocolVersion,
            owner: .recovery,
            phase: .restorePending,
            transactionID: status.transactionID,
            expectedFanIDs: status.expectedFanIDs,
            confirmedOSManagedFanIDs: status.confirmedOSManagedFanIDs,
            recoveryPending: true,
            errorCode: "STARTUP_RECOVERY_BLOCKED",
            errorMessage: recoveryBlockReason,
            recoveryAttemptCount: recoveryAttemptCount
        )
    }

    private static func blockReason(
        recoveryError: String?,
        ownershipStatus: FanControlOwnershipStatus
    ) -> String? {
        if let recoveryError,
           !recoveryError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recoveryError
        }
        if ownershipStatus.owner != nil || ownershipStatus.recoveryPending {
            return ownershipStatus.errorCode
                ?? "fan-control ownership remains \(ownershipStatus.owner?.type ?? "unresolved")"
        }
        if let errorCode = ownershipStatus.errorCode {
            return errorCode
        }
        return nil
    }
}
