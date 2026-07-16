import CryptoKit
import Darwin
import Foundation

public enum HelperMaintenanceCandidateIdentity {
    public static let maximumHelperBytes = 128 * 1_024 * 1_024

    public static func bundledHelperSHA256(
        executablePath: String? = CommandLine.arguments.first
    ) throws -> String {
        guard let executablePath, !executablePath.isEmpty else {
            throw ViftyError.helperRejected("Could not resolve the maintenance client executable.")
        }
        let executableURL = URL(fileURLWithPath: executablePath, isDirectory: false)
        guard executableURL.lastPathComponent == "viftyctl"
                || executableURL.lastPathComponent == "ViftyCtl" else {
            throw ViftyError.helperRejected(
                "Helper maintenance must be prepared by the bundled viftyctl executable."
            )
        }
        return try sha256(
            at: executableURL.deletingLastPathComponent()
                .appendingPathComponent("ViftyHelper", isDirectory: false)
        )
    }

    public static func sha256(
        at url: URL,
        maximumBytes: Int = maximumHelperBytes
    ) throws -> String {
        guard maximumBytes > 0 else {
            throw ViftyError.helperRejected("Maintenance helper identity limit is invalid.")
        }
        var pathMetadata = stat()
        guard lstat(url.path, &pathMetadata) == 0,
              pathMetadata.st_mode & S_IFMT == S_IFREG,
              pathMetadata.st_nlink == 1,
              pathMetadata.st_mode & 0o111 != 0,
              pathMetadata.st_size > 0,
              pathMetadata.st_size <= off_t(maximumBytes) else {
            throw ViftyError.helperRejected(
                "Bundled ViftyHelper must be a bounded, singly linked executable regular file."
            )
        }
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ViftyError.helperRejected("Could not open bundled ViftyHelper without following links.")
        }
        defer { close(descriptor) }
        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0,
              openedMetadata.st_dev == pathMetadata.st_dev,
              openedMetadata.st_ino == pathMetadata.st_ino,
              openedMetadata.st_size == pathMetadata.st_size else {
            throw ViftyError.helperRejected("Bundled ViftyHelper changed while it was opened.")
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var totalBytes = 0
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ViftyError.helperRejected("Could not read bundled ViftyHelper identity.")
            }
            totalBytes += count
            guard totalBytes <= maximumBytes else {
                throw ViftyError.helperRejected("Bundled ViftyHelper exceeds the identity limit.")
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        var finalMetadata = stat()
        guard fstat(descriptor, &finalMetadata) == 0,
              finalMetadata.st_dev == openedMetadata.st_dev,
              finalMetadata.st_ino == openedMetadata.st_ino,
              finalMetadata.st_size == openedMetadata.st_size,
              totalBytes == Int(openedMetadata.st_size) else {
            throw ViftyError.helperRejected("Bundled ViftyHelper changed while it was hashed.")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum HelperMaintenanceOperation: String, Codable, CaseIterable, Sendable {
    case repair
    case uninstall
    case voluntaryTermination
    case offlineRecovery
}

public enum HelperMaintenanceBlockerCode: String, Codable, Equatable, Sendable {
    case restoreFailed = "RESTORE_FAILED"
    case ownershipUnresolved = "OWNERSHIP_UNRESOLVED"
    case snapshotUnavailable = "SNAPSHOT_UNAVAILABLE"
    case protocolMismatch = "PROTOCOL_MISMATCH"
    case fanInventoryInvalid = "FAN_INVENTORY_INVALID"
    case fanStateUnconfirmed = "FAN_STATE_UNCONFIRMED"
    case helperIdentityUnavailable = "HELPER_IDENTITY_UNAVAILABLE"
    case offlineAuthorizationUnavailable = "OFFLINE_AUTHORIZATION_UNAVAILABLE"
}

public struct HelperMaintenanceBlocker: Codable, Equatable, Sendable {
    public var code: HelperMaintenanceBlockerCode
    public var message: String
    public var recommendedRecoveryAction: String

    public init(
        code: HelperMaintenanceBlockerCode,
        message: String,
        recommendedRecoveryAction: String
    ) {
        self.code = code
        self.message = message
        self.recommendedRecoveryAction = recommendedRecoveryAction
    }
}

public struct HelperMaintenanceFanResult: Codable, Equatable, Sendable {
    public var fanID: Int
    public var observedMode: String?
    public var confirmedOSManaged: Bool
    public var freshConfirmationAt: Date?
    public var failure: String?

    public init(
        fanID: Int,
        observedMode: String?,
        confirmedOSManaged: Bool,
        freshConfirmationAt: Date?,
        failure: String? = nil
    ) {
        self.fanID = fanID
        self.observedMode = observedMode
        self.confirmedOSManaged = confirmedOSManaged
        self.freshConfirmationAt = freshConfirmationAt
        self.failure = failure
    }
}

/// A maintenance token is not a bearer secret and is never trusted from JSON
/// alone. The daemon retains the authoritative copy and revalidates every
/// binding before atomically consuming it while control remains quiesced.
public struct HelperMaintenanceToken: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var tokenID: String
    public var operation: HelperMaintenanceOperation
    public var issuedAt: Date
    public var expiresAt: Date
    public var bootSessionID: String
    public var daemonSessionID: String
    public var journalGeneration: UInt64
    public var expectedFanIDs: [Int]
    public var helperSHA256: String
    public var quiesceGeneration: UInt64

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        tokenID: String,
        operation: HelperMaintenanceOperation,
        issuedAt: Date,
        expiresAt: Date,
        bootSessionID: String,
        daemonSessionID: String,
        journalGeneration: UInt64,
        expectedFanIDs: [Int],
        helperSHA256: String,
        quiesceGeneration: UInt64
    ) {
        self.schemaVersion = schemaVersion
        self.tokenID = tokenID
        self.operation = operation
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.bootSessionID = bootSessionID
        self.daemonSessionID = daemonSessionID
        self.journalGeneration = journalGeneration
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.helperSHA256 = helperSHA256
        self.quiesceGeneration = quiesceGeneration
    }
}

public struct HelperMaintenanceReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let schemaID = "https://vifty.app/schemas/helper-maintenance-report-v1.json"

