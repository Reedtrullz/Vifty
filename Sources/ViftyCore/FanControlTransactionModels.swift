import Foundation

public enum FanControlOwner: Equatable, Sendable {
    case manual(sessionID: String)
    case agent(leaseID: String)
    case recovery

    public var type: String {
        switch self {
        case .manual: "manual"
        case .agent: "agent"
        case .recovery: "recovery"
        }
    }
}

extension FanControlOwner: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case sessionID
        case leaseID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "manual":
            self = .manual(sessionID: try container.decode(String.self, forKey: .sessionID))
        case "agent":
            self = .agent(leaseID: try container.decode(String.self, forKey: .leaseID))
        case "recovery":
            self = .recovery
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown fan-control owner type."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .manual(let sessionID):
            try container.encode(sessionID, forKey: .sessionID)
        case .agent(let leaseID):
            try container.encode(leaseID, forKey: .leaseID)
        case .recovery:
            break
        }
    }
}

public enum FanControlPhase: String, Codable, Equatable, Sendable {
    case prepared
    case applying
    case active
    case restoring
    case restorePending
}

public struct FanControlJournalRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let transactionID: String
    public var owner: FanControlOwner
    public var phase: FanControlPhase
    public var expectedFanIDs: [Int]
    public var targetRPMByFanID: [Int: Int]
    public var appliedFanIDs: [Int]
    public let createdAt: Date
    public var updatedAt: Date
    public var lastErrorCode: String?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        transactionID: String,
        owner: FanControlOwner,
        phase: FanControlPhase,
        expectedFanIDs: [Int],
        targetRPMByFanID: [Int: Int],
        appliedFanIDs: [Int] = [],
        createdAt: Date,
        updatedAt: Date,
        lastErrorCode: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.transactionID = transactionID
        self.owner = owner
        self.phase = phase
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.targetRPMByFanID = targetRPMByFanID
        self.appliedFanIDs = Array(Set(appliedFanIDs)).sorted()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastErrorCode = lastErrorCode
    }

    public mutating func includeExpectedFanIDs(_ fanIDs: some Sequence<Int>) {
        expectedFanIDs = Array(Set(expectedFanIDs).union(fanIDs)).sorted()
    }

    public mutating func includeAppliedFanID(_ fanID: Int) {
        appliedFanIDs = Array(Set(appliedFanIDs).union([fanID])).sorted()
    }
}

public struct ManualFanControlRequest: Codable, Equatable, Sendable {
    public var transactionID: String
    public var sessionID: String
    public var expectedFanIDs: [Int]
    public var targetRPMByFanID: [Int: Int]
    public var reason: String

    public init(
        transactionID: String,
        sessionID: String,
        expectedFanIDs: [Int],
        targetRPMByFanID: [Int: Int],
        reason: String
    ) {
        self.transactionID = transactionID
        self.sessionID = sessionID
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.targetRPMByFanID = targetRPMByFanID
        self.reason = reason
    }
}

public struct AgentFanControlRequest: Codable, Equatable, Sendable {
    public var transactionID: String
    public var leaseID: String
    public var expectedFanIDs: [Int]
    public var targetRPMByFanID: [Int: Int]

    public init(
        transactionID: String,
        leaseID: String,
        expectedFanIDs: [Int],
        targetRPMByFanID: [Int: Int]
    ) {
        self.transactionID = transactionID
        self.leaseID = leaseID
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.targetRPMByFanID = targetRPMByFanID
    }
}

/// Narrow authority for replacing an unreadable fan-control journal with a
/// new, fully synchronized recovery transaction. A normal/global Auto request
/// is deliberately insufficient because automatic lifecycle paths also issue
/// those requests.
public enum UnreadableJournalRecoveryAuthority: String, Codable, Equatable, Sendable {
    case durableState
    case explicitOperator
}

public struct AutoRestoreRequest: Codable, Equatable, Sendable {
    public var transactionID: String
    public var expectedFanIDs: [Int]
    public var reason: String
    public var allowRestoreAllTrustedFans: Bool
    public var unreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority?

    public init(
        transactionID: String,
        expectedFanIDs: [Int] = [],
        reason: String,
        allowRestoreAllTrustedFans: Bool = false,
        unreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority? = nil
    ) {
        self.transactionID = transactionID
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.reason = reason
        self.allowRestoreAllTrustedFans = allowRestoreAllTrustedFans
        self.unreadableJournalRecoveryAuthority = unreadableJournalRecoveryAuthority
    }
}

public struct FanControlOwnershipStatus: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var owner: FanControlOwner?
    public var phase: FanControlPhase?
    public var transactionID: String?
    public var expectedFanIDs: [Int]
    public var confirmedOSManagedFanIDs: [Int]
    public var recoveryPending: Bool
    public var errorCode: String?
    public var errorMessage: String?
    public var recoveryAttemptCount: Int

    public init(
        protocolVersion: Int = FanControlProtocolVersion.current,
        owner: FanControlOwner?,
        phase: FanControlPhase?,
        transactionID: String?,
        expectedFanIDs: [Int],
        confirmedOSManagedFanIDs: [Int] = [],
        recoveryPending: Bool,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        recoveryAttemptCount: Int = 0
    ) {
        self.protocolVersion = protocolVersion
        self.owner = owner
        self.phase = phase
        self.transactionID = transactionID
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.confirmedOSManagedFanIDs = Array(Set(confirmedOSManagedFanIDs)).sorted()
        self.recoveryPending = recoveryPending
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.recoveryAttemptCount = max(0, recoveryAttemptCount)
    }

    public static let osManaged = FanControlOwnershipStatus(
        owner: nil,
        phase: nil,
        transactionID: nil,
        expectedFanIDs: [],
        recoveryPending: false
    )
}

public struct FanControlTransactionResult: Codable, Equatable, Sendable {
    public var transactionID: String
    public var owner: FanControlOwner?
    public var phase: FanControlPhase?
    public var expectedFanIDs: [Int]
    public var confirmedFanIDs: [Int]
    public var warnings: [String]

    public init(
        transactionID: String,
        owner: FanControlOwner?,
        phase: FanControlPhase?,
        expectedFanIDs: [Int],
        confirmedFanIDs: [Int],
        warnings: [String] = []
    ) {
        self.transactionID = transactionID
        self.owner = owner
        self.phase = phase
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.confirmedFanIDs = Array(Set(confirmedFanIDs)).sorted()
        self.warnings = warnings
    }
}
