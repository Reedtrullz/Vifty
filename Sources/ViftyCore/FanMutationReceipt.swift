import Foundation

/// Immutable evidence returned after a low-level fan mutation is confirmed by
/// fresh SMC readback. A successful write call alone is never a receipt.
public struct FanMutationReceipt: Equatable, Sendable {
    public let fanID: Int
    public let requestedMode: FanHardwareMode
    public let observedMode: FanHardwareMode?
    public let observedTargetRPM: Int?
    public let forceTestDisabled: Bool
    public let recoveryConfirmed: Bool
    public let warnings: [String]

    public init(
        fanID: Int,
        requestedMode: FanHardwareMode,
        observedMode: FanHardwareMode?,
        observedTargetRPM: Int?,
        forceTestDisabled: Bool,
        recoveryConfirmed: Bool,
        warnings: [String]
    ) {
        self.fanID = fanID
        self.requestedMode = requestedMode
        self.observedMode = observedMode
        self.observedTargetRPM = observedTargetRPM
        self.forceTestDisabled = forceTestDisabled
        self.recoveryConfirmed = recoveryConfirmed
        self.warnings = warnings
    }
}

public enum FanMutationErrorCode: String, Equatable, Sendable {
    case mutationFailed
    case readbackMismatch
    case recoveryUnconfirmed
}

/// Structured failure evidence for an operation that reached its first SMC
/// write. Preflight failures retain their original error and never produce this
/// type because no physical mutation was attempted.
public struct FanMutationError: Error, Equatable, LocalizedError, Sendable {
    public let code: FanMutationErrorCode
    public let primaryError: String
    public let cleanupErrors: [String]
    public let receipt: FanMutationReceipt

    public init(
        code: FanMutationErrorCode,
        primaryError: String,
        cleanupErrors: [String],
        receipt: FanMutationReceipt
    ) {
        self.code = code
        self.primaryError = primaryError
        self.cleanupErrors = cleanupErrors
        self.receipt = receipt
    }

    public var errorDescription: String? {
        var components = ["Fan mutation \(code.rawValue): \(primaryError)"]
        if !cleanupErrors.isEmpty {
            components.append("cleanup: \(cleanupErrors.joined(separator: "; "))")
        }
        return components.joined(separator: " | ")
    }
}