    public var schemaVersion: Int
    public var schemaID: String
    public var operation: HelperMaintenanceOperation
    public var safeToStop: Bool
    public var quiesced: Bool
    public var restoreAttempted: Bool
    public var restoreSucceeded: Bool
    public var completeExpectedSetConfirmed: Bool
    public var fanResults: [HelperMaintenanceFanResult]
    public var blockers: [HelperMaintenanceBlocker]
    public var token: HelperMaintenanceToken?
    public var tokenConsumed: Bool

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        schemaID: String = Self.schemaID,
        operation: HelperMaintenanceOperation,
        safeToStop: Bool,
        quiesced: Bool,
        restoreAttempted: Bool,
        restoreSucceeded: Bool,
        completeExpectedSetConfirmed: Bool,
        fanResults: [HelperMaintenanceFanResult],
        blockers: [HelperMaintenanceBlocker],
        token: HelperMaintenanceToken?,
        tokenConsumed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.operation = operation
        self.safeToStop = safeToStop
        self.quiesced = quiesced
        self.restoreAttempted = restoreAttempted
        self.restoreSucceeded = restoreSucceeded
        self.completeExpectedSetConfirmed = completeExpectedSetConfirmed
        self.fanResults = fanResults.sorted { $0.fanID < $1.fanID }
        self.blockers = blockers
        self.token = token
        self.tokenConsumed = tokenConsumed
    }
}

public struct HelperMaintenanceSnapshotAnalysis: Equatable, Sendable {
    public var expectedFanIDs: [Int]
    public var fanResults: [HelperMaintenanceFanResult]
    public var blockers: [HelperMaintenanceBlocker]

    public init(
        expectedFanIDs: [Int],
        fanResults: [HelperMaintenanceFanResult],
        blockers: [HelperMaintenanceBlocker]
    ) {
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.fanResults = fanResults.sorted { $0.fanID < $1.fanID }
        self.blockers = blockers
    }
}

