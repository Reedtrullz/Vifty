import Foundation

public enum AgentControlWorkload: String, Codable, CaseIterable, Equatable, Sendable {
    case build
    case test
    case render
    case localModel
    case custom

    public var displayName: String {
        switch self {
        case .build: "Build"
        case .test: "Test"
        case .render: "Render"
        case .localModel: "Local Model"
        case .custom: "Custom"
        }
    }
}

public enum AgentControlErrorCode: String, Codable, Equatable, Sendable {
    case disabled = "AGENT_CONTROL_DISABLED"
    case unsupportedHardware = "UNSUPPORTED_HARDWARE"
    case helperUnreachable = "HELPER_UNREACHABLE"
    case temperatureSensorUnavailable = "TEMP_SENSOR_UNAVAILABLE"
    case noControllableFans = "NO_CONTROLLABLE_FANS"
    case policyDenied = "POLICY_DENIED"
    case durationTooLong = "DURATION_TOO_LONG"
    case rpmOutOfRange = "RPM_OUT_OF_RANGE"
    case thermalCritical = "THERMAL_CRITICAL"
    case leaseNotFound = "LEASE_NOT_FOUND"
    case restoreFailed = "RESTORE_FAILED"
    case invalidArguments = "INVALID_ARGUMENTS"
    case childCommandFailed = "CHILD_COMMAND_FAILED"
    case prepareRateLimited = "PREPARE_RATE_LIMITED"
    case restoreRequested = "RESTORE_REQUESTED"
}

public struct AgentControlRequest: Codable, Equatable, Sendable {
    public var workload: AgentControlWorkload
    public var durationSeconds: Int
    public var maxRPMPercent: Int
    public var reason: String
    public var idempotencyKey: String

    public init(workload: AgentControlWorkload, durationSeconds: Int, maxRPMPercent: Int, reason: String, idempotencyKey: String) {
        self.workload = workload
        self.durationSeconds = durationSeconds
        self.maxRPMPercent = maxRPMPercent
        self.reason = reason
        self.idempotencyKey = idempotencyKey
    }
}

public struct AgentControlDecision: Codable, Equatable, Sendable {
    public var allowed: Bool
    public var errorCode: AgentControlErrorCode?
    public var message: String
    public var targetRPMByFanID: [Int: Int]
    public var warnings: [String]
    public var retryAfterSeconds: Int?

    public static func allowed(targetRPMByFanID: [Int: Int], warnings: [String] = []) -> AgentControlDecision {
        AgentControlDecision(allowed: true, errorCode: nil, message: "Allowed", targetRPMByFanID: targetRPMByFanID, warnings: warnings)
    }

    public static func denied(_ code: AgentControlErrorCode, message: String, retryAfterSeconds: Int? = nil) -> AgentControlDecision {
        AgentControlDecision(allowed: false, errorCode: code, message: message, targetRPMByFanID: [:], warnings: [], retryAfterSeconds: retryAfterSeconds)
    }

    public init(
        allowed: Bool,
        errorCode: AgentControlErrorCode?,
        message: String,
        targetRPMByFanID: [Int: Int],
        warnings: [String],
        retryAfterSeconds: Int? = nil
    ) {
        self.allowed = allowed
        self.errorCode = errorCode
        self.message = message
        self.targetRPMByFanID = targetRPMByFanID
        self.warnings = warnings
        self.retryAfterSeconds = retryAfterSeconds
    }
}

public struct AgentCoolingLease: Codable, Equatable, Sendable {
    public var id: String
    public var request: AgentControlRequest
    public var createdAt: Date
    public var expiresAt: Date
    public var targetRPMByFanID: [Int: Int]
    public var restoredAt: Date?

    public init(id: String, request: AgentControlRequest, createdAt: Date, expiresAt: Date, targetRPMByFanID: [Int: Int], restoredAt: Date? = nil) {
        self.id = id
        self.request = request
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.targetRPMByFanID = targetRPMByFanID
        self.restoredAt = restoredAt
    }

    public func isActive(at date: Date) -> Bool {
        restoredAt == nil && date < expiresAt
    }
}

public struct AgentControlStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var activeLease: AgentCoolingLease?
    public var lastDecision: AgentControlDecision?
    public var lastErrorCode: AgentControlErrorCode?
    public var policy: AgentControlPolicySnapshot?

    public init(
        enabled: Bool,
        activeLease: AgentCoolingLease?,
        lastDecision: AgentControlDecision?,
        lastErrorCode: AgentControlErrorCode?,
        policy: AgentControlPolicySnapshot? = nil
    ) {
        self.enabled = enabled
        self.activeLease = activeLease
        self.lastDecision = lastDecision
        self.lastErrorCode = lastErrorCode
        self.policy = policy
    }
}

public struct AgentControlPolicySnapshot: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var minimumAgentRPMPercent: Int
    public var maximumAllowedRPMPercent: Int
    public var maxDurationSeconds: Int
    public var prepareCooldownSeconds: Int

    public init(
        enabled: Bool,
        minimumAgentRPMPercent: Int,
        maximumAllowedRPMPercent: Int,
        maxDurationSeconds: Int,
        prepareCooldownSeconds: Int
    ) {
        self.enabled = enabled
        self.minimumAgentRPMPercent = minimumAgentRPMPercent
        self.maximumAllowedRPMPercent = maximumAllowedRPMPercent
        self.maxDurationSeconds = maxDurationSeconds
        self.prepareCooldownSeconds = prepareCooldownSeconds
    }
}
