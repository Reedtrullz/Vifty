import Darwin
import Foundation
import ViftyCore

public enum FanControlJournalStoreError: Error, Equatable, LocalizedError {
    case unsafePath(String)
    case unsupportedSchemaVersion(Int)
    case invalidRecord(String)
    case expectedFanSetShrank
    case unresolvedTransactionExists(String)
    case unreadableRecoveryNotAllowed(String)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let reason): "Unsafe fan-control journal path: \(reason)"
        case .unsupportedSchemaVersion(let version): "Unsupported fan-control journal schema version \(version)."
        case .invalidRecord(let reason): "Invalid fan-control journal: \(reason)"
        case .expectedFanSetShrank: "Fan-control expected fan IDs may not shrink before restoration."
        case .unresolvedTransactionExists(let transactionID):
            "Fan-control transaction \(transactionID) is unresolved."
        case .unreadableRecoveryNotAllowed(let reason):
            "Unreadable fan-control journal recovery is not allowed: \(reason)"
        case .ioFailure(let reason): "Fan-control journal I/O failed: \(reason)"
        }
    }
}

public enum FanControlJournalSyncPoint: Equatable, Sendable {
    case temporaryFile
    case directoryAfterReplace
    case directoryAfterClear
}

public struct FanControlJournalDurabilityHooks: Sendable {
    public var synchronize: @Sendable (Int32, FanControlJournalSyncPoint) throws -> Void

    public init(
        synchronize: @escaping @Sendable (Int32, FanControlJournalSyncPoint) throws -> Void
    ) {
        self.synchronize = synchronize
    }

    public static let live = FanControlJournalDurabilityHooks { descriptor, point in
        guard fsync(descriptor) == 0 else {
            throw FanControlJournalStoreError.ioFailure(
                "fsync failed at \(String(describing: point)): \(String(cString: strerror(errno)))"
            )
        }
    }
}

/// Durable fan ownership state anchored to one retained directory identity.
/// Once opened, a renamed or substituted path is never silently adopted.
public final class FanControlJournalStore: @unchecked Sendable {
    public static let maximumJournalBytes = 1_048_576
    public static let defaultDirectoryURL = URL(
        fileURLWithPath: "/Library/Application Support/Vifty/FanControl",
        isDirectory: true
    )

    public let directoryURL: URL
    public let journalURL: URL
    public let preservedUnreadableJournalURL: URL
    private let fileName: String
    private let preservedUnreadableFileName: String
    private let requiredOwnerID: uid_t
    private let hooks: FanControlJournalDurabilityHooks
    private let operationLock = NSLock()
    private var anchoredDirectory: SecureStorageDirectory?

    public init(
        directoryURL: URL = FanControlJournalStore.defaultDirectoryURL,
        fileName: String = "transaction-v2.json",
        requiredOwnerID: uid_t = 0,
        hooks: FanControlJournalDurabilityHooks = .live
    ) {
        self.directoryURL = directoryURL
        self.journalURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        self.preservedUnreadableFileName = "\(fileName).unreadable-preserved"
        self.preservedUnreadableJournalURL = directoryURL.appendingPathComponent(
            "\(fileName).unreadable-preserved",
            isDirectory: false
        )
        self.fileName = fileName
        self.requiredOwnerID = requiredOwnerID
        self.hooks = hooks
    }