public enum HelperMaintenanceSnapshotAnalyzer {
    public static func analyze(_ snapshot: HardwareSnapshot) -> HelperMaintenanceSnapshotAnalysis {
        var blockers: [HelperMaintenanceBlocker] = []
        if snapshot.fanControlProtocolVersion < FanControlProtocolVersion.current {
            blockers.append(HelperMaintenanceBlocker(
                code: .protocolMismatch,
                message: "Fan-control protocol v\(snapshot.fanControlProtocolVersion) cannot authorize v2 helper maintenance.",
                recommendedRecoveryAction: "Use the installed version's Restore Auto flow or reboot before a trusted upgrade."
            ))
        }

        // Every physical fan is in the safety domain. Mode-only fans may not
        // support Fixed RPM, but trusted Auto restoration still must include them.
        let fans = snapshot.fans.sorted { $0.id < $1.id }
        let expectedFanIDs = fans.map(\.id)
        if fans.isEmpty
            || expectedFanIDs != Array(Set(expectedFanIDs)).sorted()
            || !fans.allSatisfy({
                SMCFanControlKeys.isValidFanID($0.id)
                    && $0.controlEligibility.canRestoreOSManagedMode
            }) {
            blockers.append(HelperMaintenanceBlocker(
                code: .fanInventoryInvalid,
                message: "Fresh telemetry did not contain one complete, unique, trusted physical fan set.",
                recommendedRecoveryAction: "Restore trusted fan telemetry or reboot; never bypass the maintenance preflight."
            ))
        }

        let fanResults = fans.map { fan -> HelperMaintenanceFanResult in
            let confirmed = fan.controlEligibility.canRestoreOSManagedMode
                && (fan.hardwareMode == .automatic || fan.hardwareMode == .system)
            return HelperMaintenanceFanResult(
                fanID: fan.id,
                observedMode: fan.hardwareMode.map(modeName),
                confirmedOSManaged: confirmed,
                freshConfirmationAt: snapshot.capturedAt,
                failure: confirmed
                    ? nil
                    : "Fan \(fan.id) was not freshly confirmed in Auto/System mode with trusted restore telemetry."
            )
        }
        if fanResults.contains(where: { !$0.confirmedOSManaged }) {
            blockers.append(HelperMaintenanceBlocker(
                code: .fanStateUnconfirmed,
                message: "At least one fan is Forced, Unknown, missing, or lacks trusted restore telemetry.",
                recommendedRecoveryAction: "Restore the complete fan set to Auto/System and confirm it from fresh telemetry."
            ))
        }
        return HelperMaintenanceSnapshotAnalysis(
            expectedFanIDs: expectedFanIDs,
            fanResults: fanResults,
            blockers: blockers
        )
    }

    private static func modeName(_ mode: FanHardwareMode) -> String {
        switch mode {
        case .automatic: "automatic"
        case .forced: "forced"
        case .system: "system"
        case .unknown(let value): "unknown(\(value))"
        }
    }
}

public struct HelperMaintenanceAuthorizationRequest: Codable, Equatable, Sendable {
    public var operation: HelperMaintenanceOperation
    public var token: HelperMaintenanceToken

    public init(operation: HelperMaintenanceOperation, token: HelperMaintenanceToken) {
        self.operation = operation
        self.token = token
    }
}

public struct HelperMaintenanceAuthorization: Codable, Equatable, Sendable {
    public var authorized: Bool
    public var operation: HelperMaintenanceOperation
    public var tokenID: String
    public var consumedAt: Date
    public var quiesced: Bool
    public var tokenConsumed: Bool

    public init(
        authorized: Bool,
        operation: HelperMaintenanceOperation,
        tokenID: String,
        consumedAt: Date,
        quiesced: Bool,
        tokenConsumed: Bool
    ) {
        self.authorized = authorized
        self.operation = operation
        self.tokenID = tokenID
        self.consumedAt = consumedAt
        self.quiesced = quiesced
        self.tokenConsumed = tokenConsumed
    }
}

