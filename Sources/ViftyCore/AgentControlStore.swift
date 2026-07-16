import Darwin
import Foundation

public protocol AgentControlPersisting: Sendable {
    func saveActiveLease(_ lease: AgentCoolingLease?) throws
    func loadActiveLease() throws -> AgentCoolingLease?
    func appendAuditEvent(_ event: AgentControlAuditEvent) throws
    func loadRecentAuditEvents(limit: Int) throws -> [AgentControlAuditEvent]
}

public enum AgentControlStoreError: Error, Equatable, LocalizedError, Sendable {
    case unsafePath(String)
    case unsupportedLeaseSchemaVersion(Int)
    case invalidActiveLease(String)
    case invalidAuditLog(String)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let reason):
            "Unsafe agent-control storage path: \(reason)"
        case .unsupportedLeaseSchemaVersion(let version):
            "Unsupported active-lease schema version \(version)."
        case .invalidActiveLease(let reason):
            "Invalid active-lease record: \(reason)"
        case .invalidAuditLog(let reason):
            "Invalid agent-control audit log: \(reason)"
        case .ioFailure(let reason):
            "Agent-control storage I/O failed: \(reason)"
        }
    }
}

public struct AgentControlAuditEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var action: String
    public var leaseID: String?
    public var message: String

    public init(timestamp: Date, action: String, leaseID: String?, message: String) {
        self.timestamp = timestamp
        self.action = action
        self.leaseID = leaseID
        self.message = message
    }
}

public final class AgentControlStore: AgentControlPersisting, @unchecked Sendable {
    public static let defaultMaximumAuditEvents = 2_000
    public static let maximumActiveLeaseBytes = 64 * 1_024
    public static let maximumAuditBytes = 8 * 1_024 * 1_024
    public static let activeLeaseSchemaVersion = 1
    public static let defaultDirectoryURL = URL(
        fileURLWithPath: "/Library/Application Support/Vifty/AgentControl",
        isDirectory: true
    )

    private static let activeLeaseKind = "tech.reidar.vifty.agent-control.active-lease"
    private static let activeLeaseFileName = "active-lease.json"
    private static let auditFileName = "audit.jsonl"

    private let directoryURL: URL
    private let maximumAuditEvents: Int
    private let requiredOwnerID: uid_t
    private let hooks: SecureStorageDurabilityHooks
    private let operationLock = NSLock()
    private var anchoredDirectory: SecureStorageDirectory?

    public convenience init(
        directory: URL = AgentControlStore.defaultDirectoryURL,
        maximumAuditEvents: Int = AgentControlStore.defaultMaximumAuditEvents,
        hooks: SecureStorageDurabilityHooks = .live
    ) {
        self.init(
            directory: directory,
            maximumAuditEvents: maximumAuditEvents,
            requiredOwnerID: directory.standardizedFileURL.path
                == Self.defaultDirectoryURL.standardizedFileURL.path ? 0 : geteuid(),
            hooks: hooks
        )
    }

    public init(
        directory: URL,
        maximumAuditEvents: Int = AgentControlStore.defaultMaximumAuditEvents,
        requiredOwnerID: uid_t,
        hooks: SecureStorageDurabilityHooks = .live
    ) {
        self.directoryURL = directory
        self.maximumAuditEvents = max(1, maximumAuditEvents)
        self.requiredOwnerID = requiredOwnerID
        self.hooks = hooks
    }