    public func load() throws -> FanControlJournalRecord? {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false) else { return nil }
                return try loadLocked(from: directory)
            }
        }
    }

    public func save(_ record: FanControlJournalRecord) throws {
        try validate(record)
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: true) else {
                    throw FanControlJournalStoreError.ioFailure("could not create journal directory")
                }
                if let existing = try loadLocked(from: directory) {
                    guard existing.transactionID == record.transactionID else {
                        throw FanControlJournalStoreError.unresolvedTransactionExists(existing.transactionID)
                    }
                    guard Set(record.expectedFanIDs).isSuperset(of: existing.expectedFanIDs) else {
                        throw FanControlJournalStoreError.expectedFanSetShrank
                    }
                }

                let data = try encodedRecord(record)
                try directory.replaceRegularFile(
                    named: fileName,
                    data: data,
                    maximumBytes: Self.maximumJournalBytes,
                    hooks: secureHooks
                )
            }
        }
    }

    /// Replaces only a syntactically corrupt or newer-schema primary journal,
    /// after preserving its exact bytes durably under a separate name. The
    /// caller must already have established a typed recovery authority and a
    /// complete trusted fan set. Ordinary save paths can never use this escape
    /// hatch. The bounded preservation slot always contains the latest incident:
    /// a later authorized recovery durably replaces older preserved bytes before
    /// it replaces the current primary journal.
    public func replaceUnreadableForAuthorizedRecovery(
        with record: FanControlJournalRecord
    ) throws {
        try validate(record)
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false) else {
                    throw FanControlJournalStoreError.unreadableRecoveryNotAllowed(
                        "the primary journal is missing"
                    )
                }

                let loadFailure: FanControlJournalStoreError
                do {
                    if try loadLocked(from: directory) == nil {
                        throw FanControlJournalStoreError.unreadableRecoveryNotAllowed(
                            "the primary journal is missing"
                        )
                    }
                    throw FanControlJournalStoreError.unreadableRecoveryNotAllowed(
                        "the primary journal is readable"
                    )
                } catch let error as FanControlJournalStoreError {
                    loadFailure = error
                } catch let error as SecureStorageError {
                    if case .fileTooLarge(_, let maximumBytes) = error {
                        loadFailure = .invalidRecord(
                            "encoded size exceeds \(maximumBytes) bytes"
                        )
                    } else {
                        throw error
                    }
                }
                switch loadFailure {
                case .invalidRecord, .unsupportedSchemaVersion:
                    break
                default:
                    throw loadFailure
                }

                let preservedIdentity = try directory.copyRegularFile(
                    named: fileName,
                    to: preservedUnreadableFileName,
                    hooks: secureHooks
                )

                try directory.replaceRegularFile(
                    named: fileName,
                    data: try encodedRecord(record),
                    maximumBytes: Self.maximumJournalBytes,
                    expectedOriginalIdentity: preservedIdentity,
                    hooks: secureHooks
                )
            }
        }
    }

    public func clear() throws {
        try operationLock.withLock {
            try mapStorageErrors {
                guard let directory = try secureDirectoryLocked(createIfMissing: false),
                      try loadLocked(from: directory) != nil else {
                    return
                }
                _ = try directory.removeRegularFile(
                    named: fileName,
                    hooks: secureHooks
                )
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

    private func loadLocked(
        from directory: SecureStorageDirectory
    ) throws -> FanControlJournalRecord? {
        guard let data = try directory.readRegularFile(
            named: fileName,
            maximumBytes: Self.maximumJournalBytes
        ) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw FanControlJournalStoreError.invalidRecord(error.localizedDescription)
        }
        guard header.schemaVersion == FanControlJournalRecord.currentSchemaVersion else {
            throw FanControlJournalStoreError.unsupportedSchemaVersion(header.schemaVersion)
        }

        let record: FanControlJournalRecord
        do {
            record = try decoder.decode(FanControlJournalRecord.self, from: data)
        } catch {
            throw FanControlJournalStoreError.invalidRecord(error.localizedDescription)
        }
        try validate(record)
        return record
    }

    private func encodedRecord(_ record: FanControlJournalRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw FanControlJournalStoreError.invalidRecord(error.localizedDescription)
        }
        guard data.count <= Self.maximumJournalBytes else {
            throw FanControlJournalStoreError.invalidRecord(
                "encoded size exceeds \(Self.maximumJournalBytes) bytes"
            )
        }
        return data
    }

    private var secureHooks: SecureStorageDurabilityHooks {
        SecureStorageDurabilityHooks { [hooks] descriptor, point in
            switch point {
            case .temporaryFile:
                try hooks.synchronize(descriptor, .temporaryFile)
            case .directoryAfterReplace:
                try hooks.synchronize(descriptor, .directoryAfterReplace)
            case .directoryAfterDelete:
                try hooks.synchronize(descriptor, .directoryAfterClear)
            }
        }
    }

    private func mapStorageErrors<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as FanControlJournalStoreError {
            throw error
        } catch let error as SecureStorageError {
            switch error {
            case .invalidPath(let reason), .unsafePath(let reason):
                throw FanControlJournalStoreError.unsafePath(reason)
            case .fileTooLarge(_, let maximumBytes):
                throw FanControlJournalStoreError.invalidRecord(
                    "encoded size exceeds \(maximumBytes) bytes"
                )
            case .lockUnavailable(let name):
                throw FanControlJournalStoreError.ioFailure("secure file \(name) is locked")
            case .ioFailure(let reason):
                throw FanControlJournalStoreError.ioFailure(reason)
            }
        } catch {
            throw FanControlJournalStoreError.ioFailure(error.localizedDescription)
        }
    }

    private func validate(_ record: FanControlJournalRecord) throws {
        guard record.schemaVersion == FanControlJournalRecord.currentSchemaVersion else {
            throw FanControlJournalStoreError.unsupportedSchemaVersion(record.schemaVersion)
        }
        guard !record.transactionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FanControlJournalStoreError.invalidRecord("transactionID is blank")
        }
        guard !record.expectedFanIDs.isEmpty else {
            throw FanControlJournalStoreError.invalidRecord("expectedFanIDs is empty")
        }
        guard record.expectedFanIDs == Array(Set(record.expectedFanIDs)).sorted() else {
            throw FanControlJournalStoreError.invalidRecord("expectedFanIDs is not unique and sorted")
        }
        guard record.appliedFanIDs == Array(Set(record.appliedFanIDs)).sorted() else {
            throw FanControlJournalStoreError.invalidRecord("appliedFanIDs is not unique and sorted")
        }
        guard record.expectedFanIDs.allSatisfy(SMCFanControlKeys.isValidFanID) else {
            throw FanControlJournalStoreError.invalidRecord("expectedFanIDs contains an invalid fan ID")
        }
        guard Set(record.appliedFanIDs).isSubset(of: record.expectedFanIDs) else {
            throw FanControlJournalStoreError.invalidRecord("appliedFanIDs is outside expectedFanIDs")
        }
        guard Set(record.targetRPMByFanID.keys).isSubset(of: record.expectedFanIDs) else {
            throw FanControlJournalStoreError.invalidRecord("targetRPMByFanID is outside expectedFanIDs")
        }
        switch record.owner {
        case .manual(let sessionID):
            guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FanControlJournalStoreError.invalidRecord("manual sessionID is blank")
            }
            guard record.phase == .prepared || record.phase == .applying || record.phase == .active else {
                throw FanControlJournalStoreError.invalidRecord(
                    "manual owner has invalid phase \(record.phase.rawValue)"
                )
            }
            guard Set(record.targetRPMByFanID.keys) == Set(record.expectedFanIDs) else {
                throw FanControlJournalStoreError.invalidRecord(
                    "manual targetRPMByFanID does not cover expectedFanIDs"
                )
            }
        case .agent(let leaseID):
            guard !leaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FanControlJournalStoreError.invalidRecord("agent leaseID is blank")
            }
            guard record.phase == .prepared || record.phase == .applying || record.phase == .active else {
                throw FanControlJournalStoreError.invalidRecord(
                    "agent owner has invalid phase \(record.phase.rawValue)"
                )
            }
            guard Set(record.targetRPMByFanID.keys) == Set(record.expectedFanIDs) else {
                throw FanControlJournalStoreError.invalidRecord(
                    "agent targetRPMByFanID does not cover expectedFanIDs"
                )
            }
        case .recovery:
            guard record.phase == .restoring || record.phase == .restorePending else {
                throw FanControlJournalStoreError.invalidRecord(
                    "recovery owner has invalid phase \(record.phase.rawValue)"
                )
            }
        }
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }
}