/// Durable handoff from the authenticated daemon to the administrator-owned
/// lifecycle worker. The JSON representation is authority only while it is a
/// root-owned, mode-0600 regular file inside the fixed root-owned maintenance
/// directory; a caller-supplied copy is never accepted.
public struct HelperMaintenanceAuthorityReceipt: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let schemaID = "https://vifty.app/schemas/helper-maintenance-authority-v1.json"
    public static let recordKind = "daemon-authorized-helper-maintenance"

    public var schemaVersion: Int
    public var schemaID: String
    public var recordKind: String
    public var operation: HelperMaintenanceOperation
    public var tokenID: String
    public var tokenIssuedAt: Date
    public var authorizedAt: Date
    public var expiresAt: Date
    public var bootSessionID: String
    public var daemonSessionID: String
    public var journalGeneration: UInt64
    public var expectedFanIDs: [Int]
    public var helperSHA256: String
    public var quiesceGeneration: UInt64
    public var quiesced: Bool
    public var tokenConsumed: Bool

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        schemaID: String = Self.schemaID,
        recordKind: String = Self.recordKind,
        operation: HelperMaintenanceOperation,
        tokenID: String,
        tokenIssuedAt: Date,
        authorizedAt: Date,
        expiresAt: Date,
        bootSessionID: String,
        daemonSessionID: String,
        journalGeneration: UInt64,
        expectedFanIDs: [Int],
        helperSHA256: String,
        quiesceGeneration: UInt64,
        quiesced: Bool = true,
        tokenConsumed: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.recordKind = recordKind
        self.operation = operation
        self.tokenID = tokenID
        self.tokenIssuedAt = tokenIssuedAt
        self.authorizedAt = authorizedAt
        self.expiresAt = expiresAt
        self.bootSessionID = bootSessionID
        self.daemonSessionID = daemonSessionID
        self.journalGeneration = journalGeneration
        self.expectedFanIDs = Array(Set(expectedFanIDs)).sorted()
        self.helperSHA256 = helperSHA256
        self.quiesceGeneration = quiesceGeneration
        self.quiesced = quiesced
        self.tokenConsumed = tokenConsumed
    }
}

public enum HelperServiceManagementAction: String, Codable, Sendable {
    case register
    case unregister
}

public enum HelperServiceRegistrationState: String, Codable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unknown
}

public struct HelperServiceManagementReport: Codable, Equatable, Sendable {
    public var action: HelperServiceManagementAction
    public var state: HelperServiceRegistrationState
    public var complete: Bool
    public var operatorActionRequired: Bool
    public var maintenanceAuthorized: Bool
    public var tokenID: String?
    public var legacyProtocolGateUsed: Bool
    public var legacyMarkerPresent: Bool

    public init(
        action: HelperServiceManagementAction,
        state: HelperServiceRegistrationState,
        complete: Bool,
        operatorActionRequired: Bool,
        maintenanceAuthorized: Bool = false,
        tokenID: String? = nil,
        legacyProtocolGateUsed: Bool = false,
        legacyMarkerPresent: Bool = false
    ) {
        self.action = action
        self.state = state
        self.complete = complete
        self.operatorActionRequired = operatorActionRequired
        self.maintenanceAuthorized = maintenanceAuthorized
        self.tokenID = tokenID
        self.legacyProtocolGateUsed = legacyProtocolGateUsed
        self.legacyMarkerPresent = legacyMarkerPresent
    }
}

/// Uses one bounded JSON data value so XPC decoding has an exact payload shape
/// and cannot silently accept partially typed nested NSDictionary values.
public enum XPCHelperMaintenanceCoding {
    public static let maximumPayloadBytes = 1_048_576

    public static func encode(_ report: HelperMaintenanceReport) -> NSDictionary {
        encodeValue(report)
    }

    public static func decodeReport(_ dictionary: NSDictionary) -> HelperMaintenanceReport? {
        decodeValue(dictionary, as: HelperMaintenanceReport.self)
    }

    public static func encode(_ request: HelperMaintenanceAuthorizationRequest) -> NSDictionary {
        encodeValue(request)
    }

    public static func decodeAuthorizationRequest(
        _ dictionary: NSDictionary
    ) -> HelperMaintenanceAuthorizationRequest? {
        decodeValue(dictionary, as: HelperMaintenanceAuthorizationRequest.self)
    }

    public static func encode(_ authorization: HelperMaintenanceAuthorization) -> NSDictionary {
        encodeValue(authorization)
    }

    public static func decodeAuthorization(
        _ dictionary: NSDictionary
    ) -> HelperMaintenanceAuthorization? {
        decodeValue(dictionary, as: HelperMaintenanceAuthorization.self)
    }

    private static func encodeValue<T: Encodable>(_ value: T) -> NSDictionary {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value), data.count <= maximumPayloadBytes else {
            return [:]
        }
        return ["json": data] as NSDictionary
    }

    private static func decodeValue<T: Decodable>(
        _ dictionary: NSDictionary,
        as type: T.Type
    ) -> T? {
        guard dictionary.count == 1,
              let data = dictionary["json"] as? Data,
              !data.isEmpty,
              data.count <= maximumPayloadBytes else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}