    public func saveActiveLease(_ lease: AgentCoolingLease?) throws {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: true) else {
                    throw AgentControlStoreError.ioFailure("could not create the agent-control directory")
                }
                if let lease {
                    try Self.validate(lease)
                    let envelope = ActiveLeaseEnvelope(
                        schemaVersion: Self.activeLeaseSchemaVersion,
                        kind: Self.activeLeaseKind,
                        lease: lease
                    )
                    let data: Data
                    do {
                        data = try encoder.encode(envelope)
                    } catch {
                        throw AgentControlStoreError.invalidActiveLease(error.localizedDescription)
                    }
                    try directory.replaceRegularFile(
                        named: Self.activeLeaseFileName,
                        data: data,
                        maximumBytes: Self.maximumActiveLeaseBytes,
                        hooks: hooks
                    )
                } else {
                    _ = try directory.removeRegularFile(
                        named: Self.activeLeaseFileName,
                        hooks: hooks
                    )
                }
            }
        }
    }

    public func loadActiveLease() throws -> AgentCoolingLease? {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false),
                      let data = try directory.readRegularFile(
                          named: Self.activeLeaseFileName,
                          maximumBytes: Self.maximumActiveLeaseBytes
                      ) else {
                    return nil
                }
                let header: ActiveLeaseEnvelopeHeader
                do {
                    header = try decoder.decode(ActiveLeaseEnvelopeHeader.self, from: data)
                } catch {
                    throw AgentControlStoreError.invalidActiveLease(
                        "missing the authenticated versioned envelope; legacy JSON is untrusted"
                    )
                }
                guard header.schemaVersion == Self.activeLeaseSchemaVersion else {
                    throw AgentControlStoreError.unsupportedLeaseSchemaVersion(header.schemaVersion)
                }
                guard header.kind == Self.activeLeaseKind else {
                    throw AgentControlStoreError.invalidActiveLease("record kind is not recognized")
                }
                let envelope: ActiveLeaseEnvelope
                do {
                    envelope = try decoder.decode(ActiveLeaseEnvelope.self, from: data)
                } catch {
                    throw AgentControlStoreError.invalidActiveLease(error.localizedDescription)
                }
                try Self.validate(envelope.lease)
                return envelope.lease
            }
        }
    }

    public func appendAuditEvent(_ event: AgentControlAuditEvent) throws {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: true) else {
                    throw AgentControlStoreError.ioFailure("could not create the agent-control directory")
                }
                var events = try loadAuditEventsLocked(from: directory)
                events.append(event)
                events = Array(events.suffix(maximumAuditEvents))

                var data = Data()
                for retainedEvent in events {
                    do {
                        data.append(try encoder.encode(retainedEvent))
                    } catch {
                        throw AgentControlStoreError.invalidAuditLog(error.localizedDescription)
                    }
                    data.append(contentsOf: "\n".utf8)
                }
                try directory.replaceRegularFile(
                    named: Self.auditFileName,
                    data: data,
                    maximumBytes: Self.maximumAuditBytes,
                    hooks: hooks
                )
            }
        }
    }

    public func loadRecentAuditEvents(
        limit: Int = AgentControlStore.defaultMaximumAuditEvents
    ) throws -> [AgentControlAuditEvent] {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false) else { return [] }
                return Array(try loadAuditEventsLocked(from: directory).suffix(max(1, limit)))
            }
        }
    }

    private func secureDirectoryLocked(createIfMissing: Bool) throws -> SecureStorageDirectory? {
        if let anchoredDirectory {
            try anchoredDirectory.validatePathIdentity()
            return anchoredDirectory
        }
        let opened = try SecureStorageDirectory.open(
            directoryURL: directoryURL,
            requiredOwnerID: requiredOwnerID,
            createIfMissing: createIfMissing
        )
        anchoredDirectory = opened
        return opened
    }

    private func loadAuditEventsLocked(
        from directory: SecureStorageDirectory
    ) throws -> [AgentControlAuditEvent] {
        guard let data = try directory.readRegularFile(
            named: Self.auditFileName,
            maximumBytes: Self.maximumAuditBytes
        ) else {
            return []
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw AgentControlStoreError.invalidAuditLog("audit data is not valid UTF-8")
        }
        return try contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                guard let lineData = String(line).data(using: .utf8) else {
                    throw AgentControlStoreError.invalidAuditLog("audit event is not valid UTF-8")
                }
                do {
                    return try decoder.decode(AgentControlAuditEvent.self, from: lineData)
                } catch {
                    throw AgentControlStoreError.invalidAuditLog(error.localizedDescription)
                }
            }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func mapStorageErrors<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as AgentControlStoreError {
            throw error
        } catch let error as SecureStorageError {
            switch error {
            case .invalidPath(let reason), .unsafePath(let reason):
                throw AgentControlStoreError.unsafePath(reason)
            case .fileTooLarge(let name, let maximumBytes):
                if name == Self.activeLeaseFileName {
                    throw AgentControlStoreError.invalidActiveLease(
                        "encoded size exceeds \(maximumBytes) bytes"
                    )
                }
                throw AgentControlStoreError.invalidAuditLog(
                    "encoded size exceeds \(maximumBytes) bytes"
                )
            case .ioFailure(let reason):
                throw AgentControlStoreError.ioFailure(reason)
            }
        } catch {
            throw AgentControlStoreError.ioFailure(error.localizedDescription)
        }
    }

    private static func validate(_ lease: AgentCoolingLease) throws {
        let trimmedID = lease.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, trimmedID.count <= 256 else {
            throw AgentControlStoreError.invalidActiveLease("lease ID is blank or too long")
        }
        guard lease.request.metadataValidationFailureMessage == nil else {
            throw AgentControlStoreError.invalidActiveLease(
                lease.request.metadataValidationFailureMessage ?? "request metadata is invalid"
            )
        }
        guard lease.request.durationSeconds > 0,
              (0...100).contains(lease.request.maxRPMPercent) else {
            throw AgentControlStoreError.invalidActiveLease("request limits are invalid")
        }
        let created = lease.createdAt.timeIntervalSince1970
        let expires = lease.expiresAt.timeIntervalSince1970
        guard created.isFinite,
              expires.isFinite,
              expires > created,
              abs((expires - created) - Double(lease.request.durationSeconds)) < 0.001 else {
            throw AgentControlStoreError.invalidActiveLease(
                "lease timestamps do not match the requested duration"
            )
        }
        guard lease.restoredAt == nil else {
            throw AgentControlStoreError.invalidActiveLease(
                "a restored lease must be cleared instead of persisted as active"
            )
        }
        guard !lease.targetRPMByFanID.isEmpty,
              lease.targetRPMByFanID.count <= 10,
              lease.targetRPMByFanID.allSatisfy({ fanID, rpm in
                  SMCFanControlKeys.isValidFanID(fanID)
                      && rpm > 0
                      && rpm <= Int(Int32.max)
              }) else {
            throw AgentControlStoreError.invalidActiveLease(
                "target RPMs do not describe a bounded valid fan set"
            )
        }
    }

    private struct ActiveLeaseEnvelopeHeader: Decodable {
        let schemaVersion: Int
        let kind: String
    }

    private struct ActiveLeaseEnvelope: Codable {
        let schemaVersion: Int
        let kind: String
        let lease: AgentCoolingLease
    }
}
